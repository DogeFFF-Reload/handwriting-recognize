import InkCore
import SceneUI
import SwiftUI

/// 最外面一层：草稿画廊（参考无边记），点一份草稿打开。
/// CI 截图用启动参数 `-demo <名字>`：直接打开一张不存盘的演示纸；`-demo gallery` 是放了几份示例草稿的画廊。
struct ContentView: View {
    @State private var library: BoardLibrary
    @State private var open: BoardMeta?
    private let demo: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        let demo = args.firstIndex(of: "-demo").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        self.demo = demo
        if demo == "gallery" {
            // 演示画廊：放在临时目录，不碰真的草稿
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DemoBoards", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            _library = State(initialValue: BoardLibrary.demo(at: tmp))
        } else {
            _library = State(initialValue: BoardLibrary())
        }
    }

    var body: some View {
        if let demo, demo != "gallery" {
            BoardScreen(library: library, meta: nil, demo: demo, onClose: {})
        } else {
            NavigationStack {
                GalleryView(library: library) { open = $0 }
                    .navigationDestination(item: $open) { meta in
                        BoardScreen(library: library, meta: meta, demo: nil) { open = nil }
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden()
                    }
            }
            .tint(Theme.accent)
        }
    }
}

/// 一份草稿：整屏一张可以上下滚的纸，顶上浮着工具栏；函数图像是挂在式子右上角的卡片。
/// 打开时读出来，开着的时候每 3 秒有变化就存，离开、切到后台时存并截缩略图。
struct BoardScreen: View {
    let library: BoardLibrary
    /// nil：演示纸，不存盘。
    let meta: BoardMeta?
    let demo: String?
    var onClose: () -> Void

    @State private var app = AppModel()
    @State private var showSettings = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var lastSaved: (board: Data, drawing: Data)?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("allowFinger") private var allowFinger = false
    @AppStorage("engine") private var engine = "auto"
    @AppStorage("dashscopeKey") private var dashscopeKey = ""
    @AppStorage("serverURL") private var serverURL = ""

