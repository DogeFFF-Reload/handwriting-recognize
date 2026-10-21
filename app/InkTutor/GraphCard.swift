import SceneUI
import SwiftUI

/// 画板的坐标空间：画布 point，和 PencilKit 笔画、InkLine.band、Annotation.bbox 一致。
enum Board {
    static let space = "board"
}

/// 像 PS 自由变换那样的浮动卡片。
///
/// - 拖标题栏：移动（任何时候）。
/// - 点标题栏：选中，出现变换框。选中时：拖卡片任意处移动；拖四角 / 四边的手柄改大小（对角 / 对边不动）；
///   拖上方的圆形手柄旋转（靠近 0°、90°、180°、270° 时吸附）；双指捏合缩放、双指转动旋转。
/// - 没选中时，卡片里的内容自己接手势（函数图像拖动平移、双指缩放）。
/// - 拖完松手时调 onMoveEnded（函数卡片用它判断是不是拖到了另一张函数卡片上，合成一张图）。
struct TransformableCard<Header: View, Content: View>: View {
    @Binding var frame: CardFrame
    var selected: Bool
    var dimmed: Bool = false
    var onSelect: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: (_ interactive: Bool) -> Content
    /// 放在 content 后面：前面的尾随闭包照样按 header、content 对上。
    var onMoveEnded: (() -> Void)? = nil

    @State private var start: CardFrame?
    @State private var readout: String?
    @State private var shown = false

