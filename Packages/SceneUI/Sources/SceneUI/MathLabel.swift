import SwiftMath
import SwiftUI
import UIKit

/// 用 SwiftMath 排一段 LaTeX。P1 的识别回显、direct 模式的正确项、右侧公式都用这一个组件。
/// 排不了的式子（SwiftMath 报错）退回等宽原文，不让排版挡住演示。
public struct MathLabel: UIViewRepresentable {
    public var latex: String
    public var fontSize: CGFloat
    public var color: UIColor
    public var alignment: MTTextAlignment

    public init(_ latex: String, fontSize: CGFloat = 22, color: UIColor = .label, alignment: MTTextAlignment = .left) {
        self.latex = latex
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
    }

    public func makeUIView(context: Context) -> MTMathUILabel {
        let v = MTMathUILabel()
        v.labelMode = .text
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    public func updateUIView(_ v: MTMathUILabel, context: Context) {
        v.latex = latex
        v.fontSize = fontSize
        v.textColor = color
        v.textAlignment = alignment
    }

    @available(iOS 16.0, *)
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        let s = uiView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? s.width, s.width), height: s.height)
    }
}
