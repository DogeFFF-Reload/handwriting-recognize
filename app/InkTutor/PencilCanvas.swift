import InkCore
import PencilKit
import SwiftUI

/// 整块画板的 PencilKit 画布。不显示 PKToolPicker；笔 / 橡皮由工具栏和 Pencil Pro 捏一下切换；
/// Pencil 双击由 App 接管：这一段写完了，在笔尖旁弹出「函数 / 求解 / 几何」（D2）。
/// 纸可以上下、左右滚（没开手指书写时一根手指拖，开了是两根手指），两根手指捏合缩放（0.5–3 倍）。
/// 上下、左右都是无边界的：滚到靠近底边或右边，纸再接一屏。
/// 笔迹存在画布坐标里，缩放不改它；UIScrollView 的 contentSize、contentOffset 是放大后的屏幕 point。
/// 上面一层的式子、卡片、图形用画布坐标摆放，跟着 scrollOffset、zoom 一起移动和缩放。
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
        canvas.alwaysBounceHorizontal = true
        canvas.isDirectionalLockEnabled = true
        canvas.showsVerticalScrollIndicator = true
        canvas.showsHorizontalScrollIndicator = true
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = AppModel.zoomRange.lowerBound
        canvas.maximumZoomScale = AppModel.zoomRange.upperBound
        canvas.bouncesZoom = true
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
        app.attach(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = app.tool
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        context.coordinator.app = app
        // 纸的大小：往下、往右接长（画布坐标），乘上现在的倍数就是 contentSize
        let size = Self.contentSize(app: app, width: contentWidth, height: contentHeight, zoom: canvas.zoomScale)
        if abs(canvas.contentSize.width - size.width) > 0.5 || abs(canvas.contentSize.height - size.height) > 0.5 {
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

    /// 放大后的纸有多大（屏幕 point）。纸至少盖满窗口。
    static func contentSize(app: AppModel, width: CGFloat, height: CGFloat, zoom: CGFloat) -> CGSize {
        CGSize(width: max(width, app.boardSize.width / zoom) * zoom, height: max(height, app.boardSize.height / zoom) * zoom)
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
            app.scrolled(to: scrollView.contentOffset, zoom: scrollView.zoomScale)
        }

        // 捏合缩放：contentSize 按新的倍数算（笔迹的画布坐标不变），上面一层跟着放大缩小
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let z = scrollView.zoomScale
            let size = PencilCanvas.contentSize(app: app, width: app.contentWidth, height: app.contentHeight, zoom: z)
            if abs(scrollView.contentSize.width - size.width) > 0.5 || abs(scrollView.contentSize.height - size.height) > 0.5 {
                scrollView.contentSize = size
            }
            app.scrolled(to: scrollView.contentOffset, zoom: z)
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
            // 落点在画布视图（UIScrollView）的坐标里，放大过：除回画布坐标
            let zoom = (interaction.view as? UIScrollView)?.zoomScale ?? 1
            let point = tap.hoverPose.map { CGPoint(x: $0.location.x / zoom, y: $0.location.y / zoom) }
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
            guard squeeze.phase == .ended else { return }
            app.eraserOn.toggle()
        }

        private func keepAppTool(on view: UIView?) {
            (view as? PKCanvasView)?.tool = app.tool
        }
    }
}
