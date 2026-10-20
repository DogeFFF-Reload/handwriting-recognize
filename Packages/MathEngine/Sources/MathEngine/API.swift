//
//  API.swift
//  MathEngine
//
//  v3 接口层。App 直接调（不经过网络，见 PDF 待定建议 A2）和 Vapor 进程调的都是这里。
//  字段与 `contracts/v3/*.json` 一一对应；契约改先改 JSON，再改这里。
//
//  和 v2 的区别（PDF 已定决策）：
//    + feedback_mode : "direct"（默认）| "socratic"
//    + explanation   : direct 模式下的一句说明（模板生成，不调模型）
//    + expected_latex: direct 模式下下发正确项；socratic 模式永远不下发
//    + lines[].line_id / revision：P1 按 y 带分行的结果原样回注
//

import Foundation

// MARK: - 请求

public struct CheckRequest: Codable, Equatable {

    public struct LineInput: Codable, Equatable {
        public var id: String
        public var latex: String
        public var bbox: Box?
        public var revision: Int?

        // 解码策略是 convertFromSnakeCase：契约里的 line_id 到这里就是 lineId
        private enum CodingKeys: String, CodingKey {
            case id, latex, bbox, revision, lineId
        }

        public init(id: String, latex: String, bbox: Box? = nil, revision: Int? = nil) {
            self.id = id
            self.latex = latex
            self.bbox = bbox
            self.revision = revision
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            latex = try c.decode(String.self, forKey: .latex)
            revision = try c.decodeIfPresent(Int.self, forKey: .revision)
            bbox = try c.decodeIfPresent(Box.self, forKey: .bbox)
            // 老客户端发 id，PDF 里的新字段叫 line_id；两个都认
            let byId = try c.decodeIfPresent(String.self, forKey: .id)
            let byLineId = try c.decodeIfPresent(String.self, forKey: .lineId)
            id = byId ?? byLineId ?? "L1"
        }

        /// 编码时按 v3 契约写 `line_id`（P3 的 InkModel 就是这么产生的行号）
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .lineId)
            try c.encode(latex, forKey: .latex)
            try c.encodeIfPresent(bbox, forKey: .bbox)
            try c.encodeIfPresent(revision, forKey: .revision)
        }
    }

    public struct Context: Codable, Equatable {
        public var functionLatex: String?
        public var variable: String?
        public var template: String?

        private enum CodingKeys: String, CodingKey {
            case functionLatex, variable, template
        }

        public init(functionLatex: String? = nil, variable: String? = nil, template: String? = nil) {
            self.functionLatex = functionLatex
            self.variable = variable
            self.template = template
        }
    }

    public struct Options: Codable, Equatable {
        public var withScene: Bool?
        public var maxErrors: Int?

        private enum CodingKeys: String, CodingKey {
            case withScene, maxErrors
        }

        public init(withScene: Bool? = nil, maxErrors: Int? = nil) {
            self.withScene = withScene
            self.maxErrors = maxErrors
        }
    }

    public struct Region: Codable, Equatable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public var scale: Double

        public init(x: Double, y: Double, w: Double, h: Double, scale: Double = 2) {
            self.x = x; self.y = y; self.w = w; self.h = h; self.scale = scale
        }
    }

    public var mode: String
    public var lines: [LineInput]
    public var context: Context?
    public var options: Options?
    public var strokes: [InkStroke]?
    public var region: Region?
    /// 缺省 direct（第一版）。
    public var feedbackMode: FeedbackMode

    private enum CodingKeys: String, CodingKey {
        case mode, lines, context, options, strokes, region, feedbackMode
    }

    public init(mode: String, lines: [LineInput], context: Context? = nil,
                options: Options? = nil, strokes: [InkStroke]? = nil,
                region: Region? = nil, feedbackMode: FeedbackMode = .direct) {
        self.mode = mode
        self.lines = lines
        self.context = context
        self.options = options
        self.strokes = strokes
        self.region = region
        self.feedbackMode = feedbackMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "auto"
        lines = try c.decode([LineInput].self, forKey: .lines)
        context = try c.decodeIfPresent(Context.self, forKey: .context)
        options = try c.decodeIfPresent(Options.self, forKey: .options)
        strokes = try c.decodeIfPresent([InkStroke].self, forKey: .strokes)
        region = try c.decodeIfPresent(Region.self, forKey: .region)
        let fm = try c.decodeIfPresent(String.self, forKey: .feedbackMode)
        feedbackMode = FeedbackMode(rawValue: fm ?? "") ?? .direct
    }
}

