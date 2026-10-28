import AppKit
import SwiftUI

@main
struct SpeedtestApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate

    var body: some Scene {
        Window("SPEEDTEST", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.async {
            for w in NSApp.windows {
                w.isMovableByWindowBackground = true
                w.backgroundColor = .black
                w.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ n: Notification) { sc_stop() }
}

// MARK: - Engine

enum Mode: UInt32, CaseIterable {
    case down = 0, up = 1, alt = 2

    var key: String { ["D", "U", "A"][Int(rawValue)] }
    var label: String { ["▼ DOWN", "▲ UP", "⇅ ALT"][Int(rawValue)] }
}

struct Sample {
    let v: Double
    let up: Bool
}

struct LogRow: Identifiable {
    let id: Int
    let down: Double
    let up: Double
    let ping: Double
}

struct Report {
    let id: Int
    let mode: Mode
    let down: Double
    let up: Double
    let ping: Double
    let samples: [Sample]
    let date: Date

    func peak(up: Bool) -> Double {
        samples.filter { $0.up == up }.map(\.v).max() ?? 0
    }
}

@MainActor
final class Engine: ObservableObject {
    @Published var mode: Mode = .alt
    @Published private(set) var st = ScStatus()
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var log: [LogRow] = []
    @Published private(set) var result: Report?
    @Published private(set) var shown: Double = 0
    @Published private(set) var ticks = 0
    @Published private(set) var glitchAt = Date.distantPast

    private var runs = 0
    private var runMode: Mode = .alt
    private var wasRunning = false
    private var lastUp = false
    private var timer: Timer?
    private var monitor: Any?

    var running: Bool { st.running != 0 }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self,
                  ev.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let c = ev.charactersIgnoringModifiers?.lowercased()
            else { return ev }
            switch c {
            case "d": self.select(.down)
            case "u": self.select(.up)
            case "a": self.select(.alt)
            case " ": self.result == nil ? self.toggle() : self.retest()
            case "\r": self.result == nil ? self.toggle() : self.close()
            case "\u{1b}": self.close()
            default: return ev
            }
            return nil
        }
    }

    func select(_ m: Mode) {
        if !running && result == nil { mode = m }
    }

    func toggle() {
        if running {
            sc_stop()
        } else {
            samples.removeAll()
            shown = 0
            lastUp = mode == .up
            runMode = mode
            sc_start(mode.rawValue)
            tick()
        }
    }

    func close() {
        guard result != nil else { return }
        withAnimation { result = nil }
    }

    func retest() {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.running else { return }
            self.toggle()
        }
    }

    private func tick() {
        var s = ScStatus()
        sc_status(&s)
        ticks &+= 1

        let active = s.phase == 2 || s.phase == 3
        if active {
            lastUp = s.phase == 3
            if ticks % 2 == 0 {
                samples.append(Sample(v: s.mbps, up: lastUp))
                if samples.count > 400 { samples.removeFirst(samples.count - 400) }
            }
        }
        if s.running != 0 && s.phase != st.phase {
            glitchAt = Date()
        }

        let isRunning = s.running != 0
        if wasRunning && !isRunning && s.error == 0 && s.cycle > 0 {
            runs += 1
            log.insert(LogRow(id: runs, down: s.down_mbps, up: s.up_mbps, ping: s.ping_ms), at: 0)
            let r = Report(
                id: runs, mode: runMode, down: s.down_mbps, up: s.up_mbps,
                ping: s.ping_ms, samples: samples, date: Date()
            )
            withAnimation { result = r }
        }
        wasRunning = isRunning

        let target = active ? s.mbps : (lastUp ? s.up_mbps : s.down_mbps)
        shown += (target - shown) * 0.22
        if abs(target - shown) < 0.05 { shown = target }
        st = s
    }

    var blink: Bool { (ticks / 10) % 2 == 0 }

    var accent: Color {
        if st.error != 0 { return Palette.err }
        return lastUp ? Palette.up : Palette.down
    }
}
