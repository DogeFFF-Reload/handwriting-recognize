// iPadOS 27 起 PencilKit 自带的设备上手写识别（WWDC26 session 203：PKStrokeRecognizer）。
// 它面向「文字」，官方没说支持数学式和上标，所以这里只作为候选引擎：
// 用 20 条样本和 Qwen、MyScript 一起实测后再决定要不要当主路径。
//
// 需要 Xcode 27 的 SDK。为了不让旧 Xcode 编译失败，默认不编译；
// 在 InkTutor target 的 Build Settings › Active Compilation Conditions 里加 PKSTROKERECOGNIZER 打开，
// 或者给 InkCore 包加 swiftSettings: [.define("PKSTROKERECOGNIZER")]。
#if PKSTROKERECOGNIZER && canImport(PencilKit) && canImport(UIKit)
import PencilKit

@available(iOS 27.0, *)
public final class AppleStrokeRecognizer: InkRecognizer {
    private let recognizer = PKStrokeRecognizer()
    /// 识别用的整张画布；P1 每次识别前更新。
    public var drawing: PKDrawing = PKDrawing()
    public var ids = PencilKitBridge.IDTable()

    public init() {}

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        let t0 = Date()
        let wanted = Set(line.strokes.map(\.id))
        let only = drawing.strokes.filter { wanted.contains(ids.id(for: $0)) }
        await recognizer.updateDrawing(PKDrawing(strokes: only))
        let text = await recognizer.recognizedText() ?? ""
        return RecognitionResult(lineID: line.id, revision: line.revision, latex: AppleStrokeRecognizer.toLatex(text),
                                 engine: "PKStrokeRecognizer", ms: Int(Date().timeIntervalSince(t0) * 1000))
    }

    /// 文字识别结果 → 粗略 LaTeX：x2 / x² → x^2，× → \cdot。上标的位置信息文字识别拿不到，只能这样猜。
    static func toLatex(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "²", with: "^2").replacingOccurrences(of: "³", with: "^3")
            .replacingOccurrences(of: "×", with: "\\cdot ").replacingOccurrences(of: " ", with: "")
        while let r = t.range(of: #"x(\d)"#, options: .regularExpression) {
            let d = t[r].dropFirst()
            t.replaceSubrange(r, with: "x^" + d)
        }
        return t
    }
}
#endif
