import InkCore
import SceneUI
import SwiftUI

/// 整屏一张纸。顶上浮着工具栏；不再分左右半屏，函数图像是挂在式子右上角的卡片。
struct ContentView: View {
    @State private var app = AppModel()
    @State private var showSettings = false
    @AppStorage("allowFinger") private var allowFinger = false
    @AppStorage("engine") private var engine = "auto"
    @AppStorage("dashscopeKey") private var dashscopeKey = ""
    @AppStorage("serverURL") private var serverURL = ""

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    PaperBackground()
                    PencilCanvas(app: app, eraserOn: app.eraserOn, penColor: app.penColor, penWidth: app.penWidth,
                                 allowFinger: allowFinger)
                    if !app.hasInk, app.functions.isEmpty, app.geometries.isEmpty {
                        EmptyBoardHint()
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.46)
                            .transition(.opacity)
                    }
                    BoardOverlay(app: app)
                }
                .coordinateSpace(name: Board.space)
                .onAppear { app.boardSize = geo.size }
                .onChange(of: geo.size) { _, s in app.boardSize = s }
            }
            .ignoresSafeArea()

            TopBar(app: app, engine: AppModel.engineLabel(pref: engine, key: dashscopeKey, server: serverURL)) {
                showSettings = true
            }
            .padding(.top, 8)
        }
        .animation(.easeOut(duration: 0.25), value: app.hasInk)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            // CI 截图：启动参数 -demo <名字>
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demo"), i + 1 < args.count {
                try? await Task.sleep(nanoseconds: 500_000_000)
                app.loadDemo(args[i + 1])
            }
        }
    }
}

/// 横线纸，左边一道淡红的页边线。只是书写引导，分段由笔迹自己算。
struct PaperBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var rules = Path()
            var y: CGFloat = 132
            while y < size.height {
                rules.move(to: CGPoint(x: 0, y: y))
                rules.addLine(to: CGPoint(x: size.width, y: y))
                y += 76
            }
            ctx.stroke(rules, with: .color(Theme.rule), lineWidth: 1)
            var margin = Path()
            margin.move(to: CGPoint(x: 64, y: 0))
            margin.addLine(to: CGPoint(x: 64, y: size.height))
            ctx.stroke(margin, with: .color(Theme.margin), lineWidth: 1)
        }
        .background(Theme.paper)
        .allowsHitTesting(false)
    }
}

struct SettingsView: View {
    @AppStorage("engine") private var engine = "auto"
    @AppStorage("dashscopeKey") private var key = ""
    @AppStorage("serverURL") private var server = ""
    @AppStorage("allowFinger") private var allowFinger = false
    @AppStorage("recordReplay") private var recordReplay = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别引擎", selection: $engine) {
                        Text("自动（MyScript 优先）").tag("auto")
                        Text("MyScript（设备上）").tag("myscript")
                        Text("直连百炼（Qwen）").tag("direct")
                        Text("Mac 上的 Server").tag("server")
                        Text("回放（断网）").tag("replay")
                    }
                } footer: {
                    Text("自动：MyScript 就绪就用它（设备上识别），认不出时再试百炼和 Server；都没有就回放。"
                         + "指定的引擎没配好（例如选了百炼却没填 Key）时也按这个顺序。"
                         + "回放不看笔迹内容：第一条函数先当作 x^3-5x，改过笔迹之后当作 x^3-3x；选「求导」的那一行当作 f'(x)，按上面的函数直接求。")
                }
                Section {
                    LabeledContent("状态") {
                        Text(MyScriptMath.shared.status.summary)
                            .foregroundStyle(MyScriptMath.shared.status.isReady ? Theme.ok : Theme.warn)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("MyScript iink · Math Recognizer")
                } footer: {
                    Text("证书和识别资源都不进仓库：MyCertificate.c 放进 app/InkTutor/MyScriptCertificate/；"
                         + "数学识别资源在 Mac 上编译时自动下载到 app/MyScript/（也可以手动运行 tools/myscript/fetch-assets.sh）。")
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
                    Toggle("录制回放（彩排时打开）", isOn: $recordReplay)
                    Button("清除录好的回放", role: .destructive) { AppModel.replayRecorder.clear() }
                } footer: {
                    Text("打开后，真识别的结果按「第几条、改过几轮、这一轮写了几笔」记下来，断网或选「回放」时照着放。"
                         + "演示的人按真实写法把黄金路径走一遍就行；没录过的用内置的。")
                }
                Section {
                    Toggle("允许手指书写（没有 Pencil 时测试用）", isOn: $allowFinger)
                } footer: {
                    Text("Pencil 双击 = 这一段写完了；Pencil Pro 捏一下 = 切换笔和橡皮。双击没反应时点工具栏上的「完成一段」。")
                }
            }
            .navigationTitle("设置")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
