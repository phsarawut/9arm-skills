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

    static func + (lhs: Complex, rhs: Complex) -> Complex { Complex(lhs.re + rhs.re, lhs.im + rhs.im) }
    static func - (lhs: Complex, rhs: Complex) -> Complex { Complex(lhs.re - rhs.re, lhs.im - rhs.im) }
    static func * (lhs: Complex, rhs: Complex) -> Complex {
        Complex(lhs.re * rhs.re - lhs.im * rhs.im,
                lhs.re * rhs.im + lhs.im * rhs.re)
    }
    static func / (lhs: Complex, rhs: Complex) -> Complex {
        let d = rhs.magnitudeSquared
        guard d > 1e-300 else { return Complex(Double.infinity, Double.infinity) }
        return Complex((lhs.re * rhs.re + lhs.im * rhs.im) / d,
                       (lhs.im * rhs.re - lhs.re * rhs.im) / d)
    }
    static func + (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re + rhs, lhs.im) }
    static func - (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re - rhs, lhs.im) }
    static func * (lhs: Complex, rhs: Double) -> Complex { Complex(lhs.re * rhs, lhs.im * rhs) }
}

// MARK: - Smith Chart Engine

struct SmithChartEngine {
    /// Normalize impedance: zn = Z / Z0
    static func normalize(_ Z: Complex, z0: Double = 50.0) -> Complex {
        Complex(Z.re / z0, Z.im / z0)
    }

    /// Reflection coefficient Γ = (zn - 1) / (zn + 1)
    static func reflectionCoeff(zn: Complex) -> Complex {
        (zn - Complex(1, 0)) / (zn + Complex(1, 0))
    }

    /// zn from Γ: zn = (1 + Γ) / (1 - Γ)
    static func impedanceFromGamma(_ gamma: Complex) -> Complex {
        (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma)
    }

    /// Map Γ to screen CGPoint
    static func gammaToPoint(_ gamma: Complex, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(gamma.re) * radius,
            y: center.y - CGFloat(gamma.im) * radius   // y-axis flipped
        )
    }

    /// Map screen CGPoint back to Γ
    static func pointToGamma(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Complex {
        Complex(
            Double((point.x - center.x) / radius),
            Double((center.y - point.y) / radius)
        )
    }

    // MARK: Transmission line rotation
    /// Move Γ along transmission line of electrical length θ (radians) toward generator
    static func transmissionLine(gamma: Complex, theta: Double) -> Complex {
        // Γ_new = Γ * e^{-j2θ}
        let angle = -2.0 * theta
        let rot = Complex(cos(angle), sin(angle))
        return gamma * rot
    }

    // MARK: Series component matching
    /// Add series reactance jX (normalised) to zn
    static func seriesReactance(zn: Complex, jx: Double) -> Complex {
        zn + Complex(0, jx)
    }

    /// Add series resistance r (normalised)
    static func seriesResistance(zn: Complex, r: Double) -> Complex {
        zn + Complex(r, 0)
    }

    // MARK: Shunt component matching
    /// Add shunt susceptance jB (normalised) to yn
    static func shuntSusceptance(yn: Complex, jb: Double) -> Complex {
        yn + Complex(0, jb)
    }

    /// Admittance from normalised impedance
    static func admittance(zn: Complex) -> Complex {
        Complex(1, 0) / zn
    }
}

// MARK: - Trajectory Step

enum MatchingStep {
    case seriesL(normX: Double)     // series inductor: +jX arc
    case seriesC(normX: Double)     // series capacitor: -jX arc
    case shuntL(normB: Double)      // shunt inductor:  -jB arc
    case shuntC(normB: Double)      // shunt capacitor: +jB arc
    case tLine(degrees: Double)     // transmission line rotation
}

// MARK: - Marker Info

struct MarkerInfo {
    var index: Int
    var gamma: Complex
    var zn: Complex
    var z0: Double = 50.0

    var Z: Complex { Complex(zn.re * z0, zn.im * z0) }