public struct FunctionRequest: Codable, Equatable {
    public struct ViewInput: Codable, Equatable {
        public var xMin: Double
        public var xMax: Double
        public var yMin: Double
        public var yMax: Double
        private enum CodingKeys: String, CodingKey { case xMin, xMax, yMin, yMax }
        public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
            self.xMin = xMin; self.xMax = xMax; self.yMin = yMin; self.yMax = yMax
        }
    }
    public struct LineInput: Codable, Equatable {
        public var id: String
        public var latex: String
        public var bbox: Box?
        public init(id: String, latex: String, bbox: Box? = nil) {
            self.id = id; self.latex = latex; self.bbox = bbox
        }
    }
    public var latex: String
    public var variable: String?
    public var view: ViewInput?
    public var lines: [LineInput]?

    public init(latex: String, variable: String? = nil, view: ViewInput? = nil, lines: [LineInput]? = nil) {
        self.latex = latex; self.variable = variable; self.view = view; self.lines = lines
    }
}

public struct GeometryRequest: Codable, Equatable {
    public struct PointInput: Codable, Equatable {
        public var id: String
        public var x: Double
        public var y: Double
        public var free: Bool
        public init(id: String, x: Double, y: Double, free: Bool) {
            self.id = id; self.x = x; self.y = y; self.free = free
        }
    }
    public struct RelationInput: Codable, Equatable {
        public var type: String
        public var of: [String]
        public var point: String
        public init(type: String, of: [String], point: String) {
            self.type = type; self.of = of; self.point = point
        }
    }
    public var mode: String?
    public var points: [PointInput]?
    public var relations: [RelationInput]?
    public var context: CheckRequest.Context?

    public init(mode: String? = nil, points: [PointInput]? = nil,
                relations: [RelationInput]? = nil, context: CheckRequest.Context? = nil) {
        self.mode = mode; self.points = points; self.relations = relations; self.context = context
    }
}

// MARK: - 响应

public struct FunctionParamJSON: Codable, Equatable {
    public var name: String
    public var value: Double
    public var sign: Int
    public var min: Double
    public var max: Double
    public var step: Double
    public var pow: Int
}

public struct TermJSON: Codable, Equatable {
    public var coef: Double
    public var pow: Int
    public var param: String
    public var sign: Int
}

public struct MarkJSON: Codable, Equatable {
    public var type: String
    public var kind: String?
    public var x: Double
    public var y: Double
    public var slope: Double?
}

public struct ViewJSON: Codable, Equatable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double
}

public struct FunctionPayload: Codable, Equatable {
    public var terms: [TermJSON]
    public var params: [FunctionParamJSON]
    public var marks: [MarkJSON]
    public var view: ViewJSON
}

public struct SceneLine: Codable, Equatable {
    public var id: String
    public var latex: String
    public var bbox: Box?
}

public struct FunctionSceneJSON: Codable, Equatable {
    public var kind: String = "function"
    public var lines: [SceneLine]
    public var function: FunctionPayload
}

public struct FunctionResponse: Codable, Equatable {
    public var ok: Bool
    public var scene: FunctionSceneJSON?
    public var error: String?
    public var degraded: [String]
    public var replayed: Bool
    public var engine: String
}

