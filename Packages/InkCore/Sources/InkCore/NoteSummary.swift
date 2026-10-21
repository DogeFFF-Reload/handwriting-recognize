import Foundation

// 总结笔记：学生离开草稿时点「总结内容」，把这一页交给 qwen3.8-max 写几条要点（不自动调用）。
// 收成标准式子的部分（函数、导数、求解结果、矩阵、几何图形）按文字给，没收成式子的手写（文字笔记、草算）截成图给。
// 没有百炼 Key 时，按纸上的式子拼一份本地的要点。

/// 一页草稿上收成式子的东西，从上到下。存盘时一起存（digest.json），画廊里不打开草稿也能总结。
public struct NoteDigest: Codable, Equatable {
    public struct Line: Codable, Equatable {
        public enum Kind: String, Codable {
            case function, derivative, solution, matrix, shape, check
        }
        public var kind: Kind
        /// 式子的 LaTeX（含算出来的结果）；几何图形是名字和尺寸（普通文字）。
        public var text: String
        /// 补一句：求解的种类（积分、矩阵求逆……）、检查的结论。
        public var note: String?

        public init(kind: Kind, text: String, note: String? = nil) {
            self.kind = kind
            self.text = text
            self.note = note
        }
    }

    public var title: String
    public var lines: [Line]
    /// 纸上还有没收成式子的手写：总结时截成图一起发。
    public var hasLooseInk: Bool

    public init(title: String, lines: [Line], hasLooseInk: Bool) {
        self.title = title
        self.lines = lines
        self.hasLooseInk = hasLooseInk
    }

    /// 什么都没写：不用总结。
    public var isEmpty: Bool { lines.isEmpty && !hasLooseInk }
}

/// 总结出来的要点。存在草稿文件夹的 summary.json 里，画廊格子下面显示前一两条。
public struct NoteSummary: Codable, Equatable {
    public var title: String
    public var points: [String]
    /// 谁写的：qwen3.8-max，或者「本地」。
    public var engine: String
    public var created: Date

    public init(title: String, points: [String], engine: String, created: Date = Date()) {
        self.title = title
        self.points = points
        self.engine = engine
        self.created = created
    }

    public var isLocal: Bool { engine == NoteSummarizer.localEngine }
}

public enum NoteSummarizer {
    public static let model = "qwen3.8-max"
    public static let localEngine = "本地"

    static let system = """
    你是学生的数学学习助理，帮学生把一页手写笔记总结成几条要点。
    已经识别成标准式子的部分以文字给出（LaTeX）；没有识别的手写（文字笔记、草算）在图片里。
    要求：只根据给出的内容总结，不要补充没写的知识，也不要编造结果；
    写 3 到 5 条要点，每条不超过 40 个字，按重要程度排；数学式子用普通文字写（如 x²、f'(x) = 2x），不要用 LaTeX；
    再起一个不超过 12 个字的标题。
    只输出一个 JSON 对象：{"title": "…", "points": ["…", "…"]}
    """

    /// 发给模型的用户消息。
    public static func prompt(_ d: NoteDigest, withImage: Bool) -> String {
        var out = ["草稿名：\(d.title)"]
        if d.lines.isEmpty {
            out.append("纸上没有收成标准式子的内容。")
        } else {
            out.append("纸上收成标准式子的内容（从上到下）：")
            for (k, line) in d.lines.enumerated() {
                var s = "\(k + 1). \(label(line.kind))：\(line.text)"
                if let note = line.note { s += "（\(note)）" }
                out.append(s)
            }
        }
        if withImage { out.append("另附一张图：纸上没有收成式子的手写部分。") }
        return out.joined(separator: "\n")
    }

    static func label(_ k: NoteDigest.Line.Kind) -> String {
        switch k {
        case .function: return "函数"
        case .derivative: return "求导"
        case .solution: return "求解"
        case .matrix: return "矩阵"
        case .shape: return "图形"
        case .check: return "检查"
        }
    }

    /// 从模型回复里取出 {"title": …, "points": […]}（容忍前后多出来的字和 ``` 包裹）。
    public static func parse(_ reply: String) throws -> (title: String, points: [String]) {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["points"] as? [Any] else {
            throw RecognizerError.badResponse(String(reply.prefix(120)))
        }
        let points = raw.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !points.isEmpty else { throw RecognizerError.badResponse("没有要点") }
        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (title, Array(points.prefix(6)))
    }

