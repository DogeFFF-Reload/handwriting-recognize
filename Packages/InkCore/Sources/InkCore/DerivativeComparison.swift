import Foundation

/// 「批改」的后备：原函数不是多项式（sin x、e^x、分式……）时 MathEngine 判不了，
/// 就把学生写的右边和真正的导数在一串点上比数值，只判整行对不对，不圈到项。
public enum DerivativeComparison {
    /// 避开整数点（ln、分母、根号最容易在那里出事）。
    static let samples: [Double] = [-2.7, -1.9, -1.3, -0.6, -0.23, 0.37, 0.8, 1.45, 2.1, 2.9]

    /// `f^{\prime}\left( x\right) =3x^{2}` → `3x^{2}`；没有等号或等号后面是空的返回 nil。
    public static func rightHandSide(_ latex: String) -> String? {
        guard let eq = latex.firstIndex(of: "=") else { return nil }
        let rhs = latex[latex.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rhs.isEmpty ? nil : rhs
    }

    /// 学生写的右边和 `expected` 在取样点上是否处处相等。
    /// nil：右边读不懂、里面有自变量以外的字母，或者能比的点太少。
    public static func matches(student rhsLatex: String, expected: MathExpr, variable: String) -> Bool? {
        guard let parsed = try? FunctionDefinition.parse(rhsLatex) else { return nil }
        var body = parsed.body
        // 学生用的字母和原函数不一样（写成 t）：统一换成原函数的自变量
        if parsed.variable != variable, body.symbols.contains(parsed.variable) {
            body = body.substituting(parsed.variable, with: .symbol(variable))
        }
        guard body.symbols.isSubset(of: [variable]), expected.symbols.isSubset(of: [variable]) else { return nil }
        var compared = 0
        for x in samples {
            let a = body.evaluate([variable: x])
            let b = expected.evaluate([variable: x])
            guard a.isFinite, b.isFinite else { continue }
            compared += 1
            if Swift.abs(a - b) > 1e-6 * Swift.max(1, Swift.abs(a), Swift.abs(b)) { return false }
        }
        return compared >= 4 ? true : nil
    }
}
