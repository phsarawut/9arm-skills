import SwiftUI

// MARK: - Complex Number

struct Complex {
    var re: Double
    var im: Double
    init(_ re: Double, _ im: Double = 0) { self.re = re; self.im = im }

    var magnitude: Double { (re*re + im*im).squareRoot() }
    var magnitudeSquared: Double { re*re + im*im }
    var angle: Double { atan2(im, re) }

    static func +(l: Complex, r: Complex) -> Complex { Complex(l.re+r.re, l.im+r.im) }
    static func -(l: Complex, r: Complex) -> Complex { Complex(l.re-r.re, l.im-r.im) }
    static func *(l: Complex, r: Complex) -> Complex {
        Complex(l.re*r.re - l.im*r.im, l.re*r.im + l.im*r.re)
    }
    static func /(l: Complex, r: Complex) -> Complex {
        let d = r.magnitudeSquared
        guard d > 1e-300 else { return Complex(.infinity, .infinity) }
        return Complex((l.re*r.re + l.im*r.im)/d, (l.im*r.re - l.re*r.im)/d)
    }
    static func +(l: Complex, r: Double) -> Complex { Complex(l.re+r, l.im) }
    static func -(l: Complex, r: Double) -> Complex { Complex(l.re-r, l.im) }
    static func *(l: Complex, r: Double) -> Complex { Complex(l.re*r, l.im*r) }
    static func polar(r: Double, theta: Double) -> Complex { Complex(r*cos(theta), r*sin(theta)) }
}

// MARK: - Engine

struct SCE {
    static func norm(_ Z: Complex, z0: Double = 50) -> Complex { Complex(Z.re/z0, Z.im/z0) }
    static func gamma(_ zn: Complex) -> Complex { (zn - 1.0) / (zn + 1.0) }
    static func zFromGamma(_ g: Complex) -> Complex { (Complex(1,0)+g) / (Complex(1,0)-g) }
    static func Y(_ z: Complex) -> Complex { Complex(1,0) / z }
    static func tLine(_ g: Complex, theta: Double) -> Complex {
        g * Complex.polar(r: 1, theta: -2*theta)
    }
    static func screen(_ g: Complex, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(g.re)*r, y: c.y - CGFloat(g.im)*r)
    }
}

// MARK: - Marker

struct Marker: Identifiable {
    let id = UUID()
    var idx: Int; var g: Complex; var zn: Complex; var z0: Double
    var Z: Complex  { Complex(zn.re*z0, zn.im*z0) }
    var yn: Complex { SCE.Y(zn) }
    var swr: Double { let m = g.magnitude; return m < 1 ? (1+m)/(1-m) : .infinity }
}

// MARK: - ViewModel

final class VM: ObservableObject {
    @Published var loadR = 20.0,  loadX  = 50.0
    @Published var shuntB = 1.15, seriesX = -1.1
    @Published var tLineDeg = 55.0
    @Published var showY = true, showTLine = true
    let z0 = 50.0

    var markers: [Marker] {
        var ms = [Marker]()
        // ① load
        let zn1 = SCE.norm(Complex(loadR, loadX), z0: z0)
        ms.append(Marker(idx: 0, g: SCE.gamma(zn1), zn: zn1, z0: z0))
        // ② shunt B (Y domain)
        let yn2 = Complex(SCE.Y(zn1).re, SCE.Y(zn1).im + shuntB)
        let zn2 = SCE.Y(yn2)
        ms.append(Marker(idx: 1, g: SCE.gamma(zn2), zn: zn2, z0: z0))
        // ③ series X
        let zn3 = Complex(zn2.re, zn2.im + seriesX)
        ms.append(Marker(idx: 2, g: SCE.gamma(zn3), zn: zn3, z0: z0))
        // ④ T-line
        if showTLine {
            let g4 = SCE.tLine(SCE.gamma(zn3), theta: tLineDeg * .pi/180)
            ms.append(Marker(idx: 3, g: g4, zn: SCE.zFromGamma(g4), z0: z0))
        }
        return ms
    }

