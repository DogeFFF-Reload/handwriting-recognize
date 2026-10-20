import Foundation

// 断网回放（方案第 8 节）。按「哪种模式的第几行 + 这一行擦过几轮 + 这一轮新写了几笔」取录好的 LaTeX，
// 不按调用顺序取：写到一半多停顿一次、擦掉重写、清屏重来，都不会错位。
// App 的 ReplayRecognizer 和 Server 的 /recognize 回放共用这里的脚本格式和行状态。

/// 回放脚本。键是 `<模式>/<这一模式下的第几行>`，如 `function/1`、`derivative/1`；
/// 每行按擦除轮次分段，每段按「这一轮新写了几笔」分步：取 `min_strokes` 不超过它的最后一步。
/// 第 0 轮（还没擦过）就是整行的笔画数；擦过之后只数擦除开始以后新写的笔，
/// 所以「5 擦了一半」和「5 擦完写了 3」不会混（两者整行笔画数可能一样）。
public struct ReplayScript: Codable, Equatable {
    public struct Step: Codable, Equatable {
        public var minStrokes: Int
        public var latex: String

        enum CodingKeys: String, CodingKey {
            case latex
            case minStrokes = "min_strokes"
        }

        public init(minStrokes: Int, latex: String) {
            self.minStrokes = minStrokes
            self.latex = latex
        }
    }

    public struct Pass: Codable, Equatable {
        public var erasePasses: Int
        public var steps: [Step]

        enum CodingKeys: String, CodingKey {
            case steps
            case erasePasses = "erase_passes"
        }

        public init(erasePasses: Int, steps: [Step]) {
            self.erasePasses = erasePasses
            self.steps = steps
        }
    }

    public var lines: [String: [Pass]]

    public init(lines: [String: [Pass]] = [:]) {
        self.lines = lines
    }

    public static func key(mode: InkMode, ordinal: Int) -> String { "\(mode.rawValue)/\(ordinal)" }

    /// 这一行在这个状态下该放的 LaTeX。笔画还不够第一步时是空串（当作「没看清」，不会提前批改）。
    /// 第 n 行没录过就用这一模式里最近的前一行（清屏后行号接着往上数，也能对上）。这一模式完全没录过时返回 nil。
    /// `wholeLine`：这一段已经由学生双击确认写完了，这一轮写过笔就放这一轮的最后一步，不再按笔画数猜写到哪儿。
    public func latex(mode: InkMode, ordinal: Int, erasePasses: Int, strokesInPass: Int, wholeLine: Bool = false) -> String? {
        let prefix = "\(mode.rawValue)/"
        let recorded = lines.keys.compactMap { k -> Int? in k.hasPrefix(prefix) ? Int(k.dropFirst(prefix.count)) : nil }
        guard let n = recorded.filter({ $0 <= ordinal }).max(),
              let passes = lines[Self.key(mode: mode, ordinal: n)], !passes.isEmpty else { return nil }
        let pass = passes.filter { $0.erasePasses <= erasePasses }.max { $0.erasePasses < $1.erasePasses } ?? passes[0]
        if wholeLine, strokesInPass > 0, let last = pass.steps.max(by: { $0.minStrokes < $1.minStrokes }) {
            return last.latex
        }
        let step = pass.steps.filter { $0.minStrokes <= strokesInPass }.max { $0.minStrokes < $1.minStrokes }
        return step?.latex ?? ""
    }

    /// 录一次真实识别结果。同一行、同一轮、同一笔画数只留最后一次。
    public mutating func record(mode: InkMode, ordinal: Int, erasePasses: Int, strokesInPass: Int, latex: String) {
        let key = Self.key(mode: mode, ordinal: ordinal)
        var passes = lines[key] ?? []
        if let i = passes.firstIndex(where: { $0.erasePasses == erasePasses }) {
            passes[i].steps.removeAll { $0.minStrokes == strokesInPass }
            passes[i].steps.append(Step(minStrokes: strokesInPass, latex: latex))
            passes[i].steps.sort { $0.minStrokes < $1.minStrokes }
        } else {
            passes.append(Pass(erasePasses: erasePasses, steps: [Step(minStrokes: strokesInPass, latex: latex)]))
            passes.sort { $0.erasePasses < $1.erasePasses }
        }
        lines[key] = passes
    }

