import InkCore
import SceneUI
import SwiftUI

/// 画在笔迹上面的一层：识别回显（点一下可改）、红圈、正确项、一句说明、对勾、双击闪边。
/// 坐标全是 PencilKit 画布的 point，和 InkLine.band / Annotation.bbox 一致。
struct InkOverlay: View {
    @Bindable var app: AppModel
    @State private var editing: String?
    @State private var editText = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(app.lines.filter { !$0.strokes.isEmpty }) { line in
                lineDecorations(line)
            }
        }
        .alert("改一下识别结果", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("LaTeX，例如 f'(x)=3x^2-3", text: $editText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("确定") {
                if let id = editing { app.manualEdit(lineID: id, latex: editText) }
                editing = nil
            }
            Button("取消", role: .cancel) { editing = nil }
        }
    }

    @ViewBuilder
    private func lineDecorations(_ line: InkLine) -> some View {
        let band = line.band
        // 双击闪边
        if app.flashLine == line.id {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: band.width + 24, height: band.height + 16)
                .position(x: band.midX, y: band.midY)
                .allowsHitTesting(false)
        }
        // 回显：笔迹下方，点一下手动改
        Button {
            editText = app.echo[line.id] ?? ""
            editing = line.id
        } label: {
            if let latex = app.echo[line.id], !latex.isEmpty {
                MathLabel(latex, fontSize: 15, color: .secondaryLabel).fixedSize()
            } else if let n = app.notices[line.id] {
                Text(n).font(.footnote).foregroundStyle(.orange)
            } else {
                Text(line.mode == .geometry ? "画好后双击笔确认" : "识别中…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
        .position(x: band.minX + 120, y: band.maxY + 16)

        if let n = app.notices[line.id], app.echo[line.id] != nil {
            Text(n).font(.footnote).foregroundStyle(.orange)
                .padding(6).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
                .position(x: band.maxX + 120, y: band.midY)
                .allowsHitTesting(false)
        }

        if let a = app.annotations[line.id] {
            if a.ok {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.green)
                    .position(x: band.maxX + 30, y: band.midY)
                    .transition(.scale)
            } else if let err = a.errors.first, let box = err.rect {
                ErrorCircle(box: box)
                VStack(alignment: .leading, spacing: 6) {
                    if let exp = err.expectedLatex, !exp.isEmpty {
                        HStack(spacing: 6) {
                            Text("应为").font(.footnote).foregroundStyle(.secondary)
                            MathLabel(exp, fontSize: 22, color: .systemGreen).fixedSize()
                        }
                    }
                    if let e = a.explanation {
                        Text(e).font(.callout).foregroundStyle(.primary)
                    }
                }
                .padding(10)
                .frame(maxWidth: 300, alignment: .leading)
                .background(Color(red: 1, green: 0.97, blue: 0.88), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5)))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300)
                .position(x: box.maxX + 180, y: box.midY)
                .allowsHitTesting(false)
            }
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
            .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-120))
            .frame(width: box.width + 28, height: box.height + 22)
            .position(x: box.midX, y: box.midY)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { progress = 1 } }
    }
}