    private let headerHeight: CGFloat = 42

    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .gesture(moveGesture)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content(!selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .background(CardBackground())
        .opacity(dimmed ? 0.5 : 1)
        .overlay {
            if selected {
                // 选中时整张卡片都能拖着走，内容不接手势
                Color.clear
                    .contentShape(Rectangle())
                    .padding(.top, headerHeight)
                    .gesture(moveGesture)
                    .simultaneousGesture(pinchGesture)
            }
        }
        .overlay { if selected { handles } }
        .frame(width: frame.size.width, height: frame.size.height)
        // 出现时从左下角（挂在式子右上角的那一点）长出来
        .scaleEffect(shown ? 1 : 0.55, anchor: .bottomLeading)
        .opacity(shown ? 1 : 0)
        .rotationEffect(frame.rotation)
        .position(frame.center)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { shown = true }
        }
    }

    // MARK: 手势

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Board.space))
            .onChanged { g in
                if start == nil { start = frame }
                guard let s = start else { return }
                frame.center = CGPoint(x: s.center.x + g.translation.width, y: s.center.y + g.translation.height)
            }
            .onEnded { _ in
                start = nil
                onMoveEnded?()
            }
    }

    private var pinchGesture: some Gesture {
        SimultaneousGesture(MagnifyGesture(), RotateGesture())
            .onChanged { v in
                if start == nil { start = frame }
                guard let s = start else { return }
                if let m = v.first?.magnification {
                    frame.size = Self.clampedSize(CGSize(width: s.size.width * m, height: s.size.height * m))
                }
                if let r = v.second?.rotation {
                    frame.rotation = Self.snapped(.radians(s.rotation.radians + r.radians))
                }
                readout = "\(Int(frame.size.width)) × \(Int(frame.size.height))  ·  \(Self.degrees(frame.rotation))°"
            }
            .onEnded { _ in
                start = nil
                withAnimation(.easeOut(duration: 0.2)) { readout = nil }
            }
    }

    /// sx、sy ∈ {−1, 0, 1}：拖的是哪个角 / 哪条边。0 表示那个方向不变。
    private func resizeGesture(sx: CGFloat, sy: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Board.space))
            .onChanged { g in
                if start == nil { start = frame }
                guard let s = start else { return }
                let theta = s.rotation.radians
                // 对角（对边中点）固定
                let fixed = s.center + Self.rotate(CGPoint(x: -sx * s.size.width / 2, y: -sy * s.size.height / 2), theta)
                let handle = s.center + Self.rotate(CGPoint(x: sx * s.size.width / 2, y: sy * s.size.height / 2), theta)
                let p = CGPoint(x: handle.x + g.translation.width, y: handle.y + g.translation.height)
                let d = Self.rotate(p - fixed, -theta)
                var size = s.size
                if sx != 0 { size.width = sx * d.x }
                if sy != 0 { size.height = sy * d.y }
                size = Self.clampedSize(size)
                frame.size = size
                frame.center = fixed + Self.rotate(CGPoint(x: sx * size.width / 2, y: sy * size.height / 2), theta)
                readout = "\(Int(size.width)) × \(Int(size.height))"
            }
            .onEnded { _ in
                start = nil
                withAnimation(.easeOut(duration: 0.2)) { readout = nil }
            }
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Board.space))
            .onChanged { g in
                if start == nil { start = frame }
                guard let s = start else { return }
                let a0 = atan2(g.startLocation.y - s.center.y, g.startLocation.x - s.center.x)
                let a1 = atan2(g.location.y - s.center.y, g.location.x - s.center.x)
                frame.rotation = Self.snapped(.radians(s.rotation.radians + Double(a1 - a0)))
                readout = "\(Self.degrees(frame.rotation))°"
            }
            .onEnded { _ in
                start = nil
                withAnimation(.easeOut(duration: 0.2)) { readout = nil }
            }
    }

    // MARK: 变换框

    private var handles: some View {
        let w = frame.size.width, h = frame.size.height
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius + 3, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .padding(-3)
                .allowsHitTesting(false)
            // 旋转手柄：上边中点往上伸出一截
            Path { p in
                p.move(to: CGPoint(x: w / 2, y: -3))
                p.addLine(to: CGPoint(x: w / 2, y: -26))
            }
            .stroke(Theme.accent, lineWidth: 1.5)
            .allowsHitTesting(false)
            Circle()
                .fill(Theme.card)
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1.5))
                .overlay(Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent))
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .position(x: w / 2, y: -36)
                .gesture(rotateGesture)
                .accessibilityLabel("旋转")
            ForEach(Grip.all, id: \.self) { g in
                grip(corner: g.x != 0 && g.y != 0)
                    .position(x: w / 2 + g.x * w / 2, y: h / 2 + g.y * h / 2)
                    .gesture(resizeGesture(sx: g.x, sy: g.y))
            }
            if let readout {
                Text(readout)
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent, in: Capsule())
                    .position(x: w / 2, y: h + 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
    }

    private func grip(corner: Bool) -> some View {
        RoundedRectangle(cornerRadius: corner ? 3 : 2.5)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: corner ? 3 : 2.5).strokeBorder(Theme.accent, lineWidth: 1.5))
            .frame(width: corner ? 13 : 9, height: corner ? 13 : 9)
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    // MARK: 几何小工具

    static func rotate(_ p: CGPoint, _ theta: Double) -> CGPoint {
        let c = CGFloat(cos(theta)), s = CGFloat(sin(theta))
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }

    static func clampedSize(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, CardFrame.minSize.width), 1100),
               height: min(max(s.height, CardFrame.minSize.height), 900))
    }

    /// 靠近 0°、90°、180°、270° 时吸附过去。
    static func snapped(_ a: Angle) -> Angle {
        let deg = a.degrees
        let nearest = (deg / 90).rounded() * 90
        return abs(deg - nearest) < 4 ? .degrees(nearest) : a
    }

    static func degrees(_ a: Angle) -> Int {
        var d = Int(a.degrees.rounded()) % 360
        if d < 0 { d += 360 }
        return d
    }
}

/// 变换框的八个手柄：四角改两个方向，四边改一个方向（放在泛型类型外面：泛型里不能有静态存储属性）。
private struct Grip: Hashable {
    var x: CGFloat
    var y: CGFloat

    static let all = [Grip(x: -1, y: -1), Grip(x: 0, y: -1), Grip(x: 1, y: -1), Grip(x: 1, y: 0),
                      Grip(x: 1, y: 1), Grip(x: 0, y: 1), Grip(x: -1, y: 1), Grip(x: -1, y: 0)]
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}

// MARK: - 函数卡片

/// 式子右上角的函数图像卡片。别的函数可以画进来（标题栏的「叠加」，或者把那张卡片拖到这张上面松手）：
/// 两条曲线同图，标出交点，在选的区间里涂出两条曲线之间的面积；拖滑条时交点和面积跟着变。
struct FunctionCard: View {
    @Bindable var item: FunctionItem
    var app: AppModel

