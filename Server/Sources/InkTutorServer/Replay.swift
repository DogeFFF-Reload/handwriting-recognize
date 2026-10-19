import Foundation

/// 断网兜底（方案第 8 节）：黄金路径每一步的真实返回存下来，现场网络不行时按顺序放出来。
/// - INKTUTOR_REPLAY=record：真跑，同时把每次返回追加到 replay/<route>.json
/// - INKTUTOR_REPLAY=play：不联网，按顺序返回录好的结果（放完从头循环）
/// - INKTUTOR_REPLAY=fallback（默认）：真跑；3 秒没返回或出错，才放录好的下一条
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
            let r = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await live() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ReplayError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            return (r, false)
        } catch {
            if let r = await store.next(route) { return (r, true) }
            throw error
        }
    }
}

enum ReplayError: Error {
    case timeout
    case nothingRecorded(String)
}
