import SwiftUI

/// 双击笔身后在笔尖旁弹出的菜单：函数 / 推导 / 几何。
///
/// 三个圆钮沿笔尖上方的一段圆弧展开（右手握笔时手在笔尖右下，不会挡住）；
/// 笔尖离顶太近就翻到下方。要处理的那一段笔迹用流动的虚线框标出来。
/// 用 Pencil 点选；再双击一次、落笔写字、或手指点空白处都会收起。
struct SegmentMenu: View {
    let state: SegmentMenuState
    var boardSize: CGSize
    var topInset: CGFloat
    var onChoose: (SegmentKind) -> Void

    @State private var shown = false
    @State private var phase: CGFloat = 0

    private let radius: CGFloat = 86

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
                .allowsHitTesting(false)

            // 笔尖
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
                .frame(width: 18, height: 18)
                .scaleEffect(shown ? 1 : 0.2)
                .position(state.anchor)
                .allowsHitTesting(false)

            ForEach(Array(SegmentKind.allCases.enumerated()), id: \.element) { i, kind in
                option(kind)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                    .position(shown ? point(i) : state.anchor)
                    .animation(.spring(response: 0.34, dampingFraction: 0.7).delay(Double(i) * 0.035), value: shown)
            }
        }
        .onAppear {
            shown = true
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -22 }
        }
    }

    private func point(_ i: Int) -> CGPoint {
        let a = state.anchor
        let up = a.y - radius - 44 > topInset
        let angles: [Double] = up ? [-152, -90, -28] : [152, 90, 28]
        let t = angles[i] * .pi / 180
        let p = CGPoint(x: a.x + radius * CGFloat(cos(t)), y: a.y + radius * CGFloat(sin(t)))
        return CGPoint(x: min(max(p.x, 44), boardSize.width - 44), y: min(max(p.y, topInset + 40), boardSize.height - 44))
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
        case .derivation:
            Text("ƒ′").font(.system(size: 21, design: .serif).italic())
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
