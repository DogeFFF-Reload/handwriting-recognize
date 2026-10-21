import SwiftUI

/// 顶上只放笔的状态和功能键，三枚浮在纸上的胶囊：
/// 最左边回草稿画廊、草稿的名字（点一下改名）；然后是笔（笔 / 橡皮、颜色、粗细）；
/// 右边是撤销、重做、「完成一段」、清空、识别引擎、设置。
/// 模式不再在这里选：写完一段双击笔身，在笔尖旁选。
struct TopBar: View {
    @Bindable var app: AppModel
    var engine: String
    /// 草稿的名字。
    var title: String
    /// 回画廊。
    var onBack: () -> Void
    /// 改名（演示纸没有）。
    var onRename: (() -> Void)?
    var onSettings: () -> Void
    @State private var confirmClear = false

    var body: some View {
        if app.compact {
            // 窗口化：右上角一枚小胶囊，左上角留给窗口按钮
            HStack {
                Spacer(minLength: 0)
                compactGroup
            }
            .padding(.horizontal, 10)
        } else {
            HStack(alignment: .top, spacing: 12) {
                boardGroup
                penGroup
                Spacer(minLength: 0)
                actionGroup
            }
            .padding(.horizontal, 16)
        }
    }

    /// 名字太长时截短（胶囊不跟着名字变宽）。
    private var shortTitle: String {
        title.count > 14 ? String(title.prefix(13)) + "…" : title
    }

    // MARK: 窗口化：只留笔、橡皮、清空、设置

    private var compactGroup: some View {
        HStack(spacing: 2) {
            SmallToolButton(systemImage: "pencil.tip", help: "笔", selected: !app.eraserOn, dot: app.penColor.swatch) {
                withAnimation(.snappy(duration: 0.2)) { app.eraserOn = false }
            }
            SmallToolButton(systemImage: app.eraserOn ? "eraser.fill" : "eraser", help: "橡皮", selected: app.eraserOn) {
                withAnimation(.snappy(duration: 0.2)) { app.eraserOn = true }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 3)
            SmallToolButton(systemImage: "trash", help: "清空", selected: false) { confirmClear = true }
                .disabled(!(app.hasInk || !app.functions.isEmpty || !app.geometries.isEmpty || !app.shapes.isEmpty))
                .confirmationDialog("清空整页？", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("清空", role: .destructive) { app.clear() }
                } message: {
                    Text("笔迹、式子和卡片都会去掉，回放从第一行重新数。")
                }
            moreMenu
        }
        .padding(.horizontal, 4)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }

