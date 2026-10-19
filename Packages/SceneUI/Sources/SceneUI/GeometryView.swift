import SwiftUI

/// 动态几何（第三幕）。照 GeoGebra 的对象模型：
/// - 自由点（role = free）可以拖；
/// - 依赖点（role = constrained）不存真坐标，每次由 relations 重算（中点）；
/// - 线段只引用点的 id，所以拖顶点时中线自动仍过对边中点；三条中线都在时，交点自己出现。
public struct GeometryView: View {
    @Bindable var model: SceneModel
    let scene: GeometryScene
    @State private var dragging: String?
    @State private var fit: CGAffineTransform?

    public init(model: SceneModel, scene: GeometryScene) {
        self.model = model
        self.scene = scene
    }

    public var body: some View {
        GeometryReader { geo in
            let pos = model.resolvedPoints(scene)
            let t = fit ?? Self.fitTransform(points: Array(pos.values), into: geo.size)
            Canvas { ctx, _ in
                draw(ctx: &ctx, pos: pos, t: t)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if fit == nil { fit = t }   // 拖动期间锁住缩放，避免图跟着跳
                        let inv = t.inverted()
                        if dragging == nil {
                            dragging = scene.points
                                .filter { $0.role == "free" }
                                .map { ($0.id, pos[$0.id]!.applying(t)) }
                                .filter { hypot($0.1.x - g.startLocation.x, $0.1.y - g.startLocation.y) < 32 }
                                .min { hypot($0.1.x - g.startLocation.x, $0.1.y - g.startLocation.y) < hypot($1.1.x - g.startLocation.x, $1.1.y - g.startLocation.y) }?.0
                        }
                        if let id = dragging { model.freePoints[id] = g.location.applying(inv) }
                    }
                    .onEnded { _ in dragging = nil }
            )
            .overlay(alignment: .topLeading) { caption(pos: pos) }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
        .accessibilityLabel("动态几何：拖动 A、B、C")
    }

    private var medianIDs: [String] { scene.objects.filter { $0.id.hasPrefix("median") }.map(\.id) }

    private func draw(ctx: inout GraphicsContext, pos: [String: CGPoint], t: CGAffineTransform) {
        for o in scene.objects where o.type == "segment" && o.points.count == 2 {
            guard let a = pos[o.points[0]], let b = pos[o.points[1]] else { continue }
            var p = Path()
            p.move(to: a.applying(t)); p.addLine(to: b.applying(t))
            let isMedian = o.id.hasPrefix("median")
            ctx.stroke(p, with: .color(isMedian ? .orange : .primary.opacity(0.85)),
                       style: StrokeStyle(lineWidth: isMedian ? 2.5 : 3, lineCap: .round, dash: isMedian ? [8, 5] : []))
        }
        // 中点标记：两侧各一道短线表示「相等」
        for r in scene.relations where r.type == "midpoint" {
            guard let a = pos[r.of[0]], let b = pos[r.of[1]], let m = pos[r.point] else { continue }
            for end in [a, b] {
                let q = CGPoint(x: (end.x + m.x) / 2, y: (end.y + m.y) / 2).applying(t)
                let dir = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                let len = max(hypot(dir.dx, dir.dy), 1)
                let nx = -dir.dy / len * 7, ny = dir.dx / len * 7
                var tick = Path()
                tick.move(to: CGPoint(x: q.x - nx, y: q.y - ny)); tick.addLine(to: CGPoint(x: q.x + nx, y: q.y + ny))
                ctx.stroke(tick, with: .color(.orange), lineWidth: 2)
            }
        }
        // 三条中线都在：重心
        if medianIDs.count == 3, let a = pos["A"], let b = pos["B"], let c = pos["C"] {
            let g = CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3).applying(t)
            ctx.fill(Path(ellipseIn: CGRect(x: g.x - 7, y: g.y - 7, width: 14, height: 14)), with: .color(.red))
            ctx.draw(Text("G").font(.headline).foregroundStyle(.red), at: g.applying(.init(translationX: 14, y: -12)))
        }
        for p in scene.points {
            guard let q = pos[p.id]?.applying(t) else { continue }
            let free = p.role == "free"
            let r: CGFloat = free ? 9 : 6
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(free ? .blue : .orange))
            if free && dragging == p.id {
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 18, y: q.y - 18, width: 36, height: 36)), with: .color(.blue.opacity(0.4)), lineWidth: 2)
            }
            ctx.draw(Text(p.id).font(.headline).foregroundStyle(free ? .blue : .orange), at: q.applying(.init(translationX: 16, y: -14)))
        }
    }

    @ViewBuilder private func caption(pos: [String: CGPoint]) -> some View {
        let n = medianIDs.count
        Text(n == 3 ? "拖动 A、B、C：三条中线始终交于一点 G" : n > 0 ? "拖动 A、B、C：中线始终过对边中点" : "拖动 A、B、C 试试")
            .font(.footnote)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
    }

    /// 把草图坐标（左半屏画布 point）缩放平移进右半屏，留边。
    static func fitTransform(points: [CGPoint], into size: CGSize, pad: CGFloat = 48) -> CGAffineTransform {
        guard let first = points.first else { return .identity }
        var r = CGRect(origin: first, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        let w = max(r.width, 1), h = max(r.height, 1)
        let s = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h)
        let ox = (size.width - w * s) / 2 - r.minX * s
        let oy = (size.height - h * s) / 2 - r.minY * s
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: ox, ty: oy)
    }
}
