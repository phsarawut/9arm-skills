import SwiftUI

// MARK: - Complex Number

struct Complex {
    var re: Double
    var im: Double

    init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    var magnitude: Double { (re * re + im * im).squareRoot() }
    var magnitudeSquared: Double { re * re + im * im }
    var angle: Double { atan2(im, re) }

    static func + (lhs: Complex, rhs: Complex) -> Complex { Complex(lhs.re + rhs.re, lhs.im + rhs.im) }
    static func - (lhs: Complex, rhs: Complex) -> Complex { Complex(lhs.re - rhs.re, lhs.im - rhs.im) }
    static func * (lhs: Complex, rhs: Complex) -> Complex {
        Complex(lhs.re * rhs.re - lhs.im * rhs.im,
                lhs.re * rhs.im + lhs.im * rhs.re)
    }
    static func / (lhs: Complex, rhs: Complex) -> Complex {
        let d = rhs.magnitudeSquared
        guard d > 1e-300 else { return Complex(.infinity, .infinity) }
        return Complex((lhs.re * rhs.re + lhs.im * rhs.im) / d,
                       (lhs.im * rhs.re - lhs.re * rhs.im) / d)
    }
    static func + (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re + rhs, lhs.im) }
    static func - (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re - rhs, lhs.im) }
    static func * (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re * rhs, lhs.im * rhs) }

    static func polar(r: Double, theta: Double) -> Complex {
        Complex(r * cos(theta), r * sin(theta))
    }
}

// MARK: - Smith Chart Engine

struct SmithChartEngine {
    static func normalize(_ Z: Complex, z0: Double = 50) -> Complex {
        Complex(Z.re / z0, Z.im / z0)
    }

    /// Γ = (zn − 1) / (zn + 1)
    static func gamma(zn: Complex) -> Complex {
        (zn - 1.0) / (zn + 1.0)
    }

    /// zn = (1 + Γ) / (1 − Γ)
    static func zFromGamma(_ g: Complex) -> Complex {
        (Complex(1, 0) + g) / (Complex(1, 0) - g)
    }

    /// yn = 1 / zn
    static func admittance(_ zn: Complex) -> Complex {
        Complex(1, 0) / zn
    }

    /// Map Γ → screen point (Im axis flipped: positive Im → upward)
    static func toScreen(_ g: Complex, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(g.re) * radius,
                y: center.y - CGFloat(g.im) * radius)
    }

    /// Rotate Γ along constant-|Γ| circle (T-line toward generator)
    /// Γ_new = Γ · e^{−j2θ}
    static func tLineRotate(_ g: Complex, theta: Double) -> Complex {
        g * Complex.polar(r: 1, theta: -2 * theta)
    }

    static func addSeriesX(_ zn: Complex, dx: Double) -> Complex { Complex(zn.re, zn.im + dx) }
    static func addShuntB(_ yn: Complex, db: Double) -> Complex  { Complex(yn.re, yn.im + db) }
}

// MARK: - Marker Info

struct MarkerInfo: Identifiable {
    let id = UUID()
    var index: Int
    var gamma: Complex
    var zn: Complex
    var z0: Double

    var Z: Complex  { Complex(zn.re * z0, zn.im * z0) }
    var yn: Complex { SmithChartEngine.admittance(zn) }
    var swr: Double {
        let m = gamma.magnitude
        return m < 1 ? (1 + m) / (1 - m) : .infinity
    }
}

// MARK: - View Model

final class SmithChartVM: ObservableObject {
    @Published var z0: Double = 50

    // ① Load
    @Published var loadR: Double = 20
    @Published var loadX: Double = 50

    // ① → ② Shunt susceptance (normalised) — constant-g arc
    @Published var shuntB: Double = 1.15

    // ② → ③ Series reactance (normalised) — constant-r arc
    @Published var seriesX: Double = -1.1

    // ③ → ④ Transmission line (degrees)
    @Published var tLineDeg: Double = 55