    var swr: Double {
        let mag = gamma.magnitude
        if mag >= 1.0 { return Double.infinity }
        return (1 + mag) / (1 - mag)
    }

    var label: String { "①②③④"[index] }
}

extension String {
    subscript(_ i: Int) -> Character { self[index(startIndex, offsetBy: i)] }
}

// MARK: - Smith Chart View Model

final class SmithChartVM: ObservableObject {
    @Published var z0: Double = 50.0

    // Source impedance
    @Published var sourceR: Double = 25.0
    @Published var sourceX: Double = -30.0

    // Load impedance
    @Published var loadR: Double = 100.0
    @Published var loadX: Double = 50.0

    // Matching element 1 (series)
    @Published var seriesX: Double = 0.4      // normalized

    // Matching element 2 (shunt susceptance)
    @Published var shuntB: Double = -0.6      // normalized

    // Transmission line (optional extra step)
    @Published var tLineDeg: Double = 45.0

    @Published var showY: Bool = false
    @Published var showTLine: Bool = false

    // Derived markers
    var markers: [MarkerInfo] {
        var result: [MarkerInfo] = []

        // Marker ①: Load
        let znLoad = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        let gLoad  = SmithChartEngine.reflectionCoeff(zn: znLoad)
        result.append(MarkerInfo(index: 0, gamma: gLoad, zn: znLoad, z0: z0))

        // Marker ②: After series X
        let zn2 = SmithChartEngine.seriesReactance(zn: znLoad, jx: seriesX)
        let g2  = SmithChartEngine.reflectionCoeff(zn: zn2)
        result.append(MarkerInfo(index: 1, gamma: g2, zn: zn2, z0: z0))

        // Marker ③: After shunt B
        let yn2 = SmithChartEngine.admittance(zn: zn2)
        let yn3 = SmithChartEngine.shuntSusceptance(yn: yn2, jb: shuntB)
        let zn3 = SmithChartEngine.admittance(zn: yn3)  // 1/yn = zn
        let g3  = SmithChartEngine.reflectionCoeff(zn: zn3)
        result.append(MarkerInfo(index: 2, gamma: g3, zn: zn3, z0: z0))

        // Marker ④: After transmission line (optional)
        if showTLine {
            let theta = tLineDeg * .pi / 180.0
            let g4 = SmithChartEngine.transmissionLine(gamma: g3, theta: theta)
            let zn4 = SmithChartEngine.impedanceFromGamma(g4)
            result.append(MarkerInfo(index: 3, gamma: g4, zn: zn4, z0: z0))
        }

        return result
    }

    // Trajectory points for each segment (fine-step interpolation)
    func trajectorySegments(center: CGPoint, radius: CGFloat) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        let steps = 120

        guard let m0 = markers.first else { return [] }

        // Segment 1 → 2: series reactance arc (constant-r circle)
        let znLoad = SmithChartEngine.normalize(Complex(loadR, loadX), z0: z0)
        segments.append(arcSeriesX(
            znStart: znLoad,
            xEnd: znLoad.im + seriesX,
            steps: steps, center: center, radius: radius
        ))

        // Segment 2 → 3: shunt susceptance arc (constant-g circle in Y chart)
        let zn2 = SmithChartEngine.seriesReactance(zn: znLoad, jx: seriesX)
        let yn2 = SmithChartEngine.admittance(zn: zn2)
        segments.append(arcShuntB(
            ynStart: yn2,
            bEnd: yn2.im + shuntB,
            steps: steps, center: center, radius: radius
        ))

        // Segment 3 → 4: transmission line rotation arc
        if showTLine, markers.count >= 4 {
            let g3 = markers[2].gamma
            segments.append(arcTLine(
                gammaStart: g3,
                degrees: tLineDeg,
                steps: steps, center: center, radius: radius
            ))
        }

