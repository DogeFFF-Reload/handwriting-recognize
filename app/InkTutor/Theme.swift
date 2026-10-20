import SwiftUI
import UIKit

/// 视觉规范：暖白的纸、淡蓝横线、墨色笔迹、靛蓝的选中和菜单、每个函数一种曲线颜色（GeoGebra 的做法）。
enum Theme {
    static let paper = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.105, green: 0.108, blue: 0.118, alpha: 1)
                                      : UIColor(red: 0.985, green: 0.979, blue: 0.965, alpha: 1)
    })
    static let rule = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.055)
                                      : UIColor(red: 0.33, green: 0.46, blue: 0.70, alpha: 0.13)
    })
    static let margin = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.45, blue: 0.45, alpha: 0.10)
                                      : UIColor(red: 0.86, green: 0.35, blue: 0.35, alpha: 0.16)
    })
    /// 选中框、菜单、处理中的高亮。
    static let accent = Color(red: 0.31, green: 0.35, blue: 0.93)
    static let ok = Color(red: 0.13, green: 0.62, blue: 0.38)
    static let warn = Color(red: 0.91, green: 0.52, blue: 0.11)
    static let wrong = Color(red: 0.86, green: 0.24, blue: 0.21)
    static let card = Color(.systemBackground)
    static let cardRadius: CGFloat = 18
    static let hairline = Color.primary.opacity(0.08)

    /// 曲线颜色：第一条蓝，往后依次换。
    static let curves: [Color] = [
        Color(red: 0.16, green: 0.42, blue: 0.86),
        Color(red: 0.85, green: 0.33, blue: 0.22),
        Color(red: 0.10, green: 0.58, blue: 0.47),
        Color(red: 0.55, green: 0.32, blue: 0.82),
        Color(red: 0.80, green: 0.55, blue: 0.08),
    ]

    static func curve(_ index: Int) -> Color { curves[index % curves.count] }
}

/// 笔的颜色。
enum PenColor: String, CaseIterable, Identifiable {
    case ink, blue, red

    var id: String { rawValue }

    /// 交给 PencilKit 的颜色：按浅色模式给，深色模式下 PencilKit 自己把黑墨显示成白的。
    /// （给 .label 这种动态色会被反转两次，深色模式下墨迹反而是黑的。）
    var uiColor: UIColor {
        switch self {
        case .ink: return .black
        case .blue: return UIColor(red: 0.16, green: 0.33, blue: 0.78, alpha: 1)
        case .red: return UIColor(red: 0.80, green: 0.22, blue: 0.18, alpha: 1)
        }
    }

    /// 工具栏上的色块：墨色跟着深浅色模式走。
    var swatch: Color {
        self == .ink ? Color(UIColor.label) : Color(uiColor)
    }

    var name: String {
        switch self {
        case .ink: return "墨黑"
        case .blue: return "靛蓝"
        case .red: return "朱红"
        }
    }
}

enum PenWidth: CGFloat, CaseIterable, Identifiable {
    case fine = 2.2
    case medium = 3.2
    case bold = 5

    var id: CGFloat { rawValue }

    var name: String {
        switch self {
        case .fine: return "细"
        case .medium: return "中"
        case .bold: return "粗"
        }
    }
}

/// 卡片统一的底：圆角、细边、两层柔和的影子。
struct CardBackground: View {
    var radius: CGFloat = Theme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}
