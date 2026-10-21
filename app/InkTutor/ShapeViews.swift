import InkCore
import SceneUI
import SwiftUI

// 纸上的几何图形（选「几何」认出来的）。课本的画法：黑线、淡淡的填色、顶点字母、直角记号、相等的边打短线；
// 立体图形看不见的棱画虚线。点一下选中：出节点（拖动改形状、大小、方向）和上方的信息条（名字、边长面积体积、
// 三视图、变立体、还原笔迹、删除）。没选中时只有线条附近接触摸，笔照样能在图形里面写字。

/// 一个图形。
struct ShapeView: View {
    @Bindable var item: ShapeItem
    var app: AppModel
    @State private var moveStart: Figure?

    private var selected: Bool { app.selection == .shape(item.id) }

    var body: some View {
        let fig = item.figure
        let box = fig.bounds.insetBy(dx: -34, dy: -34)
        Canvas { ctx, _ in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ShapeArt.draw(fig, in: &ctx, selected: selected, labels: item.showsLabels)
        }
        .frame(width: max(box.width, 1), height: max(box.height, 1))
        .contentShape(FigureHit(figure: fig, origin: box.origin, interior: selected))
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { app.selection = selected ? nil : .shape(item.id) }
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named(Board.space))
                .onChanged { g in
                    if moveStart == nil { moveStart = item.figure }
                    app.update(item, to: moveStart!.translated(by: g.translation))
                }
                .onEnded { _ in moveStart = nil },
            including: selected ? .all : .subviews
        )
        .position(x: box.midX, y: box.midY)
        .accessibilityLabel(fig.name)
    }
}

/// 点选范围：没选中时只有线条附近（不挡笔在图形里写字），选中后整个图形都能拖。
struct FigureHit: Shape {
    var figure: Figure
    var origin: CGPoint
    var interior: Bool

    func path(in rect: CGRect) -> Path {
        let shift = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        let outline = ShapeArt.outline(figure).applying(shift)
        var out = outline.strokedPath(StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round))
        if interior { out.addPath(outline) }
        if case .solid = figure { out.addPath(outline) }
        return out
    }
}

// MARK: - 节点

/// 选中图形的节点：顶点、边、中心、半轴、旋转、立体的尺寸和视角。拖动时从按下那一刻的样子算起。
struct ShapeHandles: View {
    @Bindable var item: ShapeItem
    var app: AppModel
    @State private var start: Figure?
    @State private var startPoint: CGPoint = .zero
    @State private var active: FigureHandle.Role?

    var body: some View {
        let handles = item.figure.handles
        ZStack {
            // 旋转手柄的柄
            if let r = handles.first(where: { $0.role == .rotate }), case .polygon(let p) = item.figure {
                let c = p.centroid
                let d = hypot(r.point.x - c.x, r.point.y - c.y)
                let stemEnd = CGPoint(x: r.point.x + (c.x - r.point.x) / max(d, 1) * 26, y: r.point.y + (c.y - r.point.y) / max(d, 1) * 26)
                Path { path in
                    path.move(to: r.point)
                    path.addLine(to: stemEnd)
                }
                .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .allowsHitTesting(false)
            }
            ForEach(handles) { h in
                HandleKnob(role: h.role, active: active == h.role)
                    .position(h.point)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Board.space))
                            .onChanged { g in
                                if start == nil {
                                    start = item.figure
                                    startPoint = h.point
                                    active = h.role
                                }
                                let p = CGPoint(x: startPoint.x + g.translation.width, y: startPoint.y + g.translation.height)
                                app.update(item, to: start!.dragging(h.role, to: p))
                            }
                            .onEnded { _ in
                                start = nil
                                active = nil
                            }
                    )
            }
        }
    }
}

/// 一个节点的样子。按 PS 的习惯：白底描边的小圆是顶点，方块是尺寸，带箭头的圆是旋转。
struct HandleKnob: View {
    var role: FigureHandle.Role
    var active: Bool

    var body: some View {
        knob
            .scaleEffect(active ? 1.25 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: active)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .hoverEffect(.highlight)
    }

