import InkCore
import SwiftUI

/// 双击笔身后在笔尖旁弹出的菜单：函数 / 求解 / 几何。
/// 识别结果里有矩阵时再加一枚「矩阵」，点开是计算、求逆矩阵、求行列式。
///
/// 圆钮沿笔尖上方的一段圆弧展开（右手握笔时手在笔尖右下，不会挡住）；
/// 笔尖离顶太近就翻到下方。要处理的那一段笔迹用流动的虚线框标出来。
/// 用 Pencil 点选；再双击一次（或再点「识别」）、落笔写字、或手指点空白处都会收起。
/// 点工具栏的「识别」时没有笔尖落点，弹在最后一笔收笔的地方。
struct SegmentMenu: View {
    let state: SegmentMenuState
    /// 看得见的那块纸（画布坐标）：圆钮不放到屏幕外、不钻到工具栏下面。
    var visible: CGRect
    var topInset: CGFloat
    /// 窗口化时整个菜单小一号。
    var compact = false
    var onChoose: (SegmentKind) -> Void
    var onMatrix: (MatrixAction) -> Void

    @State private var shown = false
    @State private var phase: CGFloat = 0

    private var radius: CGFloat { compact ? 68 : 92 }
    private var size: CGFloat { compact ? 46 : 64 }

    private var kinds: [SegmentKind] {
        var list: [SegmentKind] = [.function, .solve]
        if state.offersMatrix { list.append(.matrix) }
        list.append(.geometry)
        return list
    }

    var body: some View {
        let spots = fan(kinds.count)
        ZStack {
            let r = state.segment.bounds.insetBy(dx: -12, dy: -10)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: phase))
                )
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: shown)
                .allowsHitTesting(false)

            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
                .frame(width: 18, height: 18)
                .scaleEffect(shown ? 1 : 0.2)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: shown)
                .position(state.anchor)
                .allowsHitTesting(false)

            ForEach(Array(kinds.enumerated()), id: \.element) { i, kind in
                option(kind)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                    .position(shown ? spots[i] : state.anchor)
                    .animation(.spring(response: 0.34, dampingFraction: 0.7).delay(Double(i) * 0.035), value: shown)
                    .animation(.spring(response: 0.34, dampingFraction: 0.72), value: state.offersMatrix)
            }

            if state.matrixOpen, let index = kinds.firstIndex(of: .matrix) {
                let actions = submenuSpots(from: spots[index])
                ForEach(Array(MatrixAction.allCases.enumerated()), id: \.element) { i, action in
                    matrixAction(action)
                        .position(actions[i])
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: state.matrixOpen)
        .onAppear {
            shown = true
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -22 }
        }
    }

    /// 圆钮绕笔尖展开成扇形。三个时间隔 50°，多了「矩阵」就稍收一点。
    /// 优先往右上方展开，选第一个既不压住这段笔迹、也不出屏幕、不钻到工具栏下面的。
    private func fan(_ count: Int) -> [CGPoint] {
        let a = state.anchor
        let ink = state.segment.bounds.insetBy(dx: -8, dy: -8)
        let half: CGFloat = size / 2 + 2
        let step = count > 3 ? 42.0 : 50.0
        let offsets = (0..<count).map { step * (Double($0) - Double(count - 1) / 2) }
        func spots(_ center: Double) -> [CGPoint] {
            offsets.map { d in
                let t = (center + d) * .pi / 180
                return CGPoint(x: a.x + radius * CGFloat(cos(t)), y: a.y + radius * CGFloat(sin(t)))
            }
        }
        func fits(_ ps: [CGPoint]) -> Bool {
            ps.allSatisfy { p in
                let box = CGRect(x: p.x - half, y: p.y - half, width: 2 * half, height: 2 * half)
                return !box.intersects(ink) && box.minX > visible.minX + 8 && box.maxX < visible.maxX - 8
                    && box.minY > visible.minY + topInset && box.maxY < visible.maxY - 8
            }
        }
        for center in [-60.0, -90, -30, 0, -120, -150, 180, 30, 150, 60, 120, 90] where fits(spots(center)) {
            return spots(center)
        }
        return spots(-90).map {
            CGPoint(x: min(max($0.x, visible.minX + 44), visible.maxX - 44),
                    y: min(max($0.y, visible.minY + topInset + 40), visible.maxY - 44))
        }
    }

    /// 二级菜单从「矩阵」再往外排开，不盖住那一圈主按钮。
    private func submenuSpots(from matrix: CGPoint) -> [CGPoint] {
        let vx = matrix.x - state.anchor.x
        let vy = matrix.y - state.anchor.y
        let len = max(1, hypot(vx, vy))
        let ux = vx / len
        let uy = vy / len
        let sx = -uy
        let sy = ux
        let center = CGPoint(x: matrix.x + ux * 108, y: matrix.y + uy * 108)
        return (-1...1).map { i in
            let p = CGPoint(x: center.x + sx * CGFloat(i) * 128, y: center.y + sy * CGFloat(i) * 128)
            return CGPoint(x: min(max(p.x, visible.minX + 64), visible.maxX - 64),
                           y: min(max(p.y, visible.minY + topInset + 22), visible.maxY - 22))
        }
    }

    private func option(_ kind: SegmentKind) -> some View {
        let primary = kind == .function || (kind == .matrix && state.matrixOpen)
        return Button {
            onChoose(kind)
        } label: {
            VStack(spacing: 1) {
                glyph(kind)
                    .frame(height: compact ? 17 : 24)
                    .scaleEffect(compact ? 0.75 : 1)
                Text(kind.title)
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
            }
            .foregroundStyle(primary ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background {
                if primary {
                    Circle().fill(kind == .matrix ? Theme.ok : Theme.accent)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .overlay(Circle().strokeBorder(primary ? Color.white.opacity(0.25) : Theme.hairline))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(MenuPressStyle())
        .hoverEffect(.lift)
        .accessibilityLabel("\(kind.title)：\(kind.hint)")
    }

    private func matrixAction(_ action: MatrixAction) -> some View {
        Button {
            onMatrix(action)
        } label: {
            Label(title(action), systemImage: icon(action))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 118, height: 36)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                .contentShape(Capsule())
        }
        .buttonStyle(MenuPressStyle())
        .hoverEffect(.lift)
        .accessibilityLabel(title(action))
    }

    private func title(_ action: MatrixAction) -> String {
        switch action {
        case .calculate: return "计算"
        case .inverse: return "求逆矩阵"
        case .determinant: return "求行列式"
        }
    }

    private func icon(_ action: MatrixAction) -> String {
        switch action {
        case .calculate: return "plus.forwardslash.minus"
        case .inverse: return "arrow.uturn.backward"
        case .determinant: return "number"
        }
    }

    @ViewBuilder private func glyph(_ kind: SegmentKind) -> some View {
        switch kind {
        case .function:
            Text("ƒ(x)").font(.system(size: 19, design: .serif).italic())
        case .solve:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("∫").font(.system(size: 22, design: .serif).italic())
                Text("Σ").font(.system(size: 13, design: .serif)).baselineOffset(-1)
            }
        case .geometry:
            Image(systemName: "triangle").font(.system(size: 18, weight: .medium))
        case .matrix:
            Image(systemName: "square.grid.2x2").font(.system(size: 16, weight: .medium))
        }
    }
}

private struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
