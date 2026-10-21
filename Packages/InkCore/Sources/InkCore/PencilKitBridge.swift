#if canImport(PencilKit) && canImport(UIKit)
import PencilKit
import UIKit

/// PencilKit ↔ InkCore。P1 在 `canvasViewDrawingDidChange` 里：
///
///     let strokes = PencilKitBridge.strokes(from: canvas.drawing, ids: &idTable)
///     let lines = inkModel.apply(strokes: strokes)
///     for line in lines where line.revision != lastRevision[line.id] { gate.strokeChanged(line: line, at: Date()) }
///
/// 识别时用 `PencilKitBridge.png(of: line, in: canvas.drawing)` 取这一行的白底截图。
public enum PencilKitBridge {
    /// PKStroke 在 iPadOS 27 以前没有稳定 id：用 creationDate + 外框做键，分配 s1、s2…（开发方向报告 D3）。
    /// iPadOS 27 起 PKStroke 自带 UUID，换成它即可（id 生成方式变化不影响 InkModel）。
    public struct IDTable {
        var map: [String: String] = [:]
        var next = 1
        public init() {}

        mutating func id(for stroke: PKStroke) -> String {
            let b = stroke.renderBounds
            let key = String(format: "%.6f|%.1f|%.1f|%.1f|%.1f", stroke.path.creationDate.timeIntervalSinceReferenceDate,
                             b.minX, b.minY, b.width, b.height)
            if let id = map[key] { return id }
            let id = "s\(next)"
            next += 1
            map[key] = id
            return id
        }
    }

    /// `spacing`：沿着笔画实际画出来的那条线每隔多少 pt 取一个点。
    /// （PKStrokePath 本身存的是样条的控制点，快速画的直线可能只有两三个，弯的地方控制点还不在线上，几何识别要用线上的点。）
    public static func strokes(from drawing: PKDrawing, ids: inout IDTable, spacing: CGFloat = 3) -> [InkStroke] {
        drawing.strokes.map { s in
            var pts: [CGPoint] = s.path.interpolatedPoints(by: .distance(spacing)).map { $0.location.applying(s.transform) }
            if pts.count < 2 {
                pts = s.path.map { $0.location.applying(s.transform) }
            }
            return InkStroke(id: ids.id(for: s), bounds: s.renderBounds, createdAt: s.path.creationDate, points: pts)
        }
    }

    /// 只含这一行笔画的白底 PNG，外扩 16pt；scale 2 足够 Qwen 识别。
    public static func png(of line: InkLine, in drawing: PKDrawing, ids: inout IDTable, scale: CGFloat = 2) -> Data? {
        let wanted = Set(line.strokes.map(\.id))
        let only = drawing.strokes.filter { wanted.contains(ids.id(for: $0)) }
        guard !only.isEmpty else { return nil }
        let sub = PKDrawing(strokes: only)
        let rect = sub.bounds.insetBy(dx: -16, dy: -16)
        let traits = UITraitCollection(userInterfaceStyle: .light)
        var image = UIImage()
        traits.performAsCurrent { image = sub.image(from: rect, scale: scale) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let out = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
            image.draw(at: .zero)
        }
        return out.pngData()
    }
}
#endif
