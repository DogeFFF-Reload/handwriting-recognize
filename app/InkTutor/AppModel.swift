import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 整块画板的状态。
///
/// 全局规则：先只显示原始墨迹；学生写完一段，双击 Pencil Pro 表示这一段输入完了，
/// 笔尖旁弹出「函数 / 推导 / 几何」。选「函数」时用 MyScript iink 的 Math Recognizer 把这段笔迹收成 LaTeX，
/// 手写笔迹换成标准式子，式子右上角挂一张可以移动、缩放、旋转、收起的函数卡片。
/// 推导和几何沿用 P3 的批改和草图识别，触发方式统一成双击后选。
///
/// 所有回调都在主线程：PencilKit 回调、Pencil 双击、识别结果用 MainActor 切回来。
@Observable
final class AppModel {
    // MARK: 笔
    var penColor: PenColor = .ink
    var penWidth: PenWidth = .medium
    var eraserOn = false

    // MARK: 画板上的东西
    private(set) var functions: [FunctionItem] = []
    private(set) var derivations: [DerivationItem] = []
    private(set) var geometries: [GeometryItem] = []
    /// 选中的式子或卡片（显示操作条或变换框）。
    var selection: Selection?
    /// 正在手动改 LaTeX 的式子（操作条上的「改式子」）。
    var editingFormula: UUID?
    var menu: SegmentMenuState?
    private(set) var busy: [BusySegment] = []
    private(set) var ghosts: [InkGhost] = []
    private(set) var toasts: [Toast] = []
    private(set) var hasInk = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// 画板大小（ContentView 量好了告诉这里，用来把卡片摆在屏幕里）。
    var boardSize: CGSize = CGSize(width: 1180, height: 820)
    /// 顶上工具栏占掉的高度（状态栏 24 + 上边距 8 + 胶囊 52 + 留白），卡片和菜单不往那里放。
    let topInset: CGFloat = 100

    @ObservationIgnored private weak var canvas: PKCanvasView?
    @ObservationIgnored private var drawing = PKDrawing()
    @ObservationIgnored private var ids = PencilKitBridge.IDTable()
    @ObservationIgnored private var strokes: [InkStroke] = []
    @ObservationIgnored private var pkByID: [String: PKStroke] = [:]
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var lineNumbers: [String: Int] = [:]

    init() {
        // 装机时从控制台就能看出 MyScript 缺不缺证书 / 资源（xcrun devicectl … --console）
        print("[InkTutor] MyScript: \(MyScriptMath.shared.status.summary)")
        MyScriptMath.shared.warmUp()
    }

    // MARK: 画布

    func attach(_ canvas: PKCanvasView) {
        self.canvas = canvas
        drawing = canvas.drawing
    }

    var tool: PKTool {
        // 整笔擦除（.vector）：笔画只会整笔消失，id 不会乱
        eraserOn ? PKEraserTool(.vector) : PKInkingTool(.pen, color: penColor.uiColor, width: penWidth.rawValue)
    }

    func drawingChanged(_ d: PKDrawing) {
        drawing = d
        strokes = PencilKitBridge.strokes(from: d, ids: &ids)
        pkByID = Dictionary(zip(strokes.map(\.id), d.strokes), uniquingKeysWith: { a, _ in a })
        let present = Set(strokes.map(\.id))
        let added = strokes.filter { !seen.contains($0.id) }
        seen = present
        hasInk = !strokes.isEmpty
        if menu != nil, !added.isEmpty || menu!.segment.strokeIDs.contains(where: { !present.contains($0) }) {
            menu = nil
        }

        // 推导行：擦掉的笔从这一行去掉；这一行被改过（擦了或在旁边新写了），旧的圈收起来
        for item in derivations {
            let before = item.strokeIDs
            item.strokeIDs.formIntersection(present)
            let touched = added.contains { $0.bounds.intersects(item.band.insetBy(dx: -24, dy: -12)) }
            if item.strokeIDs != before || touched {
                item.annotation = nil
                item.notice = nil
            }
            if item.strokeIDs != before {
                item.band = InkSegmenter.bounds(of: strokes.filter { item.strokeIDs.contains($0.id) })
            }
        }
        derivations.removeAll { $0.strokeIDs.isEmpty }
        // 还原了笔迹的函数：擦掉的笔不再算它的；笔迹全擦光、原处也没写新的，就整条删掉
        for f in functions where f.showingInk {
            f.inkIDs = f.inkIDs.filter { present.contains($0) }
        }
        functions.removeAll { $0.showingInk && $0.inkIDs.isEmpty && !hasStrokes(near: $0) }
        refreshUndo()
    }

