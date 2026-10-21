import PencilKit
import UIKit

/// 演示用的「手写」笔画：几个字符用几段平滑曲线拼出来，带一点抖动。
/// 只在启动参数 `-demo <名字>` 时用（CI 在模拟器上截图看界面），正常使用不会走到这里。
enum DemoInk {
    /// 字形：坐标以字高为 1，y 向下，基线在 1，小写字母上沿在 0.45。每个字形是几笔，每笔是几个控制点。
    private struct Glyph {
        var width: CGFloat
        var strokes: [[CGPoint]]
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static let glyphs: [Character: Glyph] = [
        "f": Glyph(width: 0.72, strokes: [[p(0.70, 0.06), p(0.52, -0.02), p(0.40, 0.14), p(0.38, 0.55), p(0.36, 1.02), p(0.26, 1.24), p(0.10, 1.18)],
                                          [p(0.12, 0.47), p(0.66, 0.44)]]),
        "(": Glyph(width: 0.42, strokes: [[p(0.40, -0.04), p(0.16, 0.34), p(0.14, 0.72), p(0.38, 1.12)]]),
        ")": Glyph(width: 0.42, strokes: [[p(0.06, -0.04), p(0.30, 0.34), p(0.32, 0.72), p(0.08, 1.12)]]),
        "x": Glyph(width: 0.62, strokes: [[p(0.06, 0.46), p(0.30, 0.74), p(0.56, 1.0)], [p(0.54, 0.45), p(0.28, 0.74), p(0.04, 1.0)]]),
        "=": Glyph(width: 0.72, strokes: [[p(0.06, 0.60), p(0.64, 0.58)], [p(0.06, 0.82), p(0.66, 0.80)]]),
        "-": Glyph(width: 0.62, strokes: [[p(0.06, 0.72), p(0.54, 0.70)]]),
        "3": Glyph(width: 0.70, strokes: [[p(0.10, 0.12), p(0.38, 0.0), p(0.60, 0.14), p(0.36, 0.46), p(0.64, 0.66), p(0.44, 0.98), p(0.08, 0.90)]]),
        "5": Glyph(width: 0.70, strokes: [[p(0.18, 0.04), p(0.12, 0.44), p(0.44, 0.38), p(0.62, 0.64), p(0.48, 0.96), p(0.08, 0.90)],
                                          [p(0.16, 0.04), p(0.62, 0.0)]]),
        "2": Glyph(width: 0.70, strokes: [[p(0.08, 0.22), p(0.34, 0.0), p(0.60, 0.18), p(0.44, 0.52), p(0.06, 1.0), p(0.64, 0.97)]]),
        "'": Glyph(width: 0.30, strokes: [[p(0.22, 0.02), p(0.10, 0.30)]]),
        "∫": Glyph(width: 0.46, strokes: [[p(0.44, -0.08), p(0.34, -0.16), p(0.26, 0.10), p(0.24, 0.60), p(0.20, 1.10), p(0.10, 1.18), p(0.02, 1.10)]]),
        "d": Glyph(width: 0.66, strokes: [[p(0.50, 0.56), p(0.30, 0.46), p(0.08, 0.70), p(0.20, 1.0), p(0.50, 0.86)],
                                          [p(0.54, -0.02), p(0.52, 0.50), p(0.56, 1.0)]]),
    ]

