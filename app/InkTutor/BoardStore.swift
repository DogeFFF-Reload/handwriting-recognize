import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI
import UIKit

// 多份草稿（参考无边记）：每份草稿是 Documents/Boards/<id>/ 下的一个文件夹——
//   meta.json     名字、建立和修改时间（画廊只读它）
//   board.json    式子、卡片、几何图形（BoardSnapshot）
//   drawing.data  纸上的笔迹（PKDrawing）
//   thumb.jpg     画廊里的缩略图（离开草稿、切到后台时截一张）
// 草稿打开时每 3 秒检查一次，有变化就存；离开、切到后台时也存。

/// 画廊里显示的一份草稿。
struct BoardMeta: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var created: Date
    var modified: Date
}

/// 卡片的位置、大小、旋转、收没收起。
struct CardSnapshot: Codable {
    var center: CGPoint
    var size: CGSize
    var rotation: Double
    var minimized: Bool

    init(_ f: CardFrame) {
        center = f.center
        size = f.size
        rotation = f.rotation.degrees
        minimized = f.minimized
    }

    var frame: CardFrame { CardFrame(center: center, size: size, rotation: .degrees(rotation), minimized: minimized) }
}

/// 一条式子：函数（带卡片）、求出来的导数、求解。重新打开时按 LaTeX 重新解析、重新求，不存算出来的结果。
struct FunctionSnapshot: Codable {
    enum Kind: String, Codable { case function, derivative, solve }
    var kind: Kind
    var lineID: String
    var latex: String
    var origin: CGPoint
    var fontSize: CGFloat
    var size: CGSize
    var card: CardSnapshot
    var tintIndex: Int
    var showsSliders: Bool
    var minimal: Bool
    var engine: String?
    var ms: Int?
    /// 原来的笔迹（PKDrawing 数据）：「改笔迹」时放回纸上。
    var ink: Data
    /// 导数：原函数是第几条。
    var parent: Int?
    var request: DerivativeRequest?
    var solveSource: String?
    /// 参数滑条的值（a、b、k…）。多项式系数已经写进 latex 了。
    var params: [String: Double]
    var reveal: Bool
}

struct ShapeSnapshot: Codable {
    var figure: Figure
    var group: UUID
    var ink: Data
    var showsLabels: Bool
}

struct GeometrySnapshot: Codable {
    var geometry: GeometryScene
    var points: [String: CGPoint]
    var card: CardSnapshot
    var ink: Data
}

/// 一份草稿里纸上的东西（笔迹另存）。
struct BoardSnapshot: Codable {
    var version = 1
    var functions: [FunctionSnapshot]
    var shapes: [ShapeSnapshot]
    var geometries: [GeometrySnapshot]
    var lineNumbers: [String: Int]
    /// 上次看到哪儿了：重新打开时滚回去。
    var scrollY: CGFloat
}

/// 所有草稿。
@Observable
final class BoardLibrary {
    private(set) var boards: [BoardMeta] = []
    /// 缩略图换过就加一，画廊重新读图。
    private(set) var thumbnailVersion = 0
    let root: URL
    @ObservationIgnored private var thumbnails: [UUID: (Date, UIImage?)] = [:]

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("Boards", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        boards = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
            return try? Self.decoder.decode(BoardMeta.self, from: data)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// 新建一份空白草稿：「未命名草稿」「未命名草稿 2」……
    @discardableResult
    func create(title: String? = nil) -> BoardMeta {
        let base = "未命名草稿"
        var name = title ?? base
        if title == nil {
            var n = 2
            while boards.contains(where: { $0.title == name }) {
                name = "\(base) \(n)"
                n += 1
            }
        }
        let now = Date()
        let meta = BoardMeta(id: UUID(), title: name, created: now, modified: now)
        try? FileManager.default.createDirectory(at: folder(meta.id), withIntermediateDirectories: true)
        writeMeta(meta)
        boards.insert(meta, at: 0)
        return meta
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].title = t
        writeMeta(boards[i])
    }