    private func hasStrokes(near f: FunctionItem) -> Bool {
        strokes.contains { $0.bounds.intersects(f.frame.insetBy(dx: -30, dy: -20)) }
    }

    /// 已经属于某一项的笔（推导行、还原了笔迹的函数），不算「新写的一段」。
    private var claimed: Set<String> {
        var s = Set<String>()
        for d in derivations { s.formUnion(d.strokeIDs) }
        for f in functions where f.showingInk { s.formUnion(f.inkIDs) }
        return s
    }

    // MARK: 双击确认

    /// Pencil 双击：有落点就在笔尖旁弹菜单；没有落点就弹在这一段最后一笔收笔的地方。再双击一次收起菜单。
    func pencilDoubleTapped(at point: CGPoint?) {
        if menu != nil {
            menu = nil
            return
        }
        selection = nil
        guard let segment = segment(near: point) else {
            toast("先写一段，写完再双击笔身", at: point ?? CGPoint(x: boardSize.width / 2, y: boardSize.height / 2), .info)
            return
        }
        let tip = point ?? lastPenPoint(in: segment) ?? CGPoint(x: segment.bounds.maxX, y: segment.bounds.midY)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            menu = SegmentMenuState(anchor: tip, segment: segment)
        }
    }

    /// 工具栏上的「完成一段」：双击没进回调（或用模拟器）时用它顶上。
    func confirmLatestSegment() {
        pencilDoubleTapped(at: nil)
    }

    func dismissMenu() {
        withAnimation(.easeOut(duration: 0.15)) { menu = nil }
    }

    private func segment(near point: CGPoint?) -> InkSegment? {
        let taken = claimed
        let free = strokes.filter { !taken.contains($0.id) }
        var picked: [InkStroke] = []
        if let seed = InkSegmenter.seed(in: free, near: point) {
            picked = InkSegmenter.cluster(free, from: seed)
        }
        // 碰到的已有项（留着笔迹的推导行、还原了笔迹的函数）整项并进来，改完重新确认
        let reach: CGRect
        if picked.isEmpty {
            guard let point else { return latestClaimedSegment() }
            reach = CGRect(origin: point, size: .zero).insetBy(dx: -48, dy: -40)
        } else {
            reach = InkSegmenter.bounds(of: picked).insetBy(dx: -28, dy: -14)
        }
        var members = Set(picked.map(\.id))
        var target: UUID?
        for d in derivations where d.band.intersects(reach) {
            members.formUnion(d.strokeIDs)
            target = target ?? d.id
        }
        for f in functions where f.showingInk {
            let inkBounds = InkSegmenter.bounds(of: strokes.filter { f.inkIDs.contains($0.id) })
            // 原来的笔迹全擦了、在原处重写：按式子原来的位置认
            if (inkBounds.isNull ? f.frame : inkBounds).intersects(reach) {
                members.formUnion(f.inkIDs)
                target = f.id
            }
        }
        let chosen = strokes.filter { members.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        return InkSegment(strokeIDs: chosen.map(\.id), bounds: InkSegmenter.bounds(of: chosen), targetID: target)
    }

    private func latestClaimedSegment() -> InkSegment? {
        if let f = functions.last(where: { $0.showingInk && !$0.inkIDs.isEmpty }) {
            let s = strokes.filter { f.inkIDs.contains($0.id) }
            return InkSegment(strokeIDs: s.map(\.id), bounds: InkSegmenter.bounds(of: s), targetID: f.id)
        }
        if let d = derivations.last {
            let s = strokes.filter { d.strokeIDs.contains($0.id) }
            return s.isEmpty ? nil : InkSegment(strokeIDs: s.map(\.id), bounds: InkSegmenter.bounds(of: s), targetID: d.id)
        }
        return nil
    }

    private func lastPenPoint(in segment: InkSegment) -> CGPoint? {
        strokes.filter { segment.strokeIDs.contains($0.id) }.max { $0.createdAt < $1.createdAt }?.points.last
    }

    /// 菜单里选了一项。
    func choose(_ kind: SegmentKind) {
        guard let m = menu else { return }
        withAnimation(.easeOut(duration: 0.15)) { menu = nil }
        let seg = m.segment
        guard !busy.contains(where: { $0.bounds.intersects(seg.bounds) }) else {
            toast("这一段正在识别", at: CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24), .info)
            return
        }
        // 换了处理方式：原来那一项不要了（笔迹留着，按新的方式处理）
        if let t = seg.targetID {
            if kind != .derivation, let i = derivations.firstIndex(where: { $0.id == t }) { derivations.remove(at: i) }
            if kind != .function, let f = functions.first(where: { $0.id == t }) { delete(f, keepInk: true) }
        }
        switch kind {
        case .function: recognizeFunction(seg)
        case .derivation: checkDerivation(seg)
        case .geometry: buildGeometry(seg)
        }
    }

    // MARK: 函数

    private func recognizeFunction(_ seg: InkSegment) {
        let target = functions.first { $0.id == seg.targetID }
        let lineID = target?.lineID ?? nextLineID("F")
        let revision = (target?.revision ?? 0) + 1
        target?.revision = revision
        let line = makeLine(lineID, revision: revision, mode: .function, seg)
        let pk = seg.strokeIDs.compactMap { pkByID[$0] }
        let job = BusySegment(bounds: seg.bounds, kind: .function)
        busy.append(job)
        let png = PencilKitBridge.png(of: line, in: drawing, ids: &ids)
        let recognizer = Self.makeRecognizer(strokes: pk)
        Task { @MainActor [weak self] in
            defer { self?.busy.removeAll { $0.id == job.id } }
            do {
                let r = try await recognizer.recognize(line: line, imagePNG: png)
                self?.finishFunction(seg, result: r, target: target, lineID: lineID, revision: revision, ink: pk)
            } catch {
                self?.toast("没认出来：\(AppModel.describe(error))", at: CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24), .warning)
            }
        }
    }

    private func finishFunction(_ seg: InkSegment, result r: RecognitionResult, target: FunctionItem?,
                                lineID: String, revision: Int, ink: [PKStroke]) {
        if let target, target.revision != revision { return }   // 又确认了一次，这次的结果过期了
        let below = CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24)
        guard seg.strokeIDs.allSatisfy({ pkByID[$0] != nil }) else {
            toast("识别时这段又改过了，改完再双击一次", at: below, .info)
            return
        }
        let latex = r.latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            toast("没认出来：写清楚一点再双击", at: below, .warning)
            return
        }

        // 标准式子放在原来那行笔迹的位置：左对齐，竖直居中，字号跟着手写的大小走
        let fontSize = min(max(seg.bounds.height * 0.62, 24), 64)
        let size = MathLabel.measure(latex, fontSize: fontSize)
        let origin = CGPoint(x: seg.bounds.minX, y: seg.bounds.midY - size.height / 2)

        let item: FunctionItem
        if let target {
            item = target
            item.latex = latex
            item.origin = origin
            item.fontSize = fontSize
            item.size = size
        } else {
            let frame = CGRect(origin: origin, size: size)
            item = FunctionItem(lineID: lineID, latex: latex, origin: origin, fontSize: fontSize, size: size,
                                card: placeCard(next: frame, size: CGSize(width: 360, height: 252)),
                                tint: Theme.curve(functions.count))
            item.revision = revision
        }
        item.engine = r.engine
        item.ms = r.ms
        item.ink = ink
        item.inkIDs = seg.strokeIDs
        item.inkSourceIDs = seg.strokeIDs
        apply(latex: latex, to: item)

        // 笔迹淡出、式子淡入
        if let image = snapshot(of: ink, in: seg.bounds) {
            let ghost = InkGhost(image: image, frame: seg.bounds.insetBy(dx: -6, dy: -6))
            ghosts.append(ghost)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.ghosts.removeAll { $0.id == ghost.id }
            }
        }
        // 先把这一项标成「显示式子」再收走笔迹，免得 drawingChanged 当它的笔迹被擦光了
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            item.showingInk = false
            if target == nil { functions.append(item) }
        }
        removeStrokes(Set(seg.strokeIDs))
    }

    /// 解析式子、建或换函数图像。
    private func apply(latex: String, to item: FunctionItem) {
        do {
            let d = try FunctionDefinition.parse(latex)
            item.definition = d
            item.problem = nil
            let graph: GraphModel
            if let p = d.polynomial {
                graph = GraphModel(polynomial: p.sorted { $0.key > $1.key }.map { PolyTerm(coef: $0.value, pow: $0.key) })
            } else {
                let body = d
                graph = GraphModel(parameters: d.parameters) { x, values in body.evaluate(x, parameters: values) }
            }
            if let old = item.graph { old.replace(with: graph) } else { item.graph = graph }
        } catch {
            item.definition = nil
            item.problem = Self.describe(error)
        }
    }

    /// 函数卡片默认挂在式子右上角；贴边放不下时挪进屏幕，还是会压住式子就放到式子下面。
    private func placeCard(next formula: CGRect, size: CGSize) -> CardFrame {
        func clamped(_ c: CGPoint) -> CGPoint {
            CGPoint(x: min(max(c.x, size.width / 2 + 16), boardSize.width - size.width / 2 - 16),
                    y: min(max(c.y, topInset + size.height / 2 + 8), boardSize.height - size.height / 2 - 16))
        }
        var c = clamped(CGPoint(x: formula.maxX + 18 + size.width / 2, y: formula.minY - 14 - size.height / 2))
        var rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
        if rect.intersects(formula.insetBy(dx: -8, dy: -8)) {
            c = clamped(CGPoint(x: formula.maxX - size.width / 2, y: formula.maxY + 16 + size.height / 2))
            rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
        }
        return CardFrame(center: c, size: size)
    }

    /// 式子上的「编辑」：手动改 LaTeX。
    func edit(_ item: FunctionItem, latex: String) {
        let tex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tex.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            item.latex = tex
            item.size = MathLabel.measure(tex, fontSize: item.fontSize)
            item.engine = "手动"
            apply(latex: tex, to: item)
        }
    }

    /// 式子上的「改笔迹」：把原来的笔迹放回画布，式子先藏起来；擦改完双击、选「函数」更新这一项（卡片位置不变）。
    func restoreInk(_ item: FunctionItem) {
        guard !item.ink.isEmpty else { return }
        selection = nil
        var d = drawing
        d.strokes.append(contentsOf: item.ink)
        setDrawing(d)
        item.inkIDs = item.inkSourceIDs
        withAnimation(.easeOut(duration: 0.2)) { item.showingInk = true }
        toast("改完后双击笔身，选「函数」重新识别", at: CGPoint(x: item.frame.midX, y: item.frame.maxY + 26), .info)
    }

    /// 改笔迹改到一半不想改了：笔迹收走，式子回来。
    func cancelInk(_ item: FunctionItem) {
        let ink = Set(item.inkIDs)
        withAnimation(.easeOut(duration: 0.2)) { item.showingInk = false }
        removeStrokes(ink)
    }

    func delete(_ item: FunctionItem, keepInk: Bool = false) {
        if item.showingInk, !keepInk { removeStrokes(Set(item.inkIDs)) }
        if selection?.id == item.id { selection = nil }
        withAnimation(.easeOut(duration: 0.2)) { functions.removeAll { $0.id == item.id } }
    }

    /// 拖动式子：卡片一起走。
    func move(_ item: FunctionItem, by d: CGSize) {
        item.origin.x += d.width
        item.origin.y += d.height
        item.card.center.x += d.width
        item.card.center.y += d.height
    }

    /// 卡片的滑条改了多项式系数：式子跟着重写。
    func coefficientsChanged(_ item: FunctionItem) {
        item.rewriteFromTerms()
    }

    // MARK: 推导

    private func checkDerivation(_ seg: InkSegment) {
        let item = derivations.first { $0.id == seg.targetID }
            ?? DerivationItem(lineID: nextLineID("D"), strokeIDs: Set(seg.strokeIDs), band: seg.bounds)
        if !derivations.contains(where: { $0.id == item.id }) { derivations.append(item) }
        item.strokeIDs = Set(seg.strokeIDs)
        item.band = seg.bounds
        item.revision += 1
        item.annotation = nil
        item.notice = nil
        let revision = item.revision
        let line = makeLine(item.lineID, revision: revision, mode: .derivative, seg)
        let job = BusySegment(bounds: seg.bounds, kind: .derivation)
        busy.append(job)
        let png = PencilKitBridge.png(of: line, in: drawing, ids: &ids)
        let recognizer = Self.makeRecognizer(strokes: seg.strokeIDs.compactMap { pkByID[$0] })
        Task { @MainActor [weak self] in
            defer { self?.busy.removeAll { $0.id == job.id } }
            do {
                let r = try await recognizer.recognize(line: line, imagePNG: png)
                guard let self, item.revision == revision else { return }
                self.grade(item, line: line, latex: r.latex.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                item.notice = "识别失败，点这里手动输入"
            }
        }
    }

    /// 点回显手动改：当成这一版的识别结果，立即重批。
    func manualEdit(_ item: DerivationItem, latex: String) {
        let s = strokes.filter { item.strokeIDs.contains($0.id) }
        let line = InkLine(id: item.lineID, revision: item.revision, mode: .derivative, band: item.band,
                           strokes: s, removedStrokeIDs: [])
        grade(item, line: line, latex: latex.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func grade(_ item: DerivationItem, line: InkLine, latex: String) {
        item.latex = latex.isEmpty ? nil : latex
        item.checkedStrokes = item.strokeIDs
        guard !latex.isEmpty else {
            item.notice = "这一行没看清，点一下识别结果可以手动改"
            return
        }
        guard LatexTerms.parse(latex).kind == .derivative else {
            item.notice = "这一行要写成 f'(x) = … 才能批改"
            return
        }
        // 对照的是写在它上面、离它最近的那条函数（没有就取最后一条）
        let above = functions.filter { $0.definition != nil && $0.frame.minY < item.band.minY }
        guard let f = above.max(by: { $0.frame.minY < $1.frame.minY }) ?? functions.last(where: { $0.definition != nil }) else {
            item.notice = "先写一个函数（双击后选「函数」），再写它的导数"
            return
        }
        guard let a = DerivativeCheck.annotation(line: line, functionLatex: f.latexForChecking, derivativeLatex: latex, mode: .direct) else {
            item.notice = "这一行没看清，点一下识别结果可以手动改"
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            item.annotation = a
            item.notice = nil
            f.graph?.reveal = a.ok
        }
        if a.ok, f.card.minimized { withAnimation(.spring) { f.card.minimized = false } }
    }

    // MARK: 几何

    private func buildGeometry(_ seg: InkSegment) {
        let s = strokes.filter { seg.strokeIDs.contains($0.id) }
        guard let sketch = GeometrySketchRecognizer.recognize(strokes: s), let json = try? sketch.jsonData(),
              let scene = try? JSONDecoder().decode(GeometryScene.self, from: json) else {
            toast("这张图收不进来：现在只认三角形和中线", at: CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24), .warning)
            return
        }
        let ink = seg.strokeIDs.compactMap { pkByID[$0] }
        // 卡片就放在草图原来的位置（GeometryView 四周留 48 pt，点基本落在原处）
        let rect = seg.bounds.insetBy(dx: -48, dy: -56)
        let size = CGSize(width: max(rect.width, 280), height: max(rect.height + 36, 240))
        let item = GeometryItem(geometry: scene, ink: ink, card: CardFrame(center: CGPoint(x: rect.midX, y: rect.midY - 18), size: size))
        if let image = snapshot(of: ink, in: seg.bounds) {
            let ghost = InkGhost(image: image, frame: seg.bounds.insetBy(dx: -6, dy: -6))
            ghosts.append(ghost)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.ghosts.removeAll { $0.id == ghost.id } }
        }
        removeStrokes(Set(seg.strokeIDs))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { geometries.append(item) }
    }

    func restoreInk(_ item: GeometryItem) {
        var d = drawing
        d.strokes.append(contentsOf: item.ink)
        setDrawing(d)
        withAnimation(.easeOut(duration: 0.2)) { geometries.removeAll { $0.id == item.id } }
    }

    func delete(_ item: GeometryItem) {
        if selection?.id == item.id { selection = nil }
        withAnimation(.easeOut(duration: 0.2)) { geometries.removeAll { $0.id == item.id } }
    }

    // MARK: 工具栏

    func undo() {
        canvas?.undoManager?.undo()
        refreshUndo()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refreshUndo()
    }

    func clear() {
        menu = nil
        selection = nil
        withAnimation(.easeOut(duration: 0.2)) {
            functions = []
            derivations = []
            geometries = []
        }
        setDrawing(PKDrawing())
        lineNumbers = [:]
        // 演示从头来：回放的行号重新从第 1 行数（Server 那边也一起）。
        Self.replayTracker.reset()
        if let s = URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? ""), s.host != nil {
            var req = URLRequest(url: s.appendingPathComponent("replay/reset"))
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        }
    }

    func toast(_ text: String, at point: CGPoint, _ style: Toast.Style) {
        let t = Toast(text: text, point: point, style: style)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toasts.append(t) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toasts.removeAll { $0.id == t.id } }
        }
    }

    // MARK: 笔画工具

    private func makeLine(_ id: String, revision: Int, mode: InkMode, _ seg: InkSegment) -> InkLine {
        InkLine(id: id, revision: revision, mode: mode, band: seg.bounds,
                strokes: strokes.filter { seg.strokeIDs.contains($0.id) }, removedStrokeIDs: [])
    }

    private func nextLineID(_ prefix: String) -> String {
        let n = (lineNumbers[prefix] ?? 0) + 1
        lineNumbers[prefix] = n
        return "\(prefix)\(n)"
    }

    private func removeStrokes(_ ids: Set<String>) {
        var d = drawing
        d.strokes = zip(d.strokes, strokes).filter { !ids.contains($0.1.id) }.map(\.0)
        setDrawing(d)
    }

    /// 程序改画布：PencilKit 的撤销记录跟不上，清掉（「改笔迹」可以把收成式子的笔迹找回来）。
    private func setDrawing(_ d: PKDrawing) {
        if let canvas {
            canvas.drawing = d
            canvas.undoManager?.removeAllActions()
        }
        // PencilKit 对程序赋值是否回调 canvasViewDrawingDidChange 没有保证：自己同步一次（重复调用无副作用）
        drawingChanged(d)
    }

    private func refreshUndo() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }

    private func snapshot(of ink: [PKStroke], in rect: CGRect) -> UIImage? {
        guard !ink.isEmpty else { return nil }
        let r = rect.insetBy(dx: -6, dy: -6)
        var image: UIImage?
        (canvas?.traitCollection ?? UITraitCollection.current).performAsCurrent {
            image = PKDrawing(strokes: ink).image(from: r, scale: canvas?.window?.screen.scale ?? 2)
        }
        return image
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let e as FunctionDefinition.ParseError:
            switch e {
            case .empty: return "式子是空的"
            case .notAFunction(let lhs): return "「\(lhs) = …」不是 y = … 或 f(x) = … 的形式"
            case .unexpected(let s): return "看不懂「\(s)」"
            }
        case let e as RecognizerError:
            switch e {
            case .noImage: return "没有截到图"
            case .badResponse(let s): return s
            case .http(let code, _): return "网络错误 \(code)"
            }
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 识别引擎（设置页里选）

    /// 识别链：MyScript（设备上）→ 百炼 → Server；都没有时用回放（断网演示）。
    static func makeRecognizer(strokes: [PKStroke]) -> InkRecognizer {
        let d = UserDefaults.standard
        let pref = d.string(forKey: "engine") ?? "auto"
        let key = (d.string(forKey: "dashscopeKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let server = URL(string: d.string(forKey: "serverURL") ?? "").flatMap { $0.host == nil ? nil : $0 }
        let myscript: InkRecognizer? = MyScriptMath.shared.status.isReady ? MyScriptMathRecognizer(strokes: strokes) : nil
        let qwen: InkRecognizer? = key.isEmpty ? nil : DashScopeRecognizer(apiKey: key)
        let mac: InkRecognizer? = server.map { ServerRecognizer(baseURL: $0, trigger: .doubleTap) }

        var chain: [InkRecognizer]
        switch pref {
        case "myscript": chain = [myscript].compactMap { $0 }
        case "direct": chain = [qwen].compactMap { $0 }
        case "server": chain = [mac].compactMap { $0 }
        case "replay": chain = []
        default: chain = [myscript, qwen, mac].compactMap { $0 }
        }
        // 指定的引擎没配好（比如选了直连百炼却没填 Key）：按自动的顺序来，不直接退到回放
        if chain.isEmpty, pref != "replay" { chain = [myscript, qwen, mac].compactMap { $0 } }
        guard !chain.isEmpty else {
            return ReplayRecognizer(script: ReplayScript.golden.overlaid(with: replayRecorder.script), tracker: replayTracker,
                                    wholeLine: true)
        }
        // 真识别也让回放的行状态跟着走，中途切到回放不会数错；设置里打开「录制回放」时顺便录下来。
        return TrackingRecognizer(FallbackRecognizer(chain), tracker: replayTracker,
                                  recorder: d.bool(forKey: "recordReplay") ? replayRecorder : nil)
    }

    /// 工具栏上显示的当前引擎。
    static func engineLabel(pref: String, key: String, server: String) -> String {
        let hasKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasServer = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines))?.host != nil
        let ms = MyScriptMath.shared.status.isReady
        // 和 makeRecognizer 一样：指定的引擎没配好时按自动的顺序
        switch pref {
        case "replay": return "回放"
        case "myscript" where ms: return "MyScript"
        case "direct" where hasKey: return "百炼"
        case "server" where hasServer: return "Server"
        default: return ms ? "MyScript" : hasKey ? "百炼" : hasServer ? "Server" : "回放"
        }
    }

    /// 回放按「哪种模式的第几行 + 擦过几轮 + 这一轮新写了几笔」取，不按调用顺序：所有引擎共用这一份行状态。
    static let replayTracker = ReplayTracker()
    /// 彩排时录下的回放，存在这台 iPad 的 Documents/replay-script.json；录过的行替换内置的黄金路径。
    static let replayRecorder = ReplayRecorder(
        fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("replay-script.json"))
}

