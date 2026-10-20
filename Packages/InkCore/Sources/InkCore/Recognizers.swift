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
public let recognitionPrompt = """
你是手写数学识别器，只负责逐字照抄，不做任何数学判断。
图片是学生在平板上手写的一行数学式子，里面可能有计算错误。必须按学生实际写的内容原样转写：
绝对不要改正、补全、化简或调整项的顺序；看不清的字按最像的字写。
只输出一个 JSON 对象：{"latex": "这行的 LaTeX"}
图里没有字或只是涂改的痕迹，就输出 {"latex": ""}。
"""

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