    /// 把一行写出来。`^` 表示后面一个字符是上标。返回的笔画按书写顺序，各自有不同的创建时间。
    static func strokes(_ text: String, at origin: CGPoint, height: CGFloat, color: UIColor = .black,
                        start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> [PKStroke] {
        var out: [PKStroke] = []
        var x = origin.x
        var superscript = false
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func jitter() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(Double(seed >> 33) / Double(1 << 31)) - 0.5
        }
        for ch in text {
            if ch == "^" { superscript = true; continue }
            guard let g = glyphs[ch] else { x += height * 0.4; continue }
            let scale = superscript ? height * 0.55 : height
            let lift: CGFloat = superscript ? -height * 0.08 : 0
            for control in g.strokes {
                var pts: [CGPoint] = []
                for c in control {
                    let dx: CGFloat = jitter() * height * 0.03
                    let dy: CGFloat = jitter() * height * 0.03
                    pts.append(CGPoint(x: x + c.x * scale + dx, y: origin.y + lift + c.y * scale + dy))
                }
                let samples = smooth(pts)
                let date = start.addingTimeInterval(Double(out.count) * 0.4)
                let points = samples.enumerated().map { i, q in
                    PKStrokePoint(location: q, timeOffset: Double(i) * 0.008, size: CGSize(width: 3.2, height: 3.2),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                out.append(PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: date)))
            }
            x += g.width * scale + height * 0.06
            superscript = false
        }
        return out
    }

    /// 按给的点直接连成一笔（几何演示用：草图的点由调用方生成），带一点手抖。
    static func freehand(_ pts: [CGPoint], start: Date, color: UIColor = .black) -> PKStroke {
        var seed: UInt64 = UInt64(abs(start.timeIntervalSinceReferenceDate.rounded())) | 1
        func jitter() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(Double(seed >> 33) / Double(1 << 31)) - 0.5
        }
        let points = pts.enumerated().map { i, q in
            PKStrokePoint(location: CGPoint(x: q.x + jitter() * 1.6, y: q.y + jitter() * 1.6), timeOffset: Double(i) * 0.008,
                          size: CGSize(width: 3.2, height: 3.2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: start))
    }

    /// 两点之间的直线（几何演示用）。
    static func segment(_ a: CGPoint, _ b: CGPoint, n: Int = 28) -> [CGPoint] {
        (0...n).map { (i: Int) -> CGPoint in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// 线段两头各伸长 d（负数是缩短，留缝）：手画一笔一条边时常见的画过头 / 没碰上。
    static func extend(_ a: CGPoint, _ b: CGPoint, by d: CGFloat) -> (CGPoint, CGPoint) {
        let len = max(hypot(b.x - a.x, b.y - a.y), 1)
        let ux: CGFloat = (b.x - a.x) / len, uy: CGFloat = (b.y - a.y) / len
        return (CGPoint(x: a.x - ux * d, y: a.y - uy * d), CGPoint(x: b.x + ux * d, y: b.y + uy * d))
    }

    /// 椭圆弧（几何演示用）。
    static func arc(_ c: CGPoint, _ a: CGFloat, _ b: CGFloat, from t0: CGFloat = 0, to t1: CGFloat = 2 * .pi, n: Int = 96) -> [CGPoint] {
        (0...n).map { (i: Int) -> CGPoint in
            let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(n)
            return CGPoint(x: c.x + a * cos(t), y: c.y + b * sin(t))
        }
    }

    /// Catmull–Rom：过每个控制点的平滑曲线，每段取 10 个点。
    private static func smooth(_ c: [CGPoint]) -> [CGPoint] {
        guard c.count > 2 else {
            guard let a = c.first, let b = c.last else { return c }
            return (0...10).map { i in
                let t = CGFloat(i) / 10
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
        }
        var out: [CGPoint] = []
        for i in 0..<(c.count - 1) {
            let p0 = c[max(i - 1, 0)], p1 = c[i], p2 = c[i + 1], p3 = c[min(i + 2, c.count - 1)]
            for k in 0..<10 {
                let t = CGFloat(k) / 10
                out.append(CGPoint(x: catmullRom(p0.x, p1.x, p2.x, p3.x, t), y: catmullRom(p0.y, p1.y, p2.y, p3.y, t)))
            }
        }
        out.append(c[c.count - 1])
        return out
    }

    private static func catmullRom(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2: CGFloat = t * t
        let t3: CGFloat = t2 * t
        let k1: CGFloat = (c - a) * t
        let k2: CGFloat = (2 * a - 5 * b + 4 * c - d) * t2
        let k3: CGFloat = (3 * b - a - 3 * c + d) * t3
        return 0.5 * (2 * b + k1 + k2 + k3)
    }
}
