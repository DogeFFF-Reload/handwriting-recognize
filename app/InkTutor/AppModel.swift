import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 把 P3（分行、门禁、识别、批改）和 P2（右半屏场景）串起来的 App 状态。
/// 所有回调都在主线程：PencilKit 回调、CheckGate 的主队列计时器、识别结果用 MainActor 切回来。
@Observable
final class AppModel {
    var mode: InkMode = .function { didSet { ink.mode = mode } }
    var eraserOn = false
    let scene = SceneModel()

    private(set) var lines: [InkLine] = []
    /// 识别回显（line id → LaTeX）
    var echo: [String: String] = [:]
    /// 批注（line id → Annotation）
    var annotations: [String: Annotation] = [:]
    /// 行旁边的提示（没看清、识别失败、收不进几何…）
    var notices: [String: String] = [:]
    /// 双击后闪一下的行
    var flashLine: String?
    /// 清空画布的信号（PencilCanvas 看到它变了就清 drawing）
    var clearToken = 0

    private(set) var functionLatex: String?
    private var functionLineID: String?

    @ObservationIgnored private let ink = BandInkModel(mode: .function)
    @ObservationIgnored private let gate = CheckGate()
    @ObservationIgnored private var ids = PencilKitBridge.IDTable()
    @ObservationIgnored private var drawing = PKDrawing()
    @ObservationIgnored private var seenRevision: [String: Int] = [:]
    @ObservationIgnored private var lastChangedLine: String?

    init() {
        gate.expectedTermCount = { [weak self] _ in
            self?.functionLatex.flatMap { DerivativeCheck.expectedTermCount(functionLatex: $0) }
        }
        gate.onRecognize = { [weak self] line, trigger in self?.recognize(line, trigger) }
        gate.onCheck = { [weak self] line, _ in self?.check(line) }
        gate.onUnreadable = { [weak self] line in
            self?.notices[line.id] = "这一行没看清，点一下识别结果可以手动改"
        }
    }

    // MARK: 笔画

    func drawingChanged(_ d: PKDrawing) {
        drawing = d
        lines = ink.apply(strokes: PencilKitBridge.strokes(from: d, ids: &ids))
        for l in lines where seenRevision[l.id] != l.revision {
            seenRevision[l.id] = l.revision
            annotations[l.id] = nil
            notices[l.id] = nil
            if l.strokes.isEmpty {          // 整行擦光了
                echo[l.id] = nil
                if l.id == functionLineID { functionLatex = nil; functionLineID = nil; scene.clear() }
                continue
            }
            lastChangedLine = l.id
            gate.strokeChanged(line: l, at: Date())
        }
    }

    /// Pencil 双击 = 确认：函数模式立即刷新，推导模式立即批改，几何模式立即收成动态几何。
    func doubleTap() {
        guard let id = lastChangedLine ?? lines.last(where: { !$0.strokes.isEmpty })?.id else { return }
        flashLine = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.flashLine == id { self?.flashLine = nil }
        }
        gate.doubleTapped(lineID: id)
    }

    func clear() {
        clearToken += 1
    }

    // MARK: 识别

    private func recognize(_ line: InkLine, _ trigger: CheckTrigger) {
        if line.mode == .geometry {
            guard trigger == .doubleTap else { return }   // 几何只在双击确认时收
            if let g = GeometrySketchRecognizer.recognize(strokes: line.strokes), let json = try? g.jsonData() {
                try? scene.load(json: json)
                notices[line.id] = nil
            } else {
                notices[line.id] = "这张图收不进来：现在只认三角形和中线"
            }
            return
        }
        guard let png = PencilKitBridge.png(of: line, in: drawing, ids: &ids) else { return }
        if echo[line.id] == nil { notices[line.id] = nil }
        let recognizer = Self.makeRecognizer()
        Task { @MainActor [weak self] in
            do {
                let r = try await recognizer.recognize(line: line, imagePNG: png)
                guard let self, let cur = self.lines.first(where: { $0.id == r.lineID }), cur.revision == r.revision else { return }
                self.accept(latex: r.latex, for: cur)
            } catch {
                self?.notices[line.id] = "识别失败，点这里手动输入"
            }
        }
    }

    /// 收到一行的 LaTeX（识别或手动改）。
    private func accept(latex: String, for line: InkLine) {
        echo[line.id] = latex
        ink.markSent(lineID: line.id)
        let p = LatexTerms.parse(latex)
        if p.kind == .function, let terms = p.terms, !terms.isEmpty {
            functionLatex = latex
            functionLineID = line.id
            scene.setTerms(terms.map { PolyTerm(coef: $0.coef, pow: $0.pow) })
            scene.reveal = false
        }
        gate.recognitionReturned(lineID: line.id, revision: line.revision, latex: latex,
                                 termCount: p.termCount, parseable: p.parseable)
    }

    /// 点回显手动改：当成这一版的识别结果，推导行顺带立即批改。
    func manualEdit(lineID: String, latex: String) {
        guard let line = lines.first(where: { $0.id == lineID }) else { return }
        notices[lineID] = nil
        accept(latex: latex, for: line)
        if line.mode != .function { gate.doubleTapped(lineID: lineID) }
    }

    // MARK: 批改

    private func check(_ line: InkLine) {
        guard line.mode == .derivative, let latex = echo[line.id] else { return }
        guard LatexTerms.parse(latex).kind == .derivative else {
            notices[line.id] = "这一行要写成 f'(x) = … 才能批改"
            return
        }
        guard let f = functionLatex else {
            notices[line.id] = "先在上面写 f(x) = …"
            return
        }
        guard let a = DerivativeCheck.annotation(line: line, functionLatex: f, derivativeLatex: latex, mode: .direct) else {
            notices[line.id] = "这一行没看清，点一下识别结果可以手动改"
            return
        }
        annotations[line.id] = a
        scene.reveal = a.ok
    }

    // MARK: 识别引擎（设置页里选）

    static let goldenReplay = ["f(x)=x^3-5x", "f(x)=x^3-3x", "f'(x)=3x^2-3x", "f'(x)=3x^2-3"]

    static func makeRecognizer() -> InkRecognizer {
        let d = UserDefaults.standard
        let engine = d.string(forKey: "engine") ?? "auto"
        let key = (d.string(forKey: "dashscopeKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let server = URL(string: d.string(forKey: "serverURL") ?? "")
        switch engine {
        case "direct" where !key.isEmpty: return DashScopeRecognizer(apiKey: key)
        case "server" where server?.host != nil: return ServerRecognizer(baseURL: server!)
        case "replay": return replay
        default:
            if !key.isEmpty { return DashScopeRecognizer(apiKey: key) }
            if let s = server, s.host != nil { return ServerRecognizer(baseURL: s) }
            return replay
        }
    }

    private static let replay = ReplayRecognizer(sequence: goldenReplay)
}
