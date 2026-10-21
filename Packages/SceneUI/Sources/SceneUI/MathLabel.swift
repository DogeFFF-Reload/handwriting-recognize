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
    /// 矩阵换行写成 `\\ `。这里若把其中的 `\ ` 换成 `\,`，下一行开头会画出一个逗号。
    public static func typesettable(_ latex: String) -> String {
        var s = stripCommasInsideMatrices(latex)
        for (a, b) in [("$", ""), ("\\displaystyle", ""), ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        s = thinSpaces(s)
        let known = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
                     "ln", "lg", "log", "exp"]
        while let r = s.range(of: #"\\(operatorname|mathrm)\{([a-z]+)\}"#, options: .regularExpression) {
            let inner = String(s[r]).components(separatedBy: CharacterSet(charactersIn: "{}"))[1]
            s.replaceSubrange(r, with: known.contains(inner) ? "\\" + inner + " " : (inner.count == 1 ? inner : "\\text{\(inner)}"))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `\ ` 换成细间距 `\,`。`\\ ` 是矩阵换行，第二个反斜杠后面的空格不能动。
    private static func thinSpaces(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == " ", i == 0 || chars[i - 1] != "\\" {
                out.append("\\,")
                i += 2
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    /// 识别器常在矩阵里多写逗号，尤其是下一行开头。排版时去掉，不改矩阵外面的逗号。
    private static func stripCommasInsideMatrices(_ s: String) -> String {
        let envs = ["pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix", "matrix", "array"]
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "\\" else {
                out.append(s[i])
                i = s.index(after: i)
                continue
            }
            let matched = envs.first { env in s[i...].hasPrefix("\\begin{\(env)}") }
            guard let env = matched,
                  let bodyStart = s.index(i, offsetBy: "\\begin{\(env)}".count, limitedBy: s.endIndex),
                  let end = s.range(of: "\\end{\(env)}", range: bodyStart..<s.endIndex) else {
                out.append(s[i])
                i = s.index(after: i)
                continue
            }
            out.append(contentsOf: s[i..<bodyStart])
            out.append(contentsOf: s[bodyStart..<end.lowerBound].filter { $0 != "," })
            out.append(contentsOf: s[end])
            i = end.upperBound
        }
        return out
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
