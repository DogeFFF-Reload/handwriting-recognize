import Foundation
import InkCore
import PencilKit
#if canImport(libiink)
import libiink
#endif

/// MyScript iink 的 Math Recognizer（识别在设备上做，几百毫秒）：把一段笔迹的点原样送进去，取 LaTeX。
///
/// 注意：建 Engine 时 iink 会联网到 license.myscript.com 查一次授权。证书在授权后台没启用、或 Bundle ID 对不上，
/// 都只报 "invalid certificate"；没网时的表现还没实测。MyScript 不可用时 App 按识别链退回其他引擎。
///
/// 要三样东西，缺一样就报出是哪一样，App 退回其他识别引擎：
/// 1. iink SDK（Swift 包 MyScript/interactive-ink-packages-ios，工程里已经加好）；
/// 2. 证书：MyScript 开发者后台发的 MyCertificate.c，复制到 app/InkTutor/MyScriptCertificate/（不进仓库）；
/// 3. 数学识别资源 math2：tools/myscript/fetch-assets.sh 下载到 app/MyScript/，编译时拷进 App。
enum MyScriptStatus: Equatable {
    case notLinked
    case noCertificate
    case invalidCertificate
    case noAssets
    case ready(version: String)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// 设置页和工具栏上的一句话。
    var summary: String {
        switch self {
        case .notLinked: return "这一版没有编进 iink SDK"
        case .noCertificate: return "缺证书：把 MyCertificate.c 放进 app/InkTutor/MyScriptCertificate/"
        case .invalidCertificate: return "证书无效（和 App 的 Bundle ID 对不上？）"
        case .noAssets: return "缺数学识别资源：运行 tools/myscript/fetch-assets.sh 后重新编译"
        case .ready(let v): return "已就绪 · iink \(v) · 设备上识别"
        case .failed(let m): return "出错：\(m)"
        }
    }
}

enum MyScriptError: LocalizedError {
    case unavailable(String)
    case noLatexOutput

    var errorDescription: String? {
        switch self {
        case .unavailable(let s): return "MyScript 不可用：\(s)"
        case .noLatexOutput: return "MyScript 没有给出 LaTeX"
        }
    }
}

final class MyScriptMath {
    static let shared = MyScriptMath()

    /// 输入坐标是画布 point。iPad Pro 是 264 ppi、2 倍屏：1 pt = 25.4 / 132 mm。
    static let millimetersPerPoint: Float = 25.4 / 132

    private(set) var status: MyScriptStatus

#if canImport(libiink)
    private let engine: IINKEngine?
    private var recognizer: IINKRecognizer?
    private let errors = RecognizerErrors()
    /// iink 的调用都在这一条串行队列上（waitForIdle 会阻塞）。
    private let queue = DispatchQueue(label: "inktutor.myscript.math", qos: .userInitiated)

    private init() {
        guard myCertificate.length > 0, let bytes = myCertificate.bytes else {
            status = .noCertificate
            engine = nil
            return
        }
        guard let e = IINKEngine(certificate: Data(bytes: bytes, count: myCertificate.length)) else {
            status = .invalidCertificate
            engine = nil
            return
        }
        let conf = (Bundle.main.resourcePath ?? "") + "/recognition-assets/conf"
        guard FileManager.default.fileExists(atPath: conf + "/math2.conf") else {
            status = .noAssets
            engine = e
            return
        }
        do {
            try e.configuration.set(stringArray: [conf], forKey: "recognizer.configuration-manager.search-path")
            try e.configuration.set(stringArray: [conf], forKey: "configuration-manager.search-path")
            try e.configuration.set(string: NSTemporaryDirectory(), forKey: "content-package.temp-folder")
            // 只要识别：不求解、不补全
            try? e.configuration.set(boolean: false, forKey: "math.solver.enable")
            status = .ready(version: e.version)
        } catch {
            status = .failed(error.localizedDescription)
        }
        engine = e
    }

    /// 提前建好识别器（加载资源要一点时间），第一次双击时就不用等。
    func warmUp() {
        guard status.isReady else { return }
        queue.async { _ = try? self.makeRecognizerIfNeeded() }
    }

