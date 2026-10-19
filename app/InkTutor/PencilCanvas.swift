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

        init(app: AppModel) {
            self.app = app
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            app.drawingChanged(canvasView.drawing)
        }

        // iPadOS 17.5+：双击 = 确认
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            app.doubleTap()
        }

        // Pencil Pro 捏一下 = 切换笔/橡皮
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            if squeeze.phase == .ended { app.eraserOn.toggle() }
        }
    }
}
