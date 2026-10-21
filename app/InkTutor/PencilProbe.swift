import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 用的是哪种笔：尽力检测，结论存在 UserDefaults；工具栏的「识别」键默认显不显示按它定。
///
/// iPadOS 没有公开 API 能直接查「配对的是哪一支 Apple Pencil」：UITouch 只说是不是 Pencil（`type == .pencil`），
/// UIPencilInteraction 只有双击 / 捏压回调和用户在「设置」里选的动作偏好（文档没说偏好能反映配没配过哪支笔，不拿它推断）。
/// 所以只能从收到过的输入推断：
/// - 捏压（`pencilInteraction(_:didReceiveSqueeze:)`）：Apple 文档写明只有 Apple Pencil Pro 支持 → Pro；
/// - 笔画带滚转角（`UITouch.rollAngle` 不为 0）：文档写明不支持滚转的型号这个值是 0，Apple 公布的规格里只有 Pro 支持滚转 → 也算 Pro；
/// - 双击（`pencilInteraction(_:didReceiveTap:)`）：二代或 Pro；
/// - 只见过 `touch.type == .pencil`：一代、USB-C，或者还没双击、没捏过的二代 / Pro。
/// 结论只升不降。刚装好、还没用 Pencil 写过时什么都不知道，当作没有 Pencil Pro；
/// 换了一支笔（比如 Pro 换成 USB-C）也不会自己降回去，设置里「重新检测」清掉重来。
enum PencilProbe {
    enum Evidence: Int, Comparable {
        case unknown = 0
        case pencil = 1
        case doubleTap = 2
        case pro = 3

        static func < (a: Evidence, b: Evidence) -> Bool { a.rawValue < b.rawValue }

        /// 设置页上的一句话。
        var summary: String {
            switch self {
            case .unknown: return "还没用 Apple Pencil 写过"
            case .pencil: return "Apple Pencil，还没双击过（一代、USB-C，或没双击过的二代 / Pro）"
            case .doubleTap: return "能双击的 Apple Pencil（二代或 Pro）"
            case .pro: return "Apple Pencil Pro"
            }
        }
    }

    static let evidenceKey = "pencilEvidence"
    /// 用户自己拨过的「显示识别按键」。没拨过就没有这个键，按检测结果定。
    static let buttonKey = "showRecognizeButton"

    /// 拨过就按用户的；没拨过：认出 Pencil Pro 时不显示，否则显示。
    static func showsButton(choice: Bool?, evidence: Int) -> Bool {
        choice ?? (evidence < Evidence.pro.rawValue)
    }

    static var evidence: Evidence {
        Evidence(rawValue: UserDefaults.standard.integer(forKey: evidenceKey)) ?? .unknown
    }

    static var choice: Bool? {
        UserDefaults.standard.object(forKey: buttonKey) as? Bool
    }

    /// 记下新看到的证据（只升不降）。返回这次是不是升上来了。
    @discardableResult
    static func note(_ e: Evidence) -> Bool {
        guard e > evidence else { return false }
        UserDefaults.standard.set(e.rawValue, forKey: evidenceKey)
        return true
    }
}

/// 只看不拦的手势：Apple Pencil 落到纸上时报一声，带不带滚转角。自己从不识别成功（抬笔、或者认出 Pro 就 failed），
/// 不取消、不推迟别的触摸，PencilKit 照常画。只收 Pencil 的触摸，手指不经过这里。
final class PencilTouchProbe: UIGestureRecognizer {
    /// rolled：这一笔带滚转角（只有 Pencil Pro 会有）。
    var onPencil: ((_ rolled: Bool) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // 已经认出 Pro：没什么可看的了
        guard PencilProbe.evidence < .pro, let touch = touches.first(where: { $0.type == .pencil }) else {
            state = .failed
            return
        }
        let rolled = Self.rolled(touch)
        onPencil?(rolled)
        if rolled { state = .failed }
    }

    // 落笔那一下的滚转角可能还是估计值，写的过程中再看
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if let touch = touches.first(where: { $0.type == .pencil }), Self.rolled(touch) {
            onPencil?(true)
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    // PencilKit 的画笔手势开始画时不把这里判失败（否则收不到写的过程），这里也从不挡别人
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private static func rolled(_ touch: UITouch) -> Bool {
        abs(touch.rollAngle) > 0.001
    }
}