    private var title: String {
        guard let meta else { return "演示" }
        return library.meta(meta.id)?.title ?? meta.title
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    PaperBackground(app: app)
                    PencilCanvas(app: app, eraserOn: app.eraserOn, penColor: app.penColor, penWidth: app.penWidth,
                                 allowFinger: allowFinger, contentHeight: app.contentHeight)
                    if !app.hasInk, app.functions.isEmpty, app.geometries.isEmpty, app.shapes.isEmpty {
                        EmptyBoardHint()
                            .scaleEffect(app.compact ? 0.78 : 1)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.46)
                            .transition(.opacity)
                    }
                    ScrollingOverlay(app: app)
                }
                .onAppear { resized(geo.size) }
                .onChange(of: geo.size) { _, s in resized(s) }
            }
            .ignoresSafeArea()

            TopBar(app: app, engine: AppModel.engineLabel(pref: engine, key: dashscopeKey, server: serverURL),
                   title: title, onBack: { close() }, onRename: meta.map { _ in startRename }) {
                showSettings = true
            }
            .padding(.top, 8)
        }
        .animation(.easeOut(duration: 0.25), value: app.hasInk)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("重命名草稿", isPresented: $renaming) {
            TextField("草稿名字", text: $newName)
            Button("好") { if let meta { library.rename(meta.id, to: newName) } }
            Button("取消", role: .cancel) {}
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let demo {
                try? await Task.sleep(nanoseconds: 200_000_000)
                app.loadDemo(demo)
                return
            }
            guard let meta else { return }
            let (snap, drawing) = library.read(meta.id)
            app.restore(snap, drawing: drawing)
            lastSaved = (try? BoardLibrary.encoder.encode(app.snapshot())).map { ($0, app.drawingData) }
            if let y = snap?.scrollY, y > 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                app.scroll(to: y)
            }
            // 开着的时候每 3 秒看一次，有变化就存；缩略图最多一分钟换一次（App 被直接关掉时画廊里也是新的）
            var lastThumb = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let refresh = Date().timeIntervalSince(lastThumb) > 60
                if save(thumbnail: refresh), refresh { lastThumb = Date() }
            }
        }
        .onChange(of: scenePhase) { old, phase in
            // 刚要离开（还看得见）时截缩略图；已经到后台了只存数据——这时候截到的是一张白图
            if phase == .inactive, old == .active { save(thumbnail: true, force: true) }
            if phase == .background { save(thumbnail: false) }
        }
    }

    /// 窗口大小变了：记下来，窗口比屏幕小（台前调度、分屏）或者很窄就换成小号的工具栏。
    private func resized(_ size: CGSize) {
        app.boardSize = size
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? size
        let windowed = size.width < screen.width - 40 || size.height < screen.height - 40
        withAnimation(.easeInOut(duration: 0.2)) {
            app.compact = demo == "compact" || windowed || size.width < 900
        }
        app.growPage()
    }

    private func startRename() {
        newName = title
        renaming = true
    }

    /// 回画廊：收起菜单和选中框，截一张缩略图，存好再走。
    private func close() {
        app.dismissMenu()
        app.selection = nil
        DispatchQueue.main.async {
            save(thumbnail: true, force: true)
            onClose()
        }
    }

    /// 存这份草稿。thumbnail：顺便截缩略图（内容没变时只在 force 时截）。返回有没有写盘。
    @discardableResult
    private func save(thumbnail: Bool, force: Bool = false) -> Bool {
        guard let meta, let board = try? BoardLibrary.encoder.encode(app.snapshot()) else { return false }
        let drawing = app.drawingData
        let changed = lastSaved.map { $0.board != board || $0.drawing != drawing } ?? true
        let thumbnail = thumbnail && (changed || force)
        guard changed || thumbnail else { return false }
        let image = thumbnail ? BoardThumbnail.capture() : nil
        library.write(meta.id, board: board, drawing: drawing, thumbnail: image)
        lastSaved = (board, drawing)
        return true
    }
}

/// 式子、卡片、图形那一层：用画布坐标摆放，纸滚多少它就移多少。只有这一层读 scrollOffset，滚动时别的不重算。
private struct ScrollingOverlay: View {
    var app: AppModel

    var body: some View {
        BoardOverlay(app: app)
            .frame(width: app.boardSize.width, height: max(app.contentHeight, app.boardSize.height), alignment: .topLeading)
            .coordinateSpace(name: Board.space)
            .offset(x: -app.scrollOffset.x, y: -app.scrollOffset.y)
    }
}

/// 横线纸，左边一道淡红的页边线，跟着笔迹一起滚。只是书写引导，分段由笔迹自己算。
struct PaperBackground: View {
    var app: AppModel

    var body: some View {
        let offset = app.scrollOffset.y
        Canvas { ctx, size in
            // 第一条线在纸上 y = 132，往下每 76 一条；只画看得见的
            var rules = Path()
            let first = max(0, ((offset - 132) / 76).rounded(.up))
            var y: CGFloat = 132 + first * 76 - offset
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
    @AppStorage("checkSocratic") private var checkSocratic = false
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
                         + "回放不看笔迹内容：第一条函数先当作 x^3-5x，改过笔迹之后当作 x^3-3x；选「求解」的那一行当作 f'(x)，按上面的函数直接求；"
                         + "选「批改」的那一行先当作 f'(x)=3x^2-3x，擦改一轮之后当作 f'(x)=3x^2-3。")
                }
                Section {
                    Toggle("批改只提问，不给正确答案", isOn: $checkSocratic)
                } header: {
                    Text("批改")
                } footer: {
                    Text("在函数下面手写 f'(x) = …，双击选「批改」。关着：圈出算错的那一项，旁边写出正确结果和原因。"
                         + "打开：只圈出来、问一句，屏幕上不出现正确导数，学生自己改对为止。改对后图像里才画出导函数、极值点和切线。")
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