    var body: some View {
        if let graph = item.graph, item.mergedInto == nil {
            let others = app.companions(of: item)
            if item.card.minimized {
                CardPill(tint: item.tint, title: ([item] + others).map { "\($0.name)(x)" }.joined(separator: "、")) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { item.card.minimized = false }
                }
                .pinned(.bottomLeading, at: CGPoint(x: item.anchor.x + 10, y: item.anchor.y - 2))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                TransformableCard(frame: $item.card, selected: app.selection == .card(item.id), dimmed: item.showingInk,
                                  onSelect: { toggleSelection() }) {
                    header(graph, others: others)
                } content: { interactive in
                    VStack(spacing: 0) {
                        FunctionGraphView(model: graph, name: item.name, tint: item.tint, interactive: interactive && !item.showingInk,
                                          minimal: item.minimal, companions: curves(others), valueText: AppModel.graphValue)
                        if item.showsSliders, hasSliders(graph, others), !item.minimal {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            VStack(spacing: 0) {
                                if graph.hasSliders {
                                    GraphSliders(model: graph, tint: item.tint) { app.coefficientsChanged(item) }
                                }
                                ForEach(others) { f in
                                    if let g = f.graph, g.hasSliders {
                                        Text("\(f.name)(x)")
                                            .font(.system(size: 12, design: .serif).italic())
                                            .foregroundStyle(f.tint)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.top, 2)
                                        GraphSliders(model: g, tint: f.tint) { app.coefficientsChanged(f) }
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .allowsHitTesting(interactive)
                        }
                    }
                } onMoveEnded: {
                    app.cardDropped(item)
                }
                .overlay {
                    if item.showingInk {
                        Text("改完笔迹后双击，重新识别")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .position(item.card.center)
                            .allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func toggleSelection() {
        withAnimation(.easeOut(duration: 0.15)) {
            app.selection = app.selection == .card(item.id) ? nil : .card(item.id)
        }
    }

    private func curves(_ others: [FunctionItem]) -> [GraphCurve] {
        others.compactMap { f in f.graph.map { GraphCurve(name: f.name, tint: f.tint, model: $0) } }
    }

    private func hasSliders(_ graph: GraphModel, _ others: [FunctionItem]) -> Bool {
        graph.hasSliders || others.contains { $0.graph?.hasSliders ?? false }
    }

    /// 滑条一共几行（展开滑条时卡片要多高）。
    private func sliderRows(_ graph: GraphModel, _ others: [FunctionItem]) -> Int {
        let models = [graph] + others.compactMap(\.graph)
        return models.reduce(0) { total, g in total + (g.terms?.count ?? g.params.count) } + others.count
    }

    private func header(_ graph: GraphModel, others: [FunctionItem]) -> some View {
        HStack(spacing: 8) {
            CurveGlyph(tint: item.tint)
            if item.minimal {
                Spacer(minLength: 0)
            } else if !others.isEmpty {
                // 几条函数同图：标题栏是图例
                HStack(spacing: 10) {
                    ForEach([item] + others) { f in
                        HStack(spacing: 4) {
                            Capsule().fill(f.tint).frame(width: 14, height: 3)
                            Text("\(f.name)(x)").font(.system(size: 14, design: .serif).italic())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MathLabel(item.latex, fontSize: 15, color: .label)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .clipped()
            }
            if !item.minimal { overlayMenu(graph, others: others) }
            if !others.isEmpty, !item.minimal {
                HeaderButton(systemImage: "arrow.left.and.right", active: graph.region != nil,
                             help: graph.region == nil ? "选一个区间：看两曲线之间的面积" : "不看区间") {
                    app.toggleRegion(item)
                }
            }
            if graph.reveal, !item.minimal {
                // 图例：绿色虚线是导函数
                HStack(spacing: 5) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 1))
                        p.addLine(to: CGPoint(x: 16, y: 1))
                    }
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 16, height: 2)
                    Text("\(item.name)′").font(.system(size: 13, design: .serif).italic())
                }
                .foregroundStyle(Theme.ok)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.ok.opacity(0.12), in: Capsule())
            }
            if hasSliders(graph, others), !item.minimal {
                HeaderButton(systemImage: "slider.horizontal.3", active: item.showsSliders, help: "参数滑条") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if !item.showsSliders {
                            let rows = CGFloat(sliderRows(graph, others))
                            item.card.size.height = max(item.card.size.height, 252 + rows * 30 + 12)
                        }
                        item.showsSliders.toggle()
                    }
                }
            }
            // 小眼睛：简洁模式只留函数图像和坐标轴
            HeaderButton(systemImage: item.minimal ? "eye.slash" : "eye", active: item.minimal,
                         help: item.minimal ? "显示参数、切线和式子" : "只看图像") {
                withAnimation(.easeInOut(duration: 0.2)) { item.minimal.toggle() }
            }
            HeaderButton(systemImage: "arrow.down.right.and.arrow.up.left", help: "收起") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    if app.selection?.id == item.id { app.selection = nil }
                    item.card.minimized = true
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
    }

    /// 「叠加」：把纸上别的函数画进这张图，或者把画进来的拿出去。纸上只有这一条函数时不出现。
    @ViewBuilder private func overlayMenu(_ graph: GraphModel, others: [FunctionItem]) -> some View {
        let candidates = app.mergeCandidates(for: item)
        if !candidates.isEmpty || !others.isEmpty {
            Menu {
                if !candidates.isEmpty {
                    Section("画进这张图") {
                        ForEach(candidates) { f in
                            Button { app.merge(f, into: item) } label: { Label("\(f.name)(x)", systemImage: "plus") }
                        }
                    }
                }
                if !others.isEmpty {
                    Section("拿出去，单独作图") {
                        ForEach(others) { f in
                            Button { app.unmerge(f) } label: { Label("\(f.name)(x)", systemImage: "minus") }
                        }
                    }
                }
            } label: {
                Image(systemName: "square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(others.isEmpty ? Color.secondary : Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(others.isEmpty ? Color.clear : Theme.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("叠加别的函数")
        }
    }
}

// MARK: - 几何卡片

struct GeometryCard: View {
    @Bindable var item: GeometryItem
    var app: AppModel

    var body: some View {
        if item.card.minimized {
            CardPill(tint: Theme.warn, title: "△ABC") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { item.card.minimized = false }
            }
            .pinned(.topLeading, at: CGPoint(x: item.card.center.x - item.card.size.width / 2,
                                              y: item.card.center.y - item.card.size.height / 2))
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        } else {
            TransformableCard(frame: $item.card, selected: app.selection == .card(item.id), onSelect: {
                withAnimation(.easeOut(duration: 0.15)) { app.selection = app.selection == .card(item.id) ? nil : .card(item.id) }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "triangle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.warn)
                    Text("动态几何").font(.subheadline.weight(.semibold))
                    Text("拖动顶点试试").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HeaderButton(systemImage: "scribble.variable", help: "还原笔迹") { app.restoreInk(item) }
                    HeaderButton(systemImage: "trash", help: "删除") { app.delete(item) }
                    HeaderButton(systemImage: "arrow.down.right.and.arrow.up.left", help: "收起") {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { item.card.minimized = true }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
            } content: { interactive in
                GeometryView(model: item.scene, scene: item.geometry, chrome: false, interactive: interactive)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - 零件

/// 收起后的样子：一枚小胶囊，点一下展开。
struct CardPill: View {
    var tint: Color
    var title: String
    var onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 7) {
                CurveGlyph(tint: tint)
                Text(title)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(.primary)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 32)
            .background(CardBackground(radius: 16))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("展开函数图像")
    }
}

/// 卡片标题栏左边的小曲线图标。
struct CurveGlyph: View {
    var tint: Color

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let n = 24
            for i in 0...n {
                let t = Double(i) / Double(n)
                let x = size.width * t
                let y = size.height * (0.5 - 0.38 * sin((t - 0.5) * 2 * .pi) * (1 - 0.3 * abs(t - 0.5)))
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 18, height: 14)
        .padding(4)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct HeaderButton: View {
    var systemImage: String
    var active = false
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : .secondary)
                .frame(width: 32, height: 32)
                .background(active ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(help)
    }
}

extension View {
    /// 把视图的某个角钉在画布上的一个点（大小由内容决定）。
    func pinned(_ alignment: Alignment, at p: CGPoint) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: alignment) { self.fixedSize() }
            .position(p)
    }
}
