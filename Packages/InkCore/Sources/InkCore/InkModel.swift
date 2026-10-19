#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum InkMode: String, Codable, Equatable {
    case function
    case derivative
    case geometry
}

public struct InkStroke: Equatable, Identifiable {
    public var id: String
    public var bounds: CGRect
    public var createdAt: Date
    /// 笔画上的点（画布 point）。分行只用 bounds；几何草图识别要用点。
    public var points: [CGPoint]

    public init(id: String, bounds: CGRect, createdAt: Date, points: [CGPoint] = []) {
        self.id = id
        self.bounds = bounds
        self.createdAt = createdAt
        self.points = points
    }
}

public struct InkLine: Equatable, Identifiable {
    public var id: String
    public var revision: Int
    public var mode: InkMode
    public var band: CGRect
    public var strokes: [InkStroke]
    public var removedStrokeIDs: [String]

    public init(id: String, revision: Int, mode: InkMode, band: CGRect, strokes: [InkStroke], removedStrokeIDs: [String]) {
        self.id = id
        self.revision = revision
        self.mode = mode
        self.band = band
        self.strokes = strokes
        self.removedStrokeIDs = removedStrokeIDs
    }
}

public protocol InkModeling {
    func apply(strokes: [InkStroke]) -> [InkLine]
}

public protocol CheckGating {
    func strokeChanged(line: InkLine, at: Date)
    func recognitionReturned(lineID: String, revision: Int, latex: String, termCount: Int, parseable: Bool)
    func doubleTapped(lineID: String)
}

// One line for the whole canvas. P3 replaces this with y-band grouping.
public struct PlaceholderInkModel: InkModeling {
    public var mode: InkMode

    public init(mode: InkMode = .function) {
        self.mode = mode
    }

    public func apply(strokes: [InkStroke]) -> [InkLine] {
        guard let first = strokes.first else { return [] }
        let band = strokes.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
        return [
            InkLine(
                id: "L1",
                revision: strokes.count,
                mode: mode,
                band: band,
                strokes: strokes,
                removedStrokeIDs: []
            )
        ]
    }
}

/// 按 y 带状分行（开发方向报告 D3）。
///
/// - 每次把画布上**现存的全部笔画**传进 `apply`，它自己比对出新增和删除。
/// - 新笔画的垂直中心落进某行的带内（上下各外扩 0.3 倍行高）就归入该行，落进多行取最近的；
///   都不落入就新建一行 `L<n>`，记下建行时的模式。行号永不复用。
/// - 几何模式不分行：所有几何笔画进同一行 `G1`。
/// - 一行每增删一次笔画 `revision + 1`；被删的笔画记进 `removedStrokeIDs`，
///   上传以后调用 `markSent(lineID:)` 清空。
public final class BandInkModel: InkModeling {
    public var mode: InkMode
    /// 行带上下外扩的比例。
    public var bandPadding: CGFloat = 0.3
    /// 一行至少按这么高算外扩，避免第一笔是个「-」时带太窄。
    public var minLineHeight: CGFloat = 48

    private struct LineState {
        var id: String
        var mode: InkMode
        var revision = 0
        var band: CGRect = .null
        var strokeIDs: [String] = []
        var removed: [String] = []
    }

    private var lines: [LineState] = []
    private var strokeLine: [String: Int] = [:]   // stroke id -> lines 下标
    private var known: [String: InkStroke] = [:]
    private var nextLineNumber = 1
    private var geometryLine: Int?

    public init(mode: InkMode = .function) {
        self.mode = mode
    }

    public func apply(strokes: [InkStroke]) -> [InkLine] {
        let current = Dictionary(strokes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 删除
        for (id, _) in known where current[id] == nil {
            if let li = strokeLine.removeValue(forKey: id) {
                lines[li].strokeIDs.removeAll { $0 == id }
                lines[li].removed.append(id)
                lines[li].revision += 1
                lines[li].band = band(of: lines[li].strokeIDs, in: current)
            }
            known[id] = nil
        }
        // 新增：按创建时间顺序归行
        let added = strokes.filter { known[$0.id] == nil }.sorted { $0.createdAt < $1.createdAt }
        for s in added {
            let li = lineIndex(for: s)
            lines[li].strokeIDs.append(s.id)
            lines[li].revision += 1
            lines[li].band = lines[li].band.isNull ? s.bounds : lines[li].band.union(s.bounds)
            strokeLine[s.id] = li
            known[s.id] = s
        }
        // 位置可能被移动过（套索），用最新的
        for s in strokes { known[s.id] = s }

        return lines
            .filter { !$0.strokeIDs.isEmpty || !$0.removed.isEmpty }
            .sorted { ($0.band.isNull ? .greatestFiniteMagnitude : $0.band.minY) < ($1.band.isNull ? .greatestFiniteMagnitude : $1.band.minY) }
            .map { st in
                InkLine(id: st.id, revision: st.revision, mode: st.mode,
                        band: st.band.isNull ? .zero : st.band,
                        strokes: st.strokeIDs.compactMap { current[$0] },
                        removedStrokeIDs: st.removed)
            }
    }

    /// 这一行的上传已经发出：清空待上报的删除记录。
    public func markSent(lineID: String) {
        if let i = lines.firstIndex(where: { $0.id == lineID }) { lines[i].removed = [] }
    }

    /// 某一笔属于哪一行。
    public func lineID(ofStroke id: String) -> String? {
        strokeLine[id].map { lines[$0].id }
    }

    private func band(of ids: [String], in current: [String: InkStroke]) -> CGRect {
        ids.compactMap { current[$0]?.bounds }.reduce(CGRect.null) { $0.union($1) }
    }

    private func lineIndex(for s: InkStroke) -> Int {
        if mode == .geometry {
            if let g = geometryLine { return g }
            lines.append(LineState(id: "G1", mode: .geometry))
            geometryLine = lines.count - 1
            return lines.count - 1
        }
        let cy = s.bounds.midY
        var best: (Int, CGFloat)?
        for (i, l) in lines.enumerated() where l.mode != .geometry && !l.band.isNull {
            let h = max(l.band.height, minLineHeight)
            let lo = l.band.minY - bandPadding * h, hi = l.band.maxY + bandPadding * h
            guard cy >= lo, cy <= hi else { continue }
            let d = abs(cy - l.band.midY)
            if best == nil || d < best!.1 { best = (i, d) }
        }
        if let b = best { return b.0 }
        lines.append(LineState(id: "L\(nextLineNumber)", mode: mode))
        nextLineNumber += 1
        return lines.count - 1
    }
}
