#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// contracts/ 里四份 JSON 的 Codable 版本。字段名和样例完全一致（snake_case）。
// App 内部只用 CGRect；`Region` 是 {x,y,w,h}，`bbox` 是 [x1,y1,x2,y2]，换算只在这里做（A3）。

public struct Region: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var scale: Double

    public init(_ r: CGRect, scale: Double = 2) {
        x = Double(r.minX); y = Double(r.minY); w = Double(r.width); h = Double(r.height); self.scale = scale
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

public enum BBox {
    public static func array(_ r: CGRect) -> [Double] {
        [Double(r.minX), Double(r.minY), Double(r.maxX), Double(r.maxY)]
    }

    public static func rect(_ a: [Double]) -> CGRect? {
        guard a.count == 4 else { return nil }
        return CGRect(x: a[0], y: a[1], width: a[2] - a[0], height: a[3] - a[1])
    }
}

public struct UploadStroke: Codable, Equatable {
    public var id: String
    /// 每个点 [x, y, 时间秒, 压感]
    public var points: [[Double]]

    public init(id: String, points: [[Double]]) {
        self.id = id
        self.points = points
    }
}

public struct UploadContext: Codable, Equatable {
    public var functionLatex: String?

    enum CodingKeys: String, CodingKey { case functionLatex = "function_latex" }

    public init(functionLatex: String? = nil) { self.functionLatex = functionLatex }
}

/// contracts/upload.sample.json
public struct UploadRequest: Codable, Equatable {
    public var mode: InkMode
    public var lineID: String
    public var revision: Int
    public var trigger: CheckTrigger
    public var region: Region
    public var latex: String?
    public var strokes: [UploadStroke]
    public var removedStrokeIDs: [String]
    public var context: UploadContext?
    /// 只有走 Flash（Qwen 看图）时才带：这一行的 PNG，base64。
    public var imageBase64: String?

    enum CodingKeys: String, CodingKey {
        case mode, revision, trigger, region, latex, strokes, context
        case lineID = "line_id"
        case removedStrokeIDs = "removed_stroke_ids"
        case imageBase64 = "image_base64"
    }

    public init(mode: InkMode, lineID: String, revision: Int, trigger: CheckTrigger, region: Region,
                latex: String? = nil, strokes: [UploadStroke], removedStrokeIDs: [String],
                context: UploadContext? = nil, imageBase64: String? = nil) {
        self.mode = mode; self.lineID = lineID; self.revision = revision; self.trigger = trigger
        self.region = region; self.latex = latex; self.strokes = strokes
        self.removedStrokeIDs = removedStrokeIDs; self.context = context; self.imageBase64 = imageBase64
    }

    /// 从一行生成上传体。`points` 没有时间和压感的，补 0 和 0.5。
    public init(line: InkLine, trigger: CheckTrigger, latex: String? = nil,
                functionLatex: String? = nil, imageBase64: String? = nil, scale: Double = 2) {
        self.init(mode: line.mode, lineID: line.id, revision: line.revision, trigger: trigger,
                  region: Region(line.band, scale: scale), latex: latex,
                  strokes: line.strokes.map { s in
                      UploadStroke(id: s.id, points: s.points.map { [Double($0.x), Double($0.y), 0, 0.5] })
                  },
                  removedStrokeIDs: line.removedStrokeIDs,
                  context: functionLatex.map { UploadContext(functionLatex: $0) },
                  imageBase64: imageBase64)
    }
}

public enum FeedbackMode: String, Codable, Equatable {
    case direct
    case socratic
}

public struct AnnotationError: Codable, Equatable {
    public var kind: String
    public var wrongLatex: String
    /// 只在 direct 模式下下发。
    public var expectedLatex: String?
    public var bbox: [Double]?

    enum CodingKeys: String, CodingKey {
        case kind, bbox
        case wrongLatex = "wrong_latex"
        case expectedLatex = "expected_latex"
    }

    public init(kind: String, wrongLatex: String, expectedLatex: String? = nil, bbox: [Double]? = nil) {
        self.kind = kind; self.wrongLatex = wrongLatex; self.expectedLatex = expectedLatex; self.bbox = bbox
    }

    public var rect: CGRect? { bbox.flatMap(BBox.rect) }
}

/// contracts/annotation.sample.json
public struct Annotation: Codable, Equatable {
    public var lineID: String
    public var revision: Int
    public var ok: Bool
    public var feedbackMode: FeedbackMode
    public var errors: [AnnotationError]
    public var explanation: String?
    public var hintURL: String?

    enum CodingKeys: String, CodingKey {
        case revision, ok, errors, explanation
        case lineID = "line_id"
        case feedbackMode = "feedback_mode"
        case hintURL = "hint_url"
    }

    public init(lineID: String, revision: Int, ok: Bool, feedbackMode: FeedbackMode = .direct,
                errors: [AnnotationError] = [], explanation: String? = nil, hintURL: String? = nil) {
        self.lineID = lineID; self.revision = revision; self.ok = ok; self.feedbackMode = feedbackMode
        self.errors = errors; self.explanation = explanation; self.hintURL = hintURL
    }

    /// socratic 模式下不能带正确项：发出去之前调用。
    public func redactedForSocratic() -> Annotation {
        var a = self
        a.feedbackMode = .socratic
        a.errors = errors.map { var e = $0; e.expectedLatex = nil; return e }
        a.explanation = nil
        return a
    }
}

/// 识别结果：/recognize 的返回。
public struct RecognitionResult: Codable, Equatable {
    public var lineID: String
    public var revision: Int
    public var latex: String
    public var engine: String?
    public var ms: Int?

    enum CodingKeys: String, CodingKey {
        case revision, latex, engine, ms
        case lineID = "line_id"
    }

    public init(lineID: String, revision: Int, latex: String, engine: String? = nil, ms: Int? = nil) {
        self.lineID = lineID; self.revision = revision; self.latex = latex; self.engine = engine; self.ms = ms
    }
}
