#if canImport(Darwin)
import Foundation

/// 交给 Mac 上的 Server：POST {base}/recognize，体是 UploadRequest（带 image_base64）。
public struct ServerRecognizer: InkRecognizer {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        guard let png = imagePNG else { throw RecognizerError.noImage }
        let body = UploadRequest(line: line, trigger: .pause, imageBase64: png.base64EncodedString())
        var req = URLRequest(url: baseURL.appendingPathComponent("recognize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw RecognizerError.http(code, String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(RecognitionResult.self, from: data)
    }
}

/// 直接调百炼的 OpenAI 兼容接口。模型先 qwen3.8-flash，失败换 qwen3-vl-plus。
public struct DashScopeRecognizer: InkRecognizer {
    public var apiKey: String
    public var models: [String]
    public var endpoint: URL
    public var session: URLSession

    public init(apiKey: String,
                models: [String] = ["qwen3.8-flash", "qwen3-vl-plus"],
                endpoint: URL = DashScope.beijing,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.models = models
        self.endpoint = endpoint
        self.session = session
    }

    public func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        guard let png = imagePNG else { throw RecognizerError.noImage }
        var lastError: Error = RecognizerError.badResponse("no model")
        for model in models {
            let t0 = Date()
            do {
                let text = try await DashScope.chat(apiKey: apiKey, endpoint: endpoint, session: session, model: model,
                                                    imagePNG: png, prompt: recognitionPrompt, maxTokens: 200, temperature: 0)
                let latex = try extractLatex(fromModelReply: text)
                return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: model,
                                         ms: Int(Date().timeIntervalSince(t0) * 1000))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

/// 百炼 OpenAI 兼容接口的最小封装（建议 A6：不用第三方 OpenAI 库，enable_thinking 这类参数自己写）。
public enum DashScope {
    public static let beijing = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    public static func chat(apiKey: String, endpoint: URL = beijing, session: URLSession = .shared, model: String,
                            imagePNG: Data? = nil, system: String? = nil, prompt: String,
                            maxTokens: Int = 300, temperature: Double = 0.2) async throws -> String {
        var content: [[String: Any]] = []
        if let png = imagePNG {
            content.append(["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]])
        }
        content.append(["type": "text", "text": prompt])
        var messages: [[String: Any]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": content])
        var body: [String: Any] = ["model": model, "messages": messages, "max_tokens": maxTokens, "temperature": temperature]
        if model.hasPrefix("qwen3.8") { body["enable_thinking"] = false }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw RecognizerError.http(code, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else {
            throw RecognizerError.badResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return text
    }
}

/// 订阅 hint_url 的 SSE（每条 `data: …` 是一段字），结束标记 `data: [DONE]`。
public enum HintStream {
    public static func chunks(from url: URL, session: URLSession = .shared) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let (bytes, _) = try await session.bytes(from: url)
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        cont.yield(payload)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