        _ = m0 // suppress unused warning
        return segments
    }

    // Arc along constant-r circle (series reactance)
    private func arcSeriesX(znStart: Complex, xEnd: Double, steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let x = znStart.im + (xEnd - znStart.im) * t
            let zn = Complex(znStart.re, x)
            let g = SmithChartEngine.reflectionCoeff(zn: zn)
            return SmithChartEngine.gammaToPoint(g, center: center, radius: radius)
        }
    }

    // Arc along constant-g circle (shunt susceptance)
    private func arcShuntB(ynStart: Complex, bEnd: Double, steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let b = ynStart.im + (bEnd - ynStart.im) * t
            let yn = Complex(ynStart.re, b)
            let zn = SmithChartEngine.admittance(zn: yn)
            let g = SmithChartEngine.reflectionCoeff(zn: zn)
            return SmithChartEngine.gammaToPoint(g, center: center, radius: radius)
        }
    }

    // Arc along constant-|Γ| circle (transmission line)
    private func arcTLine(gammaStart: Complex, degrees: Double, steps: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        let totalRad = degrees * .pi / 180.0
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let g = SmithChartEngine.transmissionLine(gamma: gammaStart, theta: totalRad * t)
            return SmithChartEngine.gammaToPoint(g, center: center, radius: radius)
        }
    }
}

// MARK: - Smith Chart Canvas

struct SmithChartCanvas: View {
    @ObservedObject var vm: SmithChartVM
    let size: CGFloat

    private var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    private var radius: CGFloat { size * 0.46 }

    // Color palette
    private let rCircleColor   = Color(white: 0.35)
    private let xArcColor      = Color(white: 0.45)
    private let yCircleColor   = Color.teal.opacity(0.5)
    private let outerRingColor = Color.gray
    private let seg1Color      = Color.orange
    private let seg2Color      = Color.green
    private let seg3Color      = Color.purple
    private let markerColors: [Color] = [.red, .orange, .green, .purple]

    var body: some View {
        Canvas { ctx, size in
            let c = center
            let r = radius

            drawBackground(ctx: ctx, center: c, radius: r)
            drawRCircles(ctx: ctx, center: c, radius: r)
            if vm.showY { drawYCircles(ctx: ctx, center: c, radius: r) }
            drawXArcs(ctx: ctx, center: c, radius: r)
            drawLabels(ctx: ctx, center: c, radius: r)
            drawTrajectory(ctx: ctx, center: c, radius: r)
            drawMarkers(ctx: ctx, center: c, radius: r)
        }
        .frame(width: size, height: size)
    }

