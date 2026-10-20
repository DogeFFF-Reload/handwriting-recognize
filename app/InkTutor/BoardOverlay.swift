import InkCore
import SceneUI
import SwiftUI

/// 画在笔迹上面的一层，坐标全是画布 point：标准式子和函数卡片、推导行的回显和批注、几何卡片、
/// 笔尖菜单、识别中的流光、笔迹淡出、提示。空白处不接触摸，笔照样写在下面的画布上。
struct BoardOverlay: View {
    @Bindable var app: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)

            ForEach(app.ghosts) { GhostView(ghost: $0) }

            ForEach(app.derivations) { DerivationMarks(item: $0, app: app) }

            ForEach(app.functions) { item in
                FormulaView(item: item, app: app)
            }
            ForEach(app.geometries) { item in
                GeometryCard(item: item, app: app)
            }
            // 卡片画在所有式子上面
            ForEach(app.functions) { item in
                FunctionCard(item: item, app: app)
            }

            ForEach(app.busy) { BusyOverlay(job: $0) }

            if let menu = app.menu {
                SegmentMenu(state: menu, boardSize: app.boardSize, topInset: app.topInset) { app.choose($0) }
                    .transition(.opacity)
            }

            ForEach(app.toasts) { ToastView(toast: $0, boardSize: app.boardSize) }
        }
    }
}

// MARK: - 标准式子

/// 换掉手写笔迹的标准式子。点一下出操作条：改式子、改笔迹、图像、删除；按住拖动，卡片一起走。
struct FormulaView: View {
    @Bindable var item: FunctionItem
    var app: AppModel
    @State private var editing = false
    @State private var editText = ""
    @State private var lastDrag: CGSize?

    private var selected: Bool { app.selection == item.id }

    var body: some View {
        if item.showingInk {
            // 笔迹放回画布了：提示改完怎么办
            HStack(spacing: 10) {
                Image(systemName: "scribble.variable").foregroundStyle(Theme.accent)
                Text("改好笔迹后双击笔身，选「函数」").font(.footnote)
                Button("取消") { app.cancelInk(item) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .pinned(.topLeading, at: CGPoint(x: item.frame.minX, y: item.frame.maxY + 14))
            .transition(.opacity)
        } else {
            formula
                .position(x: item.frame.midX, y: item.frame.midY)
                .transition(.opacity)
        }
    }

    private var formula: some View {
        MathLabel(item.latex, fontSize: item.fontSize, color: .label, style: .display)
            .frame(width: item.size.width, height: item.size.height)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.07) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(selected ? 0.55 : 0), lineWidth: 1.2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { app.selection = selected ? nil : item.id }
            }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(Board.space))
                    .onChanged { g in
                        let last = lastDrag ?? .zero
                        app.move(item, by: CGSize(width: g.translation.width - last.width, height: g.translation.height - last.height))
                        lastDrag = g.translation
                    }
                    .onEnded { _ in lastDrag = nil }
            )
            .overlay(alignment: .topLeading) {
                if selected { actionBar.fixedSize().offset(y: -50).transition(.opacity.combined(with: .offset(y: 6))) }
            }
            .overlay(alignment: .bottomLeading) {
                if let problem = item.problem {
                    Label("无法作图：\(problem)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.warn.opacity(0.1), in: Capsule())
                        .fixedSize()
                        .offset(y: 30)
                        .onTapGesture { beginEditing() }
                }
            }
            .alert("改一下式子", isPresented: $editing) {
                TextField("LaTeX，例如 f(x)=x^3-3x", text: $editText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("确定") { app.edit(item, latex: editText) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("识别结果不对时直接改 LaTeX，图像跟着变。")
            }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            BarButton(title: "改式子", systemImage: "character.cursor.ibeam") { beginEditing() }
            BarButton(title: "改笔迹", systemImage: "scribble.variable") { app.restoreInk(item) }
            if item.graph != nil {
                BarButton(title: item.card.minimized ? "展开图像" : "收起图像",
                          systemImage: item.card.minimized ? "chart.xyaxis.line" : "rectangle.compress.vertical") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { item.card.minimized.toggle() }
                }
            }
            BarButton(title: "删除", systemImage: "trash", role: .destructive) { app.delete(item) }
            if let engine = item.engine {
                Text(item.ms.map { "\(engine) · \($0) ms" } ?? engine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    private func beginEditing() {
        editText = item.latex
        editing = true
    }
}

private struct BarButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Theme.wrong : Color.primary)
        .hoverEffect(.highlight)
    }
}

// MARK: - 推导行

/// 推导行的笔迹留在画布上：下面回显识别结果（点一下手动改），错项上画红圈，旁边是正确项和一句说明；对了打勾。
struct DerivationMarks: View {
    @Bindable var item: DerivationItem
    var app: AppModel
    @State private var editing = false
    @State private var editText = ""

