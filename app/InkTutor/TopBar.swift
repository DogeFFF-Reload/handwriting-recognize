import SwiftUI

/// 顶上只放笔的状态和功能键，两枚浮在纸上的胶囊：
/// 左边是笔（笔 / 橡皮、颜色、粗细），右边是撤销、重做、「完成一段」、清空、识别引擎、设置。
/// 模式不再在这里选：写完一段双击笔身，在笔尖旁选。
struct TopBar: View {
    @Bindable var app: AppModel
    var engine: String
    var onSettings: () -> Void
    @State private var confirmClear = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            penGroup
            Spacer(minLength: 0)
            actionGroup
        }
        .padding(.horizontal, 16)
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
            .accessibilityHint("Pencil 双击没反应时用它：在最后一笔旁弹出函数 / 求导 / 几何")
            divider
            IconButton(systemImage: "trash", help: "清空", enabled: app.hasInk || !app.functions.isEmpty || !app.geometries.isEmpty) {
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