public struct AnnotationError: Codable, Equatable {
    public var lineId: String
    public var kind: String
    public var wrongLatex: String?
    public var charSpan: [Int]?
    public var bbox: Box?
    public var bboxSource: String?
    public var hintFallback: String
    public var expectedLatex: String?
    public var expectedPow: Int?
    public var explanation: String?
    public var row: Int?
    public var col: Int?
}

public struct CheckedJSON: Codable, Equatable {
    public var lineCount: Int
    public var rhsLatex: [String]
}

public struct Annotation: Codable, Equatable {
    public var ok: Bool
    public var mode: String
    public var feedbackMode: String
    public var errors: [AnnotationError]
    public var function: FunctionPayload?
    public var hintUrl: String?
    public var checked: CheckedJSON
    public var degraded: [String]
    public var replayed: Bool
    public var engine: String
}

public struct GeometrySceneJSON: Codable, Equatable {
    public struct PointJSON: Codable, Equatable {
        public var id: String
        public var x: Double
        public var y: Double
        public var free: Bool
    }
    public struct ObjectJSON: Codable, Equatable {
        public var type: String
        public var of: [String]
    }
    public struct RelationJSON: Codable, Equatable {
        public var type: String
        public var of: [String]
        public var point: String
    }
    public var kind: String = "geometry"
    public var points: [PointJSON]
    public var objects: [ObjectJSON]
    public var relations: [RelationJSON]
    public var degraded: [String]
}

public struct GeometryResponse: Codable, Equatable {
    public var ok: Bool
    public var scene: GeometrySceneJSON?
    public var error: String?
    public var replayed: Bool
    public var engine: String
}

// MARK: - 场景 → JSON

public extension FunctionScene {

    var payload: FunctionPayload {
        FunctionPayload(
            terms: terms.map { t in
                TermJSON(coef: t.coef.doubleValue,
                         pow: t.pow,
                         param: paramName(forPow: t.pow) ?? "",
                         sign: t.coef.isNegative ? -1 : 1)
            },
            params: params.map {
                FunctionParamJSON(name: $0.name, value: $0.value, sign: $0.sign,
                                  min: $0.min, max: $0.max, step: $0.step, pow: $0.pow)
            },
            marks: marks.map {
                MarkJSON(type: $0.type, kind: $0.kind, x: $0.x, y: $0.y, slope: $0.slope)
            },
            view: ViewJSON(xMin: view.xMin, xMax: view.xMax, yMin: view.yMin, yMax: view.yMax)
        )
    }

    /// App 内直接调用：滑条拖动时把新值回灌，得到新的场景 JSON
    func updatedPayload(values: [String: Double]) -> FunctionPayload {
        updated(values: values).payload
    }
}

// MARK: - 门面：App 和 Vapor 都只调这三个

public enum MathEngineAPI {

    public static let version = "MathEngine (swift) 0.3.0"

    public static func function(_ req: FunctionRequest,
                                replayed: Bool = false) -> FunctionResponse {
        let view: ViewWindow
        if let v = req.view {
            view = ViewWindow(xMin: v.xMin, xMax: v.xMax, yMin: v.yMin, yMax: v.yMax)
        } else {
            view = .standard
        }
        do {
            let scene = try FunctionSceneBuilder.build(req.latex, view: view)
            let lines = (req.lines ?? [FunctionRequest.LineInput(id: "L1", latex: req.latex, bbox: nil)])
                .map { SceneLine(id: $0.id, latex: $0.latex, bbox: $0.bbox) }
            return FunctionResponse(ok: true,
                                    scene: FunctionSceneJSON(lines: lines, function: scene.payload),
                                    error: nil,
                                    degraded: scene.degraded,
                                    replayed: replayed,
                                    engine: version)
        } catch {
            return FunctionResponse(ok: false, scene: nil,
                                    error: describe(error),
                                    degraded: ["scene_unavailable"],
                                    replayed: replayed,
                                    engine: version)
        }
    }

