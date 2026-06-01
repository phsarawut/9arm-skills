import SwiftUI
import PlaygroundSupport

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
    var conjugate: Complex { Complex(re, -im) }
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

    // Polar form constructor
    static func polar(r: Double, theta: Double) -> Complex {
        Complex(r * cos(theta), r * sin(theta))
    }
}

// MARK: - Smith Chart Engine

struct SmithChartEngine {
    /// Normalize: zn = Z / Z0
    static func normalize(_ Z: Complex, z0: Double = 50) -> Complex {
        Complex(Z.re / z0, Z.im / z0)
    }

    /// Γ = (zn − 1) / (zn + 1)
    static func reflectionCoeff(zn: Complex) -> Complex {
        (zn - 1.0) / (zn + 1.0)
    }

    /// zn = (1 + Γ) / (1 − Γ)
    static func impedanceFromGamma(_ g: Complex) -> Complex {
        (Complex(1, 0) + g) / (Complex(1, 0) - g)
    }

    /// yn = 1 / zn
    static func admittance(zn: Complex) -> Complex {
        Complex(1, 0) / zn
    }

    /// Map Γ → screen CGPoint (y-axis flipped: Im increases upward on chart)
    static func toScreen(_ g: Complex, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(g.re) * radius,
                y: center.y - CGFloat(g.im) * radius)
    }

    /// Rotate Γ along constant-|Γ| circle (T-line toward generator, θ in radians)
    /// Γ_new = Γ · e^{−j2θ}
    static func rotateTLine(gamma: Complex, theta: Double) -> Complex {
        gamma * Complex.polar(r: 1, theta: -2 * theta)
    }

    /// Move along constant-r circle: add series reactance Δx (normalised)
    static func addSeriesX(zn: Complex, dx: Double) -> Complex {
        Complex(zn.re, zn.im + dx)
    }

    /// Move along constant-g circle: add shunt susceptance Δb (normalised)
    static func addShuntB(yn: Complex, db: Double) -> Complex {
        Complex(yn.re, yn.im + db)
    }
}

// MARK: - Marker Info

struct MarkerInfo: Identifiable {
    let id = UUID()
    var index: Int          // 0…3
    var gamma: Complex
    var zn: Complex
    var z0: Double

    var Z: Complex { Complex(zn.re * z0, zn.im * z0) }
    var yn: Complex { SmithChartEngine.admittance(zn: zn) }
    var swr: Double {
        let m = gamma.magnitude
        return m < 1 ? (1 + m) / (1 - m) : .infinity
    }
}

// MARK: - View Model

final class SmithChartVM: ObservableObject {

    // Reference impedance
    @Published var z0: Double = 50

    // ① Load impedance
    @Published var loadR: Double = 20
    @Published var loadX: Double = 50

    // ① → ② Shunt susceptance (normalised) — moves along constant-g circle
    @Published var shuntB: Double = 1.15

    // ② → ③ Series reactance (normalised) — moves along constant-r circle
    @Published var seriesX: Double = -1.1

    // ③ → ④ Transmission line (electrical length in degrees)
    @Published var tLineDeg: Double = 55

    // Display options
    @Published var showY: Bool = true       // admittance overlay
    @Published var showTLine: Bool = true   // enable ④

    // MARK: Computed markers (① → ② → ③ → ④)
    var markers: [MarkerInfo] {
        var result: [MarkerInfo] = []

        // ① Load
        let zn1 = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        result.append(MarkerInfo(index: 0,
                                 gamma: SmithChartEngine.reflectionCoeff(zn: zn1),
                                 zn: zn1, z0: z0))

        // ② After shunt susceptance (work in Y domain, constant-g arc)
        let yn1 = SmithChartEngine.admittance(zn: zn1)
        let yn2 = SmithChartEngine.addShuntB(yn: yn1, db: shuntB)
        let zn2 = SmithChartEngine.admittance(zn: yn2)
        result.append(MarkerInfo(index: 1,
                                 gamma: SmithChartEngine.reflectionCoeff(zn: zn2),
                                 zn: zn2, z0: z0))

        // ③ After series reactance (constant-r arc)
        let zn3 = SmithChartEngine.addSeriesX(zn: zn2, dx: seriesX)
        result.append(MarkerInfo(index: 2,
                                 gamma: SmithChartEngine.reflectionCoeff(zn: zn3),
                                 zn: zn3, z0: z0))

        // ④ After transmission line (constant-|Γ| rotation)
        if showTLine {
            let g3    = SmithChartEngine.reflectionCoeff(zn: zn3)
            let g4    = SmithChartEngine.rotateTLine(gamma: g3, theta: tLineDeg * .pi / 180)
            let zn4   = SmithChartEngine.impedanceFromGamma(g4)
            result.append(MarkerInfo(index: 3, gamma: g4, zn: zn4, z0: z0))
        }
        return result
    }

