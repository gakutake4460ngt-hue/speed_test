import SwiftUI

enum Palette {
    static let bg = Color(hex: 0x04080A)
    static let line = Color(hex: 0x17322F)
    static let dim = Color(hex: 0x3D6B65)
    static let text = Color(hex: 0xA6EFE3)
    static let down = Color(hex: 0x2EF2E0)
    static let up = Color(hex: 0xFFA41C)
    static let err = Color(hex: 0xFF3B5C)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

func fmt(_ v: Double, _ f: String = "%.1f") -> String {
    v > 0 ? String(format: f, v) : "---"
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var e = Engine()

    var body: some View {
        ZStack {
            Palette.bg
            if let r = e.result {
                ResultView(r: r, retest: e.retest, close: e.close)
                    .id(r.id)
                    .transition(.crt)
            } else {
                monitor.transition(.crt)
            }
            Scanlines()
        }
        .ignoresSafeArea()
        .frame(width: 860, height: 560)
        .preferredColorScheme(.dark)
    }

    private var monitor: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 14) {
                readout
                logPanel.frame(width: 230)
            }
            .frame(height: 230)
            Panel(title: "TRACE", tint: Palette.dim) {
                Trace(samples: e.samples)
            }
            footer
        }
        .screenInsets()
        .background(Palette.bg)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            Brand()
            Spacer()
            pipeline
            Circle()
                .fill(e.running && e.blink ? e.accent : Palette.line)
                .frame(width: 7, height: 7)
                .shadow(color: e.accent, radius: e.running && e.blink ? 4 : 0)
        }
        .frame(height: 22)
    }

    private var pipeline: some View {
        let steps: [(String, UInt32, Bool)] = [
            ("PING", 1, true),
            ("DOWN", 2, e.mode != .up),
            ("UP", 3, e.mode != .down),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                if i > 0 { Text("─").foregroundStyle(Palette.line) }
                let on = e.running && e.st.phase == s.1
                Text(s.0)
                    .foregroundStyle(on ? phaseColor(s.1) : s.2 ? Palette.dim : Palette.line)
                    .shadow(color: on ? phaseColor(s.1) : .clear, radius: 4)
            }
        }
        .font(mono(11, .medium))
    }

    private func phaseColor(_ p: UInt32) -> Color {
        p == 3 ? Palette.up : p == 2 ? Palette.down : Palette.text
    }

    // MARK: readout

    private var phaseTitle: String {
        if e.st.error != 0 { return "LINK ERROR" }
        switch e.st.phase {
        case 1: return "PING"
        case 2: return "▼ DOWNLINK"
        case 3: return "▲ UPLINK"
        default: return e.running ? "STANDBY" : "IDLE"
        }
    }

    private var readout: some View {
        Panel(title: phaseTitle, tint: e.accent) {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 14) {
                    BigDigits(text: bigText, color: e.accent)
                    Text(e.st.phase == 1 ? "ms" : "Mbps")
                        .font(mono(15, .medium))
                        .foregroundStyle(e.accent.opacity(0.8))
                        .padding(.bottom, 2)
                }
                progress
                Spacer(minLength: 0)
                HStack(spacing: 26) {
                    stat("PING", fmt(e.st.ping_ms), "ms", Palette.text)
                    stat("▼", fmt(e.st.down_mbps), "Mbps", Palette.down)
                    stat("▲", fmt(e.st.up_mbps), "Mbps", Palette.up)
                    Spacer()
                }
            }
            .padding(.horizontal, 6)
        }
        .overlay(Glitch(since: e.glitchAt, tint: e.accent))
    }

    private var bigText: String {
        if e.st.phase == 1 { return "---.-" }
        let v = min(e.shown, 9999.9)
        return v > 0 ? String(format: "%5.1f", v) : "  0.0"
    }

    private var progress: some View {
        let cells = 40
        let active = e.running && e.st.phase != 0
        let p = active ? e.st.progress : 0
        let n = Int((p * Double(cells)).rounded())
        return HStack(spacing: 8) {
            Text(String(repeating: "█", count: n) + String(repeating: "░", count: cells - n))
                .foregroundStyle(active ? e.accent : Palette.line)
            Text(String(format: "%3d%%", Int(p * 100)))
                .foregroundStyle(Palette.dim)
        }
        .font(mono(10))
    }

    private func stat(_ k: String, _ v: String, _ unit: String, _ c: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(k).foregroundStyle(c.opacity(0.75))
            Text(v).font(mono(15, .semibold)).foregroundStyle(c)
            Text(unit).foregroundStyle(Palette.dim)
        }
        .font(mono(10))
    }

    // MARK: log

    private var logPanel: some View {
        Panel(title: "LOG", tint: Palette.dim) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    col("#", 26, Palette.dim)
                    col("▼", 62, Palette.down.opacity(0.7))
                    col("▲", 62, Palette.up.opacity(0.7))
                    col("ms", 40, Palette.dim)
                }
                Rectangle().fill(Palette.line).frame(height: 1)
                ForEach(e.log.prefix(11)) { r in
                    HStack(spacing: 0) {
                        col(String(format: "%02ld", r.id), 26, Palette.dim)
                        col(fmt(r.down), 62, Palette.down)
                        col(fmt(r.up), 62, Palette.up)
                        col(fmt(r.ping, "%.0f"), 40, Palette.text.opacity(0.7))
                    }
                    .opacity(r.id == e.log.first?.id ? 1 : 0.6)
                }
                Spacer(minLength: 0)
            }
            .font(mono(11))
        }
    }

    private func col(_ s: String, _ w: CGFloat, _ c: Color) -> some View {
        Text(s).foregroundStyle(c).frame(width: w, alignment: .trailing)
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases, id: \.rawValue) { m in
                Key(key: m.key, label: m.label, on: e.mode == m, locked: e.running) { e.select(m) }
            }
            Spacer()
            Key(
                key: "SPACE",
                label: e.running ? "■ STOP" : "▶ START",
                on: e.running,
                locked: false,
                tint: e.running ? e.accent : Palette.text
            ) { e.toggle() }
        }
    }
}