    /// 没有 Key（或者模型没连上）时的要点：按纸上的式子一条条写，最多 5 条。
    public static func local(_ d: NoteDigest, now: Date = Date()) -> NoteSummary {
        var points: [String] = []
        for line in d.lines {
            let text = line.kind == .shape ? line.text : plain(line.text)
            switch line.kind {
            case .function: points.append("写了函数 \(text)")
            case .derivative: points.append("求导：\(text)")
            case .solution: points.append((line.note.map { $0 + "：" } ?? "算出 ") + text)
            case .matrix: points.append(line.note.map { "矩阵\($0)" } ?? "写了一个矩阵")
            case .shape: points.append("画了\(text)")
            case .check: points.append("检查了 \(text)" + (line.note.map { "：\($0)" } ?? ""))
            }
        }
        if points.count > 5 { points = Array(points.prefix(4)) + ["还有 \(points.count - 4) 处式子和图形"] }
        if points.isEmpty { points = ["这页只有手写，还没有收成式子：填上百炼 Key 后可以把手写也总结进来"] }
        return NoteSummary(title: d.title, points: points, engine: localEngine, created: now)
    }

    /// LaTeX → 普通文字（本地要点用）：∫、∑、lim、→、数字上下标；矩阵的内容不展开。
    static func plain(_ latex: String) -> String {
        var s = latex
        while let r = s.range(of: #"\\begin\{[a-zA-Z]*matrix\}.*?\\end\{[a-zA-Z]*matrix\}"#, options: .regularExpression) {
            s.replaceSubrange(r, with: "(矩阵)")
        }
        s = s.replacingOccurrences(of: #"\\color\{#[0-9A-Fa-f]+\}"#, with: "", options: .regularExpression)
        // \infty 要在 \int 之前换
        for (a, b) in [("\\Rightarrow", " ⇒ "), ("\\rightarrow", "→"), ("\\to", "→"), ("\\infty", "∞"), ("\\int", "∫"),
                       ("\\sum", "∑"), ("\\prod", "∏"), ("\\lim", "lim"), ("\\approx", "≈"), ("\\prime", "'"),
                       ("\\sin", "sin"), ("\\cos", "cos"), ("\\tan", "tan"), ("\\det", "det"), ("\\dfrac", "\\frac")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        // lim_{x→∞} → lim(x→∞)，∑_{k=1}^{n} → ∑(k=1…n)
        s = s.replacingOccurrences(of: #"lim_\{([^{}]*)\}"#, with: "lim($1) ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([∑∏])_\{([^{}]*)\}\^\{([^{}]*)\}"#, with: "$1($2…$3) ", options: .regularExpression)
        s = scripts(s, "_", ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "-": "₋"])
        s = scripts(s, "\\^", ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"])
        return tidy(Solver.plainText(s))
    }

    /// 排一下空格：括号里面不留空，等号两边各一个，二元的加减号两边各一个（x² − 4，−16/3 前面的负号不动）。
    static func tidy(_ s: String) -> String {
        var t = s
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        for (a, b) in [("( ", "("), (" )", ")"), (" =", "="), ("= ", "="), ("=", " = ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        var out = ""
        var prev: Character?
        for ch in t {
            if ch == "+" || ch == "−", let p = prev, p.isLetter || p.isNumber || p == ")" || p == "|" {
                out += " \(ch) "
            } else {
                out.append(ch)
            }
            prev = ch
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 纯数字的上下标换成小字：_{0} → ₀，^2 → ²。mark 是正则里的写法（_ 或 \^）。
    static func scripts(_ s: String, _ mark: String, _ map: [Character: Character]) -> String {
        var out = s
        for pattern in [mark + #"\{-?[0-9]+\}"#, mark + "[0-9]"] {
            while let r = out.range(of: pattern, options: .regularExpression) {
                out.replaceSubrange(r, with: String(out[r].compactMap { map[$0] }))
            }
        }
        return out
    }
}

#if canImport(Darwin)
extension NoteSummarizer {
    /// 调百炼的 qwen3.8-max：式子按文字发，没收成式子的手写按图片（PNG）发。大模型慢，超时放宽到 60 秒。
    public static func summarize(_ d: NoteDigest, apiKey: String, inkPNG: Data?,
                                 session: URLSession = .shared) async throws -> NoteSummary {
        let reply = try await DashScope.chat(apiKey: apiKey, session: session, model: model, imagePNG: inkPNG, system: system,
                                             prompt: prompt(d, withImage: inkPNG != nil), maxTokens: 600, temperature: 0.3,
                                             timeout: 60)
        let (title, points) = try parse(reply)
        return NoteSummary(title: title.isEmpty ? d.title : title, points: points, engine: model)
    }
}
#endif
