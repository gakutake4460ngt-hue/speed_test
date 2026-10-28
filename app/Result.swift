import SwiftUI

struct Brand: View {
    var sub: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Spacer().frame(width: 60)
            Text("SPEEDTEST").font(mono(12, .bold)).kerning(5).foregroundStyle(Palette.text)
            Text("//").font(mono(12)).foregroundStyle(Palette.dim)
            if let sub {
                Text(sub).font(mono(12, .bold)).kerning(3).foregroundStyle(Palette.down)
            }
        }
    }
}

extension View {
    func screenInsets() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
    }
}

struct ResultView: View {
    let r: Report
    let retest: () -> Void
    let close: () -> Void

    @State private var start = Date()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return f
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Date().timeIntervalSince(start) > 3.5)) { tl in
            // Insertion transition finishes ~0.95s after appearance.
            let t = tl.date.timeIntervalSince(start) - 0.95
            VStack(spacing: 16) {
                HStack {
                    Brand(sub: "RESULT")
                    Spacer()
                    Text(Self.stamp.string(from: r.date))
                        .font(mono(11))
                        .foregroundStyle(Palette.dim)
                }
                .frame(height: 22)

                HStack(alignment: .top, spacing: 14) {
                    if r.mode != .up {
                        card("▼ DOWNLINK", r.down, peak: r.peak(up: false), Palette.down, t)
                    }
                    if r.mode != .down {
                        card("▲ UPLINK", r.up, peak: r.peak(up: true), Palette.up, t - 0.2)
                    }
                    pingCard(t - 0.4)
                }
                .frame(height: 230)

                Panel(title: "TRACE", tint: Palette.dim) {
                    Trace(samples: r.samples)
                }
                .opacity(reveal(t - 0.5, 0.4))

                HStack(spacing: 10) {
                    Spacer()
                    Key(key: "ESC", label: "✕ CLOSE", on: false, locked: false, action: close)
                    Key(key: "SPACE", label: "↻ RETEST", on: true, locked: false, action: retest)
                }
            }
        }
        .screenInsets()
        .background(Palette.bg)
    }

    private func card(_ title: String, _ v: Double, peak: Double, _ c: Color, _ t: Double) -> some View {
        let shown = v * ease(reveal(t, 1.2))
        return Panel(title: title, tint: c) {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)
                BigDigits(text: String(format: "%5.1f", min(shown, 9999.9)), color: c, cell: 12)
                HStack(spacing: 18) {
                    Text("Mbps").font(mono(14, .medium)).foregroundStyle(c.opacity(0.8))
                    Spacer()
                    Text("PEAK").foregroundStyle(Palette.dim)
                    Text(fmt(peak)).foregroundStyle(c.opacity(0.8))
                }
                .font(mono(11))
                .opacity(reveal(t - 0.8, 0.3))
                Spacer(minLength: 0)
            }
        }
        .overlay(GlitchBars(amount: t > -0.4 && t < 0 ? -t / 0.4 : 0, seed: Int(t * 30), tint: c))
        .opacity(t > -0.4 ? 1 : 0)
    }

    private func pingCard(_ t: Double) -> some View {
        let shown = r.ping * ease(reveal(t, 0.8))
        return Panel(title: "PING", tint: Palette.text) {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)
                BigDigits(text: String(format: "%3.0f", shown), color: Palette.text, cell: 9)
                Text("ms").font(mono(14, .medium)).foregroundStyle(Palette.text.opacity(0.8))
                Spacer(minLength: 0)
            }
        }
        .frame(width: 180)
        .overlay(GlitchBars(amount: t > -0.4 && t < 0 ? -t / 0.4 : 0, seed: Int(t * 30), tint: Palette.text))
        .opacity(t > -0.4 ? 1 : 0)
    }

    private func reveal(_ t: Double, _ d: Double) -> Double {
        min(max(t / d, 0), 1)
    }

    private func ease(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }
}

// MARK: - Effects

/// CRT power-off: glitch → collapse to a glowing scanline → shrink to a dot. Reversed on insertion.
struct CRT: ViewModifier, Animatable {
    var p: Double

    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        let g = min(p / 0.25, 1)
        let y = clamp((p - 0.25) / 0.45)
        let x = clamp((p - 0.7) / 0.3)
        content
            .overlay(GlitchBars(amount: g * (1 - y), seed: Int(p * 60), tint: Palette.down))
            .overlay(Palette.text.opacity(y * 0.95))
            .offset(x: p > 0 && p < 0.3 ? CGFloat(sin(p * 173)) * 12 * g : 0)
            .scaleEffect(x: max(1 - x * 0.995, 0.001), y: max(1 - y, 0.003))
            .shadow(color: Palette.down.opacity(y), radius: 14 * y)
            .opacity(1 - x * x)
            .allowsHitTesting(p == 0)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

extension AnyTransition {
    static var crt: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: CRT(p: 1), identity: CRT(p: 0))
                .animation(.easeOut(duration: 0.5).delay(0.45)),
            removal: .modifier(active: CRT(p: 1), identity: CRT(p: 0))
                .animation(.easeIn(duration: 0.45))
        )
    }
}

/// Short burst of glitch bars after `since`.
struct Glitch: View {
    let since: Date
    let tint: Color
    var duration = 0.35

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Date().timeIntervalSince(since) > duration)) { tl in
            let t = tl.date.timeIntervalSince(since)
            GlitchBars(amount: t < duration ? 1 - t / duration : 0, seed: Int(t * 30), tint: tint)
        }
        .allowsHitTesting(false)
    }
}

struct GlitchBars: View {
    let amount: Double
    let seed: Int
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            guard amount > 0.01 else { return }
            var rng = SplitMix(s: UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9 &+ 1)
            for _ in 0..<Int(4 + amount * 16) {
                let r = CGRect(
                    x: rng.unit() * size.width * 0.6,
                    y: rng.unit() * size.height,
                    width: size.width * (0.1 + rng.unit() * 0.6),
                    height: 1 + rng.unit() * 10 * amount
                )
                let c = rng.unit() < 0.25 ? Color.white : tint
                ctx.fill(Path(r), with: .color(c.opacity(0.1 + 0.5 * amount * rng.unit())))
            }
            for _ in 0..<Int(amount * 160) {
                let r = CGRect(x: rng.unit() * size.width, y: rng.unit() * size.height, width: 2, height: 2)
                ctx.fill(Path(r), with: .color(.white.opacity(0.45 * amount)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SplitMix {
    var s: UInt64

    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