    // MARK: Fine-step trajectory segments → [[CGPoint]]
    // Returns one array per segment (each ≥120 points for smooth arc)
    func trajectorySegments(center: CGPoint, radius: CGFloat) -> [[CGPoint]] {
        guard markers.count >= 3 else { return [] }
        let N = 120
        var segs: [[CGPoint]] = []

        // Segment ① → ② : shunt susceptance, constant-g arc in Γ-plane
        let zn1 = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        let yn1 = SmithChartEngine.admittance(zn: zn1)
        segs.append(interpolateShuntB(yn: yn1, deltaB: shuntB, steps: N,
                                      center: center, radius: radius))

        // Segment ② → ③ : series reactance, constant-r arc in Γ-plane
        let yn2 = SmithChartEngine.addShuntB(yn: yn1, db: shuntB)
        let zn2 = SmithChartEngine.admittance(zn: yn2)
        segs.append(interpolateSeriesX(zn: zn2, deltaX: seriesX, steps: N,
                                       center: center, radius: radius))

        // Segment ③ → ④ : T-line, constant-|Γ| arc
        if showTLine, markers.count == 4 {
            let g3 = markers[2].gamma
            segs.append(interpolateTLine(gamma: g3, degrees: tLineDeg, steps: N,
                                         center: center, radius: radius))
        }
        return segs
    }

    // Interpolate along constant-g circle (shunt B)
    private func interpolateShuntB(yn: Complex, deltaB: Double,
                                    steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...steps).map { i in
            let t  = Double(i) / Double(steps)
            let yn_t = SmithChartEngine.addShuntB(yn: yn, db: deltaB * t)
            let zn_t = SmithChartEngine.admittance(zn: yn_t)
            return SmithChartEngine.toScreen(SmithChartEngine.reflectionCoeff(zn: zn_t),
                                             center: center, radius: radius)
        }
    }

    // Interpolate along constant-r circle (series X)
    private func interpolateSeriesX(zn: Complex, deltaX: Double,
                                     steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...steps).map { i in
            let t    = Double(i) / Double(steps)
            let zn_t = SmithChartEngine.addSeriesX(zn: zn, dx: deltaX * t)
            return SmithChartEngine.toScreen(SmithChartEngine.reflectionCoeff(zn: zn_t),
                                             center: center, radius: radius)
        }
    }

    // Interpolate along constant-|Γ| circle (T-line)
    private func interpolateTLine(gamma: Complex, degrees: Double,
                                   steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        let total = degrees * .pi / 180
        return (0...steps).map { i in
            let t  = Double(i) / Double(steps)
            let g  = SmithChartEngine.rotateTLine(gamma: gamma, theta: total * t)
            return SmithChartEngine.toScreen(g, center: center, radius: radius)
        }
    }
}

// MARK: - Smith Chart Canvas

struct SmithChartCanvas: View {
    @ObservedObject var vm: SmithChartVM
    let size: CGFloat

    private var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    private var radius: CGFloat { size * 0.455 }

    // Palette matching reference image (dark background version)
    private let zGridColor  = Color(red: 0.85, green: 0.45, blue: 0.45)   // red-pink for Z
    private let yGridColor  = Color(red: 0.45, green: 0.65, blue: 0.90)   // blue for Y
    private let segColors: [Color] = [
        Color(red: 0.2, green: 0.5, blue: 1.0),   // ① → ② blue
        Color(red: 0.2, green: 0.5, blue: 1.0),   // ② → ③ blue
        Color(red: 0.2, green: 0.75, blue: 0.45)  // ③ → ④ green
    ]
    private let markerColors: [Color] = [.cyan, .cyan, .cyan, .cyan]

