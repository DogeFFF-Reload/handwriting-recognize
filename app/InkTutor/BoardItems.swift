import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 双击笔身后在笔尖旁选的处理。
/// 「求解」把求导、积分、极限、求和、解方程合在一起：写的是什么就算什么（f'(x)、\int_0^2 f(x)dx、\lim…、\sum…、x^2-4=0）。
/// 「矩阵」只在识别结果里真有矩阵时出现，点开是计算 / 求逆 / 求行列式。
/// 「批改」不替学生算：学生自己写 f'(x) = …，笔迹留在纸上，错的那一项画圈，旁边一句说明（或一句反问）。
enum SegmentKind: String, CaseIterable, Identifiable {
    case function, solve, check, geometry, matrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .function: return "函数"
        case .solve: return "求解"
        case .check: return "批改"
        case .geometry: return "几何"
        case .matrix: return "矩阵"
        }
    }

    var hint: String {
        switch self {
        case .function: return "收成标准式子并作图"
        case .solve: return "求导、积分、极限、求和、解方程，直接算出结果"
        case .check: return "检查自己写的导数，圈出算错的那一项"
        case .geometry: return "收成动态几何"
        case .matrix: return "计算、求逆矩阵、求行列式"
        }
    }

    var mode: InkMode {
        switch self {
        case .function: return .function
        case .solve, .check: return .derivative   // 回放脚本里求导那几行记在 derivative 下
        case .geometry: return .geometry
        case .matrix: return .function
        }
    }
}

/// 双击确认的那一段笔迹。
struct InkSegment: Equatable {
    var strokeIDs: [String]
    var bounds: CGRect
    /// 重新确认的是已有的哪一项（还原过笔迹的式子）。
    var targetID: UUID?
}

/// 选中的是哪一样：式子（出操作条）、卡片（出变换框）还是几何图形（出节点）。
enum Selection: Equatable {
    case formula(UUID)
    case card(UUID)
    case shape(UUID)

    var id: UUID {
        switch self {
        case .formula(let id), .card(let id), .shape(let id): return id
        }
    }
}

/// 笔尖旁的菜单。
struct SegmentMenuState: Equatable {
    var anchor: CGPoint
    var segment: InkSegment
    /// 识别结果里有矩阵时才多一枚「矩阵」。
    var offersMatrix = false
    /// 「矩阵」的二级菜单展开着。
    var matrixOpen = false
    /// 双击时先认的一遍。有结果就复用，不再打第二次模型。
    var recognized: RecognitionResult?
    /// recognized 来自真识别器。回放不预认，免得行号被偷看一次。
    var liveRecognition = false
    var previewID = UUID()
}

/// 浮动卡片在画布上的位置、大小、旋转（像 PS 的自由变换）。
struct CardFrame: Equatable {
    var center: CGPoint
    var size: CGSize
    var rotation: Angle = .zero
    var minimized = false

    static let minSize = CGSize(width: 220, height: 170)
}

/// 正在识别的一段：画一层流光提示「在处理」。
struct BusySegment: Identifiable, Equatable {
    let id = UUID()
    var bounds: CGRect
    var kind: SegmentKind
}

/// 收成标准式子那一刻，原来的笔迹淡出用的快照。
struct InkGhost: Identifiable {
    let id = UUID()
    var image: UIImage
    var frame: CGRect
}

/// 冒一下就消失的提示。
struct Toast: Identifiable, Equatable {
    enum Style { case info, warning, success }
    let id = UUID()
    var text: String
    var point: CGPoint
    var style: Style
}

/// 一条函数：标准式子（换掉了手写笔迹）+ 右上角的函数卡片。
/// 求出来的导数也是一条（derivedFrom 指向原函数），只有式子，没有自己的卡片：导函数画在原函数的卡片里。
/// 「求解」算出来的也是一条（solution 不为 nil），只有式子：∫_a^b f、lim f 标在 f 的卡片里。
@Observable
final class FunctionItem: Identifiable {
    let id = UUID()
    /// 识别器和回放用的行号 F1、F2…
    let lineID: String
    var revision = 0
    var latex: String
    var definition: FunctionDefinition?
    /// 认出来了但画不了时的原因（「不是 y = … 的形式」）。
    var problem: String?
    /// 式子的左上角和排出来的大小（画布 point）。
    var origin: CGPoint
    var fontSize: CGFloat
    var size: CGSize
    /// 原来的笔迹（「还原笔迹」时放回画布）。
    var ink: [PKStroke] = []
    /// 收成式子时那几笔的 id（还原后重新认领）。
    var inkSourceIDs: [String] = []
    /// 还原笔迹期间，画布上还属于它的笔。
    var inkIDs: [String] = []
    /// true：笔迹放回了画布等着改，式子先藏起来；改完双击、选「函数」就更新这一项。
    var showingInk = false
    var graph: GraphModel?
    var card: CardFrame
    var showsSliders = false
    /// 卡片右上角的小眼睛：只留函数图像和坐标轴，参数滑条、切线、导函数、式子都收起来。
    var minimal = false
    let tint: Color
    /// 曲线颜色是 Theme.curves 里的第几个（存盘用）；算出来的那几项是 -1（绿色）。
    var tintIndex = -1
    var engine: String?
    var ms: Int?
    /// 求导得来的：原函数是哪一条、学生写的是 f'(x) 还是 f''(x)、f'(2)。原函数一改就重新求。
    var derivedFrom: UUID?
    var request: DerivativeRequest?
    var lhsLatex: String?
    var resultLatex: String?
    /// 「求解」：学生写的那一行（引用的函数改了就拿它重新算）和算出来的结果。
    var solveSource: String?
    var solution: Solution?