    /// 录过的行整行替换内置的同名行，没录过的行沿用内置的。
    public func overlaid(with recorded: ReplayScript) -> ReplayScript {
        ReplayScript(lines: lines.merging(recorded.lines) { _, new in new })
    }

    public static func load(from url: URL) throws -> ReplayScript {
        try JSONDecoder().decode(ReplayScript.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// 内置的黄金路径。第 0 轮的笔画数是按常见写法估的（f 两笔、x 两笔、5 两笔……），
    /// 演示的人写法不同就会对不上：彩排时打开录制，按真实写法覆盖。擦除之后的几步只数新写的笔，不受写法影响。
    public static let golden = ReplayScript(lines: [
        key(mode: .function, ordinal: 1): [
            Pass(erasePasses: 0, steps: [
                Step(minStrokes: 1, latex: "f"),
                Step(minStrokes: 8, latex: "f(x)="),
                Step(minStrokes: 11, latex: "f(x)=x^3"),
                Step(minStrokes: 16, latex: "f(x)=x^3-5x"),
            ]),
            // 擦掉 5 后写 3
            Pass(erasePasses: 1, steps: [
                Step(minStrokes: 0, latex: "f(x)=x^3-x"),
                Step(minStrokes: 1, latex: "f(x)=x^3-3x"),
            ]),
        ],
        key(mode: .derivative, ordinal: 1): [
            Pass(erasePasses: 0, steps: [
                Step(minStrokes: 1, latex: "f'"),
                Step(minStrokes: 9, latex: "f'(x)="),
                Step(minStrokes: 13, latex: "f'(x)=3x^2"),
                Step(minStrokes: 17, latex: "f'(x)=3x^2-3x"),
            ]),
            // 擦掉 -3x 后写 -3（写完减号还只有 1 项，不会提前批改）
            Pass(erasePasses: 1, steps: [
                Step(minStrokes: 0, latex: "f'(x)=3x^2"),
                Step(minStrokes: 2, latex: "f'(x)=3x^2-3"),
            ]),
        ],
    ])
}

/// 回放用的行状态：每行是这一模式下的第几行、擦过几轮、这一轮新写了几笔。
/// 只看每次识别时这一行的笔画 id 增减，不依赖 `markSent`。App 和 Server 各用一个；清屏时 `reset()`。
public final class ReplayTracker: @unchecked Sendable {
    public struct Position: Equatable {
        public var mode: InkMode
        public var ordinal: Int
        public var erasePasses: Int
        /// 第 0 轮是整行笔画数；之后是这一轮擦除开始以后新写、现在还在的笔画数。
        public var strokesInPass: Int

        public init(mode: InkMode, ordinal: Int, erasePasses: Int, strokesInPass: Int) {
            self.mode = mode
            self.ordinal = ordinal
            self.erasePasses = erasePasses
            self.strokesInPass = strokesInPass
        }
    }

    private let lock = NSLock()
    private var ordinals: [String: Int] = [:]
    private var linesPerMode: [InkMode: Int] = [:]
    private var lastStrokes: [String: Set<String>] = [:]
    private var passes: [String: Int] = [:]
    private var lastWasRemoval: [String: Bool] = [:]
    /// 这一轮擦除开始时这一行有哪些笔；第 0 轮是空集。
    private var passBaseline: [String: Set<String>] = [:]

    public init() {}

    /// 每次识别这一行时调用一次。连续的擦除算一轮；擦了又写（中间没停顿）也算一轮。
    public func observe(lineID: String, mode: InkMode, strokeIDs: [String]) -> Position {
        lock.lock()
        defer { lock.unlock() }
        if ordinals[lineID] == nil {
            linesPerMode[mode, default: 0] += 1
            ordinals[lineID] = linesPerMode[mode]
        }
        let current = Set(strokeIDs)
        let previous = lastStrokes[lineID] ?? []
        let removed = !previous.subtracting(current).isEmpty
        let added = !current.subtracting(previous).isEmpty
        if removed && !(lastWasRemoval[lineID] ?? false) {
            passes[lineID, default: 0] += 1
            // 两次识别之间又擦又写时，当作先擦后写：这次新出现的笔都算这一轮写的。
            passBaseline[lineID] = previous
        }
        if added {
            lastWasRemoval[lineID] = false
        } else if removed {
            lastWasRemoval[lineID] = true
        }
        lastStrokes[lineID] = current
        return Position(mode: mode, ordinal: ordinals[lineID]!, erasePasses: passes[lineID] ?? 0,
                        strokesInPass: current.subtracting(passBaseline[lineID] ?? []).count)
    }

    /// 清屏、演示从头来时调用：之后看到的行重新从第 1 行数。
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        ordinals = [:]
        linesPerMode = [:]
        lastStrokes = [:]
        passes = [:]
        lastWasRemoval = [:]
        passBaseline = [:]
    }
}

/// 回放识别器：不联网、结果确定。
public struct ReplayRecognizer: InkRecognizer {
    public var script: ReplayScript
    public let tracker: ReplayTracker
    /// 只在学生双击确认之后才识别（App 现在的做法）时打开：见 `ReplayScript.latex(wholeLine:)`。
    public var wholeLine: Bool

