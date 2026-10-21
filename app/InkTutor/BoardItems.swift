import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 双击笔身后在笔尖旁选的处理。
/// 「求解」把求导、积分、极限、求和、解方程合在一起：写的是什么就算什么（f'(x)、\int_0^2 f(x)dx、\lim…、\sum…、x^2-4=0）。
/// 「检查」不替学生算，只看学生自己写的这一步（f'(x) = …、f'(2) = …）对不对：笔迹留着，有问题的地方画圈，
/// 提示学生自己一级一级点开。改对了打勾，原函数的图像里这时才画出导函数。
/// 「矩阵」只在识别结果里真有矩阵时出现，点开是计算 / 求逆 / 求行列式 / 看变换。
enum SegmentKind: String, CaseIterable, Identifiable {
    case function, solve, check, geometry, matrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .function: return "函数"
        case .solve: return "求解"
        case .check: return "检查"
        case .geometry: return "几何"
        case .matrix: return "矩阵"
        }
    }

    var hint: String {
        switch self {
        case .function: return "收成标准式子并作图"
        case .solve: return "求导、积分、极限、求和、解方程，直接算出结果"
        case .check: return "检查自己写的导数：先圈出有问题的地方，提示自己点开"
        case .geometry: return "收成动态几何"
        case .matrix: return "计算、求逆矩阵、求行列式、看变换"
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
    /// 认出来的是 2×2 的数字矩阵：二级菜单里多一个「看变换」。
    var offersTransform = false
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
    /// 矩阵菜单里选的是哪一种（存盘：重新打开时照这个重算，求逆不会变回计算）。
    var matrixAction: MatrixAction?
    /// 「看变换」：卡片里现在的矩阵（拖基向量会改）和刚认出来时的矩阵（「复位」回到它）。
    var linearMap: LinearMap2?
    var originalMap: LinearMap2?
    /// 画在这张卡片里的其他函数（两个函数同图：比较曲线、标交点、涂两曲线之间的面积）。
    var companions: [UUID] = []
    /// 这条函数画在别的函数的卡片里（自己的卡片不显示）。
    var mergedInto: UUID?

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

/// 「检查」过的一行。学生的笔迹留在纸上：有问题的地方画红圈，提示一级一级自己点开（想一想 → 规则 → 答案）；
/// 全对时行尾一个绿勾，原函数的图像里这时才画出导函数。圈出来以后这一行又改过（擦了、在旁边写了），
/// 或者原函数改了，圈就变淡，等学生改完再检查一次。不存盘。
@Observable
final class CheckItem: Identifiable {
    let id = UUID()
    /// 识别器和回放用的行号 C1、C2…：同一行改完再检查沿用（回放按「擦过几轮」取）。
    let lineID: String
    var revision: Int
    /// 检查时这一行的笔。
    var strokeIDs: Set<String>
    var bounds: CGRect
    var result: StepReview.Result
    /// 对照的是哪条函数：它改了、删了，这一行的检查就作废。
    var parentID: UUID
    var functionName: String
    /// 每一处问题打开到了第几级提示（0：只圈出来）。
    var levels: [Int]
    /// 正在看提示的是第几处（nil：提示收着）。
    var focus: Int?
    /// 圈出来以后这一行又改过了（或者原函数改了）。
    var stale = false
    /// 认出来的这一行（对了以后「收成式子」用）。
    var recognized: RecognitionResult

    init(lineID: String, revision: Int, strokeIDs: Set<String>, bounds: CGRect, result: StepReview.Result,
         parentID: UUID, functionName: String, recognized: RecognitionResult) {
        self.lineID = lineID
        self.revision = revision
        self.strokeIDs = strokeIDs
        self.bounds = bounds
        self.result = result
        self.parentID = parentID
        self.functionName = functionName
        self.levels = Array(repeating: 0, count: result.issues.count)
        self.recognized = recognized
    }
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