    @ViewBuilder private var knob: some View {
        switch role {
        case .vertex:
            Circle()
                .fill(Color(.systemBackground))
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.2))
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        case .edge:
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent, lineWidth: 2))
                .frame(width: 13, height: 13)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        case .center:
            ZStack {
                Circle().fill(Theme.accent).frame(width: 12, height: 12)
                Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 12, height: 12)
            }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        case .axisA, .axisB:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accent, lineWidth: 2.2))
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        case .rotate:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        case .size:
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Theme.accent)
                .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(Color.white, lineWidth: 2))
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        case .orbit:
            HStack(spacing: 5) {
                Image(systemName: "rotate.3d").font(.system(size: 13, weight: .semibold))
                Text("拖动旋转").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            .fixedSize()
        }
    }
}

// MARK: - 信息条

/// 选中图形时浮在旁边：名字和量（拖动时实时变），立体图形的三视图，变立体，标注开关，还原笔迹，删除。
struct ShapeInfoBar: View {
    @Bindable var item: ShapeItem
    var app: AppModel

    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.figure.name)
                    .font(.subheadline.weight(.semibold))
                Text(item.figure.facts.joined(separator: "  ·  "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .contentTransition(.numericText())

            Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)

            if case .solid(let s) = item.figure {
                HStack(spacing: 0) {
                    ForEach(Solid3.View.allCases, id: \.self) { v in
                        Button {
                            app.turn(item, to: s.viewed(v))
                        } label: {
                            Text(v.name)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 9)
                                .frame(height: 30)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(.horizontal, 2)
                Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
            }
            if !item.figure.solidOptions.isEmpty {
                Menu {
                    ForEach(item.figure.solidOptions, id: \.self) { k in
                        Button(k.name) { app.extrude(item, to: k) }
                    }
                } label: {
                    Label("变立体", systemImage: "cube.transparent")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .foregroundStyle(Color.primary)
            }
            ShapeBarIcon(systemImage: item.showsLabels ? "textformat.abc" : "textformat.abc.dottedunderline",
                         help: item.showsLabels ? "隐藏标注" : "显示标注") {
                item.showsLabels.toggle()
            }
            ShapeBarIcon(systemImage: "scribble.variable", help: "还原笔迹") { app.restoreInk(item) }
            ShapeBarIcon(systemImage: "trash", help: "删除", destructive: true) { app.delete(item) }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .fixedSize()
    }
}

private struct ShapeBarIcon: View {
    var systemImage: String
    var help: String
    var destructive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Theme.wrong : Color.primary)
        .hoverEffect(.highlight)
        .accessibilityLabel(help)
    }
}

// MARK: - 画法

enum ShapeArt {
    static let lineWidth: CGFloat = 2.6

    /// 外轮廓（点选、选中光晕用），画布坐标。
    static func outline(_ f: Figure) -> Path {
        var p = Path()
        switch f {
        case .segment(let a, let b):
            p.move(to: a)
            p.addLine(to: b)
        case .polygon(let poly):
            p.addLines(poly.vertices)
            p.closeSubpath()
        case .ellipse(let e):
            p.addLines((0...96).map { e.point(at: CGFloat($0) / 96 * 2 * .pi) })
            p.closeSubpath()
        case .solid(let s):
            let proj = s.projection()
            if let c = proj.circle {
                p.addEllipse(in: CGRect(x: c.center.x - c.radius, y: c.center.y - c.radius, width: 2 * c.radius, height: 2 * c.radius))
            } else {
                p.addLines(proj.outline)
                p.closeSubpath()
            }
        }
        return p
    }

