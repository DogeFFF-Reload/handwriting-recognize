import Foundation

/// 为什么发这一次请求，对应上传 JSON 的 `trigger`。
public enum CheckTrigger: String, Codable, Equatable {
    case pause
    case autoCheck = "auto_check"
    case doubleTap = "double_tap"
}

/// 能取消的定时任务。
public protocol GateCancellable {
    func cancel()
}

/// 定时器来源。App 里用主线程；单测里用手动推进的假时钟。
public protocol GateScheduler {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> GateCancellable
}

public final class MainQueueScheduler: GateScheduler {
    private final class Item: GateCancellable {
        let work: DispatchWorkItem
        init(_ w: DispatchWorkItem) { work = w }
        func cancel() { work.cancel() }
    }

    public init() {}

    public func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> GateCancellable {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return Item(item)
    }
}

/// 批改门禁（开发方向报告 D1）。
///
/// - 抬笔停 `recognizeDelay`（700 ms）：只发识别（`onRecognize(line, .pause)`），回显，不圈。
/// - 条件 a：这一行能解析 + 项数达到 `expectedTermCount` + `checkDelay`（1.5 s）没有新笔画 → `onCheck(.autoCheck)`。
/// - 条件 b：Pencil 双击 → 跳过等待和项数，立即批；识别还没回来就先识别，回来后再批。
/// - 任何新笔画或擦除都让两个计时清零。同一行同一 revision 只自动批一次。
/// - 函数模式不批改：双击 = 立即识别并刷新图像。
/// - 双击但解析失败：`onUnreadable(lineID)`，界面提示「这一行没看清，点一下识别结果可以手动改」。
public final class CheckGate: CheckGating {
    public var recognizeDelay: TimeInterval = 0.7
    public var checkDelay: TimeInterval = 1.5

    /// 这一行批改需要的项数（由 MathEngine 按题目算，例如 x^3-3x 的导数是 2 项）。返回 nil 表示不看项数。
    public var expectedTermCount: (InkLine) -> Int? = { _ in nil }
    public var onRecognize: (InkLine, CheckTrigger) -> Void = { _, _ in }
    public var onCheck: (InkLine, CheckTrigger) -> Void = { _, _ in }
    public var onUnreadable: (InkLine) -> Void = { _ in }

    private struct Recognized {
        var revision: Int
        var termCount: Int
        var parseable: Bool
    }

    private struct State {
        var line: InkLine
        var recognized: Recognized?
        var recognizeTimer: GateCancellable?
        var checkTimer: GateCancellable?
        var checkDue = false            // 1.5 s 到了，但识别还没回来
        var forcedByDoubleTap = false   // 双击时识别还没回来
        var lastAutoChecked: Int?
    }

    private let scheduler: GateScheduler
    private var states: [String: State] = [:]

    public init(scheduler: GateScheduler = MainQueueScheduler()) {
        self.scheduler = scheduler
    }

    public func strokeChanged(line: InkLine, at: Date = Date()) {
        var st = states[line.id] ?? State(line: line)
        st.recognizeTimer?.cancel()
        st.checkTimer?.cancel()
        st.line = line
        st.checkDue = false
        st.forcedByDoubleTap = false
        if let r = st.recognized, r.revision != line.revision { st.recognized = nil }
        let id = line.id
        st.recognizeTimer = scheduler.schedule(after: recognizeDelay) { [weak self] in
            guard let self, let s = self.states[id] else { return }
            self.onRecognize(s.line, .pause)
        }
        if line.mode != .function {
            st.checkTimer = scheduler.schedule(after: checkDelay) { [weak self] in
                self?.checkTimerFired(id)
            }
        }
        states[id] = st
    }

    public func recognitionReturned(lineID: String, revision: Int, latex: String, termCount: Int, parseable: Bool) {
        guard var st = states[lineID], revision == st.line.revision else { return } // 过期结果丢掉
        st.recognized = Recognized(revision: revision, termCount: termCount, parseable: parseable)
        states[lineID] = st
        if st.forcedByDoubleTap {
            states[lineID]?.forcedByDoubleTap = false
            forceCheck(lineID)
        } else if st.checkDue {
            states[lineID]?.checkDue = false
            autoCheck(lineID)
        }
    }

    public func doubleTapped(lineID: String) {
        guard var st = states[lineID] else { return }
        st.recognizeTimer?.cancel()
        st.checkTimer?.cancel()
        st.checkDue = false
        states[lineID] = st
        if st.line.mode == .function {
            onRecognize(st.line, .doubleTap)
            return
        }
        if st.recognized?.revision == st.line.revision {
            forceCheck(lineID)
        } else {
            states[lineID]?.forcedByDoubleTap = true
            onRecognize(st.line, .doubleTap)
        }
    }

    /// 当前这一行是否已经有本版本的识别结果（界面可以据此显示「识别中」）。
    public func hasRecognition(lineID: String) -> Bool {
        guard let st = states[lineID] else { return false }
        return st.recognized?.revision == st.line.revision
    }

    private func checkTimerFired(_ id: String) {
        guard let st = states[id] else { return }
        if st.recognized?.revision == st.line.revision {
            autoCheck(id)
        } else {
            states[id]?.checkDue = true
        }
    }

    private func autoCheck(_ id: String) {
        guard let st = states[id], let r = st.recognized, r.revision == st.line.revision else { return }
        guard st.line.mode != .function, r.parseable, st.lastAutoChecked != r.revision else { return }
        if let need = expectedTermCount(st.line), r.termCount < need { return }
        states[id]?.lastAutoChecked = r.revision
        onCheck(st.line, .autoCheck)
    }

    private func forceCheck(_ id: String) {
        guard let st = states[id], let r = st.recognized else { return }
        if r.parseable {
            states[id]?.lastAutoChecked = r.revision
            onCheck(st.line, .doubleTap)
        } else {
            onUnreadable(st.line)
        }
    }
}