    var body: some View {
        Canvas { ctx, _ in
            let c = center, r = radius
            drawBackground(ctx, c, r)
            if vm.showY { drawYGrid(ctx, c, r) }
            drawZGrid(ctx, c, r)
            drawOuterRing(ctx, c, r)
            drawTrajectory(ctx, c, r)
            drawMarkers(ctx, c, r)
        }
        .frame(width: size, height: size)
    }

    // MARK: Background
    private func drawBackground(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        var bg = Path()
        bg.addEllipse(in: rect(center, r))
        ctx.fill(bg, with: .color(Color(white: 0.07)))

        // Real axis
        var ax = Path()
        ax.move(to: CGPoint(x: center.x - r, y: center.y))
        ax.addLine(to: CGPoint(x: center.x + r, y: center.y))
        ctx.stroke(ax, with: .color(.gray.opacity(0.5)), lineWidth: 0.5)
    }

    // MARK: Outer ring + SWR circles
    private func drawOuterRing(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        var p = Path(); p.addEllipse(in: rect(center, r))
        ctx.stroke(p, with: .color(.gray), lineWidth: 1.5)

        // SWR = 2 circle: |Γ| = 1/3
        let swr2r = CGFloat(1.0 / 3.0)
        var s2 = Path(); s2.addEllipse(in: rect(center, r * swr2r))
        ctx.stroke(s2, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)

        // SWR = 3 circle: |Γ| = 0.5
        var s3 = Path(); s3.addEllipse(in: rect(center, r * 0.5))
        ctx.stroke(s3, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
    }

    // MARK: Z grid (constant-R circles + constant-X arcs)
    private func drawZGrid(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        // Constant-R circles: centre (R/(R+1), 0), radius 1/(R+1)
        let rVals: [Double] = [0, 0.2, 0.5, 1, 2, 5, 10]
        for rv in rVals {
            let cr = CGFloat(rv / (rv + 1))
            let rr = CGFloat(1.0 / (rv + 1))
            var p = Path()
            p.addEllipse(in: CGRect(x: center.x + (cr - rr) * r,
                                    y: center.y       - rr  * r,
                                    width: rr * r * 2, height: rr * r * 2))
            let lw: CGFloat = rv == 1 ? 1.1 : 0.65
            ctx.stroke(p, with: .color(zGridColor.opacity(0.75)), lineWidth: lw)
        }

        // Constant-X arcs (clip to unit circle)
        let xVals: [Double] = [0.2, 0.5, 1, 2, 5]
        var clip = Path(); clip.addEllipse(in: rect(center, r))
        for x in xVals {
            drawXArc(ctx, x:  x, center: center, r: r, clip: clip)
            drawXArc(ctx, x: -x, center: center, r: r, clip: clip)
        }

        // r=0 label at left edge
        drawChartLabel(ctx, "0",   at: Complex(-1, 0),      center: center, r: r, offset: CGPoint(x: -10, y: -10))
        drawChartLabel(ctx, "0.5", at: Complex(0, 0),       center: center, r: r, offset: CGPoint(x:   0, y: -10))
        drawChartLabel(ctx, "1",   at: Complex(0, 0),       center: center, r: r, offset: CGPoint(x:  12, y: -10))
        drawChartLabel(ctx, "2",   at: Complex(0.5, 0),     center: center, r: r, offset: CGPoint(x:   4, y: -10))
    }

    private func drawXArc(_ ctx: GraphicsContext, x: Double, center: CGPoint, r: CGFloat, clip: Path) {
        // Constant-X circle: centre (1, 1/x), radius 1/|x| (in Γ-plane)
        let cy = 1.0 / x
        let rr = CGFloat(abs(1.0 / x))
        var arc = Path()
        arc.addEllipse(in: CGRect(x: center.x + (1.0 - rr) * r,
                                  y: center.y - CGFloat(cy + abs(cy)) * r,
                                  width: rr * r * 2, height: rr * r * 2))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(zGridColor.opacity(0.6)), lineWidth: 0.65)
    }

