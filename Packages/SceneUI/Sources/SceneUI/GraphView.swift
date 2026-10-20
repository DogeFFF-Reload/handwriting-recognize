import SwiftUI

/// GeoGebra 式的绘图区：主次网格、带箭头的坐标轴、贴边的刻度、曲线、零点和极值点。
///
/// - 拖动平移，双指缩放，双击复位；右下角也有放大 / 缩小 / 复位按钮。
/// - Pencil 悬停时读出曲线上那一点的坐标；轻点零点或极值点，钉住它的坐标。
/// - reveal（第二幕改对）之后：极值点旁写出「极大值 (−1, 2)」、画水平切线和导函数，并出现可拖的切点（A9）。
/// - `interactive == false`（卡片正处在变换状态）时不接手势，拖动交给外面的卡片。
public struct FunctionGraphView: View {
    @Bindable var model: GraphModel
    var name: String
    var tint: Color
    var interactive: Bool

    @State private var lastDrag: CGSize?
    @State private var draggingProbe = false
    @State private var zoomStart: GraphViewport?
    @State private var hover: CGPoint?
    @State private var pinned: GraphSpecialPoint?

    public init(model: GraphModel, name: String = "f", tint: Color = .blue, interactive: Bool = true) {
        self.model = model
        self.name = name
        self.tint = tint
        self.interactive = interactive
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let vp = model.viewport ?? model.fittedViewport(for: size)
            Canvas { ctx, size in
                draw(&ctx, size: size, vp: vp)
            }
            .accessibilityLabel("\(name) 的函数图像")
            .contentShape(Rectangle())
            .gesture(drag(vp: vp, size: size), including: interactive ? .all : .none)
            .simultaneousGesture(magnify(vp: vp, size: size), including: interactive ? .all : .none)
            .onTapGesture(count: 2) {
                guard interactive else { return }
                model.viewport = model.fittedViewport(for: size)
                pinned = nil
            }
            .onTapGesture(coordinateSpace: .local) { p in
                guard interactive else { return }
                pin(at: p, vp: vp, size: size)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): hover = p
                case .ended: hover = nil
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if interactive { zoomButtons(vp: vp, size: size) }
            }
            .onChange(of: model.viewport == nil, initial: true) { _, isNil in
                // 换了函数（或第一次出现）时按函数取景，之后固定：拖滑条时视窗不跟着跳
                if isNil { model.viewport = model.fittedViewport(for: size) }
            }
            .onChange(of: model.revision) { _, _ in pinned = nil }
        }
    }

    // MARK: 手势

    private func drag(vp: GraphViewport, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                if lastDrag == nil {
                    lastDrag = .zero
                    // 从切点附近按下：拖切点；否则平移
                    if model.reveal {
                        let cur = model.viewport ?? vp
                        let p = cur.point(probeX(cur, size), model.y(probeX(cur, size)), in: size)
                        draggingProbe = hypot(p.x - g.startLocation.x, p.y - g.startLocation.y) < 30
                    }
                }
                let d = CGSize(width: g.translation.width - lastDrag!.width, height: g.translation.height - lastDrag!.height)
                lastDrag = g.translation
                let cur = model.viewport ?? vp
                if draggingProbe {
                    model.probeX = cur.value(at: g.location, in: size).x
                } else if zoomStart == nil {
                    model.viewport = cur.panned(by: d)
                }
            }
            .onEnded { _ in
                lastDrag = nil
                draggingProbe = false
            }
    }

    private func magnify(vp: GraphViewport, size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { m in
                if zoomStart == nil { zoomStart = model.viewport ?? vp }
                model.viewport = zoomStart!.zoomed(by: Double(m.magnification), around: m.startLocation, in: size)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func pin(at p: CGPoint, vp: GraphViewport, size: CGSize) {
        let hit = model.specialPoints(in: vp.xRange(size))
            .map { ($0, vp.point($0.x, $0.y, in: size)) }
            .map { ($0.0, hypot($0.1.x - p.x, $0.1.y - p.y)) }
            .filter { $0.1 < 24 }
            .min { $0.1 < $1.1 }?.0
        pinned = hit == pinned ? nil : hit
    }

    private func zoomButtons(vp: GraphViewport, size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return VStack(spacing: 6) {
            GraphButton(systemImage: "plus") {
                model.viewport = (model.viewport ?? vp).zoomed(by: 1.5, around: center, in: size)
            }
            GraphButton(systemImage: "minus") {
                model.viewport = (model.viewport ?? vp).zoomed(by: 1 / 1.5, around: center, in: size)
            }
            GraphButton(systemImage: "scope") {
                model.viewport = model.fittedViewport(for: size)
                pinned = nil
            }
        }
        .padding(8)
    }

    // MARK: 绘制

    private func probeX(_ vp: GraphViewport, _ size: CGSize) -> Double {
        let r = vp.xRange(size)
        return r.contains(model.probeX) ? model.probeX : (r.lowerBound + r.upperBound) / 2 + (r.upperBound - r.lowerBound) * 0.2
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, vp: GraphViewport) {
        let xr = vp.xRange(size), yr = vp.yRange(size)
        let xStep = GraphTicks.step(unitsPerPoint: vp.unitsPerPointX)
        let yStep = GraphTicks.step(unitsPerPoint: vp.unitsPerPointY)
        let ink = Color.primary

        // 次网格、主网格
        var minor = Path(), major = Path()
        let mx = xStep / Double(GraphTicks.minorDivisions(of: xStep))
        let my = yStep / Double(GraphTicks.minorDivisions(of: yStep))
        for x in GraphTicks.values(in: xr, step: mx) {
            let px = vp.point(x, 0, in: size).x
            minor.move(to: CGPoint(x: px, y: 0)); minor.addLine(to: CGPoint(x: px, y: size.height))
        }
        for y in GraphTicks.values(in: yr, step: my) {
            let py = vp.point(0, y, in: size).y
            minor.move(to: CGPoint(x: 0, y: py)); minor.addLine(to: CGPoint(x: size.width, y: py))
        }
        for x in GraphTicks.values(in: xr, step: xStep) {
            let px = vp.point(x, 0, in: size).x
            major.move(to: CGPoint(x: px, y: 0)); major.addLine(to: CGPoint(x: px, y: size.height))
        }
        for y in GraphTicks.values(in: yr, step: yStep) {
            let py = vp.point(0, y, in: size).y
            major.move(to: CGPoint(x: 0, y: py)); major.addLine(to: CGPoint(x: size.width, y: py))
        }
        ctx.stroke(minor, with: .color(ink.opacity(0.045)), lineWidth: 0.5)
        ctx.stroke(major, with: .color(ink.opacity(0.10)), lineWidth: 0.75)

        // 坐标轴（在视窗外时不画线，刻度贴着边）
        let o = vp.point(0, 0, in: size)
        let axisColor = ink.opacity(0.62)
        if o.y >= 0, o.y <= size.height {
            var a = Path()
            a.move(to: CGPoint(x: 0, y: o.y)); a.addLine(to: CGPoint(x: size.width - 1, y: o.y))
            a.move(to: CGPoint(x: size.width - 9, y: o.y - 4.5)); a.addLine(to: CGPoint(x: size.width - 1, y: o.y))
            a.addLine(to: CGPoint(x: size.width - 9, y: o.y + 4.5))
            ctx.stroke(a, with: .color(axisColor), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            ctx.draw(Text("x").font(.system(size: 13, design: .serif).italic()).foregroundStyle(axisColor),
                     at: CGPoint(x: size.width - 8, y: o.y - 7), anchor: .bottomTrailing)
        }
        if o.x >= 0, o.x <= size.width {
            var a = Path()
            a.move(to: CGPoint(x: o.x, y: size.height)); a.addLine(to: CGPoint(x: o.x, y: 1))
            a.move(to: CGPoint(x: o.x - 4.5, y: 9)); a.addLine(to: CGPoint(x: o.x, y: 1))
            a.addLine(to: CGPoint(x: o.x + 4.5, y: 9))
            ctx.stroke(a, with: .color(axisColor), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            ctx.draw(Text("y").font(.system(size: 13, design: .serif).italic()).foregroundStyle(axisColor),
                     at: CGPoint(x: o.x + 8, y: 4), anchor: .topLeading)
        }
        let tickFont = Font.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()
        let labelY = min(max(o.y + 4, 3), size.height - 15)
        for x in GraphTicks.values(in: xr, step: xStep) where x != 0 {
            let px = vp.point(x, 0, in: size).x
            guard px > 12, px < size.width - 18 else { continue }
            ctx.draw(Text(GraphTicks.label(x, step: xStep)).font(tickFont).foregroundStyle(.secondary),
                     at: CGPoint(x: px, y: labelY), anchor: .top)
        }
        let labelX = min(max(o.x - 5, 26), size.width - 4)
        for y in GraphTicks.values(in: yr, step: yStep) where y != 0 {
            let py = vp.point(0, y, in: size).y
            guard py > 14, py < size.height - 12 else { continue }
            ctx.draw(Text(GraphTicks.label(y, step: yStep)).font(tickFont).foregroundStyle(.secondary),
                     at: CGPoint(x: labelX, y: py), anchor: .trailing)
        }
        if o.x > 10, o.x < size.width, o.y > 0, o.y < size.height - 14 {
            ctx.draw(Text("O").font(.system(size: 10, design: .serif).italic()).foregroundStyle(.secondary),
                     at: CGPoint(x: o.x - 5, y: o.y + 4), anchor: .topTrailing)
        }

        // 导函数（reveal 后，绿色虚线）
        let derivative = Color(red: 0.12, green: 0.62, blue: 0.38)
        if model.reveal {
            ctx.stroke(curve(size: size, vp: vp, model.slope), with: .color(derivative.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
        }
        // 曲线
        ctx.stroke(curve(size: size, vp: vp, model.y), with: .color(tint),
                   style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))

        // 零点、极值点、和 y 轴的交点
        let special = model.specialPoints(in: xr)
        for p in special {
            let q = vp.point(p.x, p.y, in: size)
            guard q.y > -10, q.y < size.height + 10 else { continue }
            let isExtremum = p.kind == .maximum || p.kind == .minimum
            let r: CGFloat = isExtremum ? 4.5 : 3.8
            let dot = Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
            if isExtremum {
                ctx.fill(dot, with: .color(tint))
                ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
            } else {
                ctx.fill(dot, with: .color(Color(.systemBackground)))
                ctx.stroke(dot, with: .color(tint), lineWidth: 1.6)
            }
        }

        if model.reveal { drawReveal(&ctx, size: size, vp: vp, special: special, derivative: derivative) }

        // Pencil 悬停：曲线上这一点的坐标
        if let h = hover, !draggingProbe {
            let x = vp.value(at: h, in: size).x, y = model.y(x)
            let q = vp.point(x, y, in: size)
            if y.isFinite, q.y > -20, q.y < size.height + 20 {
                var guide = Path()
                guide.move(to: CGPoint(x: q.x, y: 0)); guide.addLine(to: CGPoint(x: q.x, y: size.height))
                ctx.stroke(guide, with: .color(tint.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                let ring = Path(ellipseIn: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12))
                ctx.fill(ring, with: .color(tint.opacity(0.18)))
                ctx.stroke(ring, with: .color(tint), lineWidth: 1.5)
                bubble(&ctx, "(\(GraphTicks.coordinate(x)), \(GraphTicks.coordinate(y)))", near: q, size: size, color: tint)
            }
        }
        if let p = pinned {
            let q = vp.point(p.x, p.y, in: size)
            bubble(&ctx, "\(p.name) (\(GraphTicks.coordinate(p.x)), \(GraphTicks.coordinate(p.y)))", near: q, size: size, color: .primary)
        }
    }

    private func drawReveal(_ ctx: inout GraphicsContext, size: CGSize, vp: GraphViewport,
                            special: [GraphSpecialPoint], derivative: Color) {
        let maxColor = Color(red: 0.89, green: 0.48, blue: 0.12), minColor = Color(red: 0.48, green: 0.31, blue: 0.85)
        let halfTangent = 36 * vp.unitsPerPointX
        for e in special where e.kind == .maximum || e.kind == .minimum {
            let color = e.kind == .maximum ? maxColor : minColor
            var tan = Path()
            tan.move(to: vp.point(e.x - halfTangent, e.y, in: size)); tan.addLine(to: vp.point(e.x + halfTangent, e.y, in: size))
            ctx.stroke(tan, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let p = vp.point(e.x, e.y, in: size), z = vp.point(e.x, 0, in: size)
            var drop = Path()
            drop.move(to: p); drop.addLine(to: z)
            ctx.stroke(drop, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: z.x - 4, y: z.y - 4, width: 8, height: 8)), with: .color(derivative))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color))
            let label = "\(e.name) (\(GraphTicks.coordinate(e.x)), \(GraphTicks.coordinate(e.y)))"
            ctx.draw(Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color),
                     at: CGPoint(x: p.x, y: p.y + (e.kind == .maximum ? -12 : 12)),
                     anchor: e.kind == .maximum ? .bottom : .top)
        }
        // 可拖的切点：斜率用导数算（学生刚写对了导数）
        let x0 = probeX(vp, size), y0 = model.y(x0), k = model.slope(x0)
        guard y0.isFinite, k.isFinite else { return }
        let reach = 48 * vp.unitsPerPointX
        var line = Path()
        line.move(to: vp.point(x0 - reach, y0 - reach * k, in: size)); line.addLine(to: vp.point(x0 + reach, y0 + reach * k, in: size))
        ctx.stroke(line, with: .color(.red), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let pp = vp.point(x0, y0, in: size)
        ctx.fill(Path(ellipseIn: CGRect(x: pp.x - 10, y: pp.y - 10, width: 20, height: 20)), with: .color(.red.opacity(0.2)))
        ctx.fill(Path(ellipseIn: CGRect(x: pp.x - 5, y: pp.y - 5, width: 10, height: 10)), with: .color(.red))
        ctx.draw(Text("斜率 \(GraphTicks.coordinate((k * 100).rounded() / 100))").font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red),
                 at: CGPoint(x: pp.x + 14, y: pp.y - 12), anchor: .bottomLeading)
    }

    /// 按每 1.5 pt 取一个样本连成曲线；跨过渐近线（相邻两点差出好几屏）时断开。
    private func curve(size: CGSize, vp: GraphViewport, _ f: (Double) -> Double) -> Path {
        var path = Path()
        let n = max(Int(size.width / 1.5), 2)
        var prev: CGPoint?
        for i in 0...n {
            let px = size.width * CGFloat(i) / CGFloat(n)
            let x = vp.value(at: CGPoint(x: px, y: 0), in: size).x
            let y = f(x)
            guard y.isFinite else { prev = nil; continue }
            let raw = vp.point(x, y, in: size).y
            let jump = prev.map { abs(raw - $0.y) > size.height * 3 } ?? false
            let p = CGPoint(x: px, y: min(max(raw, -size.height * 2), size.height * 3))
            if prev == nil || jump { path.move(to: p) } else { path.addLine(to: p) }
            prev = CGPoint(x: px, y: raw)
        }
        return path
    }

    /// 带底色的小标签，放在点的右上方；贴边时翻到另一侧。
    private func bubble(_ ctx: inout GraphicsContext, _ text: String, near q: CGPoint, size: CGSize, color: Color) {
        let t = ctx.resolve(Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color))
        let m = t.measure(in: CGSize(width: 400, height: 40))
        var origin = CGPoint(x: q.x + 10, y: q.y - 12 - m.height - 6)
        if origin.x + m.width + 12 > size.width { origin.x = q.x - 10 - m.width - 12 }
        if origin.y < 2 { origin.y = q.y + 12 }
        let box = CGRect(x: origin.x, y: origin.y, width: m.width + 12, height: m.height + 6)
        let shape = Path(roundedRect: box, cornerRadius: 6)
        ctx.fill(shape, with: .color(Color(.systemBackground).opacity(0.94)))
        ctx.stroke(shape, with: .color(color.opacity(0.35)), lineWidth: 1)
        ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }
}