    /// 一次抬笔的若干行 → 批注。**失败也返回 ok:false 的响应，绝不抛错**（HTTP 永远 200）
    public static func check(_ req: CheckRequest, replayed: Bool = false) -> Annotation {
        let mode = resolveMode(req)
        let feedback = req.feedbackMode
        let maxErrors = Swift.max(1, req.options?.maxErrors ?? 3)
        let strokes = req.strokes ?? []
        var errors: [AnnotationError] = []
        var degraded: [String] = []
        var rhs: [String] = []

        for line in req.lines {
            // char_span 相对这串正文（归一化后的），P1 拿它做字符→笔画的映射
            rhs.append(body(of: line.latex))
            let lineBox = line.bbox ?? req.region.map { Box(x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
            let defects: [Defect]
            do {
                defects = try run(mode: mode, request: req, line: line)
            } catch {
                errors.append(makeError(lineId: line.id, lineBox: lineBox, line: line, strokes: strokes,
                                        defect: Defect(kind: .parseError, wrongLatex: line.latex,
                                                       explanation: Explain.parseError),
                                        feedback: feedback, detail: describe(error)))
                continue
            }
            for d in defects {
                errors.append(makeError(lineId: line.id, lineBox: lineBox, line: line, strokes: strokes,
                                        defect: d, feedback: feedback))
            }
        }

        let ok = errors.isEmpty
        var function: FunctionPayload? = nil
        if ok, mode == "derivative", req.options?.withScene ?? true,
           let f = req.context?.functionLatex, let scene = try? FunctionSceneBuilder.build(f) {
            function = scene.payload
            degraded.append(contentsOf: scene.degraded)
        }
        if errors.count > maxErrors {
            errors = Array(errors.prefix(maxErrors))
            degraded.append("errors_truncated")
        }
        return Annotation(ok: ok,
                          mode: mode,
                          feedbackMode: feedback.rawValue,
                          errors: errors,
                          function: function,
                          hintUrl: nil,
                          checked: CheckedJSON(lineCount: req.lines.count, rhsLatex: rhs),
                          degraded: degraded,
                          replayed: replayed,
                          engine: version)
    }

    public static func geometry(_ req: GeometryRequest, replayed: Bool = false) -> GeometryResponse {
        let pts = (req.points ?? []).map {
            GeoPoint(id: $0.id, x: $0.x, y: $0.y, free: $0.free)
        }
        guard pts.count >= 3 else {
            return GeometryResponse(ok: false, scene: nil, error: "至少要有三个点",
                                    replayed: replayed, engine: version)
        }
        let rels = (req.relations ?? []).map { GeoRelation(type: $0.type, of: $0.of, point: $0.point) }
        let resolved = Geometry.resolve(points: pts, relations: rels)
        var used = Set<String>()
        var objects: [GeometrySceneJSON.ObjectJSON] = []
        // 三角形三条边：三个自由点按顺序连
        let free = resolved.filter { $0.free }
        if free.count >= 3 {
            for i in 0..<3 {
                let a = free[i].id, b = free[(i + 1) % 3].id
                objects.append(.init(type: "segment", of: [a, b]))
            }
        }
        for r in rels where r.type == "midpoint" {
            guard r.of.count == 2, let apex = free.first(where: { !r.of.contains($0.id) }) else { continue }
            used.insert(r.point)
            objects.append(.init(type: "segment", of: [apex.id, r.point]))
        }
        let scene = GeometrySceneJSON(
            points: resolved.map { .init(id: $0.id, x: $0.x, y: $0.y, free: $0.free) },
            objects: objects,
            relations: rels.map { .init(type: $0.type, of: $0.of, point: $0.point) },
            degraded: []
        )
        return GeometryResponse(ok: true, scene: scene, error: nil, replayed: replayed, engine: version)
    }

    // MARK: - 内部

    static func resolveMode(_ req: CheckRequest) -> String {
        let m = req.mode.lowercased()
        if m != "auto" && !m.isEmpty { return m }
        let all = req.lines.map { $0.latex }.joined(separator: " ")
        if all.contains("\\begin{pmatrix}") || all.contains("\\begin{bmatrix}") { return "matrix" }
        if all.contains("\\int") { return "integral" }
        if req.context?.functionLatex != nil { return "derivative" }
        return "function"
    }

    static func run(mode: String, request req: CheckRequest, line: CheckRequest.LineInput) throws -> [Defect] {
        switch mode {
        case "derivative":
            guard let f = req.context?.functionLatex else {
                throw MathError.unsupported("推导模式缺 context.function_latex")
            }
            return try DerivativeCheck.run(functionLatex: f, lineLatex: line.latex)
        case "matrix":
            return try MatrixCheck.run(line.latex)
        case "integral":
            return try IntegralCheck.run(line.latex)
        case "step":
            return try StepCheck.run(req.lines.map { $0.latex })
        case "function":
            // 函数模式不批改，只出图（D1：双击 = 立即刷新图像）
            return FunctionSceneBuilder.isPlottable(line.latex)
                ? []
                : [Defect(kind: .parseError, wrongLatex: line.latex, explanation: Explain.parseError)]
        default:
            throw MathError.unsupported("未知模式 \(mode)")
        }
    }

    static func makeError(lineId: String, lineBox: Box?, line: CheckRequest.LineInput,
                          strokes: [InkStroke], defect d: Defect,
                          feedback: FeedbackMode, detail: String? = nil) -> AnnotationError {
        var box = lineBox
        var source: String? = nil
        if let lineBox = lineBox {
            if let span = d.span {
                let est = TermBox.estimate(line: lineBox, label: label(of: line.latex),
                                           body: body(of: line.latex), span: span)
                box = TermBox.snap(est, strokes: strokes) ?? est
                source = "term"
            } else {
                source = "line"
            }
        }
        let direct = feedback == .direct
        return AnnotationError(
            lineId: lineId,
            kind: d.kind.rawValue,
            wrongLatex: d.wrongLatex,
            charSpan: d.span.map { [$0.lowerBound, $0.upperBound] },
            bbox: box,
            bboxSource: box == nil ? nil : (source ?? "line"),
            hintFallback: d.fallbackHint(),
            expectedLatex: direct ? d.expectedLatex : nil,
            expectedPow: direct ? d.expectedPow : nil,
            explanation: direct ? (d.explanation ?? defaultExplanation(d, detail: detail)) : nil,
            row: d.row,
            col: d.col
        )
    }

    static func defaultExplanation(_ d: Defect, detail: String?) -> String? {
        if let detail = detail { return detail }
        switch d.kind {
        case .parseError: return Explain.parseError
        case .notEquivalent: return nil
        default: return d.expectedLatex.map { "这一项应是 \($0)。" }
        }
    }

    /// `f'(x)=3x^2-3x` → 标签 `f'(x)`
    static func label(of latex: String) -> String? {
        if case .labelled(let l, _) = LineShape.split(latex) { return l }
        return nil
    }

    static func body(of latex: String) -> String {
        switch LineShape.split(latex) {
        case .labelled(_, let b): return b
        case .expression(let s): return s
        case .equation(let l, let r): return l + "=" + r
        }
    }

    static func describe(_ error: Error) -> String {
        if let m = error as? MathError { return m.description }
        return "\(error)"
    }
}

// MARK: - 编码辅助

public enum MathEngineJSON {

    /// 契约一律 snake_case：编码时自动转，所以 Swift 里可以继续写 camelCase。
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    /// App 解响应、Vapor 解请求都用它（snake_case → camelCase）
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func string<T: Encodable>(_ v: T) -> String {
        (try? encoder().encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