    // MARK: Y grid (constant-G circles + constant-B arcs)
    private func drawYGrid(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        // Y-grid = Z-grid rotated 180° → mirror about origin in Γ-plane
        // Constant-G circles: centre (−G/(G+1), 0), radius 1/(G+1)
        let gVals: [Double] = [0.2, 0.5, 1, 2, 5]
        for g in gVals {
            let cr = CGFloat(-g / (g + 1))
            let rr = CGFloat(1.0 / (g + 1))
            var p = Path()
            p.addEllipse(in: CGRect(x: center.x + (cr - rr) * r,
                                    y: center.y       - rr  * r,
                                    width: rr * r * 2, height: rr * r * 2))
            ctx.stroke(p, with: .color(yGridColor.opacity(0.55)), lineWidth: 0.65)
        }

        // Constant-B arcs
        let bVals: [Double] = [0.2, 0.5, 1, 2, 5]
        var clip = Path(); clip.addEllipse(in: rect(center, r))
        for b in bVals {
            drawBArc(ctx, b:  b, center: center, r: r, clip: clip)
            drawBArc(ctx, b: -b, center: center, r: r, clip: clip)
        }
    }

    private func drawBArc(_ ctx: GraphicsContext, b: Double, center: CGPoint, r: CGFloat, clip: Path) {
        // Mirror of X-arc: centre (−1, −1/b), radius 1/|b|
        let cy = -1.0 / b
        let rr = CGFloat(abs(1.0 / b))
        var arc = Path()
        arc.addEllipse(in: CGRect(x: center.x + (-1.0 - rr) * r,
                                  y: center.y - CGFloat(cy + abs(cy)) * r,
                                  width: rr * r * 2, height: rr * r * 2))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(yGridColor.opacity(0.45)), lineWidth: 0.65)
    }

    // MARK: Trajectory
    private func drawTrajectory(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        let segs = vm.trajectorySegments(center: center, radius: r)
        for (i, seg) in segs.enumerated() {
            guard seg.count > 1 else { continue }
            var p = Path()
            p.move(to: seg[0])
            seg.dropFirst().forEach { p.addLine(to: $0) }
            let color = segColors[min(i, segColors.count - 1)]
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }

        // Arrow heads on last point of each segment
        for (i, seg) in segs.enumerated() {
            guard seg.count > 2 else { continue }
            let tip  = seg.last!
            let prev = seg[seg.count - 2]
            let color = segColors[min(i, segColors.count - 1)]
            drawArrow(ctx, from: prev, to: tip, color: color)
        }
    }

    private func drawArrow(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = (dx*dx + dy*dy).squareRoot()
        guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let size: CGFloat = 8
        let l = CGPoint(x: to.x - size * ux + size * 0.5 * uy,
                        y: to.y - size * uy - size * 0.5 * ux)
        let r2 = CGPoint(x: to.x - size * ux - size * 0.5 * uy,
                         y: to.y - size * uy + size * 0.5 * ux)
        var p = Path(); p.move(to: l); p.addLine(to: to); p.addLine(to: r2)
        ctx.stroke(p, with: .color(color), lineWidth: 1.8)
    }

    // MARK: Markers
    private func drawMarkers(_ ctx: GraphicsContext, _ center: CGPoint, _ r: CGFloat) {
        let symbols = ["①", "②", "③", "④"]
        for m in vm.markers {
            let pt = SmithChartEngine.toScreen(m.gamma, center: center, radius: r)
            let col = markerColors[min(m.index, markerColors.count - 1)]

            // Outer glow ring
            var glow = Path(); glow.addEllipse(in: CGRect(x: pt.x-8, y: pt.y-8, width: 16, height: 16))
            ctx.fill(glow, with: .color(col.opacity(0.25)))

            // Filled dot
            var dot = Path(); dot.addEllipse(in: CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10))
            ctx.fill(dot, with: .color(col))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1.2)

            // Label
            ctx.draw(
                Text(symbols[m.index])
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(col),
                at: CGPoint(x: pt.x + 14, y: pt.y - 10)
            )
        }
    }

    // MARK: Helpers
    private func rect(_ center: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    }

    private func drawChartLabel(_ ctx: GraphicsContext, _ text: String,
                                 at g: Complex, center: CGPoint, r: CGFloat, offset: CGPoint) {
        let pt = SmithChartEngine.toScreen(g, center: center, radius: r)
        ctx.draw(
            Text(text).font(.system(size: 8, design: .monospaced)).foregroundColor(.gray.opacity(0.7)),
            at: CGPoint(x: pt.x + offset.x, y: pt.y + offset.y)
        )
    }
}

// MARK: - Marker Info Row

struct MarkerRow: View {
    let m: MarkerInfo
    private let colors: [Color] = [.cyan, .cyan, .cyan, .cyan]
    private let symbols = ["①", "②", "③", "④"]
    private let stepLabels = ["Load", "After Shunt B", "After Series X", "After T-Line"]