private struct GraphButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .hoverEffect(.highlight)
    }
}

/// 卡片底部的滑条：多项式每个系数一条（a、b、c 按次数从高到低，和 contracts 里的 params 对上），
/// 一般表达式每个参数一条。
public struct GraphSliders: View {
    @Bindable var model: GraphModel
    var tint: Color
    /// 拖了滑条之后调（App 用它把式子跟着改写）。
    var onEdit: () -> Void

    public init(model: GraphModel, tint: Color = .blue, onEdit: @escaping () -> Void = {}) {
        self.model = model
        self.tint = tint
        self.onEdit = onEdit
    }

    public var body: some View {
        VStack(spacing: 2) {
            if let terms = model.terms {
                let order = terms.indices.sorted { terms[$0].pow > terms[$1].pow }
                let span = model.sliderSpan
                ForEach(Array(order.enumerated()), id: \.element) { rank, i in
                    let t = terms[i]
                    row(name: ParamSliders.name(rank),
                        caption: t.pow == 0 ? "常数项" : t.pow == 1 ? "x 的系数" : "x\(ParamSliders.sup(t.pow)) 的系数",
                        value: Binding(get: { model.terms.map { $0.indices.contains(i) ? $0[i].coef : 0 } ?? 0 },
                                       set: { model.setCoefficient(($0 * 2).rounded() / 2, at: i); onEdit() }),
                        range: -span...span, step: 0.5)
                }
            } else {
                ForEach(model.params) { p in
                    row(name: p.name, caption: "参数",
                        value: Binding(get: { model.params.first { $0.name == p.name }?.value ?? 0 },
                                       set: { model.setParam(p.name, to: ($0 * 10).rounded() / 10); onEdit() }),
                        range: p.min...p.max, step: 0.1)
                }
            }
        }
    }

    private func row(name: String, caption: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 15, design: .serif).italic())
                .frame(width: 16)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(tint)
                .controlSize(.small)
            Text(GraphTicks.coordinate(value.wrappedValue))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 30)
    }
}
