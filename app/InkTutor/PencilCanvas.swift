import InkCore
import PencilKit
import SwiftUI

/// 整块画板的 PencilKit 画布。不显示 PKToolPicker；笔 / 橡皮由工具栏和 Pencil Pro 捏一下切换；
/// Pencil 双击由 App 接管：这一段写完了，在笔尖旁弹出「函数 / 求导 / 几何」（D2）。
/// 画布不滚动、不缩放：上面一层的式子和卡片直接用画布坐标摆放。
struct PencilCanvas: UIViewRepresentable {
    var app: AppModel
    /// 笔的状态显式传进来：这几个值一变 SwiftUI 就会调 updateUIView 换工具。
    var eraserOn: Bool
    var penColor: PenColor
    var penWidth: PenWidth
    var allowFinger: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
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
        app.attach(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = app.tool
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        context.coordinator.app = app
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
            guard squeeze.phase == .ended else { return }
            app.eraserOn.toggle()
        }

        private func keepAppTool(on view: UIView?) {
            (view as? PKCanvasView)?.tool = app.tool
        }
    }
}
