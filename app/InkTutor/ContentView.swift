import InkCore
import SceneUI
import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @State private var showSettings = false
    @AppStorage("allowFinger") private var allowFinger = false
    @AppStorage("engine") private var engine = "auto"
    @AppStorage("dashscopeKey") private var dashscopeKey = ""
    @AppStorage("serverURL") private var serverURL = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("模式", selection: $app.mode) {
                    Text("函数").tag(InkMode.function)
                    Text("推导").tag(InkMode.derivative)
                    Text("几何").tag(InkMode.geometry)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Button {
                    app.eraserOn.toggle()
                } label: {
                    Label(app.eraserOn ? "橡皮" : "笔", systemImage: app.eraserOn ? "eraser" : "pencil.tip")
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.eraserOn ? .orange : .accentColor)
                Button("双击确认") { app.doubleTap() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("清空", role: .destructive) { app.clear() }
                    .buttonStyle(.bordered)
                Text(engineLabel)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(engineLabel == "回放" ? Color.orange.opacity(0.18) : Color.green.opacity(0.18),
                                in: Capsule())
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    RuledPaper()
                    PencilCanvas(app: app, eraserOn: app.eraserOn, allowFinger: allowFinger)
                    InkOverlay(app: app)
                }
                .clipped()
                Divider()
                SceneHost(model: app.scene)
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// 和设置页同一套选择。没填 Key、也没填 Server 时就是回放，前两幕不靠网络。
    private var engineLabel: String {
        let key = dashscopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch engine {
        case "direct": return key.isEmpty ? "回放" : "百炼"
        case "server": return server.isEmpty ? "回放" : "Server"
        case "replay": return "回放"
        default:
            if !key.isEmpty { return "百炼" }
            if !server.isEmpty { return "Server" }
            return "回放"
        }
    }
}

/// 横线纸：只是书写引导，分行由 InkModel 按笔迹自己算。
struct RuledPaper: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 110
            var p = Path()
            while y < size.height {
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                y += 110
            }
            ctx.stroke(p, with: .color(.blue.opacity(0.12)), lineWidth: 1)
        }
        .background(Color(.systemBackground))
        .allowsHitTesting(false)
    }
}

struct SettingsView: View {
    @AppStorage("engine") private var engine = "auto"
    @AppStorage("dashscopeKey") private var key = ""
    @AppStorage("serverURL") private var server = ""
    @AppStorage("allowFinger") private var allowFinger = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别引擎", selection: $engine) {
                        Text("自动").tag("auto")
                        Text("直连百炼（Qwen）").tag("direct")
                        Text("Mac 上的 Server").tag("server")
                        Text("回放（断网）").tag("replay")
                    }
                } footer: {
                    Text("自动：填了 Key 就直连百炼；否则用 Server；都没有就回放。回放不看笔迹内容：函数行先当作 x^3-5x，这一行擦过之后当作 x^3-3x；推导行先当作 3x^2-3x，擦过之后当作 3x^2-3。")
                }
                Section("直连百炼") {
                    SecureField("DashScope API Key（只存在这台 iPad 上）", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Server") {
                    TextField("http://192.168.x.x:8080", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Toggle("允许手指书写（没有 Pencil 时测试用）", isOn: $allowFinger)
                }
            }
            .navigationTitle("设置")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