    func trajectory(c: CGPoint, r: CGFloat) -> [[CGPoint]] {
        guard markers.count >= 3 else { return [] }
        let N = 150
        var segs = [[CGPoint]]()
        let zn1 = SCE.norm(Complex(loadR, loadX), z0: z0)
        let yn1 = SCE.Y(zn1)
        // ①→② shunt B arc
        segs.append((0...N).map { i in
            let yn = Complex(yn1.re, yn1.im + shuntB * Double(i)/Double(N))
            return SCE.screen(SCE.gamma(SCE.Y(yn)), c, r)
        })
        // ②→③ series X arc
        let zn2 = SCE.Y(Complex(yn1.re, yn1.im + shuntB))
        segs.append((0...N).map { i in
            let zn = Complex(zn2.re, zn2.im + seriesX * Double(i)/Double(N))
            return SCE.screen(SCE.gamma(zn), c, r)
        })
        // ③→④ T-line arc
        if showTLine, markers.count == 4 {
            let g3 = markers[2].g; let tot = tLineDeg * .pi/180
            segs.append((0...N).map { i in
                SCE.screen(SCE.tLine(g3, theta: tot * Double(i)/Double(N)), c, r)
            })
        }
        return segs
    }
}

// MARK: - Grid Values
// Traditional Smith Chart density — fine subdivisions with distinguished main lines

private let rAll: [Double] = [
    0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
    1, 1.2, 1.4, 1.6, 1.8, 2, 2.5, 3, 4, 5, 10, 20
]
private let rKey: Set<Double> = [0, 0.2, 0.5, 1, 2, 5]

private let xAll: [Double] = [
    0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
    1, 1.2, 1.4, 1.6, 1.8, 2, 2.5, 3, 4, 5, 10, 20
]
private let xKey: Set<Double> = [0.2, 0.5, 1, 2, 5]

// MARK: - Canvas View
// center + radius are computed from the Canvas's own `size` at draw time,
// so they update automatically on every rotation or resize.

struct SmithCanvas: View {
    @ObservedObject var vm: VM

    private let zC = Color(red: 0.85, green: 0.42, blue: 0.42)
    private let yC = Color(red: 0.42, green: 0.62, blue: 0.92)
    private let seg: [Color] = [
        Color(red: 0.25, green: 0.52, blue: 1.0),
        Color(red: 0.25, green: 0.52, blue: 1.0),
        Color(red: 0.20, green: 0.80, blue: 0.42)
    ]

    var body: some View {
        Canvas { ctx, size in
            // Always recompute from canvas's live size — fixes the rotation bug
            let side = min(size.width, size.height)
            let c    = CGPoint(x: size.width/2, y: size.height/2)
            let r    = side * 0.47

            bg(ctx, c, r)
            if vm.showY { yGrid(ctx, c, r) }
            zGrid(ctx, c, r)
            ring(ctx, c, r)
            traj(ctx, c, r)
            markers(ctx, c, r)
        }
        .background(Color(white: 0.04))
    }

    // MARK: Background disk + real axis
    private func bg(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var disk = Path(); disk.addEllipse(in: rc(c, r))
        ctx.fill(disk, with: .color(Color(white: 0.04)))
        var ax = Path()
        ax.move(to: CGPoint(x: c.x-r, y: c.y))
        ax.addLine(to: CGPoint(x: c.x+r, y: c.y))
        ctx.stroke(ax, with: .color(.gray.opacity(0.3)), lineWidth: 0.4)
    }

    // MARK: Outer ring + constant-|Γ| (SWR) reference circles
    private func ring(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var p = Path(); p.addEllipse(in: rc(c, r))
        ctx.stroke(p, with: .color(Color(white: 0.72)), lineWidth: 1.2)
        for m in [1.0/3, 0.5, 2.0/3] {
            var s = Path(); s.addEllipse(in: rc(c, r * CGFloat(m)))
            ctx.stroke(s, with: .color(Color(white: 0.28)), lineWidth: 0.3)
        }
    }