    @Published var showY: Bool    = true
    @Published var showTLine: Bool = true

    // MARK: Markers ① → ② → ③ → ④
    var markers: [MarkerInfo] {
        var result: [MarkerInfo] = []

        // ① Load
        let zn1 = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        result.append(MarkerInfo(index: 0, gamma: SmithChartEngine.gamma(zn: zn1), zn: zn1, z0: z0))

        // ② After shunt B
        let yn1 = SmithChartEngine.admittance(zn1)
        let yn2 = SmithChartEngine.addShuntB(yn1, db: shuntB)
        let zn2 = SmithChartEngine.admittance(yn2)
        result.append(MarkerInfo(index: 1, gamma: SmithChartEngine.gamma(zn: zn2), zn: zn2, z0: z0))

        // ③ After series X
        let zn3 = SmithChartEngine.addSeriesX(zn2, dx: seriesX)
        result.append(MarkerInfo(index: 2, gamma: SmithChartEngine.gamma(zn: zn3), zn: zn3, z0: z0))

        // ④ After T-line
        if showTLine {
            let g3  = SmithChartEngine.gamma(zn: zn3)
            let g4  = SmithChartEngine.tLineRotate(g3, theta: tLineDeg * .pi / 180)
            let zn4 = SmithChartEngine.zFromGamma(g4)
            result.append(MarkerInfo(index: 3, gamma: g4, zn: zn4, z0: z0))
        }
        return result
    }

    // MARK: Fine-step trajectory interpolation (120 pts/segment)
    func trajectorySegments(center: CGPoint, radius: CGFloat) -> [[CGPoint]] {
        guard markers.count >= 3 else { return [] }
        let N = 120
        var segs: [[CGPoint]] = []

        let zn1 = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        let yn1 = SmithChartEngine.admittance(zn1)

        // ① → ② shunt B (constant-g arc)
        segs.append((0...N).map { i in
            let t   = Double(i) / Double(N)
            let yn  = SmithChartEngine.addShuntB(yn1, db: shuntB * t)
            let zn  = SmithChartEngine.admittance(yn)
            return SmithChartEngine.toScreen(SmithChartEngine.gamma(zn: zn),
                                             center: center, radius: radius)
        })

        // ② → ③ series X (constant-r arc)
        let yn2 = SmithChartEngine.addShuntB(yn1, db: shuntB)
        let zn2 = SmithChartEngine.admittance(yn2)
        segs.append((0...N).map { i in
            let t  = Double(i) / Double(N)
            let zn = SmithChartEngine.addSeriesX(zn2, dx: seriesX * t)
            return SmithChartEngine.toScreen(SmithChartEngine.gamma(zn: zn),
                                             center: center, radius: radius)
        })

        // ③ → ④ T-line (constant-|Γ| arc)
        if showTLine, markers.count == 4 {
            let g3    = markers[2].gamma
            let total = tLineDeg * .pi / 180
            segs.append((0...N).map { i in
                let t = Double(i) / Double(N)
                let g = SmithChartEngine.tLineRotate(g3, theta: total * t)
                return SmithChartEngine.toScreen(g, center: center, radius: radius)
            })
        }
        return segs
    }
}

// MARK: - Smith Chart Canvas

struct SmithChartCanvas: View {
    @ObservedObject var vm: SmithChartVM
    let size: CGFloat

    private var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    private var radius: CGFloat { size * 0.455 }

    private let zColor = Color(red: 0.85, green: 0.45, blue: 0.45)
    private let yColor = Color(red: 0.45, green: 0.65, blue: 0.90)
    private let segColors: [Color] = [
        Color(red: 0.20, green: 0.50, blue: 1.00),
        Color(red: 0.20, green: 0.50, blue: 1.00),
        Color(red: 0.20, green: 0.75, blue: 0.45)
    ]

