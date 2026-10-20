import Foundation

/// direct 模式（D5）的一句说明：按错误码套模板，不调模型、没有延迟。
/// 例：source = -3x → 「x 求导得 1，所以 −3x 求导后是 −3。」
public enum Explanation {
    /// 求导一项的说明。`coef`、`pow` 是原函数里那一项。
    public static func derivative(coef: Double, pow: Int) -> String {
        let src = display(coef: coef, pow: pow)
        if pow == 0 {
            return "常数求导得 0，所以 \(src) 求导后是 0。"
        }
        let expected = display(coef: coef * Double(pow), pow: pow - 1)
        if pow == 1 {
            return "x 求导得 1，所以 \(src) 求导后是 \(expected)。"
        }
        return "x\(sup(pow)) 求导得 \(pow)x\(sup(pow - 1))，所以 \(src) 求导后是 \(expected)。"
    }

    /// 错误码（MathEngine 给出）→ 一句话。拿不到原函数那一项时用这一组。
    public static func generic(kind: String, wrong: String, expected: String?) -> String {
        let w = pretty(wrong)
        let e = expected.map(pretty)
        switch kind {
        case "not_differentiated":
            return "\(w) 是原函数里的项，还要再求一次导" + (e.map { "，结果是 \($0)。" } ?? "。")
        case "missing_term":
            return "原函数还有一项没有求导" + (e.map { "，它的导数是 \($0)。" } ?? "。")
        case "extra_term":
            return "\(w) 这一项不该出现，原函数里没有项求导后会得到它。"
        default:
            return e.map { "\(w) 这一项算错了，正确的是 \($0)。" } ?? "\(w) 这一项算错了。"
        }
    }

    /// 1, -3, 1 → "x"；-3, 1 → "−3x"；1.5, 2 → "1.5x²"
    public static func display(coef: Double, pow: Int) -> String {
        let neg = coef < 0
        let a = abs(coef)
        let num = a == a.rounded() ? String(Int(a)) : String(format: "%g", a)
        var body: String
        switch pow {
        case 0: body = num
        case 1: body = (a == 1 ? "" : num) + "x"
        default: body = (a == 1 ? "" : num) + "x" + sup(pow)
        }
        if coef == 0 { body = "0" }
        return (neg && coef != 0 ? "−" : "") + body
    }

    static func sup(_ n: Int) -> String {
        let map: [Character: String] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return n == 1 ? "" : String(n).map { map[$0] ?? String($0) }.joined()
    }

    /// LaTeX 小片段 → 屏幕上好读的写法：-3x^2 → −3x²
    public static func pretty(_ latex: String) -> String {
        var s = LatexTerms.normalize(latex).replacingOccurrences(of: "-", with: "−").replacingOccurrences(of: "*", with: "·")
        while let r = s.range(of: #"\^\d+"#, options: .regularExpression) {
            let n = Int(s[r].dropFirst()) ?? 0
            s.replaceSubrange(r, with: sup(n))
        }
        return s
    }
}
