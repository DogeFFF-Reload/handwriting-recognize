import Foundation
import Vapor

/// 调大模型的口子。真实现是百炼；单测里换成假的。
protocol ModelClient: Sendable {
    func chat(model: String, system: String?, prompt: String, imagePNGBase64: String?,
              maxTokens: Int, temperature: Double) async throws -> String
}

/// 百炼 OpenAI 兼容接口（北京区域）。用 Vapor 自带的 HTTP 客户端，Linux 和 macOS 都能跑。
struct DashScopeClient: ModelClient {
    let client: Client
    let apiKey: String
    var endpoint = URI(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

    struct ImageURL: Content { var url: String }
    struct Part: Content {
        var type: String
        var text: String?
        var image_url: ImageURL?
    }
    struct Message: Content {
        var role: String
        var content: [Part]
    }
    struct Body: Content {
        var model: String
        var messages: [Message]
        var max_tokens: Int
        var temperature: Double
        var enable_thinking: Bool?
    }
    struct Reply: Content {
        struct Choice: Content {
            struct M: Content { var content: String? }
            var message: M
        }
        var choices: [Choice]
    }

    func chat(model: String, system: String?, prompt: String, imagePNGBase64: String?,
              maxTokens: Int, temperature: Double) async throws -> String {
        var parts: [Part] = []
        if let img = imagePNGBase64 {
            parts.append(Part(type: "image_url", text: nil, image_url: ImageURL(url: "data:image/png;base64," + img)))
        }
        // system 提示并进同一条用户消息，兼容只收数组 content 的模型
        let text = [system, prompt].compactMap { $0 }.joined(separator: "\n\n")
        parts.append(Part(type: "text", text: text, image_url: nil))
        let body = Body(model: model, messages: [Message(role: "user", content: parts)], max_tokens: maxTokens,
                        temperature: temperature, enable_thinking: model.hasPrefix("qwen3.8") ? false : nil)
        let res = try await client.post(endpoint) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
            req.timeout = .seconds(20)
            try req.content.encode(body, as: .json)
        }
        guard res.status == .ok else {
            throw Abort(.badGateway, reason: "DashScope \(res.status.code): \(res.body.map { String(buffer: $0) }?.prefix(200) ?? "")")
        }
        let reply = try res.content.decode(Reply.self)
        guard let content = reply.choices.first?.message.content else { throw Abort(.badGateway, reason: "empty reply") }
        return content
    }
}

/// Key：环境变量 DASHSCOPE_API_KEY，或 Server/.secrets/dashscope_key.txt（.gitignore 已排除）。
func loadAPIKey(workingDirectory: String) -> String? {
    if let k = Environment.get("DASHSCOPE_API_KEY"), !k.isEmpty { return k }
    let path = workingDirectory + ".secrets/dashscope_key.txt"
    return (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}
