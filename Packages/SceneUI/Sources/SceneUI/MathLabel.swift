import SwiftMath
import SwiftUI
import UIKit

/// 用 SwiftMath 排一段 LaTeX。P1 的识别回显、direct 模式的正确项、换掉手写笔迹的标准式子、卡片标题都用这一个组件。
/// 排不了的式子（SwiftMath 报错）退回等宽原文，不让排版挡住演示。
public struct MathLabel: UIViewRepresentable {
    /// .inline 是行内排法（分式小一号），.display 是独立成行的排法；换掉手写笔迹时用 .display。
    public enum Style {
        case inline, display

        var mode: MTMathUILabelMode { self == .display ? .display : .text }
    }

    public var latex: String
    public var fontSize: CGFloat
    public var color: UIColor
    public var alignment: MTTextAlignment
    public var style: Style

    public init(_ latex: String, fontSize: CGFloat = 22, color: UIColor = .label, alignment: MTTextAlignment = .left,
                style: Style = .inline) {
        self.latex = latex
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.style = style
    }

    public func makeUIView(context: Context) -> MTMathUILabel {
        let v = MTMathUILabel()
        // 只负责显示：点按、拖动交给外面的 SwiftUI 手势（点式子选中、拖式子移动）
        v.isUserInteractionEnabled = false
        v.displayErrorInline = false
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    public func updateUIView(_ v: MTMathUILabel, context: Context) {
        Self.configure(v, latex: latex, fontSize: fontSize, color: color, mode: style.mode)
        v.textAlignment = alignment
    }

    @available(iOS 16.0, *)
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        let s = uiView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? s.width, s.width), height: s.height)
    }

    /// 排出来有多大（画布 point）。App 用它把标准式子放在原来那行笔迹的位置，并把函数卡片挂在式子右上角。
    public static func measure(_ latex: String, fontSize: CGFloat, style: Style = .display) -> CGSize {
        let v = MTMathUILabel()
        v.displayErrorInline = false
        configure(v, latex: latex, fontSize: fontSize, color: .label, mode: style.mode)
        return v.intrinsicContentSize
    }

    /// SwiftMath 能不能排这一段（不能时界面显示原文）。
    public static func canTypeset(_ latex: String) -> Bool {
        var error: NSError?
        return MTMathListBuilder.build(fromString: typesettable(latex), error: &error) != nil && error == nil
    }

    /// 识别器给的写法里有几样 SwiftMath 不认：\dfrac \tfrac \operatorname{…} \mathrm{…} 的函数名、\displaystyle、$。
    public static func typesettable(_ latex: String) -> String {
        var s = latex
        for (a, b) in [("$", ""), ("\\displaystyle", ""), ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac"), ("\\ ", "\\,")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        let known = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
                     "ln", "lg", "log", "exp"]
        while let r = s.range(of: #"\\(operatorname|mathrm)\{([a-z]+)\}"#, options: .regularExpression) {
            let inner = String(s[r]).components(separatedBy: CharacterSet(charactersIn: "{}"))[1]
            s.replaceSubrange(r, with: known.contains(inner) ? "\\" + inner + " " : (inner.count == 1 ? inner : "\\text{\(inner)}"))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func configure(_ v: MTMathUILabel, latex: String, fontSize: CGFloat, color: UIColor, mode: MTMathUILabelMode) {
        v.labelMode = mode
        v.fontSize = fontSize
        v.textColor = color
        let tex = typesettable(latex)
        v.latex = tex
        if v.error != nil {
            // 原文照样显示出来，好让学生点开手动改
            v.latex = "\\texttt{" + tex.replacingOccurrences(of: "\\", with: "\\backslash ")
                .replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}") + "}"
            if v.error != nil { v.latex = "\\text{?}" }
        }
    }
}
