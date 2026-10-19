import InkCore
import SceneUI
import SwiftUI

struct ContentView: View {
    @State private var mode: InkMode = .function
    @State private var eraserOn = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("模式", selection: $mode) {
                    Text("函数").tag(InkMode.function)
                    Text("推导").tag(InkMode.derivative)
                    Text("几何").tag(InkMode.geometry)
                }
                .pickerStyle(.segmented)
                Button(eraserOn ? "橡皮" : "笔") {
                    eraserOn.toggle()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            HStack(spacing: 0) {
                PencilCanvas(mode: mode, eraserOn: eraserOn)
                Divider()
                SceneHost()
            }
        }
    }
}
