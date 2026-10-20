import SwiftUI

/// 函数图像：网格、坐标轴、曲线；reveal 后加极值点、水平切线、导函数虚线和一个可拖的切点（A9）。
public struct FunctionPlotView: View {
    @Bindable var model: SceneModel
    /// 可拖切点的横坐标（只在 reveal 后出现）。
    @State private var probeX: Double = 1.6

    public init(model: SceneModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { geo in
            let frame = PlotFrame(size: geo.size, terms: model.terms)
            Canvas { ctx, size in
                draw(ctx: &ctx, frame: frame)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    guard model.reveal else { return }
                    probeX = min(max(frame.xValue(g.location.x), frame.xMin), frame.xMax)
                }
            )
            .overlay(alignment: .topLeading) { labels(frame: frame) }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
        .accessibilityLabel("函数图像")
    }

    private func draw(ctx: inout GraphicsContext, frame f: PlotFrame) {
        // 网格
        var grid = Path()
        for x in stride(from: ceil(f.xMin), through: floor(f.xMax), by: 1) {
            grid.move(to: f.point(x, f.yMin)); grid.addLine(to: f.point(x, f.yMax))
        }
        for y in stride(from: ceil(f.yMin / f.yStep) * f.yStep, through: f.yMax, by: f.yStep) {
            grid.move(to: f.point(f.xMin, y)); grid.addLine(to: f.point(f.xMax, y))
        }
        ctx.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
        // 坐标轴
        var axes = Path()
        axes.move(to: f.point(f.xMin, 0)); axes.addLine(to: f.point(f.xMax, 0))
        axes.move(to: f.point(0, f.yMin)); axes.addLine(to: f.point(0, f.yMax))
        ctx.stroke(axes, with: .color(.secondary.opacity(0.7)), lineWidth: 1.2)
        for x in stride(from: ceil(f.xMin), through: floor(f.xMax), by: 1) where x != 0 {
            ctx.draw(Text(Poly.format(x)).font(.caption2).foregroundStyle(.secondary), at: f.point(x, 0).applying(.init(translationX: 0, y: 10)))
        }
        for y in stride(from: ceil(f.yMin / f.yStep) * f.yStep, through: f.yMax, by: f.yStep) where abs(y) > 1e-9 {
            ctx.draw(Text(Poly.format(y)).font(.caption2).foregroundStyle(.secondary), at: f.point(0, y).applying(.init(translationX: -14, y: 0)))
        }
        guard !model.terms.isEmpty else { return }

        // 导函数（虚线，绿色）
        if model.reveal {
            ctx.stroke(curve(Poly.derivative(model.terms), f), with: .color(.green.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        // 曲线
        ctx.stroke(curve(model.terms, f), with: .color(.blue), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        guard model.reveal else { return }
        // 极值点 + 水平切线 + 对应的 f'(x)=0
        for e in Poly.extrema(model.terms, lo: f.xMin, hi: f.xMax) {
            let color: Color = e.kind == .max ? .orange : .purple
            var tan = Path()
            tan.move(to: f.point(e.x - 0.9, e.y)); tan.addLine(to: f.point(e.x + 0.9, e.y))
            ctx.stroke(tan, with: .color(color), lineWidth: 2.5)
            let p = f.point(e.x, e.y)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color))
            let z = f.point(e.x, 0)
            ctx.fill(Path(ellipseIn: CGRect(x: z.x - 4, y: z.y - 4, width: 8, height: 8)), with: .color(.green))
            var drop = Path()
            drop.move(to: p); drop.addLine(to: z)
            ctx.stroke(drop, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let name = e.kind == .max ? "极大值" : "极小值"
            ctx.draw(Text("\(name) (\(Poly.format(e.x)), \(Poly.format(e.y)))").font(.footnote.weight(.semibold)).foregroundStyle(color),
                     at: p.applying(.init(translationX: 0, y: e.kind == .max ? -18 : 18)))
        }
        // 可拖的切点：切线斜率用导数算（学生已经写对了导数）
        let x0 = probeX, y0 = Poly.eval(model.terms, x0), k = Poly.eval(Poly.derivative(model.terms), x0)
        var tline = Path()
        tline.move(to: f.point(x0 - 1.2, y0 - 1.2 * k)); tline.addLine(to: f.point(x0 + 1.2, y0 + 1.2 * k))
        ctx.stroke(tline, with: .color(.red), lineWidth: 2)
        let pp = f.point(x0, y0)
        ctx.fill(Path(ellipseIn: CGRect(x: pp.x - 9, y: pp.y - 9, width: 18, height: 18)), with: .color(.red.opacity(0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: pp.x - 5, y: pp.y - 5, width: 10, height: 10)), with: .color(.red))
        ctx.draw(Text("斜率 \(String(format: "%.2f", k))").font(.footnote).foregroundStyle(.red), at: pp.applying(.init(translationX: 44, y: -14)))
    }

    private func curve(_ terms: [PolyTerm], _ f: PlotFrame) -> Path {
        var p = Path()
        var started = false
        let n = 400
        for i in 0...n {
            let x = f.xMin + (f.xMax - f.xMin) * Double(i) / Double(n)
            let y = Poly.eval(terms, x)
            guard y.isFinite, y > f.yMin - (f.yMax - f.yMin), y < f.yMax + (f.yMax - f.yMin) else { started = false; continue }
            if started { p.addLine(to: f.point(x, y)) } else { p.move(to: f.point(x, y)); started = true }
        }
        return p
    }

    @ViewBuilder private func labels(frame: PlotFrame) -> some View {
        if model.reveal {
            Label("导数为 0 的地方，曲线的切线是水平的", systemImage: "lightbulb")
                .font(.footnote)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
        }
    }
}

/// 数学坐标 ↔ 视图坐标。x 固定 [-3.5, 3.5]，y 按 [-3, 3] 上的最大值和极值自动定。
struct PlotFrame {
    let size: CGSize
    let xMin = -3.5, xMax = 3.5
    let yMin: Double, yMax: Double, yStep: Double

    init(size: CGSize, terms: [PolyTerm]) {
        self.size = size
        var m = 2.0
        if !terms.isEmpty {
            var x = -3.0
            while x <= 3 { m = max(m, abs(Poly.eval(terms, x))); x += 0.05 }
            m = min(30, m * 1.1)
            for e in Poly.extrema(terms, lo: -3.5, hi: 3.5) { m = max(m, abs(e.y) * 1.4) }
        }
        yMin = -m; yMax = m
        let raw = (2 * m) / 8
        let mag = Foundation.pow(10, floor(log10(raw)))
        yStep = [1, 2, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? raw
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x - xMin) / (xMax - xMin) * size.width, y: (1 - (y - yMin) / (yMax - yMin)) * size.height)
    }

    func xValue(_ px: CGFloat) -> Double { xMin + Double(px / max(size.width, 1)) * (xMax - xMin) }
}