    // MARK: Background + outer circle
    private func drawBackground(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var bg = Path()
        bg.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                 width: radius * 2, height: radius * 2))
        ctx.fill(bg, with: .color(Color(white: 0.08)))

        var ring = Path()
        ring.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.stroke(ring, with: .color(outerRingColor), lineWidth: 1.5)

        // Real axis
        var axis = Path()
        axis.move(to: CGPoint(x: center.x - radius, y: center.y))
        axis.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        ctx.stroke(axis, with: .color(Color(white: 0.5)), lineWidth: 0.6)
    }

    // MARK: Constant R circles
    private func drawRCircles(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rValues: [Double] = [0, 0.2, 0.5, 1.0, 2.0, 5.0]
        for r in rValues {
            // Circle: center at (r/(r+1), 0) in Γ-plane, radius 1/(r+1)
            let cr = CGFloat(r / (r + 1))
            let rr = CGFloat(1.0 / (r + 1))
            var p = Path()
            p.addEllipse(in: CGRect(
                x: center.x + cr * radius - rr * radius,
                y: center.y         - rr * radius,
                width: rr * radius * 2,
                height: rr * radius * 2
            ))
            let width: CGFloat = r == 1.0 ? 1.2 : 0.7
            ctx.stroke(p, with: .color(rCircleColor), lineWidth: width)
        }
    }

    // MARK: Constant X arcs (reactance)
    private func drawXArcs(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let xValues: [Double] = [0.2, 0.5, 1.0, 2.0, 5.0]
        for x in xValues {
            drawXArc(ctx: ctx, x:  x, center: center, radius: radius)
            drawXArc(ctx: ctx, x: -x, center: center, radius: radius)
        }
    }

    private func drawXArc(ctx: GraphicsContext, x: Double, center: CGPoint, radius: CGFloat) {
        // Circle for constant X: center (1, 1/x) in Γ-plane, radius 1/|x|
        let cx = CGFloat(1.0)
        let cy = CGFloat(1.0 / x)
        let rr = CGFloat(abs(1.0 / x))

        // Clip to unit circle using path clipping
        var clip = Path()
        clip.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))

        var ctx2 = ctx
        ctx2.clip(to: clip)

        var arc = Path()
        arc.addEllipse(in: CGRect(
            x: center.x + (cx - rr) * radius,
            y: center.y - (cy + rr) * radius,
            width: rr * radius * 2,
            height: rr * radius * 2
        ))
        ctx2.stroke(arc, with: .color(xArcColor), lineWidth: 0.7)
    }

    // MARK: Admittance (Y) circles overlay
    private func drawYCircles(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let gValues: [Double] = [0.2, 0.5, 1.0, 2.0, 5.0]
        for g in gValues {
            // Y-chart r-circles are r-circles rotated 180° (mirrored about origin)
            // Center at (-g/(g+1), 0), radius 1/(g+1)
            let cr = CGFloat(-g / (g + 1))
            let rr = CGFloat(1.0 / (g + 1))
            var p = Path()
            p.addEllipse(in: CGRect(
                x: center.x + cr * radius - rr * radius,
                y: center.y         - rr * radius,
                width: rr * radius * 2,
                height: rr * radius * 2
            ))
            ctx.stroke(p, with: .color(yCircleColor), lineWidth: 0.7)
        }
        // Y-chart susceptance arcs
        let bValues: [Double] = [0.2, 0.5, 1.0, 2.0, 5.0]
        for b in bValues {
            drawBArc(ctx: ctx, b:  b, center: center, radius: radius)
            drawBArc(ctx: ctx, b: -b, center: center, radius: radius)
        }
    }

    private func drawBArc(ctx: GraphicsContext, b: Double, center: CGPoint, radius: CGFloat) {
        // Susceptance arcs: mirror of X arcs about origin
        let cx = CGFloat(-1.0)
        let cy = CGFloat(-1.0 / b)
        let rr = CGFloat(abs(1.0 / b))

        var clip = Path()
        clip.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        var ctx2 = ctx
        ctx2.clip(to: clip)

        var arc = Path()
        arc.addEllipse(in: CGRect(
            x: center.x + (cx - rr) * radius,
            y: center.y - (cy + rr) * radius,
            width: rr * radius * 2,
            height: rr * radius * 2
        ))
        ctx2.stroke(arc, with: .color(yCircleColor.opacity(0.7)), lineWidth: 0.6)
    }

    // MARK: Labels
    private func drawLabels(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rLabels: [(Double, String)] = [
            (0, "0"), (0.2, "0.2"), (0.5, "0.5"), (1.0, "1"), (2.0, "2"), (5.0, "5")
        ]
        for (r, label) in rLabels {
            // Label at the rightmost point of each r-circle: Γ = (r/(r+1)+1/(r+1), 0) = (1, 0) for all...
            // Better: label near the top of the circle offset
            let gx = 2.0 * r / (r + 1) - 1.0  // Γ at rightmost point
            let pt = SmithChartEngine.gammaToPoint(Complex(gx + 0.02, 0.05), center: center, radius: radius)
            ctx.draw(
                Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray),
                at: pt
            )
        }
    }

    // MARK: Trajectory
    private func drawTrajectory(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let segments = vm.trajectorySegments(center: center, radius: radius)
        let colors: [Color] = [seg1Color, seg2Color, seg3Color]

        for (i, seg) in segments.enumerated() {
            guard seg.count > 1 else { continue }
            var p = Path()
            p.move(to: seg[0])
            for pt in seg.dropFirst() { p.addLine(to: pt) }
            ctx.stroke(p, with: .color(colors[min(i, colors.count - 1)]), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Markers
    private func drawMarkers(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let markerSymbols = ["①", "②", "③", "④"]
        for (i, m) in vm.markers.enumerated() {
            let pt = SmithChartEngine.gammaToPoint(m.gamma, center: center, radius: radius)
            let color = markerColors[min(i, markerColors.count - 1)]

            // Dot
            var dot = Path()
            dot.addEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
            ctx.fill(dot, with: .color(color))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1)

            // Label
            ctx.draw(
                Text(markerSymbols[i]).font(.system(size: 13, weight: .bold)).foregroundColor(color),
                at: CGPoint(x: pt.x + 12, y: pt.y - 8)
            )
        }
    }
}

// MARK: - Marker Detail Row

struct MarkerRow: View {
    let m: MarkerInfo
    let colors: [Color] = [.red, .orange, .green, .purple]
    let symbols = ["①", "②", "③", "④"]

    var body: some View {
        let color = colors[min(m.index, colors.count - 1)]
        HStack(spacing: 8) {
            Text(symbols[m.index]).font(.title3).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zn = \(String(format: "%.3f", m.zn.re)) + j\(String(format: "%.3f", m.zn.im))")
                    .font(.system(size: 11, design: .monospaced))
                Text("Z = \(String(format: "%.1f", m.Z.re)) + j\(String(format: "%.1f", m.Z.im)) Ω")
                    .font(.system(size: 11, design: .monospaced))
                Text("SWR = \(m.swr.isInfinite ? "∞" : String(format: "%.2f", m.swr))  |Γ| = \(String(format: "%.3f", m.gamma.magnitude))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(color.opacity(0.85))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var vm = SmithChartVM()
    let chartSize: CGFloat = 420

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // Left: Chart
            VStack(spacing: 8) {
                Text("Smith Chart – Impedance Matching")
                    .font(.headline).foregroundColor(.white)

                SmithChartCanvas(vm: vm, size: chartSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: .orange, label: "Series X")
                    legendItem(color: .green,  label: "Shunt B")
                    if vm.showTLine { legendItem(color: .purple, label: "T-Line") }
                }
                .font(.caption).foregroundColor(.white)
            }
            .padding()

            // Right: Controls + Markers
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // Toggles
                    Group {
                        Text("Display").font(.subheadline.bold()).foregroundColor(.white)
                        Toggle("Show Admittance (Y) Grid", isOn: $vm.showY)
                            .toggleStyle(.switch).foregroundColor(.white)
                        Toggle("Show Transmission Line (④)", isOn: $vm.showTLine)
                            .toggleStyle(.switch).foregroundColor(.white)
                    }

                    Divider()

                    // Load
                    sectionHeader("Load Impedance ZL")
                    sliderRow("R =", value: $vm.loadR, range: 1...500, format: "%.0f Ω")
                    sliderRow("X =", value: $vm.loadX, range: -300...300, format: "%.0f Ω")

                    Divider()

                    // Series element
                    sectionHeader("① → ② Series Reactance")
                    sliderRow("jX (norm) =", value: $vm.seriesX, range: -5...5, format: "%.2f")

                    Divider()

                    // Shunt element
                    sectionHeader("② → ③ Shunt Susceptance")
                    sliderRow("jB (norm) =", value: $vm.shuntB, range: -5...5, format: "%.2f")

                    if vm.showTLine {
                        Divider()
                        sectionHeader("③ → ④ Transmission Line")
                        sliderRow("θ =", value: $vm.tLineDeg, range: 0...360, format: "%.0f°")
                    }

                    Divider()

                    // Markers
                    Text("Markers").font(.subheadline.bold()).foregroundColor(.white)
                    ForEach(vm.markers.indices, id: \.self) { i in
                        MarkerRow(m: vm.markers[i])
                    }
                }
                .padding()
            }
            .frame(width: 300)
            .background(Color(white: 0.12))
        }
        .background(Color(white: 0.1))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 20, height: 3)
            Text(label)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.caption.bold()).foregroundColor(.cyan)
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)
            Slider(value: value, in: range)
                .accentColor(.cyan)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - Playground Entry Point

PlaygroundPage.current.setLiveView(
    ContentView()
        .frame(width: 760, height: 520)
        .preferredColorScheme(.dark)
)
