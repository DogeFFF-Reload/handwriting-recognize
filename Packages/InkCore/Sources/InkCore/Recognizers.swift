import Foundation

/// 笔迹 → LaTeX。一个协议，几个实现（开发方向报告 P3 的 InkRecognizer）：
/// - `ServerRecognizer`：把这一行的截图交给 Mac 上的 Server，Server 调 Qwen（qwen3.8-flash 看图）。
/// - `DashScopeRecognizer`：不经 Server 直接调百炼（只在演示机自己的 iPad 上、Key 不进仓库时用）。
/// - `ReplayRecognizer`：录好的 LaTeX，按行、擦除轮次、笔画数取，断网演示用（见 Replay.swift）。
/// - `AppleStrokeRecognizer`（iPadOS 27 的 PKStrokeRecognizer，设备上）：见 AppleStrokeRecognizer.swift。
/// MyScript iink 由 P1 在 App 里接，同样实现这个协议即可。
public protocol InkRecognizer {
    /// `imagePNG`：这一行的白底截图（PencilKit 渲染）；设备上识别的实现可以忽略它。
    func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult
}

public enum RecognizerError: Error, Equatable {
    case noImage
    case badResponse(String)
    case http(Int, String)
}

/// 识别提示词。2026-10-19 实测：qwen3.8-flash / qwen3.8-max / qwen3-vl-plus 在这句提示下
/// 都会照抄学生写错的式子（3x^2-3x 不会被「改对」），单行约 1–2 秒。不要往里加题目上下文。
/// 2026-10-21 加了写法约定：只说「照抄」时，qwen3.8-flash 会把极限写成 \rightarrow、\operatorname*{lim}，
/// 矩阵写成 \left(\begin{array}…\right)；加约定后 21 条求解样本（积分、极限、求和、矩阵、方程，含两条故意写错的）
/// 连跑两遍全对，写错的仍照抄。脚本见 tools/recog-bench/solve_bench.py。
public let recognitionPrompt = """
你是手写数学识别器，只负责逐字照抄，不做任何数学判断。
图片是学生在平板上手写的一段数学式子（可能是函数、求导、积分、极限、求和、方程或矩阵），里面可能有计算错误。必须按学生实际写的内容原样转写：
绝对不要改正、补全、化简、求值或调整项的顺序；看不清的字按最像的字写。
LaTeX 写法统一成这样：
- 极限 \\lim_{x \\to 0}，趋向写 \\to，单侧写 0^{+}、0^{-}；不要用 \\operatorname、\\rightarrow
- 积分 \\int_{0}^{1} x^{2} dx，不定积分 \\int x e^{x} dx；求和 \\sum_{k=1}^{n}，连乘 \\prod_{k=1}^{5}；上下限、指数都用花括号
- 分式 \\frac{a}{b}，求导 f'(x) 或 \\frac{d}{dx}
- 矩阵用 \\begin{pmatrix}1 & 2 \\\\ 3 & 4\\end{pmatrix}；方括号用 bmatrix，竖线（行列式）用 vmatrix；不要用 array 和 \\left( \\right)；数字不要加花括号
- 不要用 \\displaystyle、\\mathrm、$
只输出一个 JSON 对象：{"latex": "这段的 LaTeX"}
图里没有字或只是涂改的痕迹，就输出 {"latex": ""}。
"""

/// 模型偶尔不按约定写（换了后备模型、提示词没压住）时的兜底：把几种常见的「另一种写法」改成 App 认的写法。
/// 只改写法，不改内容：\operatorname*{lim} → \lim，\rightarrow → \to，
/// \left( \begin{array}{cc} … \end{array} \right) → pmatrix（[ ] → bmatrix，| | → vmatrix），矩阵格子里的 { 1 } → 1。
public func canonicalLatex(_ latex: String) -> String {
    var s = latex.replacingOccurrences(of: "\\displaystyle", with: "").replacingOccurrences(of: "$", with: "")
    for pattern in [#"\\operatorname\*?\s*\{\s*lim\s*\}"#, #"\\mathrm\s*\{\s*lim\s*\}"#] {
        s = s.replacingOccurrences(of: pattern, with: "\\\\lim", options: .regularExpression)
    }
    s = s.replacingOccurrences(of: #"\\(long)?rightarrow"#, with: "\\\\to", options: .regularExpression)

    let envs: [(open: String, close: String, env: String)] = [("(", ")", "pmatrix"), ("[", "]", "bmatrix"), ("|", "|", "vmatrix")]
    for e in envs {
        let o = NSRegularExpression.escapedPattern(for: e.open), c = NSRegularExpression.escapedPattern(for: e.close)
        let pattern = #"\\left\s*"# + o + #"\s*\\begin\{array\}\s*\{[^{}]*\}(.*?)\\end\{array\}\s*\\right\s*"# + c
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
        while let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let whole = Range(m.range, in: s), let body = Range(m.range(at: 1), in: s) {
            s.replaceSubrange(whole, with: "\\begin{\(e.env)}" + unbraceCells(String(s[body])) + "\\end{\(e.env)}")
        }
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 矩阵格子：「{ 1 } & { -2 } \\ { 3 } & { 4 }」→「1 & -2 \\ 3 & 4」。只拆整格外面那一层花括号。
private func unbraceCells(_ body: String) -> String {
    body.components(separatedBy: "\\\\").map { row in
        row.components(separatedBy: "&").map { cell -> String in
            var t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("{"), t.hasSuffix("}"), !t.dropFirst().dropLast().contains("{") {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return t.replacingOccurrences(of: #"-\s+"#, with: "-", options: .regularExpression)
        }.joined(separator: " & ")
    }.joined(separator: " \\\\ ")
}

/// 按顺序试几个识别器：前一个抛错或给了空结果就换下一个，最后一个的空结果照样返回（界面说「没认出来」）。
/// 例如 MyScript（设备上）→ 百炼 → Server。
public struct FallbackRecognizer: InkRecognizer {
    public var chain: [InkRecognizer]

    public init(_ chain: [InkRecognizer]) {
        self.chain = chain
    }

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        var lastError: Error = RecognizerError.badResponse("没有可用的识别器")
        for (k, r) in chain.enumerated() {
            do {
                let result = try await r.recognize(line: line, imagePNG: imagePNG)
                if !result.latex.isEmpty || k == chain.count - 1 { return result }
                lastError = RecognizerError.badResponse("空结果")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

/// 从模型回复里取出 {"latex": ...}。
public func extractLatex(fromModelReply text: String) throws -> String {
    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
          let data = String(text[start...end]).data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let latex = obj["latex"] as? String else {
        throw RecognizerError.badResponse(String(text.prefix(120)))
    }
    return latex.trimmingCharacters(in: .whitespacesAndNewlines)
}