    var body: some View {
        let band = item.band
        ZStack(alignment: .topLeading) {
            Button {
                editText = item.latex ?? ""
                editing = true
            } label: {
                Group {
                    if let latex = item.latex {
                        MathLabel(latex, fontSize: 15, color: .secondaryLabel)
                    } else if let n = item.notice {
                        Text(n).font(.footnote).foregroundStyle(Theme.warn)
                    } else {
                        Text("识别中…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .pinned(.topLeading, at: CGPoint(x: band.minX, y: band.maxY + 8))

            if let n = item.notice, item.latex != nil {
                Text(n).font(.footnote).foregroundStyle(Theme.warn)
                    .padding(8).background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .pinned(.leading, at: CGPoint(x: band.maxX + 18, y: band.midY))
                    .allowsHitTesting(false)
            }

            if let a = item.annotation {
                if a.ok {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.ok)
                        .symbolEffect(.bounce, value: a.revision)
                        .position(x: band.maxX + 32, y: band.midY)
                        .transition(.scale.combined(with: .opacity))
                } else if let err = a.errors.first, let box = err.rect {
                    ErrorCircle(box: box)
                    VStack(alignment: .leading, spacing: 6) {
                        if let exp = err.expectedLatex, !exp.isEmpty {
                            HStack(spacing: 6) {
                                Text("应为").font(.footnote).foregroundStyle(.secondary)
                                MathLabel(exp, fontSize: 22, color: UIColor(Theme.ok))
                            }
                        }
                        if let e = a.explanation {
                            Text(e).font(.callout).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(width: 300, alignment: .leading)
                    .background(CardBackground(radius: 14))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.wrong).frame(width: 3).padding(.vertical, 12)
                    }
                    .pinned(.leading, at: CGPoint(x: box.maxX + 26, y: box.midY))
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .offset(x: -8)))
                }
            }
        }
        .alert("改一下识别结果", isPresented: $editing) {
            TextField("LaTeX，例如 f'(x)=3x^2-3", text: $editText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("确定") { app.manualEdit(item, latex: editText) }
            Button("取消", role: .cancel) {}
        }
    }
}

/// 手绘感的红圈，出现时「描」一遍。
private struct ErrorCircle: View {
    let box: CGRect
    @State private var progress: CGFloat = 0

    var body: some View {
        Ellipse()
            .trim(from: 0, to: progress)
            .stroke(Theme.wrong, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-120))
            .frame(width: box.width + 28, height: box.height + 22)
            .position(x: box.midX, y: box.midY)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { progress = 1 } }
    }
}

// MARK: - 识别中、淡出、提示

/// 正在识别的那一段：一层淡淡的底色，一道光扫过去，右下角写「识别中」。
private struct BusyOverlay: View {
    let job: BusySegment
    @State private var sweep = false

    var body: some View {
        let r = job.bounds.insetBy(dx: -12, dy: -10)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.accent.opacity(0.06))
            .overlay {
                LinearGradient(colors: [.clear, Theme.accent.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(r.width * 0.35, 60))
                    .offset(x: sweep ? r.width * 0.75 : -r.width * 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(job.kind == .function ? "识别中" : "批改中").font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .offset(y: 26)
            }
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}

/// 收成标准式子时，原来的笔迹轻轻淡出。
private struct GhostView: View {
    let ghost: InkGhost
    @State private var gone = false

    var body: some View {
        Image(uiImage: ghost.image)
            .resizable()
            .frame(width: ghost.frame.width, height: ghost.frame.height)
            .opacity(gone ? 0 : 0.9)
            .blur(radius: gone ? 6 : 0)
            .scaleEffect(gone ? 0.97 : 1)
            .position(x: ghost.frame.midX, y: ghost.frame.midY)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { gone = true } }
    }
}

private struct ToastView: View {
    let toast: Toast
    var boardSize: CGSize

    private var icon: String {
        switch toast.style {
        case .info: return "hand.tap"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .info: return Theme.accent
        case .warning: return Theme.warn
        case .success: return Theme.ok
        }
    }

    var body: some View {
        Label {
            Text(toast.text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3)))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .fixedSize()
        .position(x: min(max(toast.point.x, 180), boardSize.width - 180),
                  y: min(max(toast.point.y, 110), boardSize.height - 40))
        .allowsHitTesting(false)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// 画板还是空的时候：一句怎么开始。
struct EmptyBoardHint: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("写一个函数，比如")
                .font(.title3)
                .foregroundStyle(.secondary)
            MathLabel("f(x)=x^{3}-5x", fontSize: 34, color: .tertiaryLabel, style: .display)
                .fixedSize()
            HStack(spacing: 18) {
                hint("hand.tap", "写完双击笔身")
                hint("circle.grid.cross", "在笔尖旁选「函数」")
                hint("hand.pinch", "捏一下切换橡皮")
            }
            .padding(.top, 6)
        }
        .allowsHitTesting(false)
    }

    private func hint(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
