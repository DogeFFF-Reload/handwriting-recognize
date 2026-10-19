import Foundation
import InkCore
import Vapor

@main
enum InkTutorServerMain {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

/// 一次提示的上下文，按 id 存在内存里；正确项只在这里，不进 /check 的响应（socratic 模式下）。
actor HintBook {
    private var items: [String: HintRequest] = [:]

    func put(_ h: HintRequest) -> String {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        items[id] = h
        if items.count > 500, let k = items.keys.first { items[k] = nil }
        return id
    }

    func get(_ id: String) -> HintRequest? { items[id] }
}

func configure(_ app: Application, model: ModelClient? = nil) throws {
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
    app.routes.defaultMaxBodySize = "10mb"

    let key = loadAPIKey(workingDirectory: app.directory.workingDirectory)
    let modelClient: ModelClient? = model ?? key.map { DashScopeClient(client: app.client, apiKey: $0) }
    if modelClient == nil { app.logger.warning("没有百炼 Key：只能用回放（INKTUTOR_REPLAY=play）") }

    let mode = ReplayStore.Mode(rawValue: Environment.get("INKTUTOR_REPLAY") ?? "fallback") ?? .fallback
    let store = ReplayStore(mode: mode, directory: URL(fileURLWithPath: app.directory.workingDirectory + "replay"))
    let book = HintBook()
    app.logger.notice("回放模式：\(mode.rawValue)")

    app.get("health") { _ in "ok" }

    // 笔迹截图 → LaTeX（Flash 路径）。识别器只看整行。
    app.post("recognize") { req async throws -> Response in
        let up = try req.content.decode(UploadRequest.self)
        guard let img = up.imageBase64, !img.isEmpty else { throw Abort(.badRequest, reason: "缺 image_base64") }
        let t0 = Date()
        let (text, replayed) = try await withReplayFallback(store: store, route: "recognize") {
            guard let m = modelClient else { throw Abort(.serviceUnavailable, reason: "no key") }
            var lastError: Error = Abort(.badGateway)
            for name in ["qwen3.8-flash", "qwen3-vl-plus"] {
                do {
                    let reply = try await m.chat(model: name, system: nil, prompt: recognitionPrompt, imagePNGBase64: img,
                                                 maxTokens: 200, temperature: 0)
                    return try extractLatex(fromModelReply: reply)
                } catch { lastError = error }
            }
            throw lastError
        }
        let result = RecognitionResult(lineID: up.lineID, revision: up.revision, latex: text,
                                       engine: replayed ? "replay" : "qwen", ms: Int(Date().timeIntervalSince(t0) * 1000))
        req.logger.info("recognize \(up.lineID)#\(up.revision) → \(text) (\(result.ms ?? 0) ms\(replayed ? ", 回放" : ""))")
        return try jsonResponse(result)
    }

    // 登记一次提示，返回 hint_url（/check 判出错后由 App 或 MathEngine 调用）。
    app.post("hint") { req async throws -> Response in
        let h = try req.content.decode(HintRequest.self)
        let id = await book.put(h)
        return try jsonResponse(["hint_url": "/hint/\(id)"])
    }

    // SSE：先整句生成并检查，再逐字推送；结束发 data: [DONE]。
    app.get("hint", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id"), let h = await book.get(id) else { throw Abort(.notFound) }
        let text: String
        if let m = modelClient {
            text = (try? await withReplayFallback(store: store, route: "hint", timeout: 3) {
                await Hints.generate(h, model: m).text
            })?.0 ?? Hints.fallback(h)
        } else {
            text = await store.next("hint") ?? Hints.fallback(h)
        }
        let res = Response(status: .ok)
        res.headers.contentType = HTTPMediaType(type: "text", subType: "event-stream", parameters: ["charset": "utf-8"])
        res.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        res.body = .init(asyncStream: { writer in
            for ch in text {
                try await writer.write(.buffer(ByteBuffer(string: "data: \(ch)\n\n")))
                try await Task.sleep(nanoseconds: 35_000_000)
            }
            try await writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
            try await writer.write(.end)
        })
        return res
    }
}

func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
    let res = Response(status: .ok)
    res.headers.contentType = .json
    res.body = .init(data: try JSONEncoder().encode(value))
    return res
}