    func latex(for strokes: [PKStroke]) async throws -> String {
        guard status.isReady else { throw MyScriptError.unavailable(status.summary) }
        let events = Self.pointerEvents(strokes)
        guard !events.isEmpty else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    let r = try self.makeRecognizerIfNeeded()
                    try r.clear()
                    var batch = events
                    try batch.withUnsafeMutableBufferPointer { buf in
                        try r.pointerEvents(buf.baseAddress!, count: buf.count)
                    }
                    r.waitForIdle()
                    if let message = self.errors.take() { throw MyScriptError.unavailable(message) }
                    cont.resume(returning: try Self.latexResult(of: r))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func makeRecognizerIfNeeded() throws -> IINKRecognizer {
        if let recognizer { return recognizer }
        guard let engine else { throw MyScriptError.unavailable(status.summary) }
        let mm = Self.millimetersPerPoint
        let r = try engine.createRecognizer(scaleX: mm, scaleY: mm, type: "Math")
        r.add(errors)
        recognizer = r
        return r
    }

    /// 取 LaTeX。按 MIME 名字找格式，不依赖枚举在 Swift 里叫什么；万一不给 LaTeX，就从 JIIX 的 label 里取。
    private static func latexResult(of r: IINKRecognizer) throws -> String {
        let types = r.supportedResultMimeTypes.map(\.value)
        func named(_ name: String) -> IINKMimeType? {
            types.first { IINKMimeTypeValue.iinkMimeTypeGetTypeName($0) == name }
        }
        if let latex = named("application/x-latex") {
            return try r.result(mimeType: latex).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let jiix = named("application/vnd.myscript.jiix"),
           let data = try r.result(mimeType: jiix).data(using: .utf8),
           let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let label = obj["label"] as? String { return label }
            if let exprs = obj["expressions"] as? [[String: Any]], let label = exprs.first?["label"] as? String { return label }
        }
        throw MyScriptError.noLatexOutput
    }

    /// PencilKit 的笔画 → iink 的 down / move / up。时间戳用笔画真实的时间，压感归一到 [0, 1]。
    static func pointerEvents(_ strokes: [PKStroke]) -> [IINKPointerEvent] {
        var out: [IINKPointerEvent] = []
        for stroke in strokes.sorted(by: { $0.path.creationDate < $1.path.creationDate }) {
            let points = Array(stroke.path)
            guard !points.isEmpty else { continue }
            let t0 = stroke.path.creationDate.timeIntervalSince1970
            func event(_ type: IINKPointerEventType, _ p: PKStrokePoint) -> IINKPointerEvent {
                let loc = p.location.applying(stroke.transform)
                return IINKPointerEvent(eventType: type, x: Float(loc.x), y: Float(loc.y),
                                        t: Int64(((t0 + p.timeOffset) * 1000).rounded()),
                                        f: Float(min(max(p.force / 4.17, 0), 1)),
                                        tilt: -1, orientation: -10, pointerType: .pen, pointerId: 0)
            }
            out.append(event(.down, points[0]))
            for p in points.dropFirst().dropLast() { out.append(event(.move, p)) }
            out.append(event(.up, points[points.count - 1]))
        }
        return out
    }
#else
    #warning("iink SDK 没有编进来（canImport(libiink) 为假）：MyScript 识别不可用")
    private init() {
        status = .notLinked
    }

    func warmUp() {}

    func latex(for strokes: [PKStroke]) async throws -> String {
        throw MyScriptError.unavailable(status.summary)
    }
#endif
}

#if canImport(libiink)
/// iink 在识别器里报的错（找不到资源、配置不对）先记下，识别完再抛给调用方。
private final class RecognizerErrors: NSObject, IINKRecognizerDelegate {
    private let lock = NSLock()
    private var message: String?

    func resultChanged(_ recognizer: IINKRecognizer, result: String) {}

    func onError(_ recognizer: IINKRecognizer, code: IINKRecognizerError, message: String) {
        lock.lock()
        self.message = message
        lock.unlock()
    }

    func take() -> String? {
        lock.lock()
        defer { message = nil; lock.unlock() }
        return message
    }
}
#endif

/// 接到 InkRecognizer 协议上：识别哪几笔在建的时候给（PencilKit 的笔画，带时间和压感）。
struct MyScriptMathRecognizer: InkRecognizer {
    var strokes: [PKStroke]

    func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        let t0 = Date()
        let latex = try await MyScriptMath.shared.latex(for: strokes)
        return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: "MyScript",
                                 ms: Int(Date().timeIntervalSince(t0) * 1000))
    }
}