    /// 复制一份：「名字 副本」。
    @discardableResult
    func duplicate(_ meta: BoardMeta) -> BoardMeta? {
        let copy = BoardMeta(id: UUID(), title: meta.title + " 副本", created: Date(), modified: Date())
        do {
            try FileManager.default.copyItem(at: folder(meta.id), to: folder(copy.id))
        } catch {
            return nil
        }
        writeMeta(copy)
        boards.insert(copy, at: 0)
        return copy
    }

    func delete(_ meta: BoardMeta) {
        try? FileManager.default.removeItem(at: folder(meta.id))
        boards.removeAll { $0.id == meta.id }
        thumbnails[meta.id] = nil
    }

    func meta(_ id: UUID) -> BoardMeta? { boards.first { $0.id == id } }

    // MARK: 读写

    func read(_ id: UUID) -> (BoardSnapshot?, PKDrawing) {
        let dir = folder(id)
        let snap = (try? Data(contentsOf: dir.appendingPathComponent("board.json"))).flatMap { try? Self.decoder.decode(BoardSnapshot.self, from: $0) }
        let drawing = (try? Data(contentsOf: dir.appendingPathComponent("drawing.data"))).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        return (snap, drawing)
    }

    /// 存一份草稿；内容和上次一样就不写（返回 false）。
    @discardableResult
    func write(_ id: UUID, board: Data, drawing: Data, thumbnail: UIImage?) -> Bool {
        let dir = folder(id)
        let boardURL = dir.appendingPathComponent("board.json"), drawingURL = dir.appendingPathComponent("drawing.data")
        let unchanged = (try? Data(contentsOf: boardURL)) == board && (try? Data(contentsOf: drawingURL)) == drawing
        if let thumbnail, let jpg = thumbnail.jpegData(compressionQuality: 0.82) {
            try? jpg.write(to: dir.appendingPathComponent("thumb.jpg"), options: .atomic)
            thumbnails[id] = nil
            thumbnailVersion += 1
        }
        guard !unchanged else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? board.write(to: boardURL, options: .atomic)
        try? drawing.write(to: drawingURL, options: .atomic)
        if let i = boards.firstIndex(where: { $0.id == id }) {
            boards[i].modified = Date()
            writeMeta(boards[i])
            boards.sort { $0.modified > $1.modified }
        }
        return true
    }

    func thumbnail(_ id: UUID) -> UIImage? {
        let url = folder(id).appendingPathComponent("thumb.jpg")
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        if let (d, img) = thumbnails[id], d == date { return img }
        // 以前的版本在后台截过白图：当作没有缩略图
        let img = UIImage(contentsOfFile: url.path).flatMap { BoardThumbnail.isBlank($0) ? nil : $0 }
        thumbnails[id] = (date, img)
        return img
    }