// MARK: - 演示画面（CI 在模拟器上截图用）

extension AppModel {
    /// 启动参数 `-demo menu|card|reveal`：摆出黄金路径上的几个画面，不用真机也能看界面。识别结果直接给定，不走识别器。
    func loadDemo(_ name: String) {
        clear()
        let left: CGFloat = 120
        if name == "menu" {
            setDrawing(PKDrawing(strokes: DemoInk.strokes("f(x)=x^3-5x", at: CGPoint(x: left, y: 226), height: 54)))
            let ink = InkSegmenter.bounds(of: strokes)
            pencilDoubleTapped(at: CGPoint(x: ink.maxX + 18, y: ink.maxY - 4))
            return
        }
        // 第一幕结束时的函数，已经收成标准式子
        setDrawing(PKDrawing(strokes: DemoInk.strokes("f(x)=x^3-3x", at: CGPoint(x: left, y: 226), height: 54)))
        guard let seg = segment(near: nil) else { return }
        finishFunction(seg, result: RecognitionResult(lineID: "F1", revision: 1, latex: "f\\left( x\\right) =x^{3}-3x",
                                                      engine: "MyScript", ms: 164),
                       target: nil, lineID: nextLineID("F"), revision: 1, ink: seg.strokeIDs.compactMap { pkByID[$0] })
        // 第二幕：导数那一行留着笔迹
        let fixed = name == "reveal"
        let derivative = fixed ? "f'(x)=3x^2-3" : "f'(x)=3x^2-3x"
        var d = drawing
        d.strokes.append(contentsOf: DemoInk.strokes(derivative, at: CGPoint(x: left, y: 470), height: 54,
                                                     start: Date(timeIntervalSinceReferenceDate: 800_000_100)))
        setDrawing(d)
        if let seg2 = segment(near: nil) {
            let item = DerivationItem(lineID: nextLineID("D"), strokeIDs: Set(seg2.strokeIDs), band: seg2.bounds)
            item.revision = 1
            derivations.append(item)
            grade(item, line: makeLine(item.lineID, revision: 1, mode: .derivative, seg2), latex: derivative)
        }
        guard let f = functions.first else { return }
        if fixed {
            // 顺便看橡皮选中、式子操作条的样子
            eraserOn = true
            selection = .formula(f.id)
            f.showsSliders = true
            f.card.size = CGSize(width: 430, height: 380)
            f.card.center = CGPoint(x: f.anchor.x + 24 + 215, y: max(f.anchor.y - 12 - 190, topInset + 200))
        } else {
            f.card.rotation = .degrees(-4)
            selection = .card(f.id)
            // 再放一条收起来的函数，看胶囊的样子
            let g = FunctionItem(lineID: nextLineID("F"), latex: "g(x)=\\sin x", origin: CGPoint(x: left, y: 650), fontSize: 34,
                                 size: MathLabel.measure("g(x)=\\sin x", fontSize: 34),
                                 card: CardFrame(center: CGPoint(x: 700, y: 640), size: CGSize(width: 360, height: 252), minimized: true),
                                 tint: Theme.curve(1))
            apply(latex: g.latex, to: g)
            functions.append(g)
        }
    }
}
