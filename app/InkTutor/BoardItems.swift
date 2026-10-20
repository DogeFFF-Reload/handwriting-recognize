import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 双击笔身后在笔尖旁选的三种处理。
enum SegmentKind: String, CaseIterable, Identifiable {
    case function, derivation, geometry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .function: return "函数"
        case .derivation: return "推导"
        case .geometry: return "几何"
        }
    }

    var hint: String {
        switch self {
        case .function: return "收成标准式子并作图"
        case .derivation: return "批改这一步"
        case .geometry: return "收成动态几何"
        }
    }

    var mode: InkMode {
        switch self {
        case .function: return .function
        case .derivation: return .derivative
        case .geometry: return .geometry
        }
    }
}

/// 双击确认的那一段笔迹。
struct InkSegment: Equatable {
    var strokeIDs: [String]
    var bounds: CGRect
    /// 重新确认的是已有的哪一项（还原过笔迹的函数、留着笔迹的推导行）。
    var targetID: UUID?
}

/// 笔尖旁的菜单。
struct SegmentMenuState: Equatable {
    var anchor: CGPoint
    var segment: InkSegment
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
    let tint: Color
    var engine: String?
    var ms: Int?

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
    /// 卡片挂在式子的右上角。
    var anchor: CGPoint { CGPoint(x: frame.maxX, y: frame.minY) }
    var name: String { definition?.name ?? "f" }

    /// 批改导数时用的函数：多项式写成规范的 LaTeX（滑条改过系数也跟着变）。
    var latexForChecking: String {
        if let t = graph?.terms { return "f(x)=" + Poly.latex(t) }
        return latex
    }

    /// 滑条改了多项式系数之后，式子跟着重写（GeoGebra 里代数区和绘图区是同一个对象）。
    func rewriteFromTerms() {
        guard let terms = graph?.terms, let d = definition else { return }
        let lhs = d.name == "y" ? "y" : "\(d.name)(\(d.variable))"
        latex = lhs + "=" + Poly.latex(terms)
        size = MathLabel.measure(latex, fontSize: fontSize)
    }
}

/// 一行推导：笔迹留着（圈要画在学生写的字上），下面回显识别结果，旁边是批注。
@Observable
final class DerivationItem: Identifiable {
    let id = UUID()
    let lineID: String
    var revision = 0
    var strokeIDs: Set<String>
    var band: CGRect
    var latex: String?
    var annotation: Annotation?
    var notice: String?
    /// 批注对应的那一版笔迹；之后再改就把圈收起来。
    var checkedStrokes: Set<String> = []

    init(lineID: String, strokeIDs: Set<String>, band: CGRect) {
        self.lineID = lineID
        self.strokeIDs = strokeIDs
        self.band = band
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