    // MARK: Z grid — constant-R circles and constant-X arcs (red family)
    private func zGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        // Clip all arcs to unit circle
        var clip = Path(); clip.addEllipse(in: rc(c, r))

        // Constant-R circles:  center_Γ = (R/(R+1), 0),  radius_Γ = 1/(R+1)
        for rv in rAll {
            let key = rKey.contains(rv)
            let cr  = CGFloat(rv / (rv + 1))
            let rr  = CGFloat(1.0 / (rv + 1))
            var p   = Path()
            p.addEllipse(in: CGRect(x: c.x+(cr-rr)*r, y: c.y-rr*r, width: rr*r*2, height: rr*r*2))
            ctx.stroke(p, with: .color(zC.opacity(key ? 0.70 : 0.28)),
                       lineWidth: key ? 0.65 : 0.30)
        }

        // Constant-X arcs:  center_Γ = (1, 1/X),  radius_Γ = 1/|X|
        for x in xAll {
            drawXArc(ctx, x:  x, c: c, r: r, clip: clip)
            drawXArc(ctx, x: -x, c: c, r: r, clip: clip)
        }

        // R-value labels on real axis
        for (rv, txt) in [(0.0,"0"),(0.2,"0.2"),(0.5,"0.5"),(1.0,"1"),(2.0,"2"),(5.0,"5")] {
            let gx  = rv == 0 ? -1.0 : (2*rv/(rv+1) - 1.0)
            let pt  = SCE.screen(Complex(gx, 0), c, r)
            let fs  = max(7.0, Double(r) * 0.038)
            ctx.draw(Text(txt).font(.system(size: fs, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6)),
                     at: CGPoint(x: pt.x, y: pt.y - r*0.04))
        }
    }

    private func drawXArc(_ ctx: GraphicsContext, x: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let key = xKey.contains(abs(x))
        // Circle parameters in Γ-plane
        let rr  = CGFloat(abs(1.0 / x))            // radius
        let cy  = CGFloat(1.0 / x)                 // Γ_im of center (positive = upper half)
        var arc = Path()
        // top-left of bounding box = (screen_cx - screen_r, screen_cy - screen_r)
        // screen_cx = c.x + 1*r,  screen_cy = c.y - cy*r
        arc.addEllipse(in: CGRect(
            x: c.x + (1.0 - rr) * r,
            y: c.y - (cy + rr) * r,
            width:  rr * r * 2,
            height: rr * r * 2
        ))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(zC.opacity(key ? 0.58 : 0.20)),
                    lineWidth: key ? 0.60 : 0.28)
    }

    // MARK: Y grid — constant-G circles and constant-B arcs (blue family)
    // Y-chart is the Γ-plane mirror of the Z-chart about the origin.
    private func yGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var clip = Path(); clip.addEllipse(in: rc(c, r))

        // Constant-G circles:  center_Γ = (-G/(G+1), 0),  radius_Γ = 1/(G+1)
        for gv in rAll where gv > 0 {
            let key = rKey.contains(gv)
            let cr  = CGFloat(-gv / (gv + 1))
            let rr  = CGFloat(1.0 / (gv + 1))
            var p   = Path()
            p.addEllipse(in: CGRect(x: c.x+(cr-rr)*r, y: c.y-rr*r, width: rr*r*2, height: rr*r*2))
            ctx.stroke(p, with: .color(yC.opacity(key ? 0.55 : 0.18)),
                       lineWidth: key ? 0.55 : 0.25)
        }

        // Constant-B arcs:  center_Γ = (-1, -1/B),  radius_Γ = 1/|B|
        for b in xAll {
            drawBArc(ctx, b:  b, c: c, r: r, clip: clip)
            drawBArc(ctx, b: -b, c: c, r: r, clip: clip)
        }
    }

    private func drawBArc(_ ctx: GraphicsContext, b: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let key = xKey.contains(abs(b))
        let rr  = CGFloat(abs(1.0 / b))
        let cy  = CGFloat(-1.0 / b)               // Γ_im of center
        var arc = Path()
        // screen_cx = c.x + (-1)*r,  screen_cy = c.y - cy*r
        arc.addEllipse(in: CGRect(
            x: c.x + (-1.0 - rr) * r,
            y: c.y - (cy + rr) * r,
            width:  rr * r * 2,
            height: rr * r * 2
        ))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(yC.opacity(key ? 0.42 : 0.14)),
                    lineWidth: key ? 0.52 : 0.25)
    }

    // MARK: Trajectory arcs with arrow heads
    private func traj(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let segs = vm.trajectory(c: c, r: r)
        for (i, s) in segs.enumerated() {
            guard s.count > 1 else { continue }
            var p = Path(); p.move(to: s[0])
            s.dropFirst().forEach { p.addLine(to: $0) }
            let col = seg[min(i, seg.count-1)]
            ctx.stroke(p, with: .color(col),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            if s.count >= 2 { arrow(ctx, from: s[s.count-2], to: s.last!, col: col) }
        }
    }

    private func arrow(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, col: Color) {
        let dx = b.x-a.x, dy = b.y-a.y
        let l  = (dx*dx+dy*dy).squareRoot(); guard l > 0 else { return }
        let ux = dx/l, uy = dy/l; let s: CGFloat = 9
        var p = Path()
        p.move(to: CGPoint(x: b.x-s*ux+s*0.5*uy, y: b.y-s*uy-s*0.5*ux))
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x-s*ux-s*0.5*uy, y: b.y-s*uy+s*0.5*ux))
        ctx.stroke(p, with: .color(col), lineWidth: 1.8)
    }

    // MARK: Markers ①②③④
    private func markers(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let syms = ["①","②","③","④"]
        let dot  = max(5.0, r * 0.024)
        for m in vm.markers {
            let pt = SCE.screen(m.g, c, r)
            var glow = Path(); glow.addEllipse(in: CGRect(x:pt.x-dot*1.9,y:pt.y-dot*1.9,width:dot*3.8,height:dot*3.8))
            ctx.fill(glow, with: .color(Color.cyan.opacity(0.15)))
            var d = Path(); d.addEllipse(in: CGRect(x:pt.x-dot,y:pt.y-dot,width:dot*2,height:dot*2))
            ctx.fill(d, with: .color(.cyan))
            ctx.stroke(d, with: .color(.white), lineWidth: 1)
            let fs = max(11.0, Double(r) * 0.048)
            ctx.draw(Text(syms[m.idx]).font(.system(size: fs, weight: .bold)).foregroundColor(.cyan),
                     at: CGPoint(x: pt.x+dot*2.4, y: pt.y-dot*1.6))
        }
    }

    private func rc(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x-r, y: c.y-r, width: r*2, height: r*2)
    }
}

