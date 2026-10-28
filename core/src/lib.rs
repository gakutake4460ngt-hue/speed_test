use std::collections::VecDeque;
use std::io::{self, Read};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering::*};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

const HOST: &str = "https://speed.cloudflare.com";
const STREAMS: usize = 6;
const PHASE_SECS: f64 = 10.0;
const WARMUP_SECS: f64 = 2.0;
const WINDOW_SECS: f64 = 1.5;
const DOWN_CHUNK: u64 = 25_000_000;
const UP_CHUNK: usize = 8_000_000;
const PINGS: usize = 8;

const IDLE: u32 = 0;
const PING: u32 = 1;
const DOWN: u32 = 2;
const UP: u32 = 3;

const MODE_DOWN: u32 = 0;
const MODE_UP: u32 = 1;

struct F64(AtomicU64);

impl F64 {
    const fn new() -> Self {
        F64(AtomicU64::new(0))
    }
    fn get(&self) -> f64 {
        f64::from_bits(self.0.load(Relaxed))
    }
    fn set(&self, v: f64) {
        self.0.store(v.to_bits(), Relaxed)
    }
}

struct Shared {
    running: AtomicBool,
    stop: AtomicBool,
    phase: AtomicU32,
    cycle: AtomicU32,
    error: AtomicU32,
    mbps: F64,
    down: F64,
    up: F64,
    ping: F64,
    progress: F64,
}

static S: Shared = Shared {
    running: AtomicBool::new(false),
    stop: AtomicBool::new(false),
    phase: AtomicU32::new(IDLE),
    cycle: AtomicU32::new(0),
    error: AtomicU32::new(0),
    mbps: F64::new(),
    down: F64::new(),
    up: F64::new(),
    ping: F64::new(),
    progress: F64::new(),
};

#[repr(C)]
pub struct ScStatus {
    phase: u32,
    cycle: u32,
    running: u32,
    error: u32,
    mbps: f64,
    down_mbps: f64,
    up_mbps: f64,
    ping_ms: f64,
    progress: f64,
}

#[no_mangle]
pub extern "C" fn sc_start(mode: u32) {
    if S.running.swap(true, AcqRel) {
        return;
    }
    S.stop.store(false, Release);
    S.error.store(0, Relaxed);
    S.cycle.store(0, Relaxed);
    for v in [&S.mbps, &S.down, &S.up, &S.ping, &S.progress] {
        v.set(0.0);
    }
    thread::spawn(move || {
        run(mode);
        S.phase.store(IDLE, Relaxed);
        S.mbps.set(0.0);
        S.progress.set(0.0);
        S.running.store(false, Release);
    });
}

#[no_mangle]
pub extern "C" fn sc_stop() {
    S.stop.store(true, Release);
}

/// # Safety
/// `out` must be null or point to a writable `ScStatus`.
#[no_mangle]
pub unsafe extern "C" fn sc_status(out: *mut ScStatus) {
    if out.is_null() {
        return;
    }
    *out = ScStatus {
        phase: S.phase.load(Relaxed),
        cycle: S.cycle.load(Relaxed),
        running: S.running.load(Acquire) as u32,
        error: S.error.load(Relaxed),
        mbps: S.mbps.get(),
        down_mbps: S.down.get(),
        up_mbps: S.up.get(),
        ping_ms: S.ping.get(),
        progress: S.progress.get(),
    };
}

fn stopped() -> bool {
    S.stop.load(Acquire)
}

fn fail() {
    if !stopped() {
        S.error.store(1, Relaxed);
    }
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(5))
        .timeout_read(Duration::from_secs(5))
        .timeout_write(Duration::from_secs(5))
        .build()
}

fn run(mode: u32) {
    S.phase.store(PING, Relaxed);
    S.progress.set(0.0);
    match ping() {
        Some(p) => S.ping.set(p),
        None => return fail(),
    }
    for (dir, enabled, slot) in [(DOWN, mode != MODE_UP, &S.down), (UP, mode != MODE_DOWN, &S.up)] {
        if !enabled {
            continue;
        }
        S.phase.store(dir, Relaxed);
        match measure(dir == UP) {
            Some(v) => slot.set(v),
            None => return fail(),
        }
        S.mbps.set(0.0);
    }
    S.cycle.fetch_add(1, Relaxed);
}

