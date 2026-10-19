import CoreGraphics
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

    public init(id: String, bounds: CGRect, createdAt: Date) {
        self.id = id
        self.bounds = bounds
        self.createdAt = createdAt
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
