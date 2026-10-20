import Foundation
import MathEngine
import Vapor

// /check、/function、/geometry：只是把 MathEngine 包成 HTTP（P4）。判分全在 MathEngine 里。
// 这个文件不 import InkCore：两个包都有 Annotation、FeedbackMode、InkStroke，放一起会重名。
// 契约见 Packages/MathEngine/Tests/MathEngineTests/contracts/v3/。HTTP 永远 200，失败写在 ok:false 里。

enum MathRoutes {
    /// /check 的核心，不碰 Vapor，方便单测。
    /// 判出错时 `register` 登记一条提示，返回的 id 写进 hint_url。
    /// 提示要用正确项，所以另按 direct 判一遍拿 expected_latex；socratic 的响应里仍然没有它。
    static func check(_ body: Data, register: (HintRequest) async -> String) async throws -> Data {
        let req = try MathEngineJSON.decoder().decode(CheckRequest.self, from: body)
        var result = MathEngineAPI.check(req)
        if let first = result.errors.first(where: { $0.kind != "parse_error" }) {
            var direct = req
            direct.feedbackMode = .direct
            let full = MathEngineAPI.check(direct).errors.first { $0.lineId == first.lineId && $0.wrongLatex == first.wrongLatex }
            let line = req.lines.first { $0.id == first.lineId }
            let hint = HintRequest(kind: first.kind,
                                   wrongLatex: first.wrongLatex ?? "",
                                   expectedLatex: full?.expectedLatex,
                                   sourceLatex: nil,
                                   functionLatex: req.context?.functionLatex,
                                   studentLine: line?.latex,
                                   feedbackMode: req.feedbackMode.rawValue,
                                   level: nil,
                                   explanation: full?.explanation)
            result.hintUrl = "/hint/\(await register(hint))"
        }
        return try MathEngineJSON.encoder().encode(result)
    }

    static func function(_ body: Data) throws -> Data {
        let req = try MathEngineJSON.decoder().decode(FunctionRequest.self, from: body)
        return try MathEngineJSON.encoder().encode(MathEngineAPI.function(req))
    }

    static func geometry(_ body: Data) throws -> Data {
        let req = try MathEngineJSON.decoder().decode(GeometryRequest.self, from: body)
        return try MathEngineJSON.encoder().encode(MathEngineAPI.geometry(req))
    }
}

func registerMathRoutes(_ app: Application, book: HintBook) {
    func json(_ data: Data) -> Response {
        let res = Response(status: .ok)
        res.headers.contentType = .json
        res.body = .init(data: data)
        return res
    }
    func body(_ req: Request) throws -> Data {
        guard let buf = req.body.data else { throw Abort(.badRequest, reason: "空请求") }
        return Data(buffer: buf)
    }

    app.post("check") { req async throws -> Response in
        let data = try await MathRoutes.check(try body(req)) { await book.put($0) }
        return json(data)
    }
    app.post("function") { req throws -> Response in json(try MathRoutes.function(try body(req))) }
    app.post("geometry") { req throws -> Response in json(try MathRoutes.geometry(try body(req))) }
}