fn ping() -> Option<f64> {
    let a = agent();
    let url = format!("{HOST}/__down?bytes=0");
    a.get(&url).call().ok()?.into_string().ok()?;
    let mut v = Vec::with_capacity(PINGS);
    for i in 0..PINGS {
        if stopped() {
            return None;
        }
        let t = Instant::now();
        if let Ok(r) = a.get(&url).call() {
            let _ = r.into_string();
            v.push(t.elapsed().as_secs_f64() * 1000.0);
        }
        S.progress.set((i + 1) as f64 / PINGS as f64);
    }
    if v.is_empty() {
        return None;
    }
    v.sort_by(|a, b| a.total_cmp(b));
    Some(v[v.len() / 2])
}

fn measure(up: bool) -> Option<f64> {
    let counter = Arc::new(AtomicU64::new(0));
    let halt = Arc::new(AtomicBool::new(false));
    let payload = Arc::new(noise(UP_CHUNK));
    for _ in 0..STREAMS {
        let (c, h, p) = (counter.clone(), halt.clone(), payload.clone());
        thread::spawn(move || worker(up, c, h, p));
    }

    let t0 = Instant::now();
    let mut hist: VecDeque<(f64, u64)> = VecDeque::from([(0.0, 0)]);
    let mut warm: Option<(f64, u64)> = None;
    S.progress.set(0.0);
    loop {
        thread::sleep(Duration::from_millis(100));
        let t = t0.elapsed().as_secs_f64();
        let b = counter.load(Relaxed);
        hist.push_back((t, b));
        while hist.len() > 2 && hist[1].0 <= t - WINDOW_SECS {
            hist.pop_front();
        }
        let (t1, b1) = hist[0];
        if t > t1 {
            S.mbps.set(mbps(b - b1, t - t1));
        }
        if warm.is_none() && t >= WARMUP_SECS {
            warm = Some((t, b));
        }
        S.progress.set((t / PHASE_SECS).min(1.0));
        if stopped() {
            halt.store(true, Release);
            return None;
        }
        if t >= PHASE_SECS {
            halt.store(true, Release);
            let (tw, bw) = warm?;
            return (b > bw).then(|| mbps(b - bw, t - tw));
        }
    }
}

fn mbps(bytes: u64, secs: f64) -> f64 {
    bytes as f64 * 8.0 / secs / 1e6
}

fn worker(up: bool, counter: Arc<AtomicU64>, halt: Arc<AtomicBool>, payload: Arc<Vec<u8>>) {
    let a = agent();
    while !halt.load(Acquire) {
        let r = if up {
            upload(&a, &counter, &halt, &payload)
        } else {
            download(&a, &counter, &halt)
        };
        if r.is_err() && !halt.load(Acquire) {
            thread::sleep(Duration::from_millis(200));
        }
    }
}

fn download(a: &ureq::Agent, counter: &AtomicU64, halt: &AtomicBool) -> io::Result<()> {
    let resp = a
        .get(&format!("{HOST}/__down?bytes={DOWN_CHUNK}"))
        .call()
        .map_err(io::Error::other)?;
    let mut rd = resp.into_reader();
    let mut buf = vec![0u8; 1 << 16];
    while !halt.load(Acquire) {
        let n = rd.read(&mut buf)?;
        if n == 0 {
            break;
        }
        counter.fetch_add(n as u64, Relaxed);
    }
    Ok(())
}

struct Source<'a> {
    data: &'a [u8],
    pos: usize,
    counter: &'a AtomicU64,
    halt: &'a AtomicBool,
}

impl Read for Source<'_> {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if self.halt.load(Acquire) {
            return Err(io::Error::other("halt"));
        }
        let n = out.len().min(self.data.len() - self.pos);
        out[..n].copy_from_slice(&self.data[self.pos..self.pos + n]);
        self.pos += n;
        self.counter.fetch_add(n as u64, Relaxed);
        Ok(n)
    }
}

fn upload(a: &ureq::Agent, counter: &AtomicU64, halt: &AtomicBool, data: &[u8]) -> io::Result<()> {
    let src = Source { data, pos: 0, counter, halt };
    a.post(&format!("{HOST}/__up"))
        .set("Content-Type", "application/octet-stream")
        .set("Content-Length", &data.len().to_string())
        .send(src)
        .map_err(io::Error::other)?;
    Ok(())
}

fn noise(len: usize) -> Vec<u8> {
    let mut x: u64 = 0x9E37_79B9_7F4A_7C15;
    (0..len)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x as u8
        })
        .collect()
}