// MARK: - Marker Row

struct MarkerRow: View {
    let m: Marker
    private let syms  = ["①","②","③","④"]
    private let names = ["Load ZL","After Shunt B","After Series X","After T-Line"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(syms[m.idx]).font(.title3.bold()).foregroundColor(.cyan)
                Text(names[min(m.idx, names.count-1)]).font(.caption.bold()).foregroundColor(.cyan.opacity(0.8))
            }
            row("|Γ|", String(format: "%.4f",  m.g.magnitude))
            row("∠Γ",  String(format: "%.1f°", m.g.angle * 180 / .pi))
            row("Zn",  fmt(m.zn))
            row("Z",   fmt(m.Z) + " Ω")
            row("Yn",  fmt(m.yn))
            row("SWR", m.swr.isInfinite ? "∞" : String(format: "%.2f", m.swr))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.13)))
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack(spacing: 0) {
            Text(l + ": ").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                .frame(width: 34, alignment: .leading)
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
        }
    }

    private func fmt(_ c: Complex) -> String {
        String(format: "%.3f %@ j%.3f", c.re, c.im >= 0 ? "+" : "−", abs(c.im))
    }
}

// MARK: - Slider Row

struct SliderRow: View {
    let label: String; @Binding var value: Double
    let range: ClosedRange<Double>; let fmt: String
    var color: Color = .cyan
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                Text(String(format: fmt, value)).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
            }
            Slider(value: $value, in: range).tint(color)
        }
    }
}