    static func draw(_ f: Figure, in ctx: inout GraphicsContext, selected: Bool, labels: Bool) {
        let ink = Color.primary
        let outlinePath = outline(f)
        if selected {
            ctx.stroke(outlinePath, with: .color(Theme.accent.opacity(0.18)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        }
        switch f {
        case .segment(let a, let b):
            ctx.stroke(outlinePath, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            for p in [a, b] { dot(&ctx, p, ink) }
            if labels {
                let d = unit(CGPoint(x: b.x - a.x, y: b.y - a.y))
                label(&ctx, "A", at: CGPoint(x: a.x - d.x * 14, y: a.y - d.y * 14))
                label(&ctx, "B", at: CGPoint(x: b.x + d.x * 14, y: b.y + d.y * 14))
            }
        case .polygon(let poly):
            ctx.fill(outlinePath, with: .color(Theme.accent.opacity(selected ? 0.09 : 0.05)))
            ctx.stroke(outlinePath, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            drawMarks(poly, &ctx, selected: selected)
            for p in poly.vertices { dot(&ctx, p, ink) }
            if labels {
                let c = poly.centroid
                for (p, text) in zip(poly.vertices, poly.labels) {
                    let d = unit(CGPoint(x: p.x - c.x, y: p.y - c.y))
                    label(&ctx, text, at: CGPoint(x: p.x + d.x * 16, y: p.y + d.y * 16))
                }
            }
        case .ellipse(let e):
            ctx.fill(outlinePath, with: .color(Theme.accent.opacity(selected ? 0.08 : 0.04)))
            ctx.stroke(outlinePath, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth))
            let guide = StrokeStyle(lineWidth: 1.3, dash: [5, 4])
            if e.isCircle {
                if selected {
                    var r = Path()
                    r.move(to: e.center)
                    r.addLine(to: e.point(at: 0))
                    ctx.stroke(r, with: .color(Theme.accent.opacity(0.8)), style: guide)
                    let m = CGPoint(x: (e.center.x + e.point(at: 0).x) / 2, y: e.center.y - 11)
                    label(&ctx, "r", at: m, color: Theme.accent)
                }
            } else if selected || labels {
                // 长轴、短轴（虚线）和两个焦点
                var axes = Path()
                axes.move(to: e.point(at: 0)); axes.addLine(to: e.point(at: .pi))
                axes.move(to: e.point(at: .pi / 2)); axes.addLine(to: e.point(at: 3 * .pi / 2))
                ctx.stroke(axes, with: .color(ink.opacity(selected ? 0.45 : 0.25)), style: guide)
                let (f1, f2) = e.foci
                for (p, name) in [(f1, "F₁"), (f2, "F₂")] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(Theme.accent))
                    if labels { label(&ctx, name, at: CGPoint(x: p.x, y: p.y + 15), color: Theme.accent) }
                }
            }
            if labels {
                dot(&ctx, e.center, ink)
                label(&ctx, "O", at: CGPoint(x: e.center.x - 11, y: e.center.y + 12))
            }
        case .solid(let s):
            drawSolid(s.projection(), &ctx, labels: labels)
        }
    }

    private static func drawSolid(_ p: SolidProjection, _ ctx: inout GraphicsContext, labels: Bool) {
        let ink = Color.primary
        if let c = p.circle {
            // 球：左上方打光
            let rect = CGRect(x: c.center.x - c.radius, y: c.center.y - c.radius, width: 2 * c.radius, height: 2 * c.radius)
            let hi = CGPoint(x: c.center.x - c.radius * 0.35, y: c.center.y - c.radius * 0.4)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [Theme.accent.opacity(0.03), Theme.accent.opacity(0.2)]),
                center: hi, startRadius: 0, endRadius: c.radius * 1.5))
        } else {
            // 看得见的面：越背光颜色越深
            for f in p.faces {
                var path = Path()
                path.addLines(f.points)
                path.closeSubpath()
                ctx.fill(path, with: .color(Theme.accent.opacity(0.04 + 0.32 * (1 - f.light))))
            }
        }
        // 先画虚线（看不见的棱、轴、高），再把实线盖上去
        var hidden = Path(), visible = Path()
        for e in p.edges {
            if e.visible {
                visible.move(to: e.a); visible.addLine(to: e.b)
            } else {
                hidden.move(to: e.a); hidden.addLine(to: e.b)
            }
        }
        ctx.stroke(hidden, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5]))
        if let c = p.circle {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.center.x - c.radius, y: c.center.y - c.radius, width: 2 * c.radius, height: 2 * c.radius)),
                       with: .color(ink), lineWidth: lineWidth)
        }
        ctx.stroke(visible, with: .color(ink), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        guard labels else { return }
        for l in p.labels {
            if l.dot { dot(&ctx, l.point, ink) }
            label(&ctx, l.text, at: CGPoint(x: l.point.x + l.direction.x * 15, y: l.point.y + l.direction.y * 15))
        }
    }

    /// 直角记号；相等的边打短线（正方形、菱形、等边、等腰）；选中时其余的角画小弧。
    private static func drawMarks(_ poly: Polygon2, _ ctx: inout GraphicsContext, selected: Bool) {
        let v = poly.vertices, n = v.count
        let mark = Color.primary.opacity(0.75)
        for i in 0..<n {
            let p = v[(i - 1 + n) % n], q = v[i], r = v[(i + 1) % n]
            let a = unit(CGPoint(x: p.x - q.x, y: p.y - q.y)), b = unit(CGPoint(x: r.x - q.x, y: r.y - q.y))
            let ang = acos(max(-1, min(1, Double(a.x * b.x + a.y * b.y)))) * 180 / .pi
            let side = min(hypot(p.x - q.x, p.y - q.y), hypot(r.x - q.x, r.y - q.y))
            if abs(ang - 90) < 0.6 {
                let k = min(11, side * 0.2)
                var sq = Path()
                sq.move(to: CGPoint(x: q.x + a.x * k, y: q.y + a.y * k))
                sq.addLine(to: CGPoint(x: q.x + a.x * k + b.x * k, y: q.y + a.y * k + b.y * k))
                sq.addLine(to: CGPoint(x: q.x + b.x * k, y: q.y + b.y * k))
                ctx.stroke(sq, with: .color(mark), lineWidth: 1.4)
            } else if selected {
                let rad = min(20, side * 0.3)
                let t1 = atan2(a.y, a.x), t2 = atan2(b.y, b.x)
                var arc = Path()
                arc.addArc(center: q, radius: rad, startAngle: .radians(Double(t1)), endAngle: .radians(Double(t2)),
                           clockwise: shortestIsClockwise(t1, t2))
                ctx.stroke(arc, with: .color(Theme.accent.opacity(0.7)), lineWidth: 1.4)
            }
        }
        // 相等的边：按长度分组，同一组打同样多的短线
        let sides = v.indices.map { hypot(v[($0 + 1) % n].x - v[$0].x, v[($0 + 1) % n].y - v[$0].y) }
        var groups: [[Int]] = []
        for i in sides.indices {
            if let g = groups.firstIndex(where: { abs(sides[$0[0]] - sides[i]) <= 0.01 * max(sides[$0[0]], sides[i]) }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        let equal = groups.filter { $0.count >= 2 }
        guard !equal.isEmpty, n <= 6 else { return }
        for (rank, g) in equal.prefix(2).enumerated() {
            for i in g {
                let a = v[i], b = v[(i + 1) % n]
                let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let d = unit(CGPoint(x: b.x - a.x, y: b.y - a.y)), nrm = CGPoint(x: -d.y, y: d.x)
                var ticks = Path()
                for k in 0...rank {
                    let off = (CGFloat(k) - CGFloat(rank) / 2) * 4
                    let c = CGPoint(x: m.x + d.x * off, y: m.y + d.y * off)
                    ticks.move(to: CGPoint(x: c.x - nrm.x * 6, y: c.y - nrm.y * 6))
                    ticks.addLine(to: CGPoint(x: c.x + nrm.x * 6, y: c.y + nrm.y * 6))
                }
                ctx.stroke(ticks, with: .color(mark), lineWidth: 1.4)
            }
        }
    }

    private static func shortestIsClockwise(_ t1: CGFloat, _ t2: CGFloat) -> Bool {
        var d = t2 - t1
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        // SwiftUI 的 clockwise 在 y 向下的坐标里是反的
        return d < 0
    }

    private static func dot(_ ctx: inout GraphicsContext, _ p: CGPoint, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(color))
    }

    private static func label(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, color: Color = .primary) {
        ctx.draw(Text(text).font(.system(size: 16, design: .serif).italic()).foregroundStyle(color), at: p, anchor: .center)
    }

    private static func unit(_ v: CGPoint) -> CGPoint {
        let l = hypot(v.x, v.y)
        return l > 0 ? CGPoint(x: v.x / l, y: v.y / l) : CGPoint(x: 1, y: 0)
    }
}