// MARK: - Components

struct Panel<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().stroke(Palette.line, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                Text("┤ \(title) ├")
                    .font(mono(10, .bold))
                    .kerning(1.5)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 2)
                    .background(Palette.bg)
                    .offset(x: 12, y: -7)
            }
            .overlay(alignment: .topTrailing) { corner }
            .overlay(alignment: .bottomLeading) { corner.rotationEffect(.degrees(180)) }
    }

    private var corner: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 10, y: 0))
            p.addLine(to: CGPoint(x: 10, y: 10))
        }
        .stroke(tint.opacity(0.8), lineWidth: 1.5)
        .frame(width: 10, height: 10)
    }
}

struct Key: View {
    let key: String
    let label: String
    let on: Bool
    let locked: Bool
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(mono(9, .bold))
                .foregroundStyle(on ? Palette.bg : Palette.dim)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(on ? tint : Palette.line)
            Text(label)
                .font(mono(11, .medium))
                .foregroundStyle(on ? tint : Palette.dim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(Rectangle().stroke(on ? tint.opacity(0.6) : Palette.line, lineWidth: 1))
        .shadow(color: on ? tint.opacity(0.5) : .clear, radius: 5)
        .opacity(locked && !on ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 3x5 dot-matrix numerals with ghosted unlit cells.
struct BigDigits: View {
    let text: String
    let color: Color

    private static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", "###", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", "..#", "..#", "..#"],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
        "-": ["...", "...", "###", "...", "..."],
        " ": ["...", "...", "...", "...", "..."],
        ".": [".", ".", ".", ".", "#"],
    ]

    var cell: CGFloat = 13
    private var gap: CGFloat { (cell * 0.15).rounded() }

    private var cols: [[String]] {
        text.map { Self.glyphs[$0] ?? Self.glyphs[" "]! }
    }

    private var width: CGFloat {
        let n = cols.reduce(0) { $0 + $1[0].count }
        return CGFloat(n) * (cell + gap) + CGFloat(cols.count - 1) * cell * 0.6
    }

    var body: some View {
        Canvas { ctx, _ in
            var x: CGFloat = 0
            for g in cols {
                for (row, line) in g.enumerated() {
                    for (c, ch) in line.enumerated() {
                        let r = CGRect(
                            x: x + CGFloat(c) * (cell + gap),
                            y: CGFloat(row) * (cell + gap),
                            width: cell, height: cell
                        )
                        ctx.fill(Path(r), with: .color(ch == "#" ? color : color.opacity(0.06)))
                    }
                }
                x += CGFloat(g[0].count) * (cell + gap) + cell * 0.6
            }
        }
        .frame(width: width, height: 5 * (cell + gap))
        .shadow(color: color.opacity(0.55), radius: 9)
    }
}

/// Mirrored LED-bar trace: uplink above the axis, downlink below, each on its own scale.
struct Trace: View {
    let samples: [Sample]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step: CGFloat = 5, rowStep: CGFloat = 4
            let count = Int(w / step)
            let visible = samples.suffix(count)
            let peakUp = max(visible.filter(\.up).map(\.v).max() ?? 0, 1) * 1.1
            let peakDown = max(visible.filter { !$0.up }.map(\.v).max() ?? 0, 1) * 1.1
            let mid = (h / 2).rounded()
            let rows = Int((mid - 2) / rowStep)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for x in stride(from: 0, to: w, by: step * 8) {
                        for y in stride(from: mid.truncatingRemainder(dividingBy: rowStep * 4), to: h, by: rowStep * 4) {
                            ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Palette.line))
                        }
                    }
                    ctx.fill(Path(CGRect(x: 0, y: mid, width: w, height: 1)), with: .color(Palette.line))