    var body: some View {
        Canvas { ctx, _ in
            let c = center, r = radius
            drawBG(ctx, c, r)
            if vm.showY { drawYGrid(ctx, c, r) }
            drawZGrid(ctx, c, r)
            drawOuterRing(ctx, c, r)
            drawTrajectory(ctx, c, r)
            drawMarkers(ctx, c, r)
        }
        .frame(width: size, height: size)
    }

    // MARK: Background
    private func drawBG(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var bg = Path(); bg.addEllipse(in: rect(c, r))
        ctx.fill(bg, with: .color(Color(white: 0.07)))
        var ax = Path()
        ax.move(to: CGPoint(x: c.x - r, y: c.y))
        ax.addLine(to: CGPoint(x: c.x + r, y: c.y))
        ctx.stroke(ax, with: .color(.gray.opacity(0.45)), lineWidth: 0.5)
    }

    // MARK: Outer ring + SWR circles
    private func drawOuterRing(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var p = Path(); p.addEllipse(in: rect(c, r))
        ctx.stroke(p, with: .color(.gray), lineWidth: 1.5)
        for mag in [1.0/3.0, 0.5, 2.0/3.0] {
            var s = Path(); s.addEllipse(in: rect(c, r * CGFloat(mag)))
            ctx.stroke(s, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
    }

    // MARK: Z grid
    private func drawZGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let rVals: [Double] = [0, 0.2, 0.5, 1, 2, 5, 10]
        for rv in rVals {
            let cr = CGFloat(rv / (rv + 1))
            let rr = CGFloat(1.0 / (rv + 1))
            var p = Path()
            p.addEllipse(in: CGRect(x: c.x + (cr - rr) * r,
                                    y: c.y       - rr  * r,
                                    width: rr * r * 2, height: rr * r * 2))
            ctx.stroke(p, with: .color(zColor.opacity(0.75)),
                       lineWidth: rv == 1 ? 1.1 : 0.65)
        }
        var clip = Path(); clip.addEllipse(in: rect(c, r))
        for x in [0.2, 0.5, 1.0, 2.0, 5.0] {
            drawXArc(ctx, x:  x, c: c, r: r, clip: clip)
            drawXArc(ctx, x: -x, c: c, r: r, clip: clip)
        }
        drawRLabel(ctx, "0",   gRe: -1.00, c: c, r: r, dx:  10, dy: -10)
        drawRLabel(ctx, "0.5", gRe:  0.00, c: c, r: r, dx:  -4, dy: -11)
        drawRLabel(ctx, "1",   gRe:  0.00, c: c, r: r, dx:  14, dy: -11)
        drawRLabel(ctx, "2",   gRe:  0.50, c: c, r: r, dx:   4, dy: -11)
        drawRLabel(ctx, "5",   gRe:  0.80, c: c, r: r, dx:   3, dy: -11)
    }

    private func drawXArc(_ ctx: GraphicsContext, x: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let rr = CGFloat(abs(1.0 / x))
        let cy = CGFloat(1.0 / x)
        var arc = Path()
        arc.addEllipse(in: CGRect(x: c.x + (1.0 - rr) * r,
                                  y: c.y - (cy + rr.magnitude) * r,
                                  width: rr * r * 2, height: rr * r * 2))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(zColor.opacity(0.6)), lineWidth: 0.65)
    }

    private func drawRLabel(_ ctx: GraphicsContext, _ text: String, gRe: Double,
                             c: CGPoint, r: CGFloat, dx: CGFloat, dy: CGFloat) {
        let pt = SmithChartEngine.toScreen(Complex(gRe, 0), center: c, radius: r)
        ctx.draw(
            Text(text).font(.system(size: 8, design: .monospaced)).foregroundColor(.gray.opacity(0.7)),
            at: CGPoint(x: pt.x + dx, y: pt.y + dy)
        )
    }

