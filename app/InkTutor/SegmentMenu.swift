import SwiftUI

/// 双击笔身后在笔尖旁弹出的菜单：函数 / 求解 / 几何。
///
/// 三个圆钮沿笔尖上方的一段圆弧展开（右手握笔时手在笔尖右下，不会挡住）；
/// 笔尖离顶太近就翻到下方。要处理的那一段笔迹用流动的虚线框标出来。
/// 用 Pencil 点选；再双击一次、落笔写字、或手指点空白处都会收起。
struct SegmentMenu: View {
    let state: SegmentMenuState
    /// 看得见的那块纸（画布坐标）：圆钮不放到屏幕外、不钻到工具栏下面。
    var visible: CGRect
    var topInset: CGFloat
    var onChoose: (SegmentKind) -> Void

    @State private var shown = false
    @State private var phase: CGFloat = 0

    private let radius: CGFloat = 92

    var body: some View {
        ZStack {
            // 这一段笔迹
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

            // 笔尖
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
                .frame(width: 18, height: 18)
                .scaleEffect(shown ? 1 : 0.2)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: shown)
                .position(state.anchor)
                .allowsHitTesting(false)

            let spots = fan()
            ForEach(Array(SegmentKind.allCases.enumerated()), id: \.element) { i, kind in
                option(kind)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                    .position(shown ? spots[i] : state.anchor)
                    .animation(.spring(response: 0.34, dampingFraction: 0.7).delay(Double(i) * 0.035), value: shown)
            }
        }
        .onAppear {
            shown = true
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -22 }
        }
    }

    /// 三个圆钮的位置：绕笔尖展开成扇形，相邻隔 50°。优先往右上方展开（右手握笔时手在笔尖右下），
    /// 依次换方向，选第一个既不压住这段笔迹、也不出屏幕、不钻到工具栏下面的。
    private func fan() -> [CGPoint] {
        let a = state.anchor
        let ink = state.segment.bounds.insetBy(dx: -8, dy: -8)
        let half: CGFloat = 34
        func spots(_ center: Double) -> [CGPoint] {
            [-50.0, 0, 50].map { d in
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

    private func option(_ kind: SegmentKind) -> some View {
        let primary = kind == .function
        return Button {
            onChoose(kind)
        } label: {
            VStack(spacing: 1) {
                glyph(kind)
                    .frame(height: 24)
                Text(kind.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(primary ? Color.white : Color.primary)
            .frame(width: 64, height: 64)
            .background {
                if primary {
                    Circle().fill(Theme.accent)
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

    @ViewBuilder private func glyph(_ kind: SegmentKind) -> some View {
        switch kind {
        case .function:
            Text("ƒ(x)").font(.system(size: 19, design: .serif).italic())
        case .solve:
            // 求导、积分、求和都在里面：用积分号加一个小 Σ 作标志
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("∫").font(.system(size: 22, design: .serif).italic())
                Text("Σ").font(.system(size: 13, design: .serif)).baselineOffset(-1)
            }
        case .geometry:
            Image(systemName: "triangle").font(.system(size: 18, weight: .medium))
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
