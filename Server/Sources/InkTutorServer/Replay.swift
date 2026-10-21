import Foundation
import InkCore

/// 断网兜底（方案第 8 节）：黄金路径每一步的真实返回存下来，现场网络不行时放出来。
/// - INKTUTOR_REPLAY=record：真跑，同时把返回录下来
/// - INKTUTOR_REPLAY=play：不联网，只放录好的
/// - INKTUTOR_REPLAY=fallback（默认）：真跑；3 秒没返回或出错，才放录好的
///
/// /recognize 按「哪种模式的第几行 + 擦过几轮 + 这一轮新写了几笔」取（`RecognizeReplay`，和 App 的
/// ReplayRecognizer 同一套脚本），写到一半多停顿一次也不会错位。/hint 一次批改只要一次，仍按顺序放（`ReplayStore`）。
actor ReplayStore {
    enum Mode: String { case off, record, play, fallback }

    let mode: Mode
    let directory: URL
    private var cursor: [String: Int] = [:]

    init(mode: Mode, directory: URL) {
        self.mode = mode
        self.directory = directory
    }

    private func file(_ route: String) -> URL { directory.appendingPathComponent("\(route).json") }

    func load(_ route: String) -> [String] {
        guard let data = try? Data(contentsOf: file(route)),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    func record(_ route: String, _ payload: String) {
        guard mode == .record else { return }
        var arr = load(route)
        arr.append(payload)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(arr) { try? data.write(to: file(route)) }
    }

    /// 下一条录好的返回；没有录过返回 nil。
    func next(_ route: String) -> String? {
        let arr = load(route)
        guard !arr.isEmpty else { return nil }
        let i = cursor[route, default: 0]
        cursor[route] = (i + 1) % arr.count
        return arr[i]
    }

    func reset() { cursor = [:] }
}

/// 先真跑，`timeout` 秒内没结果或出错，就用录好的。
func withReplayFallback(store: ReplayStore, route: String, timeout: Double = 3,
                        live: @escaping @Sendable () async throws -> String) async throws -> (String, Bool) {
    switch store.mode {
    case .play:
        if let r = await store.next(route) { return (r, true) }
        throw ReplayError.nothingRecorded(route)
    case .off, .record:
        let r = try await live()
        await store.record(route, r)
        return (r, false)
    case .fallback:
        do {
            return (try await withTimeout(timeout, live), false)
        } catch {
            if let r = await store.next(route) { return (r, true) }
            throw error
        }
    }
}

/// /recognize 的回放。录在 replay/recognize-script.json；录过的行替换内置的黄金路径，没录过的行用内置的。
/// 演示从头来（App 清屏）时 POST /replay/reset，让行号重新从第 1 行数；不 reset 也能对上黄金路径。
actor RecognizeReplay {
    let mode: ReplayStore.Mode
    let file: URL
    private var recorded: ReplayScript
    private let tracker = ReplayTracker()

    init(mode: ReplayStore.Mode, directory: URL) {
        self.mode = mode
        file = directory.appendingPathComponent("recognize-script.json")
        recorded = (try? ReplayScript.load(from: file)) ?? ReplayScript()
    }

    /// 每个 /recognize 请求先过一遍，更新这一行的状态。
    func position(of up: UploadRequest) -> ReplayTracker.Position {
        tracker.observe(lineID: up.lineID, mode: up.mode, strokeIDs: up.strokes.map(\.id))
    }

    /// `wholeLine`：App 双击确认后才发识别（trigger = double_tap），这一段已经写完，放这一轮的最后一步。
    func replayed(_ p: ReplayTracker.Position, wholeLine: Bool = false) -> String? {
        ReplayScript.golden.overlaid(with: recorded)
            .latex(mode: p.mode, ordinal: p.ordinal, erasePasses: p.erasePasses, strokesInPass: p.strokesInPass,
                   wholeLine: wholeLine)
    }

    /// 只在 record 模式下录；空结果不录，免得盖掉好的一步。
    func record(_ p: ReplayTracker.Position, _ latex: String) {
        guard mode == .record, !latex.isEmpty else { return }
        recorded.record(mode: p.mode, ordinal: p.ordinal, erasePasses: p.erasePasses, strokesInPass: p.strokesInPass,
                        latex: latex)
        try? recorded.save(to: file)
    }

    func reset() { tracker.reset() }
}

/// /recognize 用：和 `withReplayFallback` 一样的三种模式，回放按这一行的状态取，不按调用顺序。
func recognizeWithReplay(_ replay: RecognizeReplay, upload: UploadRequest, timeout: Double = 3,
                         live: @escaping @Sendable () async throws -> String) async throws -> (String, Bool) {
    let p = await replay.position(of: upload)
    let whole = upload.trigger == .doubleTap
    switch replay.mode {
    case .play:
        if let r = await replay.replayed(p, wholeLine: whole) { return (r, true) }
        throw ReplayError.nothingRecorded("recognize")
    case .off, .record:
        let r = try await live()
        await replay.record(p, r)
        return (r, false)
    case .fallback:
        do {
            return (try await withTimeout(timeout, live), false)
        } catch {
            if let r = await replay.replayed(p, wholeLine: whole) { return (r, true) }
            throw error
        }
    }
}

/// 不用 TaskGroup：TaskGroup 要等所有子任务收尾，而 Vapor client 底下的 EventLoopFuture 不理会取消，
/// 百炼慢的时候会一直等到它自己的 20 秒超时，回放就放不出来了。
private func withTimeout(_ seconds: Double, _ live: @escaping @Sendable () async throws -> String) async throws -> String {
    do {
        return try await withDeadline(seconds: seconds, live)
    } catch is DeadlineExceeded {
        throw ReplayError.timeout
    }
}

enum ReplayError: Error {
    case timeout
    case nothingRecorded(String)
}