    // MARK: Y grid
    private func drawYGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let gVals: [Double] = [0.2, 0.5, 1, 2, 5]
        for g in gVals {
            let cr = CGFloat(-g / (g + 1))
            let rr = CGFloat(1.0 / (g + 1))
            var p = Path()
            p.addEllipse(in: CGRect(x: c.x + (cr - rr) * r,
                                    y: c.y       - rr  * r,
                                    width: rr * r * 2, height: rr * r * 2))
            ctx.stroke(p, with: .color(yColor.opacity(0.55)), lineWidth: 0.65)
        }
        var clip = Path(); clip.addEllipse(in: rect(c, r))
        for b in [0.2, 0.5, 1.0, 2.0, 5.0] {
            drawBArc(ctx, b:  b, c: c, r: r, clip: clip)
            drawBArc(ctx, b: -b, c: c, r: r, clip: clip)
        }
    }

    private func drawBArc(_ ctx: GraphicsContext, b: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let rr = CGFloat(abs(1.0 / b))
        let cy = CGFloat(-1.0 / b)
        var arc = Path()
        arc.addEllipse(in: CGRect(x: c.x + (-1.0 - rr) * r,
                                  y: c.y - (cy + rr.magnitude) * r,
                                  width: rr * r * 2, height: rr * r * 2))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(yColor.opacity(0.45)), lineWidth: 0.65)
    }

    // MARK: Trajectory
    private func drawTrajectory(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let segs = vm.trajectorySegments(center: c, radius: r)
        for (i, seg) in segs.enumerated() {
            guard seg.count > 1 else { continue }
            var p = Path(); p.move(to: seg[0])
            seg.dropFirst().forEach { p.addLine(to: $0) }
            let col = segColors[min(i, segColors.count - 1)]
            ctx.stroke(p, with: .color(col),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // Arrow head at segment end
            if seg.count >= 2 {
                drawArrow(ctx, from: seg[seg.count - 2], to: seg.last!, color: col)
            }
        }
    }

    private func drawArrow(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = (dx*dx + dy*dy).squareRoot(); guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let sz: CGFloat = 9
        let l  = CGPoint(x: to.x - sz * ux + sz * 0.5 * uy, y: to.y - sz * uy - sz * 0.5 * ux)
        let r2 = CGPoint(x: to.x - sz * ux - sz * 0.5 * uy, y: to.y - sz * uy + sz * 0.5 * ux)
        var p = Path(); p.move(to: l); p.addLine(to: to); p.addLine(to: r2)
        ctx.stroke(p, with: .color(color), lineWidth: 2)
    }

    // MARK: Markers
    private func drawMarkers(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let symbols = ["①", "②", "③", "④"]
        let colors: [Color] = [.cyan, .cyan, .cyan, .cyan]
        for m in vm.markers {
            let pt  = SmithChartEngine.toScreen(m.gamma, center: c, radius: r)
            let col = colors[min(m.index, colors.count - 1)]
            var glow = Path(); glow.addEllipse(in: CGRect(x: pt.x-9, y: pt.y-9, width: 18, height: 18))
            ctx.fill(glow, with: .color(col.opacity(0.2)))
            var dot = Path(); dot.addEllipse(in: CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10))
            ctx.fill(dot, with: .color(col))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1.2)
            ctx.draw(
                Text(symbols[m.index]).font(.system(size: 14, weight: .bold)).foregroundColor(col),
                at: CGPoint(x: pt.x + 14, y: pt.y - 10)
            )
        }
    }

    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
}

// MARK: - Marker Row

struct MarkerRow: View {
    let m: MarkerInfo
    private let symbols   = ["①", "②", "③", "④"]
    private let stepNames = ["Load ZL", "After Shunt B", "After Series X", "After T-Line"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(symbols[m.index]).font(.title3.bold()).foregroundColor(.cyan)
                Text(stepNames[min(m.index, stepNames.count - 1)])
                    .font(.caption.bold()).foregroundColor(.cyan.opacity(0.85))
            }
            row("Zn",  fmtC(m.zn))
            row("Z",   fmtC(m.Z) + " Ω")
            row("Yn",  fmtC(m.yn))
            row("|Γ|", String(format: "%.4f", m.gamma.magnitude))
            row("∠Γ",  String(format: "%.1f°", m.gamma.angle * 180 / .pi))
            row("SWR", m.swr.isInfinite ? "∞" : String(format: "%.2f", m.swr))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.14)))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label + ": ")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
        }
    }

    private func fmtC(_ c: Complex) -> String {
        let sign = c.im >= 0 ? "+" : "−"
        return String(format: "%.3f %@ j%.3f", c.re, sign, abs(c.im))
    }
}