    private func writeMeta(_ meta: BoardMeta) {
        guard let data = try? Self.encoder.encode(meta) else { return }
        try? data.write(to: folder(meta.id).appendingPathComponent("meta.json"), options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - 演示画廊

extension BoardLibrary {
    /// `-demo gallery`：在临时目录放几份示例草稿（只有笔迹），看画廊的样子。
    static func demo(at root: URL) -> BoardLibrary {
        let lib = BoardLibrary(root: root)
        var clock = 790_000_000.0
        func strokes(_ sketch: [[CGPoint]]) -> [PKStroke] {
            sketch.map { pts in
                clock += 1
                return DemoInk.freehand(pts, start: Date(timeIntervalSinceReferenceDate: clock))
            }
        }
        let ellipse = DemoInk.arc(CGPoint(x: 360, y: 300), 200, 110, from: 0.2, to: 0.2 + 2.05 * CGFloat.pi)
        let f = [CGPoint(x: 140, y: 260), CGPoint(x: 330, y: 260), CGPoint(x: 330, y: 450), CGPoint(x: 140, y: 450)]
        let back = f.map { CGPoint(x: $0.x + 90, y: $0.y - 80) }
        var cube: [[CGPoint]] = []
        for k in 0..<4 {
            cube.append(DemoInk.segment(f[k], f[(k + 1) % 4]))
            cube.append(DemoInk.segment(back[k], back[(k + 1) % 4]))
            cube.append(DemoInk.segment(f[k], back[k]))
        }
        let tri = [CGPoint(x: 260, y: 140), CGPoint(x: 120, y: 420), CGPoint(x: 470, y: 400)]
        let triangle = (0..<3).map { DemoInk.segment(tri[$0], tri[($0 + 1) % 3]) }
        let samples: [(String, [PKStroke], Double)] = [
            ("函数与导数", DemoInk.strokes("f(x)=x^3-5x", at: CGPoint(x: 120, y: 180), height: 58)
                + DemoInk.strokes("f'(x)", at: CGPoint(x: 120, y: 330), height: 58, start: Date(timeIntervalSinceReferenceDate: 790_100_000)), 0.3),
            ("定积分与面积", DemoInk.strokes("∫f(x)dx", at: CGPoint(x: 120, y: 200), height: 64), 3),
            ("椭圆和焦点", strokes([ellipse]), 27),
            ("立体几何作业", strokes(cube), 74),
            ("三角形", strokes(triangle), 220),
        ]
        let empty = BoardSnapshot(functions: [], shapes: [], geometries: [], lineNumbers: [:], scrollY: 0)
        for (title, ink, hoursAgo) in samples.reversed() {
            let meta = lib.create(title: title)
            let drawing = PKDrawing(strokes: ink)
            if let board = try? encoder.encode(empty) {
                lib.write(meta.id, board: board, drawing: drawing.dataRepresentation(), thumbnail: BoardThumbnail.render(drawing))
            }
            lib.setDates(meta.id, modified: Date().addingTimeInterval(-hoursAgo * 3600))
        }
        lib.reload()
        return lib
    }

    fileprivate func setDates(_ id: UUID, modified: Date) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].modified = modified
        boards[i].created = modified
        writeMeta(boards[i])
    }
}

// MARK: - 缩略图

enum BoardThumbnail {
    /// 把现在屏幕上的纸截一张（去掉顶上的工具栏），宽 720。
    @MainActor
    static func capture(topInset: CGFloat = 86) -> UIImage? {
        // 在后台截到的是白图：不截，保留原来的缩略图
        guard UIApplication.shared.applicationState != .background else { return nil }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let full = window.bounds
        let crop = CGRect(x: 0, y: topInset, width: full.width, height: max(full.height - topInset, 1))
        let scale: CGFloat = 720 / crop.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            ctx.cgContext.translateBy(x: 0, y: -crop.minY)
            window.drawHierarchy(in: full, afterScreenUpdates: true)
        }
        return isBlank(image) ? nil : image
    }

    /// 截出来是一片空白（系统没给画面）：缩成 24×16 看看颜色有没有变化。
    static func isBlank(_ image: UIImage) -> Bool {
        let w = 24, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let cg = image.cgImage,
              let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lo = 255, hi = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
            lo = min(lo, v)
            hi = max(hi, v)
        }
        // 纸上至少有横线、字：最亮和最暗差得出来
        return hi - lo < 6
    }

    /// 只有笔迹时画一张（演示画廊用）：横线纸 + 墨迹。
    static func render(_ drawing: PKDrawing, size: CGSize = CGSize(width: 720, height: 500)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.985, green: 0.979, blue: 0.965, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.33, green: 0.46, blue: 0.70, alpha: 0.13).setStroke()
            var y: CGFloat = 44
            while y < size.height {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                line.lineWidth = 1
                line.stroke()
                y += 26
            }
            let bounds = drawing.bounds.insetBy(dx: -40, dy: -40)
            guard !bounds.isNull, bounds.width > 0 else { return }
            let s = min(size.width / bounds.width, size.height / bounds.height, 0.6)
            let image = drawing.image(from: bounds, scale: 2)
            let w = bounds.width * s, h = bounds.height * s
            image.draw(in: CGRect(x: 30, y: 24, width: w, height: h))
        }
    }
}
