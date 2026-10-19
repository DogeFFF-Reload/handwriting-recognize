import InkCore
import PencilKit
import SwiftUI

struct PencilCanvas: UIViewRepresentable {
    var mode: InkMode
    var eraserOn: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .systemBackground
        canvas.delegate = context.coordinator
        canvas.tool = Self.tool(eraserOn: eraserOn)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = Self.tool(eraserOn: eraserOn)
        context.coordinator.mode = mode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode)
    }

    private static func tool(eraserOn: Bool) -> PKTool {
        if eraserOn {
            return PKEraserTool(.vector)
        }
        return PKInkingTool(.pen, color: .label, width: 2)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var mode: InkMode

        init(mode: InkMode) {
            self.mode = mode
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes.map { stroke in
                InkStroke(
                    id: String(stroke.path.creationDate.timeIntervalSince1970),
                    bounds: stroke.renderBounds,
                    createdAt: stroke.path.creationDate
                )
            }
            _ = PlaceholderInkModel(mode: mode).apply(strokes: strokes)
        }
    }
}
