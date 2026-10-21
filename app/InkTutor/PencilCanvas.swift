import InkCore
import PencilKit
import SwiftUI

/// 整块画板的 PencilKit 画布。不显示 PKToolPicker；笔 / 橡皮由工具栏和 Pencil Pro 捏一下切换；
/// Pencil 双击由 App 接管：这一段写完了，在笔尖旁弹出「函数 / 求解 / 几何」（D2）。
/// 纸可以上下滚（没开手指书写时一根手指拖，开了是两根手指），比窗口宽时也能左右滚，不缩放；
/// 上面一层的式子、卡片、图形用画布坐标摆放，跟着 scrollOffset 一起移动。
struct PencilCanvas: UIViewRepresentable {
    var app: AppModel
    /// 笔的状态显式传进来：这几个值一变 SwiftUI 就会调 updateUIView 换工具。
    var eraserOn: Bool
    var penColor: PenColor
    var penWidth: PenWidth
    var allowFinger: Bool
    /// 纸有多长、多宽（显式传进来：一变就会调 updateUIView 改 contentSize）。
    var contentHeight: CGFloat
    var contentWidth: CGFloat

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = false
        canvas.isDirectionalLockEnabled = true
        canvas.showsVerticalScrollIndicator = true
        canvas.showsHorizontalScrollIndicator = true
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.delegate = context.coordinator
        canvas.tool = app.tool
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)
        // 手指点空白处：收起菜单、取消选中（Pencil 只用来写）
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fingerTapped))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)
        // Pencil 落笔时顺便看看是哪种笔（PencilProbe），不影响书写
        let probe = PencilTouchProbe(target: nil, action: nil)
        probe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        probe.onPencil = { [weak coordinator = context.coordinator] rolled in coordinator?.notice(rolled ? .pro : .pencil) }
        canvas.addGestureRecognizer(probe)
        app.attach(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = app.tool
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        context.coordinator.app = app
        // 纸的大小：往下接长；宽度一般就是窗口宽，窗口比写过的地方窄时加宽
        let size = CGSize(width: max(contentWidth, app.boardSize.width), height: max(contentHeight, app.boardSize.height))
        if canvas.contentSize != size {
            canvas.contentSize = size
            // 窗口拉宽、纸变窄了：滚出界的那部分收回来（下一轮再改，别在更新视图时改状态）
            let limit = CGPoint(x: max(0, size.width - app.boardSize.width), y: max(0, size.height - app.boardSize.height))
            let offset = canvas.contentOffset
            if offset.x > limit.x || offset.y > limit.y {
                DispatchQueue.main.async {
                    canvas.setContentOffset(CGPoint(x: min(offset.x, limit.x), y: min(offset.y, limit.y)), animated: false)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(app: app)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var app: AppModel
        private var loggedTap = false

        init(app: AppModel) {
            self.app = app
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            app.drawingChanged(canvasView.drawing)
        }

        // 纸滚了：上面一层跟着动
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            app.scrolled(to: scrollView.contentOffset)
        }

        // 一落笔就收起菜单和选中框
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if app.menu != nil { app.dismissMenu() }
            app.selection = nil
        }

        @objc func fingerTapped() {
            if app.menu != nil { app.dismissMenu() }
            app.selection = nil
        }

        // iPadOS 17.5+：双击 = 这一段写完了。不执行系统的「切到橡皮」。
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            notice(.doubleTap)
            let point = tap.hoverPose?.location
            if !loggedTap {
                loggedTap = true
                let whereText = point.map { String(format: "(%.0f, %.0f)", $0.x, $0.y) } ?? "无落点"
                print("[InkTutor] 双击 hoverPose=\(whereText) preferredTapAction=\(UIPencilInteraction.preferredTapAction)")
            }
            keepAppTool(on: interaction.view)
            app.pencilDoubleTapped(at: point)
            DispatchQueue.main.async { [weak self] in
                self?.keepAppTool(on: interaction.view)
            }
        }

        // Pencil Pro 捏一下 = 切换笔 / 橡皮
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            notice(.pro)
            guard squeeze.phase == .ended else { return }
            app.eraserOn.toggle()
        }

        /// 双击、捏压、Pencil 落笔时记下用的是哪种笔（PencilProbe），工具栏的「识别」键默认显不显示按它定。
        /// 刚认出 Pencil Pro、用户又没自己拨过开关时，「识别」键会收起来：说一声去哪找。
        func notice(_ evidence: PencilProbe.Evidence) {
            guard PencilProbe.note(evidence), evidence == .pro, PencilProbe.choice == nil else { return }
            let v = app.visibleRect
            app.toast("认出 Pencil Pro，「识别」收进了设置键", at: CGPoint(x: v.midX, y: v.minY + app.topInset + 30), .info)
        }

        private func keepAppTool(on view: UIView?) {
            (view as? PKCanvasView)?.tool = app.tool
        }
    }
}
