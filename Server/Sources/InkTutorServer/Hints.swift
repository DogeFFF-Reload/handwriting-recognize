import Foundation

/// /hint 的输入：MathEngine 判出的错误 + 题目上下文。
struct HintRequest: Codable, Equatable {
    var kind: String
    var wrongLatex: String
    var expectedLatex: String?
    var sourceLatex: String?
    var functionLatex: String?
    var studentLine: String?
    var feedbackMode: String?   // "direct"（第一版）| "socratic"
    var level: Int?             // socratic 的提示等级 1–3
    var explanation: String?    // direct 模式的模板说明，润色时以它为准

    enum CodingKeys: String, CodingKey {
        case kind, level, explanation
        case wrongLatex = "wrong_latex"
        case expectedLatex = "expected_latex"
        case sourceLatex = "source_latex"
        case functionLatex = "function_latex"
        case studentLine = "student_line"
        case feedbackMode = "feedback_mode"
    }
}

enum Hints {
    static let socraticSystem = """
    你是一位耐心的苏格拉底式数学家教，学生正在平板上手写演算。
    系统已经用符号计算确定了学生哪里出错，你的任务是用一句反问引导学生自己发现，而不是告诉他答案。
    要求：只输出一句中文问句，不超过 30 个字；绝对不能出现正确结果；不要说“你错了”；数学式子用普通文字写（如 x²、3x），不要用 LaTeX。
    """

    static let directSystem = """
    你是数学老师。把下面这句批改说明改得更口语、更好懂，保留其中的正确结果，不超过 40 个字，只输出改好的这一句。
    数学式子用普通文字写（如 x²、−3），不要用 LaTeX。
    """

    static let kindText: [String: String] = [
        "not_differentiated": "学生把原函数里的这一项原样抄了下来，没有对它求导",
        "wrong_coef": "学生对这一项求导了，但系数或指数算错了",
        "wrong_term": "这一项求导算错了",
        "extra_term": "学生写出了一项本不该出现的项",
        "missing_term": "学生漏掉了原函数某一项的导数",
        "whole_line": "这一行整体和正确的导数不相等",
    ]

    static let levelText = [
        1: "第 1 级：只把学生的注意力引到出问题的地方，问一个很轻的问题。",
        2: "第 2 级：提醒学生回想相关的规则（例如幂函数求导法则），但不要把规则套到这一项上算出来。",
        3: "第 3 级：引导学生把规则一步步用到这一项上，问出其中一小步，但仍然不能说出结果。",
    ]

    /// 发给模型的用户消息。
    static func prompt(_ h: HintRequest) -> String {
        var lines: [String] = []
        if let f = h.functionLatex { lines.append("原函数：f(x) = \(f)") }
        if let s = h.studentLine { lines.append("学生这一行：\(s)") }
        lines.append("出错的那一项：\(h.wrongLatex)")
        if let s = h.sourceLatex { lines.append("它对应原函数里的项：\(s)") }
        lines.append("错误类型：\(kindText[h.kind] ?? h.kind)")
        if h.feedbackMode == "socratic" {
            lines.append(levelText[h.level ?? 1] ?? levelText[1]!)
            if let e = h.expectedLatex { lines.append("（仅供你判断，绝对不能说出来）这一项的正确结果是：\(e)") }
        } else {
            if let e = h.expectedLatex { lines.append("这一项的正确结果：\(e)") }
            if let x = h.explanation { lines.append("批改说明：\(x)") }
        }
        return lines.joined(separator: "\n")
    }

    /// socratic 模式下，提示里是否出现了正确项（作为独立的项，后面不跟 x、数字、^）。
    /// 注意学生自己写的 -3x 本身含 -3 这个子串，所以只拦独立出现的。
    static func leaks(_ hint: String, secrets: [String]) -> Bool {
        let h = normalize(hint)
        for raw in secrets {
            let s = normalize(raw)
            guard !s.isEmpty else { continue }
            var candidates = [s]
            let unsigned = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            if unsigned.count > 2 { candidates.append(unsigned) }
            if s == "0" || s == "+0" || s == "-0" {
                if h.contains("零") { return true }
                candidates = ["0"]
            }
            for c in candidates {
                var from = h.startIndex
                while let r = h.range(of: c, range: from..<h.endIndex) {
                    let next = r.upperBound < h.endIndex ? h[r.upperBound] : " "
                    let prev = r.lowerBound > h.startIndex ? h[h.index(before: r.lowerBound)] : " "
                    let digitBefore = c.first?.isNumber == true && (prev.isNumber || prev == "." || prev == "^")
                    if !(next.isNumber || next == "x" || next == "^" || next == "."), !digitBefore { return true }
                    from = r.upperBound
                }
            }
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        var t = s
        for (a, b) in [("−", "-"), ("–", "-"), ("²", "^2"), ("³", "^3"), ("⁴", "^4"), ("{", ""), ("}", ""), ("\\cdot", "*"), (" ", "")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    /// 模型挂了或者一直泄题时用的固定句子。
    static func fallback(_ h: HintRequest) -> String {
        if h.feedbackMode != "socratic" {
            return h.explanation ?? (h.expectedLatex.map { "这一项应该是 \(pretty($0))。" } ?? "这一项再看看。")
        }
        let src = pretty(h.sourceLatex ?? h.wrongLatex)
        switch h.kind {
        case "not_differentiated": return "\(src) 这一项，求导之后还剩下什么？"
        case "wrong_coef": return "\(src) 求导时，指数和系数分别怎么变？"
        case "missing_term": return "原函数的每一项都求导了吗？"
        case "extra_term": return "原函数里有哪一项求导后会变成它？"
        default: return "x 这一项求导后还剩什么？"
        }
    }

    static func pretty(_ latex: String) -> String {
        normalize(latex).replacingOccurrences(of: "^2", with: "²").replacingOccurrences(of: "^3", with: "³")
            .replacingOccurrences(of: "-", with: "−")
    }

    /// 生成一句提示：socratic 先整句生成、检查不泄题再推（A8）；泄题就重来一次，再不行用固定句。
    static func generate(_ h: HintRequest, model: ModelClient) async -> (text: String, source: String) {
        let socratic = h.feedbackMode == "socratic"
        let system = socratic ? socraticSystem : directSystem
        for _ in 0..<2 {
            guard let raw = try? await model.chat(model: "qwen3.8-flash", system: system, prompt: prompt(h),
                                                  imagePNGBase64: nil, maxTokens: 80, temperature: socratic ? 0.7 : 0.3) else { break }
            let text = raw.split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”")) ?? ""
            guard !text.isEmpty, text.count <= 50 else { continue }
            if socratic, leaks(text, secrets: [h.expectedLatex ?? ""]) { continue }
            return (text, "model")
        }
        return (fallback(h), "fallback")
    }
}
