#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// 「一段」：双击笔身确认时要处理的那一团墨迹。
///
/// 模式不再在写之前选，而是写完双击后在笔尖旁选（函数 / 推导 / 几何），所以分段不能靠模式。
/// 规则只看位置：从离笔尖最近的一笔（没有落点时取最后写的一笔）出发，
/// 横向间隔小于 `gapX`、纵向间隔小于 `gapY` 的笔画连成一团。
/// 一行式子里字和字的横向间隔、上标和底数的上下距离都在这个范围内；
/// 横线纸上相邻两行之间隔着一行空白，不会并到一起。几何草图的笔画互相交叠，整张图是一团。
public enum InkSegmenter {
    /// 起点：离 `point` 最近（到外框的距离）且在 `maxDistance` 以内的一笔；
    /// 没有落点或都太远时取最后写的一笔。
    public static func seed(in strokes: [InkStroke], near point: CGPoint?, maxDistance: CGFloat = 160) -> InkStroke? {
        if let point {
            let near = strokes.map { ($0, distance(point, $0.bounds)) }.filter { $0.1 <= maxDistance }
            if let best = near.min(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return strokes.max { $0.createdAt < $1.createdAt }
    }

    /// 从 `seed` 出发连成的一团，按书写时间排序。
    public static func cluster(_ strokes: [InkStroke], from seed: InkStroke,
                               gapX: CGFloat = 64, gapY: CGFloat = 22) -> [InkStroke] {
        var members = [seed]
        var inside: Set<String> = [seed.id]
        var frontier = [seed]
        while let s = frontier.popLast() {
            let reach = s.bounds.insetBy(dx: -gapX / 2, dy: -gapY / 2)
            for t in strokes where !inside.contains(t.id) {
                if reach.intersects(t.bounds.insetBy(dx: -gapX / 2, dy: -gapY / 2)) {
                    inside.insert(t.id)
                    members.append(t)
                    frontier.append(t)
                }
            }
        }
        return members.sorted { $0.createdAt < $1.createdAt }
    }

    public static func bounds(of strokes: [InkStroke]) -> CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.bounds) }
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