    /// 设置键：收进去的那些（草稿列表、撤销重做、完成一段、颜色粗细）都在这个菜单里。
    private var moreMenu: some View {
        Menu {
            Section(shortTitle) {
                Button(action: onBack) { Label("草稿列表", systemImage: "square.grid.2x2") }
                if let onRename {
                    Button(action: onRename) { Label("重命名", systemImage: "pencil") }
                }
            }
            Section {
                Button { app.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                    .disabled(!app.canUndo)
                Button { app.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                    .disabled(!app.canRedo)
                Button { app.confirmLatestSegment() } label: { Label("完成一段", systemImage: "hand.tap") }
                    .disabled(!app.hasInk)
            }
            Section {
                Picker(selection: Binding(get: { app.penColor }, set: { app.penColor = $0; app.eraserOn = false })) {
                    ForEach(PenColor.allCases) { Text($0.name).tag($0) }
                } label: {
                    Label("笔的颜色", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { app.penWidth }, set: { app.penWidth = $0; app.eraserOn = false })) {
                    ForEach(PenWidth.allCases) { Text($0.name).tag($0) }
                } label: {
                    Label("笔的粗细", systemImage: "lineweight")
                }
                .pickerStyle(.menu)
            }
            Section("识别引擎：\(engine)") {
                Button(action: onSettings) { Label("设置…", systemImage: "gearshape") }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .foregroundStyle(Color.primary)
        .accessibilityLabel("设置和更多")
    }

    // MARK: 草稿

    private var boardGroup: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .hoverEffect(.highlight)
            .accessibilityLabel("回到草稿列表")
            Button {
                onRename?()
            } label: {
                HStack(spacing: 4) {
                    Text(shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if onRename != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 2)
                .padding(.trailing, 10)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .disabled(onRename == nil)
            .accessibilityLabel("草稿名字：\(title)")
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    // MARK: 笔

    private var penGroup: some View {
        HStack(spacing: 6) {
            ToolButton(systemImage: "pencil.tip", title: "笔", selected: !app.eraserOn) {
                withAnimation(.snappy(duration: 0.2)) { app.eraserOn = false }
            }
            ToolButton(systemImage: app.eraserOn ? "eraser.fill" : "eraser", title: "橡皮", selected: app.eraserOn) {
                withAnimation(.snappy(duration: 0.2)) { app.eraserOn = true }
            }
            divider
            HStack(spacing: 8) {
                ForEach(PenColor.allCases) { c in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            app.penColor = c
                            app.eraserOn = false
                        }
                    } label: {
                        Circle()
                            .fill(c.swatch)
                            .frame(width: 20, height: 20)
                            .padding(3)
                            .overlay(Circle().strokeBorder(app.penColor == c && !app.eraserOn ? Theme.accent : .clear, lineWidth: 2))
                            .frame(width: 32, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name)
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach(PenWidth.allCases) { w in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            app.penWidth = w
                            app.eraserOn = false
                        }
                    } label: {
                        Capsule()
                            .fill(app.penWidth == w && !app.eraserOn ? Theme.accent : Color.secondary.opacity(0.55))
                            .frame(width: 16, height: w.rawValue + 0.5)
                            .frame(width: 32, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(w.name)笔")
                }
            }
            .opacity(app.eraserOn ? 0.45 : 1)
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    // MARK: 功能键

    private var actionGroup: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "arrow.uturn.backward", help: "撤销", enabled: app.canUndo) { app.undo() }
            IconButton(systemImage: "arrow.uturn.forward", help: "重做", enabled: app.canRedo) { app.redo() }
            divider
            Button {
                app.confirmLatestSegment()
            } label: {
                Label("完成一段", systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .disabled(!app.hasInk)
            .accessibilityHint("Pencil 双击没反应时用它：在最后一笔旁弹出函数 / 求解 / 几何")
            divider
            IconButton(systemImage: "trash", help: "清空", enabled: app.hasInk || !app.functions.isEmpty || !app.geometries.isEmpty || !app.shapes.isEmpty) {
                confirmClear = true
            }
            .confirmationDialog("清空整页？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { app.clear() }
            } message: {
                Text("笔迹、式子和卡片都会去掉，回放从第一行重新数。")
            }
            EngineBadge(engine: engine)
            IconButton(systemImage: "gearshape", help: "设置", action: onSettings)
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 24).padding(.horizontal, 4)
    }
}

/// 笔 / 橡皮：选中时是一块带底色的方块，图标下面写字。
private struct ToolButton: View {
    var systemImage: String
    var title: String
    var selected: Bool
    var action: () -> Void

    private var tint: Color { selected ? Theme.accent : Color(UIColor.secondaryLabel) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: 46, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 窗口化时的小按键：只有图标，选中时一块淡淡的底色；笔的右下角一个小圆点是现在的颜色。
private struct SmallToolButton: View {
    var systemImage: String
    var help: String
    var selected: Bool
    var dot: Color?
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 34, height: 32)
                .background(selected ? Theme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let dot {
                        Circle().fill(dot).frame(width: 6, height: 6).padding(5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct IconButton: View {
    var systemImage: String
    var help: String
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .hoverEffect(.highlight)
        .accessibilityLabel(help)
    }
}

/// 当前识别引擎：MyScript（设备上）是绿点，回放是橙点。
private struct EngineBadge: View {
    var engine: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engine == "回放" ? Theme.warn : Theme.ok)
                .frame(width: 7, height: 7)
            Text(engine)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .padding(.horizontal, 4)
        .accessibilityLabel("识别引擎：\(engine)")
    }
}