    init(lineID: String, latex: String, origin: CGPoint, fontSize: CGFloat, size: CGSize, card: CardFrame, tint: Color) {
        self.lineID = lineID
        self.latex = latex
        self.origin = origin
        self.fontSize = fontSize
        self.size = size
        self.card = card
        self.tint = tint
    }

    var frame: CGRect { CGRect(origin: origin, size: size) }

    /// 显示用的式子：求出来的那部分用绿色（\color 会吃掉等号后面的间距，手动补一个 \;）。
    var displayLatex: String {
        if let s = solution {
            guard let r = s.result else { return s.input }
            let rel = s.relation == "\\Rightarrow" ? "\\;\\Rightarrow\\;" : s.relation
            return s.input + rel + "\\;\\color{#1E9E62}{" + r + "}"
        }
        if let lhs = lhsLatex, let rhs = resultLatex { return lhs + "=\\;\\color{#1E9E62}{" + rhs + "}" }
        return latex
    }

    /// 算出来的（导数或求解），不是学生定义的函数。
    var isComputed: Bool { derivedFrom != nil || solution != nil }
    /// 卡片挂在式子的右上角。
    var anchor: CGPoint { CGPoint(x: frame.maxX, y: frame.minY) }
    var name: String { definition?.name ?? "f" }

    /// 滑条改了多项式系数之后，式子跟着重写（GeoGebra 里代数区和绘图区是同一个对象）。
    func rewriteFromTerms() {
        guard let terms = graph?.terms, let d = definition else { return }
        let lhs = d.name == "y" ? "y" : "\(d.name)(\(d.variable))"
        latex = lhs + "=" + Poly.latex(terms)
        size = MathLabel.measure(latex, fontSize: fontSize)
        if let parsed = try? FunctionDefinition.parse(latex) { definition = parsed }
    }
}

/// 选「批改」的一行：学生自己写的 f'(x) = …。笔迹留在纸上不收走，判出来的结果画在笔迹上面。
@Observable
final class CheckItem: Identifiable {
    let id = UUID()
    /// 回放用的行号 C1、C2…：改完再批改同一行时沿用，回放才数得对「擦过几轮」。
    let lineID: String
    var revision: Int
    /// 这一行的笔（擦掉其中一笔或在旁边补写，圈就先收起来）。
    var strokeIDs: [String]
    var band: CGRect
    /// 识别出来的学生这一行。
    var latex: String
    /// 对照的是哪条函数。
    var parentID: UUID
    var ok = false
    /// 要圈的地方（错的那一项；圈不到项时是整行）。
    var marks: [CheckMark] = []
    /// 圈旁的一句：direct 模式是说明（带正确项），socratic 模式是反问（不带）。
    var message: String?
    /// direct 模式下整行判错时，正确的导数（排成式子显示）。
    var answerLatex: String?
    var socratic = false
    /// 批改之后这一行又动了笔：圈先收起来，等改完再双击批改。
    var stale = false
    var engine: String?
    var ms: Int?

    init(lineID: String, revision: Int, strokeIDs: [String], band: CGRect, latex: String, parentID: UUID) {
        self.lineID = lineID
        self.revision = revision
        self.strokeIDs = strokeIDs
        self.band = band
        self.latex = latex
        self.parentID = parentID
    }
}

struct CheckMark: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
}

/// 选「几何」认出来的一个图形：直接画在纸上原来草图的位置（不放卡片），选中后拖节点改形状、大小、方向。
@Observable
final class ShapeItem: Identifiable {
    let id = UUID()
    var figure: Figure
    /// 同一段草图认出来的几个图形是一组：「还原笔迹」时一起收回。
    let group: UUID
    /// 这一组的原始笔迹（只放在组里的一个图形上）。
    var ink: [PKStroke]
    /// 顶点字母、圆心、焦点这些标注。
    var showsLabels = true

    init(figure: Figure, group: UUID, ink: [PKStroke]) {
        self.figure = figure
        self.group = group
        self.ink = ink
    }
}

/// 一张几何草图收成的动态几何（卡片放在原来草图的位置）。
@Observable
final class GeometryItem: Identifiable {
    let id = UUID()
    let scene = SceneModel()
    let geometry: GeometryScene
    var ink: [PKStroke]
    var card: CardFrame

    init(geometry: GeometryScene, ink: [PKStroke], card: CardFrame) {
        self.geometry = geometry
        self.ink = ink
        self.card = card
        scene.show(geometry: geometry)
    }
}
