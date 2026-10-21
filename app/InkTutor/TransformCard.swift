import InkCore
import SceneUI
import SwiftUI

/// 「看变换」：2×2 矩阵式子右上角挂的一张卡片。浅灰的是原来的方格，蓝色的是变换以后的方格；
/// 单位正方形变成涂色的平行四边形（面积 ×|det|），红、绿箭头是 î、ĵ 变到了哪里。
/// 拖箭头的尖改矩阵（靠近半格时吸到半格上），纸上的式子跟着改写；「逆变换」把图形一点点变回单位正方形，「复位」回到刚写的矩阵。
struct TransformCard: View {
    @Bindable var item: FunctionItem
    var app: AppModel
    /// 逆变换的动画进度：0 是矩阵本身，1 是变回单位正方形。
    @State private var undo: Double = 0
    @State private var animation: Task<Void, Never>?

    private var name: String { MatrixMath.name(item.solveSource ?? "") ?? "A" }

    var body: some View {
        if let map = item.linearMap {
            if item.card.minimized {
                CardPill(tint: Theme.accent, title: "\(name) 的变换") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { item.card.minimized = false }
                }
                .pinned(.bottomLeading, at: CGPoint(x: item.anchor.x + 10, y: item.anchor.y - 2))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                TransformableCard(frame: $item.card, selected: app.selection == .card(item.id), dimmed: item.showingInk,
                                  onSelect: { toggleSelection() }) {
                    header
                } content: { interactive in
                    VStack(spacing: 0) {
                        TransformPlane(map: map, shown: map.interpolated(to: .identity, undo),
                                       interactive: interactive && !item.showingInk) { moved in
                            if undo > 0 { stopUndo() }
                            app.setLinearMap(item, moved)
                        }
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        footer(map)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func toggleSelection() {
        withAnimation(.easeOut(duration: 0.15)) {
            app.selection = app.selection == .card(item.id) ? nil : .card(item.id)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 22)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("\(name) 的变换").font(.subheadline.weight(.semibold))
            if !app.compact {
                Text("拖动箭头试试").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HeaderButton(systemImage: "arrow.down.right.and.arrow.up.left", help: "收起") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    if app.selection?.id == item.id { app.selection = nil }
                    item.card.minimized = true
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
    }

    private func footer(_ map: LinearMap2) -> some View {
        let undone = undo > 0.5
        return VStack(alignment: .leading, spacing: 5) {
            Text(undone ? "\(name)⁻¹ 再把它变回单位正方形" : map.kindText)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 8) {
                Text(map.areaText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if undone, let inv = map.inverse {
                    MathLabel(name + "^{-1} = " + inv.latex, fontSize: 12, color: .secondaryLabel)
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                FooterButton(title: undone ? "再变换" : "逆变换", systemImage: undone ? "arrow.uturn.forward" : "arrow.uturn.backward",
                             enabled: map.isInvertible) {
                    runUndo(to: undone ? 0 : 1)
                }
                if let original = item.originalMap, original != map {
                    FooterButton(title: "复位", systemImage: "arrow.counterclockwise", enabled: true) {
                        stopUndo()
                        app.resetTransform(item)
                    }
                }
                Spacer(minLength: 0)
                if !map.isInvertible {
                    Text("det = 0，没有逆变换")
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 逆变换：在 0.6 秒里把图形从矩阵的样子变回单位正方形（再点一次变回去）。
    private func runUndo(to target: Double) {
        animation?.cancel()
        let from = undo
        animation = Task { @MainActor in
            let steps = 36
            for k in 1...steps {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
                let t = Double(k) / Double(steps)
                let ease = t < 0.5 ? 2 * t * t : 1 - (2 - 2 * t) * (2 - 2 * t) / 2
                undo = from + (target - from) * ease
            }
        }
    }

    private func stopUndo() {
        animation?.cancel()
        undo = 0
    }
}

private struct FooterButton: View {
    var title: String
    var systemImage: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.accent.opacity(enabled ? 0.12 : 0.05), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.accent : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .hoverEffect(.highlight)
    }
}

// MARK: - 平面

/// 取景：中心（单位坐标）和每个单位多少 point。拖箭头时固定住，免得图在手指下面跟着缩放。
private struct PlaneFrame: Equatable {
    var cx: Double
    var cy: Double
    var scale: Double

    func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + (x - cx) * scale, y: Double(size.height) / 2 - (y - cy) * scale)
    }

    func value(at p: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        (cx + (Double(p.x) - Double(size.width) / 2) / scale, cy - (Double(p.y) - Double(size.height) / 2) / scale)
    }

    /// 原来的单位正方形、变换后的平行四边形和两支箭头都框进来，四周留一点。
    static func fitting(_ m: LinearMap2, in size: CGSize) -> PlaneFrame {
        let xs: [Double] = [-0.4, 1, m.a, m.b, m.a + m.b]
        let ys: [Double] = [-0.4, 1, m.c, m.d, m.c + m.d]
        let x0 = xs.min() ?? 0, x1 = xs.max() ?? 1
        let y0 = ys.min() ?? 0, y1 = ys.max() ?? 1
        let spanX = max(x1 - x0, 2.4) + 1.4
        let spanY = max(y1 - y0, 2.4) + 1.4
        let scale = min(Double(size.width) / spanX, Double(size.height) / spanY)
        return PlaneFrame(cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, scale: max(scale, 6))
    }
}

/// 画原来的方格、变换后的方格、单位正方形变成的平行四边形和 î、ĵ 两支箭头；拖箭头尖改矩阵。
private struct TransformPlane: View {
    /// 矩阵本身（拖动按它算）。
    var map: LinearMap2
    /// 画出来的样子（逆变换动画时在 map 和单位矩阵之间）。
    var shown: LinearMap2
    var interactive: Bool
    var onMove: (LinearMap2) -> Void

    private enum Arrow { case i, j }
    @State private var dragging: Arrow?
    @State private var frozen: PlaneFrame?

    private static let iColor = Color(red: 0.86, green: 0.27, blue: 0.22)
    private static let jColor = Color(red: 0.13, green: 0.60, blue: 0.36)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let f = frozen ?? PlaneFrame.fitting(map, in: size)
            Canvas { ctx, size in
                draw(&ctx, size: size, frame: f)
            }
            .contentShape(Rectangle())
            .gesture(drag(frame: f, size: size), including: interactive ? .all : .none)
            .accessibilityLabel("矩阵变换的图")
        }
    }

    // MARK: 拖箭头

    private func drag(frame f: PlaneFrame, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragging == nil {
                    let tipI = f.point(map.a, map.c, in: size), tipJ = f.point(map.b, map.d, in: size)
                    let di = hypot(tipI.x - g.startLocation.x, tipI.y - g.startLocation.y)
                    let dj = hypot(tipJ.x - g.startLocation.x, tipJ.y - g.startLocation.y)
                    guard min(di, dj) < 34 else { return }
                    dragging = di <= dj ? .i : .j
                    frozen = f
                }
                let v = f.value(at: g.location, in: size)
                let x = Self.snap(v.x), y = Self.snap(v.y)
                var m = map
                if dragging == .i {
                    m.a = x
                    m.c = y
                } else {
                    m.b = x
                    m.d = y
                }
                if m != map { onMove(m) }
            }
            .onEnded { _ in
                dragging = nil
                withAnimation(.easeOut(duration: 0.25)) { frozen = nil }
            }
    }

    /// 靠近半格就吸到半格上，否则保留一位小数。
    static func snap(_ v: Double) -> Double {
        let coarse = (v * 2).rounded() / 2
        let fine = (v * 10).rounded() / 10
        let r = abs(v - coarse) < 0.12 ? coarse : fine
        return r == 0 ? 0 : r
    }

    // MARK: 画

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, frame f: PlaneFrame) {
        let ink = Color.primary
        let m = shown
        // 原来的方格和坐标轴
        let lo = f.value(at: .zero, in: size), hi = f.value(at: CGPoint(x: size.width, y: size.height), in: size)
        var grid = Path()
        var x = (lo.x).rounded(.down)
        while x <= hi.x {
            grid.move(to: f.point(x, hi.y - 1, in: size))
            grid.addLine(to: f.point(x, lo.y + 1, in: size))
            x += 1
        }
        var y = (hi.y).rounded(.down)
        while y <= lo.y {
            grid.move(to: f.point(lo.x - 1, y, in: size))
            grid.addLine(to: f.point(hi.x + 1, y, in: size))
            y += 1
        }
        ctx.stroke(grid, with: .color(ink.opacity(0.07)), lineWidth: 0.75)
        var axes = Path()
        axes.move(to: f.point(lo.x - 1, 0, in: size))
        axes.addLine(to: f.point(hi.x + 1, 0, in: size))
        axes.move(to: f.point(0, hi.y - 1, in: size))
        axes.addLine(to: f.point(0, lo.y + 1, in: size))
        ctx.stroke(axes, with: .color(ink.opacity(0.35)), lineWidth: 1)

        // 变换以后的方格：原来的每条格线 x = k、y = k 都变到新的位置
        var moved = Path()
        let n = 10.0
        var k = -n
        while k <= n {
            let a0 = m.apply(k, -n), a1 = m.apply(k, n)
            moved.move(to: f.point(a0.x, a0.y, in: size))
            moved.addLine(to: f.point(a1.x, a1.y, in: size))
            let b0 = m.apply(-n, k), b1 = m.apply(n, k)
            moved.move(to: f.point(b0.x, b0.y, in: size))
            moved.addLine(to: f.point(b1.x, b1.y, in: size))
            k += 1
        }
        ctx.stroke(moved, with: .color(Theme.accent.opacity(0.22)), lineWidth: 1)

        // 原来的单位正方形（虚线）和变成的平行四边形（涂色）
        var unit = Path()
        unit.addLines([f.point(0, 0, in: size), f.point(1, 0, in: size), f.point(1, 1, in: size), f.point(0, 1, in: size)])
        unit.closeSubpath()
        ctx.stroke(unit, with: .color(ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        var square = Path()
        square.addLines([f.point(0, 0, in: size), f.point(m.a, m.c, in: size),
                         f.point(m.a + m.b, m.c + m.d, in: size), f.point(m.b, m.d, in: size)])
        square.closeSubpath()
        let flipped = m.determinant < 0
        ctx.fill(square, with: .color((flipped ? Theme.warn : Theme.accent).opacity(0.2)))
        ctx.stroke(square, with: .color(flipped ? Theme.warn : Theme.accent), lineWidth: 1.6)

        // 面积倍数写在平行四边形中间
        let mid = f.point((m.a + m.b) / 2, (m.c + m.d) / 2, in: size)
        let factor = abs(m.determinant)
        let label = Text("面积 ×" + Self.plain(factor))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(flipped ? Theme.warn : Theme.accent)
        ctx.draw(label, at: mid, anchor: .center)

        // î、ĵ：原来的位置画淡的，变到哪里画实的箭头，尖上一个可以拖的圆点
        arrow(&ctx, from: f.point(0, 0, in: size), to: f.point(1, 0, in: size), color: Self.iColor.opacity(0.3), width: 1.5, tip: false)
        arrow(&ctx, from: f.point(0, 0, in: size), to: f.point(0, 1, in: size), color: Self.jColor.opacity(0.3), width: 1.5, tip: false)
        let ti = f.point(m.a, m.c, in: size), tj = f.point(m.b, m.d, in: size)
        arrow(&ctx, from: f.point(0, 0, in: size), to: ti, color: Self.iColor, width: 2.8, tip: interactive)
        arrow(&ctx, from: f.point(0, 0, in: size), to: tj, color: Self.jColor, width: 2.8, tip: interactive)
        caption(&ctx, "î (" + Self.plain(m.a) + ", " + Self.plain(m.c) + ")", near: ti, color: Self.iColor, size: size)
        caption(&ctx, "ĵ (" + Self.plain(m.b) + ", " + Self.plain(m.d) + ")", near: tj, color: Self.jColor, size: size)
    }

    private func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat, tip: Bool) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 0.001)
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        if len > 8 {
            let ux = dx / len, uy = dy / len
            let head: CGFloat = 9
            p.move(to: CGPoint(x: b.x - ux * head - uy * head * 0.55, y: b.y - uy * head + ux * head * 0.55))
            p.addLine(to: b)
            p.addLine(to: CGPoint(x: b.x - ux * head + uy * head * 0.55, y: b.y - uy * head - ux * head * 0.55))
        }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        if tip {
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 11, y: b.y - 11, width: 22, height: 22)), with: .color(color.opacity(0.16)))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 4.5, y: b.y - 4.5, width: 9, height: 9)), with: .color(color))
        }
    }

    private func caption(_ ctx: inout GraphicsContext, _ text: String, near q: CGPoint, color: Color, size: CGSize) {
        let t = ctx.resolve(Text(text).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(color))
        let m = t.measure(in: CGSize(width: 200, height: 30))
        var x = q.x + 10
        if x + m.width > size.width - 4 { x = q.x - 10 - m.width }
        let y = min(max(q.y - m.height - 8, 2), size.height - m.height - 2)
        ctx.draw(t, at: CGPoint(x: x, y: y), anchor: .topLeading)
    }

    static func plain(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s == "-0" { s = "0" }
        return s.replacingOccurrences(of: "-", with: "−")
    }
}