    var body: some View {
        let col = colors[min(m.index, colors.count - 1)]
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(symbols[m.index]).font(.title3.bold()).foregroundColor(col)
                Text(stepLabels[min(m.index, stepLabels.count-1)])
                    .font(.caption.bold()).foregroundColor(col.opacity(0.85))
            }
            Group {
                infoLine("Zn", value: fmtComplex(m.zn))
                infoLine("Z",  value: "\(fmtComplex(m.Z)) Ω")
                infoLine("Yn", value: fmtComplex(m.yn))
                infoLine("|Γ|", value: String(format: "%.4f", m.gamma.magnitude))
                infoLine("∠Γ", value: String(format: "%.1f°", m.gamma.angle * 180 / .pi))
                infoLine("SWR", value: m.swr.isInfinite ? "∞" : String(format: "%.2f", m.swr))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
    }

    private func infoLine(_ label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label + ": ")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func fmtComplex(_ c: Complex) -> String {
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
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(color)
            }
            Slider(value: $value, in: range)
                .accentColor(color)
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = SmithChartVM()
    let chartSize: CGFloat = 430

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // ── Left: Smith Chart ──────────────────────────────────────
            VStack(spacing: 6) {
                Text("Smith Chart — Impedance Matching")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                SmithChartCanvas(vm: vm, size: chartSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))

                // Legend
                HStack(spacing: 18) {
                    legendDot(color: Color(red: 0.2, green: 0.5, blue: 1),  label: "①→② Shunt B")
                    legendDot(color: Color(red: 0.2, green: 0.5, blue: 1),  label: "②→③ Series X")
                    legendDot(color: Color(red: 0.2, green: 0.75, blue: 0.45), label: "③→④ T-Line")
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
            }
            .padding()

            // ── Right: Controls + Readouts ─────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // Display toggles
                    Group {
                        sectionLabel("Display Options")
                        Toggle("Show Admittance (Y) Grid [blue]", isOn: $vm.showY)
                            .font(.system(size: 12)).foregroundColor(.white)
                        Toggle("Enable T-Line Segment ④", isOn: $vm.showTLine)
                            .font(.system(size: 12)).foregroundColor(.white)
                    }

                    divider()

                    // Load
                    sectionLabel("① Load Impedance  Z₀ = 50 Ω")
                    SliderRow(label: "R  (Ω)", value: $vm.loadR, range: 1...500, format: "%.0f Ω")
                    SliderRow(label: "X  (Ω)", value: $vm.loadX, range: -300...300, format: "%.0f Ω")

                    divider()

                    // Shunt
                    sectionLabel("① → ② Shunt Susceptance")
                    Text("Constant-g arc in Y-chart").font(.system(size: 10)).foregroundColor(.gray)
                    SliderRow(label: "ΔB (norm)", value: $vm.shuntB, range: -5...5,
                              format: "%.3f", color: Color(red: 0.2, green: 0.5, blue: 1))

                    divider()

                    // Series
                    sectionLabel("② → ③ Series Reactance")
                    Text("Constant-r arc in Z-chart").font(.system(size: 10)).foregroundColor(.gray)
                    SliderRow(label: "ΔX (norm)", value: $vm.seriesX, range: -5...5,
                              format: "%.3f", color: Color(red: 0.2, green: 0.5, blue: 1))

                    if vm.showTLine {
                        divider()
                        sectionLabel("③ → ④ Transmission Line")
                        Text("Constant-|Γ| rotation (toward generator)").font(.system(size: 10)).foregroundColor(.gray)
                        SliderRow(label: "θ (°)", value: $vm.tLineDeg, range: 0...360,
                                  format: "%.1f °", color: Color(red: 0.2, green: 0.75, blue: 0.45))
                    }

                    divider()

                    // Marker readouts
                    sectionLabel("Marker Readouts")
                    ForEach(vm.markers) { m in
                        MarkerRow(m: m)
                    }
                }
                .padding(12)
            }
            .frame(width: 290)
            .background(Color(white: 0.10))
        }
        .background(Color(white: 0.08))
    }

    private func legendDot(color: Color, label: String) -> some View {
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

    @ViewBuilder private func divider() -> some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
}

// MARK: - Entry Point

PlaygroundPage.current.setLiveView(
    ContentView()
        .frame(width: 760, height: 530)
        .preferredColorScheme(.dark)
)
