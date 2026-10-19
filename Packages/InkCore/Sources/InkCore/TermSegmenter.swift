#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// 用笔画外框把一行「等号右边」按书写顺序切成项，给圈错项用（A4 的不依赖 MyScript 版本）。
///
/// 规则：等号 = 两条上下叠着的短横；减号/加号的横 = 扁平、不和当前项横向重叠、在行中线附近的笔画。
/// 切出来的项数和识别结果的项数不一致时返回 nil，调用方退回圈整行。
public enum TermSegmenter {
    public static func termBoxes(strokes: [InkStroke], expectedCount: Int? = nil) -> [CGRect]? {
        let ss = strokes.sorted { $0.bounds.minX < $1.bounds.minX }
        guard let first = ss.first else { return nil }
        let row = ss.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
        func flat(_ b: CGRect) -> Bool { b.width > 8 && b.height < max(6, b.width * 0.35) }

        // 等号
        var eqEnd: CGFloat?
        outer: for i in ss.indices where flat(ss[i].bounds) {
            for j in ss.indices where j > i {
                let a = ss[i].bounds, b = ss[j].bounds
                if b.minX > a.maxX + 20 { break }
                guard flat(b) else { continue }
                let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                let gap = abs(a.midY - b.midY)
                if overlap > 0.5 * min(a.width, b.width), gap > 3, gap < max(row.height * 0.5, 20) {
                    eqEnd = max(a.maxX, b.maxX)
                    break outer
                }
            }
        }
        let rhs = ss.filter { eqEnd == nil || $0.bounds.minX > eqEnd! - 2 }
        guard !rhs.isEmpty else { return nil }
        let mid = row.midY

        struct Group { var box: CGRect; var onlySign: Bool }
        var groups: [Group] = []
        for s in rhs {
            let b = s.bounds
            let isSign = flat(b) && abs(b.midY - mid) < row.height * 0.35
            if var cur = groups.last {
                let overlapsCur = b.minX < cur.box.maxX - 2
                if isSign, !overlapsCur, !cur.onlySign {
                    groups.append(Group(box: b, onlySign: true))
                } else {
                    cur.box = cur.box.union(b)
                    if !isSign { cur.onlySign = false }
                    groups[groups.count - 1] = cur
                }
            } else {
                groups.append(Group(box: b, onlySign: isSign))
            }
        }
        let boxes = groups.map(\.box)
        if let n = expectedCount, n != boxes.count { return nil }
        return boxes
    }
}