// MARK: - Slider Row

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var color: Color = .cyan

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(color)
            }
            Slider(value: $value, in: range).tint(color)
        }
    }
}

// MARK: - Content View (Root)

struct ContentView: View {
    @StateObject private var vm = SmithChartVM()

    // Adaptive chart size
    var chartSize: CGFloat {
        #if os(iOS)
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.58
        #else
        400
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape / iPad split
                HStack(alignment: .top, spacing: 0) {
                    chartPanel
                    controlPanel
                }
            } else {
                // Portrait: chart on top, controls below
                VStack(spacing: 0) {
                    chartPanel
                    controlPanel
                }
            }
        }
        .background(Color(white: 0.08))
        .preferredColorScheme(.dark)
    }

    // MARK: Chart panel
    private var chartPanel: some View {
        VStack(spacing: 6) {
            Text("Smith Chart — Impedance Matching")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            SmithChartCanvas(vm: vm, size: chartSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .padding(4)

            // Legend
            HStack(spacing: 14) {
                legendItem(color: Color(red: 0.2, green: 0.5, blue: 1),     label: "①→② Shunt B")
                legendItem(color: Color(red: 0.2, green: 0.5, blue: 1),     label: "②→③ Series X")
                legendItem(color: Color(red: 0.2, green: 0.75, blue: 0.45), label: "③→④ T-Line")
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.8))
        }
        .padding()
    }

    // MARK: Control panel
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Toggles
                sectionLabel("Display")
                Toggle("Admittance (Y) Grid [blue]", isOn: $vm.showY)
                    .font(.system(size: 12)).foregroundColor(.white)
                Toggle("Transmission Line segment ④", isOn: $vm.showTLine)
                    .font(.system(size: 12)).foregroundColor(.white)

                div()

                sectionLabel("① Load Impedance  (Z₀ = 50 Ω)")
                SliderRow(label: "R (Ω)", value: $vm.loadR, range: 1...500,    format: "%.0f Ω")
                SliderRow(label: "X (Ω)", value: $vm.loadX, range: -300...300, format: "%.0f Ω")

                div()

                sectionLabel("① → ② Shunt Susceptance")
                Text("Constant-g arc • +B = capacitive shunt")
                    .font(.system(size: 10)).foregroundColor(.gray)
                SliderRow(label: "ΔB (norm)", value: $vm.shuntB, range: -5...5, format: "%.3f",
                          color: Color(red: 0.2, green: 0.5, blue: 1))

                div()

                sectionLabel("② → ③ Series Reactance")
                Text("Constant-r arc • +X = series inductor")
                    .font(.system(size: 10)).foregroundColor(.gray)
                SliderRow(label: "ΔX (norm)", value: $vm.seriesX, range: -5...5, format: "%.3f",
                          color: Color(red: 0.2, green: 0.5, blue: 1))

                if vm.showTLine {
                    div()
                    sectionLabel("③ → ④ Transmission Line")
                    Text("Constant-|Γ| rotation toward generator")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    SliderRow(label: "θ (°)", value: $vm.tLineDeg, range: 0...360, format: "%.1f°",
                              color: Color(red: 0.2, green: 0.75, blue: 0.45))
                }

                div()

                sectionLabel("Marker Readouts")
                ForEach(vm.markers) { m in
                    MarkerRow(m: m)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: 300)
        .background(Color(white: 0.10))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    @ViewBuilder private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.cyan)
    }

    @ViewBuilder private func div() -> some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
}