// MARK: - Controls Panel (reusable in both orientations)

struct ControlsPanel: View {
    @ObservedObject var vm: VM
    private let blue  = Color(red: 0.25, green: 0.52, blue: 1.0)
    private let green = Color(red: 0.20, green: 0.80, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Legend
                HStack(spacing: 14) {
                    dot(blue,  "①→② Shunt B")
                    dot(blue,  "②→③ Series X")
                    dot(green, "③→④ T-Line")
                }.font(.system(size: 10)).foregroundColor(.white.opacity(0.75))
                div()
                // Toggles
                lbl("Display")
                Toggle("Admittance (Y) Grid", isOn: $vm.showY).font(.system(size: 12)).foregroundColor(.white)
                Toggle("T-Line segment ④",   isOn: $vm.showTLine).font(.system(size: 12)).foregroundColor(.white)
                div()
                // Load
                lbl("① Load  (Z₀ = 50 Ω)")
                SliderRow(label: "R (Ω)", value: $vm.loadR, range: 1...500,    fmt: "%.0f Ω")
                SliderRow(label: "X (Ω)", value: $vm.loadX, range: -300...300, fmt: "%.0f Ω")
                div()
                // Shunt B
                lbl("① → ② Shunt Susceptance")
                note("Constant-g arc  •  +B = capacitive shunt")
                SliderRow(label: "ΔB (norm)", value: $vm.shuntB,  range: -5...5, fmt: "%.3f", color: blue)
                div()
                // Series X
                lbl("② → ③ Series Reactance")
                note("Constant-r arc  •  +X = series inductor")
                SliderRow(label: "ΔX (norm)", value: $vm.seriesX, range: -5...5, fmt: "%.3f", color: blue)
                // T-line
                if vm.showTLine {
                    div()
                    lbl("③ → ④ Transmission Line")
                    note("Constant-|Γ| rotation toward generator")
                    SliderRow(label: "θ (°)", value: $vm.tLineDeg, range: 0...360, fmt: "%.1f°", color: green)
                }
                div()
                // Readouts
                lbl("Marker Readouts")
                ForEach(vm.markers) { m in MarkerRow(m: m) }
            }
            .padding(12)
        }
        .background(Color(white: 0.09))
    }

    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
    }
    @ViewBuilder private func lbl(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.cyan)
    }
    @ViewBuilder private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 10)).foregroundColor(.gray)
    }
    @ViewBuilder private func div() -> some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

// MARK: - Root View
// GeometryReader at the top level drives the layout switch on every rotation.
// SmithCanvas uses Canvas { ctx, size } so its center/radius are always live.

struct ContentView: View {
    @StateObject private var vm = VM()

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            if landscape {
                // ── Landscape: chart fills square on left, controls sidebar on right ──
                let ctrlW: CGFloat = min(310, geo.size.width * 0.36)
                HStack(spacing: 0) {
                    SmithCanvas(vm: vm)
                        .frame(width: geo.size.width - ctrlW,
                               height: geo.size.height)
                    ControlsPanel(vm: vm)
                        .frame(width: ctrlW, height: geo.size.height)
                }
            } else {
                // ── Portrait: chart square on top, controls scroll below ──
                let chartH: CGFloat = geo.size.width   // square
                VStack(spacing: 0) {
                    SmithCanvas(vm: vm)
                        .frame(width: geo.size.width, height: chartH)
                    ControlsPanel(vm: vm)
                        .frame(width: geo.size.width,
                               height: max(0, geo.size.height - chartH))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
    }
}