    public init(script: ReplayScript = .golden, tracker: ReplayTracker = ReplayTracker(), wholeLine: Bool = false) {
        self.script = script
        self.tracker = tracker
        self.wholeLine = wholeLine
    }

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        let p = tracker.observe(lineID: line.id, mode: line.mode, strokeIDs: line.strokes.map(\.id))
        let latex = script.latex(mode: p.mode, ordinal: p.ordinal, erasePasses: p.erasePasses, strokesInPass: p.strokesInPass,
                                 wholeLine: wholeLine) ?? ""
        return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: "replay", ms: 0)
    }
}

/// 把真识别的结果录进回放脚本，并存到文件（彩排时用）。
public final class ReplayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: ReplayScript
    public let fileURL: URL?

    /// 文件已存在就接着录（同一步覆盖）。
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        recorded = fileURL.flatMap { try? ReplayScript.load(from: $0) } ?? ReplayScript()
    }

    public var script: ReplayScript {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// 空结果（模型没认出来）不录，免得盖掉好的一步。
    public func record(_ p: ReplayTracker.Position, latex: String) {
        guard !latex.isEmpty else { return }
        lock.lock()
        recorded.record(mode: p.mode, ordinal: p.ordinal, erasePasses: p.erasePasses, strokesInPass: p.strokesInPass, latex: latex)
        let snapshot = recorded
        lock.unlock()
        if let fileURL { try? snapshot.save(to: fileURL) }
    }

    public func clear() {
        lock.lock()
        recorded = ReplayScript()
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

/// 包在真识别器外面：每次识别都让回放的行状态跟上（中途切到回放也不会数错擦除轮次），
/// 给了 recorder 时顺便把结果录下来。
public struct TrackingRecognizer: InkRecognizer {
    public let inner: InkRecognizer
    public let tracker: ReplayTracker
    public let recorder: ReplayRecorder?

    public init(_ inner: InkRecognizer, tracker: ReplayTracker, recorder: ReplayRecorder? = nil) {
        self.inner = inner
        self.tracker = tracker
        self.recorder = recorder
    }

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        let p = tracker.observe(lineID: line.id, mode: line.mode, strokeIDs: line.strokes.map(\.id))
        let result = try await inner.recognize(line: line, imagePNG: imagePNG)
        recorder?.record(p, latex: result.latex)
        return result
    }
}
