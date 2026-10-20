import InkCore
import PencilKit
import SwiftUI

/// 左半屏的 PencilKit 画布。不显示 PKToolPicker；笔/橡皮由按钮和 Pencil Pro 捏一下切换；
/// Pencil 双击由 App 接管为「确认」（D2）。
struct PencilCanvas: UIViewRepresentable {
    var app: AppModel
    var eraserOn: Bool
    var allowFinger: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.tool = Self.tool(eraserOn: eraserOn)
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)
        context.coordinator.clearToken = app.clearToken
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = Self.tool(eraserOn: eraserOn)
        canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        context.coordinator.app = app
        if context.coordinator.clearToken != app.clearToken {
            context.coordinator.clearToken = app.clearToken
            canvas.drawing = PKDrawing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(app: app)
    }

    private static func tool(eraserOn: Bool) -> PKTool {
        // 整笔擦除（.vector）：笔画只会整笔消失，id 不会乱
        eraserOn ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .label, width: 3)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var app: AppModel
        var clearToken = 0
        private var loggedTap = false

        init(app: AppModel) {
            self.app = app
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            app.drawingChanged(canvasView.drawing)
        }

        // iPadOS 17.5+：双击 = 确认。不执行系统的「切到橡皮」。
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            let point = contentPoint(of: tap.hoverPose, in: interaction.view)
            if !loggedTap {
                loggedTap = true
                let whereText = point.map { String(format: "(%.0f, %.0f)", $0.x, $0.y) } ?? "无落点"
                print("[InkTutor] 双击 hoverPose=\(whereText) preferredTapAction=\(UIPencilInteraction.preferredTapAction)")
            }
            keepAppTool(on: interaction.view)
            app.confirm(at: point)
            DispatchQueue.main.async { [weak self] in
                self?.keepAppTool(on: interaction.view)
            }
        }

        // Pencil Pro 捏一下 = 切换笔/橡皮
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else { return }
            app.eraserOn.toggle()
        }

        private func keepAppTool(on view: UIView?) {
            guard let canvas = view as? PKCanvasView else { return }
            canvas.tool = PencilCanvas.tool(eraserOn: app.eraserOn)
        }

        /// hover 落在画布视图上。笔画坐标在内容坐标系，滚动画布时要加 contentOffset。
        private func contentPoint(of pose: UIPencilHoverPose?, in view: UIView?) -> CGPoint? {
            guard let pose, let canvas = view as? PKCanvasView else { return nil }
            let zoom = max(canvas.zoomScale, 0.01)
            return CGPoint(
                x: (pose.location.x + canvas.contentOffset.x) / zoom,
                y: (pose.location.y + canvas.contentOffset.y) / zoom
            )
        }
    }
}
