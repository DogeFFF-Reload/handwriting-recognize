import CoreGraphics
import Foundation
import Observation

// contracts/scene-function.sample.json 和 scene-geometry.sample.json 的 Codable 版本，
// 以及右半屏的状态。P1 持有一个 SceneModel，往里喂场景 JSON；视图只读它。

public struct PolyTerm: Codable, Equatable, Hashable {
    public var coef: Double
    public var pow: Int

    public init(coef: Double, pow: Int) {
        self.coef = coef
        self.pow = pow
    }
}

public struct SceneParam: Codable, Equatable {
    public var name: String
    public var value: Double
    public var min: Double
    public var max: Double
}

public struct SceneMark: Codable, Equatable {
    public var type: String
    public var x: Double
    public var y: Double
}

public struct SceneLine: Codable, Equatable {
    public var id: String
    public var latex: String
    public var bbox: [Double]?
}

public struct FunctionScene: Codable, Equatable {
    public struct Body: Codable, Equatable {
        public var terms: [PolyTerm]
        public var params: [SceneParam]?
        public var marks: [SceneMark]?
    }

    public var kind: String
    public var lines: [SceneLine]?
    public var function: Body
}

public struct GeometryScene: Codable, Equatable {
    public struct Point: Codable, Equatable {
        public var id: String
        public var role: String
        public var x: Double
        public var y: Double
    }

    public struct Object: Codable, Equatable {
        public var type: String
        public var id: String
        public var points: [String]
    }

    public struct Relation: Codable, Equatable {
        public var type: String
        public var of: [String]
        public var point: String
    }

    public var kind: String
    public var points: [Point]
    public var objects: [Object]
    public var relations: [Relation]
}

/// 多项式的小工具：求值、求导、极值点（不依赖 MathEngine，只为了画图和拖滑条时实时更新）。
public enum Poly {
    public static func eval(_ terms: [PolyTerm], _ x: Double) -> Double {
        terms.reduce(0) { $0 + $1.coef * Foundation.pow(x, Double($1.pow)) }
    }

    public static func derivative(_ terms: [PolyTerm]) -> [PolyTerm] {
        terms.filter { $0.pow > 0 }.map { PolyTerm(coef: $0.coef * Double($0.pow), pow: $0.pow - 1) }
    }

    public struct Extremum: Equatable {
        public enum Kind { case max, min, flat }
        public var x: Double
        public var y: Double
        public var kind: Kind
    }

    /// 在 [lo, hi] 里扫描 f' 变号再二分。a = 0 退化成直线时自然没有极值。
    public static func extrema(_ terms: [PolyTerm], lo: Double = -10, hi: Double = 10) -> [Extremum] {
        let d = derivative(terms), dd = derivative(d)
        guard d.contains(where: { abs($0.coef) > 1e-12 && $0.pow > 0 }) else { return [] }
        var out: [Extremum] = []
        let step = 0.005
        var px = lo, pv = eval(d, lo)
        var x = lo + step
        while x <= hi {
            let v = eval(d, x)
            if v == 0 || pv * v < 0 {
                var a = px, b = x
                for _ in 0..<60 {
                    let m = (a + b) / 2
                    if eval(d, a) * eval(d, m) <= 0 { b = m } else { a = m }
                }
                let r = (a + b) / 2
                if !out.contains(where: { abs($0.x - r) < 1e-3 }) {
                    let s = eval(dd, r)
                    out.append(Extremum(x: r, y: eval(terms, r), kind: s < -1e-9 ? .max : s > 1e-9 ? .min : .flat))
                }
            }
            px = x; pv = v
            x += step
        }
        return out.filter { $0.kind != .flat }
    }

    /// 写成 LaTeX：[1x^3, -3x] → "x^{3} - 3x"
    public static func latex(_ terms: [PolyTerm]) -> String {
        let live = terms.filter { abs($0.coef) > 1e-9 }.sorted { $0.pow > $1.pow }
        guard !live.isEmpty else { return "0" }
        return live.enumerated().map { i, t in
            let sign = t.coef < 0 ? (i == 0 ? "-" : " - ") : (i == 0 ? "" : " + ")
            let a = abs(t.coef)
            let num = format(a)
            let c = t.pow == 0 ? num : (abs(a - 1) < 1e-9 ? "" : num)
            let v = t.pow == 0 ? "" : (t.pow == 1 ? "x" : "x^{\(t.pow)}")
            return sign + c + v
        }.joined()
    }

    public static func format(_ v: Double) -> String {
        abs(v - v.rounded()) < 1e-9 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }
}

@Observable
public final class SceneModel {
    public enum Content: Equatable {
        case empty
        case function(FunctionScene)
        case geometry(GeometryScene)
    }

    public var content: Content = .empty
    /// 当前曲线的系数（滑条改的就是它）。
    public var terms: [PolyTerm] = []
    /// 第二幕改对之后才为 true：显示极值点、水平切线、导函数和可拖的切点（A9）。
    public var reveal = false
    /// 几何里自由点的当前位置（拖动改它；受约束点每次由关系重算）。
    public var freePoints: [String: CGPoint] = [:]

    public init() {}

    /// 喂一份场景 JSON（scene-function / scene-geometry 两种都收）。
    public func load(json: Data) throws {
        struct Kind: Decodable { var kind: String }
        let kind = try JSONDecoder().decode(Kind.self, from: json).kind
        if kind == "geometry" {
            show(geometry: try JSONDecoder().decode(GeometryScene.self, from: json))
        } else {
            show(function: try JSONDecoder().decode(FunctionScene.self, from: json))
        }
    }

    public func show(function scene: FunctionScene) {
        content = .function(scene)
        terms = scene.function.terms
    }

    /// 只换系数（例如第一幕擦掉 5 写成 3，整行重识别后）。不动 reveal。
    public func setTerms(_ t: [PolyTerm]) {
        if case .function = content {} else {
            content = .function(FunctionScene(kind: "function", lines: nil, function: .init(terms: t, params: nil, marks: nil)))
        }
        terms = t
    }

    public func show(geometry scene: GeometryScene) {
        content = .geometry(scene)
        freePoints = Dictionary(uniqueKeysWithValues: scene.points.filter { $0.role == "free" }.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
    }

    public func clear() {
        content = .empty
        terms = []
        reveal = false
        freePoints = [:]
    }

    /// 所有点的当前位置：自由点取拖动后的值，受约束点按 relations 重算（GeoGebra 的依赖对象）。
    public func resolvedPoints(_ scene: GeometryScene) -> [String: CGPoint] {
        var pos = freePoints
        for p in scene.points where pos[p.id] == nil && p.role == "free" { pos[p.id] = CGPoint(x: p.x, y: p.y) }
        for _ in 0..<3 {   // 关系可能串联，迭代几遍
            for r in scene.relations where r.type == "midpoint" && r.of.count == 2 {
                if let a = pos[r.of[0]], let b = pos[r.of[1]] {
                    pos[r.point] = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
            }
        }
        for p in scene.points where pos[p.id] == nil { pos[p.id] = CGPoint(x: p.x, y: p.y) }
        return pos
    }

    public static func sampleFunction() -> FunctionScene {
        FunctionScene(kind: "function", lines: [SceneLine(id: "L1", latex: "f(x)=x^3-3x", bbox: nil)],
                      function: .init(terms: [PolyTerm(coef: 1, pow: 3), PolyTerm(coef: -3, pow: 1)], params: nil, marks: nil))
    }
}