                    for (i, s) in visible.enumerated() {
                        let x = CGFloat(i) * step
                        let peak = s.up ? peakUp : peakDown
                        let lit = Int((s.v / peak * Double(rows)).rounded())
                        let c = s.up ? Palette.up : Palette.down
                        let head = i == visible.count - 1
                        for r in 0..<lit {
                            let y = s.up ? mid - CGFloat(r + 1) * rowStep : mid + 2 + CGFloat(r) * rowStep
                            let a = head ? 1 : 0.35 + 0.55 * Double(r + 1) / Double(max(lit, 1))
                            ctx.fill(Path(CGRect(x: x, y: y, width: step - 1, height: rowStep - 1)), with: .color(c.opacity(a)))
                        }
                    }
                }
                .shadow(color: Palette.down.opacity(0.25), radius: 4)

                Text("▲ \(fmt(peakUp > 1.1 ? peakUp / 1.1 : 0))")
                    .foregroundStyle(Palette.up.opacity(0.7))
                Text("▼ \(fmt(peakDown > 1.1 ? peakDown / 1.1 : 0))")
                    .foregroundStyle(Palette.down.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .font(mono(9))
        }
    }
}

/// CRT scanlines + slow sweep band + vignette.
struct Scanlines: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                for y in stride(from: 0, to: size.height, by: 3) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.28)))
                }
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                let y = CGFloat(t) * (size.height + 160) - 80
                ctx.fill(
                    Path(CGRect(x: 0, y: y - 80, width: size.width, height: 160)),
                    with: .linearGradient(
                        Gradient(colors: [.clear, Palette.down.opacity(0.035), .clear]),
                        startPoint: CGPoint(x: 0, y: y - 80), endPoint: CGPoint(x: 0, y: y + 80)
                    )
                )
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(colors: [.clear, .black.opacity(0.55)]),
                        center: CGPoint(x: size.width / 2, y: size.height / 2),
                        startRadius: size.width * 0.35, endRadius: size.width * 0.75
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}
