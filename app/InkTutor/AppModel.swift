import InkCore
import Observation
import PencilKit
import SceneUI
import SwiftUI

/// 整块画板的状态。
///
/// 全局规则：先只显示原始墨迹；学生写完一段，双击 Pencil Pro 表示这一段输入完了，
/// 笔尖旁弹出「函数 / 求解 / 几何」。选「函数」时用 MyScript iink 的 Math Recognizer 把这段笔迹收成 LaTeX，
/// 手写笔迹换成标准式子，式子右上角挂一张可以移动、缩放、旋转、收起的函数卡片。
/// 「求解」把写下的式子直接算出来：在函数下面写 f'(x) 求导（图像里画出导函数），写 \int_0^2 f(x)dx、
/// \lim_{x\to 3} f(x)、\sum_{k=1}^{n} k^2、x^2-4=0，或者一个不引用函数的完整式子，都直接给出结果；
/// 积分和极限顺便标在 f 的图像上。选「函数」时写的其实是要算的东西，也会转去求解。
/// 几何沿用 P3 的草图识别，触发方式统一成双击后选。
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
    private(set) var geometries: [GeometryItem] = []
    /// 选「几何」认出来的图形（平面的、立体的），直接画在纸上。
    private(set) var shapes: [ShapeItem] = []
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
    @ObservationIgnored private var turnTask: Task<Void, Never>?

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

    /// 已经属于某一项的笔（还原了笔迹的式子），不算「新写的一段」。
    private var claimed: Set<String> {
        var s = Set<String>()
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
        // 碰到还原了笔迹的式子，整项并进来，改完重新确认
        let reach: CGRect
        if picked.isEmpty {
            guard let point else { return latestClaimedSegment() }
            reach = CGRect(origin: point, size: .zero).insetBy(dx: -48, dy: -40)
        } else {
            reach = InkSegmenter.bounds(of: picked).insetBy(dx: -28, dy: -14)
        }
        var members = Set(picked.map(\.id))
        var target: UUID?
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
        // 还原了笔迹的式子改成画几何：原来那一项不要了（笔迹留着）
        if kind == .geometry, let t = seg.targetID, let f = functions.first(where: { $0.id == t }) { delete(f, keepInk: true) }
        switch kind {
        case .function, .solve: recognizeMath(seg, kind)
        case .geometry: buildGeometry(seg)
        }
    }

    // MARK: 函数

    /// 函数和求解走同一条路：认出来是 f'(x) 就求导；是极限、积分、求和、方程、算式（或者选的就是「求解」）就算出来；
    /// 是 f(x) = … 就作图。
    private func recognizeMath(_ seg: InkSegment, _ kind: SegmentKind) {
        let target = functions.first { $0.id == seg.targetID }
        let lineID = target?.lineID ?? nextLineID(kind == .solve ? "D" : "F")
        let revision = (target?.revision ?? 0) + 1
        target?.revision = revision
        let line = makeLine(lineID, revision: revision, mode: kind.mode, seg)
        let pk = seg.strokeIDs.compactMap { pkByID[$0] }
        let job = BusySegment(bounds: seg.bounds, kind: kind)
        busy.append(job)
        let png = PencilKitBridge.png(of: line, in: drawing, ids: &ids)
        let recognizer = Self.makeRecognizer(strokes: pk)
        Task { @MainActor [weak self] in
            defer { self?.busy.removeAll { $0.id == job.id } }
            do {
                let r = try await recognizer.recognize(line: line, imagePNG: png)
                self?.finishFunction(seg, result: r, target: target, lineID: lineID, revision: revision, ink: pk, kind: kind)
            } catch {
                self?.toast("没认出来：\(AppModel.describe(error))", at: CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24), .warning)
            }
        }
    }

    private func finishFunction(_ seg: InkSegment, result r: RecognitionResult, target: FunctionItem?,
                                lineID: String, revision: Int, ink: [PKStroke], kind: SegmentKind = .function) {
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
        if let request = DerivativeRequest.parse(latex) {
            finishDerivative(seg, request: request, result: r, target: target, lineID: lineID, revision: revision, ink: ink)
            return
        }
        let table = functionTable(excluding: target?.id)
        if kind == .solve || Solver.looksLikeComputation(latex, functions: table) {
            if finishSolve(seg, latex: latex, result: r, target: target, lineID: lineID, revision: revision, ink: ink, functions: table) {
                return
            }
            // 选了「求解」，写的却是一条普通函数：照常作图
        }
        // 原来是算出来的那一项（导数、求解），改写成了普通的函数：当作一条新函数
        if let target, target.isComputed { delete(target, keepInk: true) }
        let reuse = (target?.isComputed ?? true) ? nil : target

        // 标准式子放在原来那行笔迹的位置：左对齐，竖直居中，字号跟着手写的大小走
        let fontSize = min(max(seg.bounds.height * 0.62, 24), 64)
        let size = MathLabel.measure(latex, fontSize: fontSize)
        let origin = CGPoint(x: seg.bounds.minX, y: seg.bounds.midY - size.height / 2)

        let item: FunctionItem
        if let reuse {
            item = reuse
            item.latex = latex
            item.origin = origin
            item.fontSize = fontSize
            item.size = size
        } else {
            let frame = CGRect(origin: origin, size: size)
            item = FunctionItem(lineID: lineID, latex: latex, origin: origin, fontSize: fontSize, size: size,
                                card: placeCard(next: frame, size: CGSize(width: 360, height: 252)),
                                tint: Theme.curve(functions.filter { !$0.isComputed }.count))
            item.revision = revision
        }
        item.engine = r.engine
        item.ms = r.ms
        apply(latex: latex, to: item)
        replaceInk(seg, ink: ink, with: item, isNew: reuse == nil)
        // 新函数加进来之后，之前写的、当时还找不到它的求解再算一次
        if reuse == nil { recomputeSolutions(using: item.name) }
    }

    /// 笔迹淡出、式子淡入，然后把这段笔迹从画布上收走（「改笔迹」时再放回来）。
    private func replaceInk(_ seg: InkSegment, ink: [PKStroke], with item: FunctionItem, isNew: Bool) {
        item.ink = ink
        item.inkIDs = seg.strokeIDs
        item.inkSourceIDs = seg.strokeIDs
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
            if isNew { functions.append(item) }
        }
        removeStrokes(Set(seg.strokeIDs))
    }

    /// 解析式子、建或换函数图像。右边可以用前面写过的函数：g(x) = f(x) + 1。
    private func apply(latex: String, to item: FunctionItem) {
        do {
            let d = try FunctionDefinition.parse(latex, functions: functionTable(excluding: item.id))
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
        recomputeDerivatives(of: item)
        recomputeSolutions(using: item.name)
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
        // 改的是求导那一行（比如 f'(x) 改成 f''(x)）：重新求
        if let request = DerivativeRequest.parse(tex), item.derivedFrom != nil || item.graph == nil {
            if let parent = parentFunction(for: request, near: item.frame) {
                withAnimation(.easeOut(duration: 0.2)) { setDerivative(item, request: request, parent: parent) }
            } else {
                toast("先写 \(request.name)(x) = …，再写 \(request.name)'(x)", at: CGPoint(x: item.frame.midX, y: item.frame.maxY + 26), .warning)
            }
            return
        }
        // 求解那一行改了，或者把一条函数改成了要算的式子：重新算
        let table = functionTable(excluding: item.id)
        if item.solveSource != nil || Solver.looksLikeComputation(tex, functions: table) {
            let outcome: Result<Solution?, Error> = Result { try Solver.solve(tex, functions: table) }
            if case .success(.none) = outcome {
                // 改成了一条普通函数
                if item.solveSource != nil { convertToFunction(item, latex: tex) ; return }
            } else {
                guard let target = item.solveSource != nil ? item : convertToComputed(item) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    target.solveSource = tex
                    target.engine = "手动"
                    setSolution(target, outcome.map { $0! })
                }
                return
            }
        }
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
        toast("改完后双击笔身，选「\(item.isComputed ? "求解" : "函数")」重新识别",
              at: CGPoint(x: item.frame.midX, y: item.frame.maxY + 26), .info)
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
        withAnimation(.easeOut(duration: 0.2)) {
            functions.removeAll { $0.id == item.id }
            // 删掉的是导数：这条函数没有别的导数了，图像里的导函数也收起来
            if let p = item.derivedFrom, let parent = functions.first(where: { $0.id == p }),
               !functions.contains(where: { $0.derivedFrom == p }) {
                parent.graph?.reveal = false
            }
            // 删掉的是求解：标在图像上的面积、点也去掉
            for f in functions { f.graph?.removeOverlay(id: item.id.uuidString) }
        }
        // 删掉的是函数：用到它的求解重新算（会提示它没有了）
        if !item.isComputed { recomputeSolutions(using: item.name) }
    }

    /// 拖动式子：卡片一起走。
    func move(_ item: FunctionItem, by d: CGSize) {
        item.origin.x += d.width
        item.origin.y += d.height
        item.card.center.x += d.width
        item.card.center.y += d.height
    }

    /// 卡片的滑条改了多项式系数或参数：式子跟着重写，下面求出来的导数也跟着变。
    func coefficientsChanged(_ item: FunctionItem) {
        item.rewriteFromTerms()
        recomputeDerivatives(of: item)
        recomputeSolutions(using: item.name)
    }

    // MARK: 求导

    /// 学生在函数下面写了 f'(x)：找到上面那条 f(x) = …，直接把导函数求出来，换成标准式子（求出来的部分是绿的），
    /// 并在 f 的图像里画出导函数、极值点和水平切线。等号后面学生写了什么都不看。
    private func finishDerivative(_ seg: InkSegment, request: DerivativeRequest, result r: RecognitionResult,
                                  target: FunctionItem?, lineID: String, revision: Int, ink: [PKStroke]) {
        let below = CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24)
        guard let parent = parentFunction(for: request, near: seg.bounds, excluding: target?.id) else {
            toast("先写 \(request.name)(x) = …（双击后选「函数」），再写 \(request.name)'(x)", at: below, .warning)
            return
        }
        // 还原笔迹改成了求导的那一项原来是一条函数：它的卡片不要了
        if let target, target.derivedFrom == nil, target.graph != nil {
            if functions.contains(where: { $0.derivedFrom == target.id }) {
                toast("这一行原来是别的导数的来源，先删掉下面的导数再改", at: below, .warning)
                return
            }
            delete(target, keepInk: true)
        }
        // 原来是一条求解，改写成了 f'(x)
        if let target, target.solveSource != nil { delete(target, keepInk: true) }
        let reuse = target?.derivedFrom != nil ? target : nil
        let fontSize = min(max(seg.bounds.height * 0.62, 24), 64)
        let item = reuse ?? FunctionItem(lineID: lineID, latex: "", origin: .zero, fontSize: fontSize, size: .zero,
                                         card: CardFrame(center: .zero, size: .zero, minimized: true), tint: Theme.ok)
        item.revision = revision
        item.fontSize = fontSize
        item.engine = r.engine
        item.ms = r.ms
        setDerivative(item, request: request, parent: parent)
        item.origin = CGPoint(x: seg.bounds.minX, y: seg.bounds.midY - item.size.height / 2)
        replaceInk(seg, ink: ink, with: item, isNew: reuse == nil)
    }

    /// 对哪条函数求导：名字对得上的（大小写都认），写在这一行上面、离得最近的那条；没有就取最后写的那条。
    private func parentFunction(for request: DerivativeRequest, near rect: CGRect, excluding: UUID? = nil) -> FunctionItem? {
        let named = functions.filter { $0.derivedFrom == nil && $0.definition != nil && $0.id != excluding }
        let exact = named.filter { $0.definition?.name == request.name }
        let pool = exact.isEmpty ? named.filter { $0.definition?.name.lowercased() == request.name.lowercased() } : exact
        let above = pool.filter { $0.frame.minY < rect.minY }
        return above.max { $0.frame.minY < $1.frame.minY } ?? pool.last
    }

    /// 求出来写进这一项：f'(x) = 2x（f'(2) = 4 这种在一点取值的也行）。
    private func setDerivative(_ item: FunctionItem, request: DerivativeRequest, parent: FunctionItem) {
        guard let d = parent.definition else { return }
        var body = d.body
        for _ in 0..<request.order { body = body.derivative(d.variable) }
        var named = request
        named.name = d.name
        let lhs = named.lhsLatex(variable: d.variable)
        let rhs: String
        if let p = request.point {
            var env: [String: Double] = [:]
            for param in parent.graph?.params ?? [] { env[param.name] = param.value }
            env[d.variable] = p
            rhs = MathExpr.formatNumber(body.evaluate(env))
        } else {
            rhs = body.latex
        }
        item.solveSource = nil
        item.solution = nil
        item.derivedFrom = parent.id
        item.request = request
        item.lhsLatex = lhs
        item.resultLatex = rhs
        item.latex = lhs + "=" + rhs
        item.definition = FunctionDefinition(name: d.name + String(repeating: "'", count: request.order), variable: d.variable, body: body)
        item.problem = nil
        item.size = MathLabel.measure(item.displayLatex, fontSize: item.fontSize)
        parent.graph?.reveal = true
        if parent.card.minimized { parent.card.minimized = false }
    }

    /// 函数改了（重新识别、改式子、拖滑条）：下面求出来的导数跟着重新求。
    private func recomputeDerivatives(of parent: FunctionItem) {
        for child in functions where child.derivedFrom == parent.id {
            if let request = child.request, parent.definition != nil {
                setDerivative(child, request: request, parent: parent)
            }
        }
    }

    // MARK: 求解

    /// 画板上已经写过的函数（按名字，后写的算数），滑条上的参数取当前值：求解里的 f(x)、f'(2) 用它。
    private func functionTable(excluding id: UUID? = nil) -> [String: FunctionDefinition] {
        var table: [String: FunctionDefinition] = [:]
        for f in functions where !f.isComputed && f.id != id {
            guard var d = f.definition else { continue }
            for p in f.graph?.params ?? [] { d.body = d.body.substituting(p.name, with: .number(p.value)) }
            d.parameters = d.body.symbols.subtracting([d.variable]).sorted()
            table[d.name] = d
        }
        return table
    }

    /// 写的是要算的东西：算出来，换成标准式子（结果是绿的）。返回 false：其实是一条普通函数，交给作图。
    private func finishSolve(_ seg: InkSegment, latex: String, result r: RecognitionResult, target: FunctionItem?,
                             lineID: String, revision: Int, ink: [PKStroke], functions table: [String: FunctionDefinition]) -> Bool {
        let outcome: Result<Solution, Error>
        do {
            guard let s = try Solver.solve(latex, functions: table) else { return false }
            outcome = .success(s)
        } catch {
            outcome = .failure(error)
        }
        let below = CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24)
        // 还原笔迹改成了要算的式子的那一项原来是一条函数：它的卡片不要了
        if let target, !target.isComputed {
            if !dependents(of: target).isEmpty {
                toast("下面还有用到 \(target.name)(x) 的式子，先删掉它们再改", at: below, .warning)
                return true
            }
            delete(target, keepInk: true)
        }
        if let target, target.derivedFrom != nil { delete(target, keepInk: true) }
        let reuse = target?.solveSource != nil ? target : nil
        let fontSize = min(max(seg.bounds.height * 0.62, 24), 64)
        let item = reuse ?? FunctionItem(lineID: lineID, latex: latex, origin: .zero, fontSize: fontSize, size: .zero,
                                         card: CardFrame(center: .zero, size: .zero, minimized: true), tint: Theme.ok)
        item.revision = revision
        item.fontSize = fontSize
        item.engine = r.engine
        item.ms = r.ms
        item.solveSource = latex
        setSolution(item, outcome)
        item.origin = CGPoint(x: seg.bounds.minX, y: seg.bounds.midY - item.size.height / 2)
        replaceInk(seg, ink: ink, with: item, isNew: reuse == nil)
        return true
    }

    /// 把算出来的结果写进这一项，图像上的标注跟着换。
    private func setSolution(_ item: FunctionItem, _ outcome: Result<Solution, Error>) {
        item.derivedFrom = nil
        item.request = nil
        item.lhsLatex = nil
        item.resultLatex = nil
        item.definition = nil
        switch outcome {
        case .success(let s):
            item.solution = s
            item.problem = nil
            item.latex = s.input
        case .failure(let e):
            item.solution = nil
            item.problem = Self.describe(e)
            item.latex = item.solveSource ?? item.latex
        }
        item.size = MathLabel.measure(item.displayLatex, fontSize: item.fontSize)
        updateOverlay(for: item)
    }

    /// ∫_a^b f(x)dx 在 f 的图像上涂出面积，lim_{x→a} f(x) 标出那一点。
    private func updateOverlay(for item: FunctionItem) {
        let key = item.id.uuidString
        for f in functions { f.graph?.removeOverlay(id: key) }
        guard let s = item.solution, let hint = s.hint else { return }
        let value = s.result.map(Solver.plainText) ?? ""
        var name = "", kind = GraphOverlay.Kind.point(x: 0, y: 0), label = ""
        switch hint {
        case .area(let fn, let a, let b):
            name = fn
            kind = .area(from: a, to: b)
            label = "∫ = " + value
        case .point(let fn, let x, let y):
            name = fn
            kind = .point(x: x, y: y)
            label = "lim = " + value
        }
        guard let parent = functions.last(where: { !$0.isComputed && $0.definition?.name == name }), let graph = parent.graph else { return }
        graph.setOverlay(GraphOverlay(id: key, kind: kind, label: label))
        if parent.card.minimized { parent.card.minimized = false }
    }

    /// 用到 name 这条函数的求解（以及上次没算成的）重新算。
    private func recomputeSolutions(using name: String?) {
        for item in functions where item.solveSource != nil {
            guard let src = item.solveSource else { continue }
            let uses = name.map { item.solution?.references.contains($0) ?? false } ?? true
            guard uses || item.solution == nil || item.solution?.result == nil else { continue }
            let table = functionTable(excluding: item.id)
            let outcome: Result<Solution, Error>
            do {
                // 这一行现在看起来像一条函数定义（f(x) = 0 里的 f 删掉了）
                guard let s = try Solver.solve(src, functions: table) else {
                    setSolution(item, .failure(MissingFunction()))
                    continue
                }
                outcome = .success(s)
            } catch {
                outcome = .failure(error)
            }
            setSolution(item, outcome)
        }
    }

    /// 用到这条函数的式子：求出来的导数、求解里引用了它的。
    private func dependents(of f: FunctionItem) -> [FunctionItem] {
        functions.filter { $0.derivedFrom == f.id || ($0.solution?.references.contains(f.name) ?? false) }
    }

    /// 手动把一条函数改成了要算的式子：换成一条求解（卡片不要了）。下面有用到它的式子时不改。
    private func convertToComputed(_ item: FunctionItem) -> FunctionItem? {
        if !dependents(of: item).isEmpty {
            toast("下面还有用到 \(item.name)(x) 的式子，先删掉它们再改", at: CGPoint(x: item.frame.midX, y: item.frame.maxY + 26), .warning)
            return nil
        }
        let new = FunctionItem(lineID: item.lineID, latex: item.latex, origin: item.origin, fontSize: item.fontSize, size: item.size,
                               card: CardFrame(center: .zero, size: .zero, minimized: true), tint: Theme.ok)
        replaceItem(item, with: new)
        return new
    }

    /// 手动把一条求解改成了普通函数：换成一条带卡片的函数。
    private func convertToFunction(_ item: FunctionItem, latex: String) {
        let size = MathLabel.measure(latex, fontSize: item.fontSize)
        let frame = CGRect(origin: item.origin, size: size)
        let new = FunctionItem(lineID: item.lineID, latex: latex, origin: item.origin, fontSize: item.fontSize, size: size,
                               card: placeCard(next: frame, size: CGSize(width: 360, height: 252)),
                               tint: Theme.curve(functions.filter { !$0.isComputed }.count))
        withAnimation(.easeOut(duration: 0.2)) {
            replaceItem(item, with: new)
            new.engine = "手动"
            apply(latex: latex, to: new)
        }
    }

    /// 原地换掉一项（笔迹跟着走），图像上它的标注去掉。
    private func replaceItem(_ old: FunctionItem, with new: FunctionItem) {
        new.ink = old.ink
        new.inkSourceIDs = old.inkSourceIDs
        new.engine = old.engine
        new.ms = old.ms
        for f in functions { f.graph?.removeOverlay(id: old.id.uuidString) }
        if let i = functions.firstIndex(where: { $0.id == old.id }) { functions[i] = new } else { functions.append(new) }
        if selection?.id == old.id { selection = .formula(new.id) }
        // 换掉的是导数：原函数没有别的导数了，导函数收起来
        if let p = old.derivedFrom, let parent = functions.first(where: { $0.id == p }),
           !functions.contains(where: { $0.derivedFrom == p }) {
            parent.graph?.reveal = false
        }
    }

    private struct MissingFunction: LocalizedError {
        var errorDescription: String? { "用到的函数已经删掉了" }
    }

    static func operationTitle(_ op: Solution.Operation) -> String {
        switch op {
        case .derivative: return "求导"
        case .integral: return "积分"
        case .limit: return "求极限"
        case .series: return "求和"
        case .equation: return "解方程"
        case .evaluate: return "计算"
        }
    }

    // MARK: 几何

    /// 选「几何」：认出草图里的平面图形（圆、椭圆、正方形、三角形……）和立体图形（正方体、圆柱、圆锥、球……），
    /// 换成标准的图形画在原处，选中后拖节点改。三角形加中线的草图沿用 P3 的动态几何卡片（中点、重心跟着拖）。
    private func buildGeometry(_ seg: InkSegment) {
        let s = strokes.filter { seg.strokeIDs.contains($0.id) }
        if let sketch = GeometrySketchRecognizer.recognize(strokes: s), !sketch.relations.isEmpty, let json = try? sketch.jsonData(),
           let scene = try? JSONDecoder().decode(GeometryScene.self, from: json) {
            buildMedianCard(seg, scene: scene)
            return
        }
        let figures = ShapeRecognizer.recognize(strokes: s)
        guard !figures.isEmpty else {
            toast("没认出图形：线画直一点、圈画圆一点再试", at: CGPoint(x: seg.bounds.midX, y: seg.bounds.maxY + 24), .warning)
            return
        }
        let ink = seg.strokeIDs.compactMap { pkByID[$0] }
        fadeOut(ink, in: seg.bounds)
        removeStrokes(Set(seg.strokeIDs))
        let group = UUID()
        let items = figures.enumerated().map { ShapeItem(figure: $0.element, group: group, ink: $0.offset == 0 ? ink : []) }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { shapes += items }
        // 选中最大的那个：节点一出来就知道能拖
        if let main = items.max(by: { $0.figure.bounds.width * $0.figure.bounds.height < $1.figure.bounds.width * $1.figure.bounds.height }) {
            selection = .shape(main.id)
        }
    }

    private func fadeOut(_ ink: [PKStroke], in rect: CGRect) {
        guard let image = snapshot(of: ink, in: rect) else { return }
        let ghost = InkGhost(image: image, frame: rect.insetBy(dx: -6, dy: -6))
        ghosts.append(ghost)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.ghosts.removeAll { $0.id == ghost.id } }
    }

    /// 拖节点、旋转、改视角之后的样子。
    func update(_ item: ShapeItem, to figure: Figure) {
        item.figure = figure
    }

    /// 三视图按钮：平滑地转到主视、左视、俯视或斜着看（只动视角，尺寸、位置不变）。
    func turn(_ item: ShapeItem, to target: Solid3) {
        guard case .solid(let from) = item.figure else { return }
        turnTask?.cancel()
        let dYaw = atan2(sin(target.yaw - from.yaw), cos(target.yaw - from.yaw))
        turnTask = Task { @MainActor in
            let steps = 22
            for k in 1...steps {
                try? await Task.sleep(nanoseconds: 15_000_000)
                if Task.isCancelled { return }
                let t = Double(k) / Double(steps)
                let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                guard case .solid(var s) = item.figure else { return }
                s.yaw = from.yaw + dYaw * ease
                s.pitch = from.pitch + (target.pitch - from.pitch) * ease
                item.figure = .solid(s)
            }
        }
    }

    /// 「变立体」：正方形 → 正方体，圆 → 圆柱……
    func extrude(_ item: ShapeItem, to kind: Solid3.Kind) {
        guard let f = item.figure.extruded(kind) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { item.figure = f }
    }

    /// 把这一组图形收回成原来的笔迹。
    func restoreInk(_ item: ShapeItem) {
        let group = shapes.filter { $0.group == item.group }
        var d = drawing
        d.strokes.append(contentsOf: group.flatMap(\.ink))
        setDrawing(d)
        if let sel = selection, group.contains(where: { $0.id == sel.id }) { selection = nil }
        withAnimation(.easeOut(duration: 0.2)) { shapes.removeAll { $0.group == item.group } }
    }

    func delete(_ item: ShapeItem) {
        if selection?.id == item.id { selection = nil }
        // 笔迹交给同组的下一个图形，「还原笔迹」还找得回来
        if !item.ink.isEmpty, let heir = shapes.first(where: { $0.group == item.group && $0.id != item.id }) {
            heir.ink = item.ink
        }
        withAnimation(.easeOut(duration: 0.2)) { shapes.removeAll { $0.id == item.id } }
    }

    private func buildMedianCard(_ seg: InkSegment, scene: GeometryScene) {
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
            geometries = []
            shapes = []
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
    /// 启动参数 `-demo menu|card|reveal|solve`：摆出几个典型画面，不用真机也能看界面。识别结果直接给定，不走识别器。
    /// - menu：写完 f(x)=x³−5x 双击，笔尖旁的菜单
    /// - card：标准式子 + 选中的函数卡片（转了一点）+ 一条收起的函数
    /// - reveal：f(x)=x²−4，下面写 f'(x) 求出来的 2x，卡片里画出导函数
    /// - solve：f(x)=x²−4，下面写 ∫_0^2 f(x)dx（卡片里涂出面积）、lim_{x→0} sin x / x、∑_{k=1}^n k²，选「求解」
    func loadDemo(_ name: String) {
        if name == "solve" {
            loadSolveDemo()
            return
        }
        if name == "shapes" || name == "solids" {
            loadShapesDemo(solids: name == "solids")
            return
        }
        clear()
        let left: CGFloat = 120
        if name == "menu" {
            setDrawing(PKDrawing(strokes: DemoInk.strokes("f(x)=x^3-5x", at: CGPoint(x: left, y: 226), height: 54)))
            let ink = InkSegmenter.bounds(of: strokes)
            pencilDoubleTapped(at: CGPoint(x: ink.maxX + 18, y: ink.maxY - 4))
            return
        }
        let reveal = name == "reveal"
        let text = reveal ? "f(x)=x^2-4" : "f(x)=x^3-3x"
        setDrawing(PKDrawing(strokes: DemoInk.strokes(text, at: CGPoint(x: left, y: 226), height: 54)))
        guard let seg = segment(near: nil) else { return }
        finishFunction(seg, result: RecognitionResult(lineID: "F1", revision: 1, latex: reveal ? "f\\left( x\\right) =x^{2}-4" : "f\\left( x\\right) =x^{3}-3x",
                                                      engine: "MyScript", ms: 164),
                       target: nil, lineID: nextLineID("F"), revision: 1, ink: seg.strokeIDs.compactMap { pkByID[$0] })
        guard let f = functions.first else { return }
        if reveal {
            // 在下面写 f'(x)，求出来
            var d = drawing
            d.strokes.append(contentsOf: DemoInk.strokes("f'(x)", at: CGPoint(x: left, y: 470), height: 54,
                                                         start: Date(timeIntervalSinceReferenceDate: 800_000_100)))
            setDrawing(d)
            if let seg2 = segment(near: nil) {
                finishDerivative(seg2, request: DerivativeRequest(name: "f", order: 1, variable: "x"),
                                 result: RecognitionResult(lineID: "D1", revision: 1, latex: "f^{\\prime}\\left( x\\right)", engine: "MyScript", ms: 121),
                                 target: nil, lineID: nextLineID("D"), revision: 1, ink: seg2.strokeIDs.compactMap { pkByID[$0] })
            }
            // 顺便看橡皮选中、式子操作条的样子
            eraserOn = true
            if let df = functions.first(where: { $0.derivedFrom != nil }) { selection = .formula(df.id) }
            f.card.size = CGSize(width: 430, height: 330)
            f.card.center = CGPoint(x: f.anchor.x + 24 + 215, y: max(f.anchor.y - 12 - 165, topInset + 175))
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

    /// -demo shapes：手画的正方形、椭圆、直角三角形认出来，椭圆选中（焦点、节点）。
    /// -demo solids：手画的正方体、圆柱、圆锥认出来，正方体选中（尺寸节点、拖动旋转、三视图）。
    private func loadShapesDemo(solids: Bool) {
        clear()
        var clock = 800_000_000.0
        func draw(_ sketch: [[CGPoint]]) {
            var d = drawing
            for pts in sketch {
                clock += 1
                d.strokes.append(DemoInk.freehand(pts, start: Date(timeIntervalSinceReferenceDate: clock)))
            }
            setDrawing(d)
            if let seg = segment(near: nil) { buildGeometry(seg) }
        }
        let y: CGFloat = 400
        if !solids {
            // 正方形歪了 2°：认出来会摆正
            let c = CGPoint(x: 250, y: y)
            let ct: CGFloat = cos(0.04), st: CGFloat = sin(0.04)
            let offsets: [CGPoint] = [CGPoint(x: -95, y: -95), CGPoint(x: 95, y: -95), CGPoint(x: 95, y: 95),
                                      CGPoint(x: -95, y: 95), CGPoint(x: -95, y: -95)]
            let sq = offsets.map { (o: CGPoint) -> CGPoint in
                CGPoint(x: c.x + o.x * ct - o.y * st, y: c.y + o.x * st + o.y * ct)
            }
            // 正方形四笔画，角上留了缝；三角形三笔画，每笔都画过了头：一样认成一个图形
            draw(zip(sq, sq.dropFirst()).map { pair -> [CGPoint] in
                let (p, q) = DemoInk.extend(pair.0, pair.1, by: -9)
                return DemoInk.segment(p, q)
            })
            draw([DemoInk.arc(CGPoint(x: 640, y: y), 160, 88, from: 0.2, to: 0.2 + 2.05 * .pi)])
            let a = CGPoint(x: 940, y: y - 120), b = CGPoint(x: 944, y: y + 110), t = CGPoint(x: 1180, y: y + 108)
            let sides: [(CGPoint, CGPoint)] = [(a, b), (b, t), (t, a)]
            draw(sides.map { e -> [CGPoint] in
                let (p, q) = DemoInk.extend(e.0, e.1, by: 16)
                return DemoInk.segment(p, q)
            })
            if let e = shapes.first(where: { if case .ellipse = $0.figure { return true }; return false }) { selection = .shape(e.id) }
        } else {
            // 正方体：前后两个正方形 + 四条连线
            let f = [CGPoint(x: 140, y: 340), CGPoint(x: 310, y: 340), CGPoint(x: 310, y: 510), CGPoint(x: 140, y: 510)]
            let back = f.map { CGPoint(x: $0.x + 80, y: $0.y - 70) }
            let loop = { (v: [CGPoint]) in (0..<4).flatMap { DemoInk.segment(v[$0], v[($0 + 1) % 4]) } }
            draw([loop(f), loop(back)] + (0..<4).map { DemoInk.segment(f[$0], back[$0]) })
            // 圆柱：上底整个椭圆、下底前半个、两条母线
            let top = CGPoint(x: 640, y: 290), bottom = CGPoint(x: 640, y: 520)
            draw([DemoInk.arc(top, 105, 32), DemoInk.segment(CGPoint(x: 535, y: 292), CGPoint(x: 536, y: 518)),
                  DemoInk.segment(CGPoint(x: 745, y: 290), CGPoint(x: 744, y: 521)), DemoInk.arc(bottom, 105, 32, from: 0, to: .pi)])
            // 圆锥：底面 + 交于顶点的两条线
            let base = CGPoint(x: 1040, y: 520), apex = CGPoint(x: 1042, y: 270)
            draw([DemoInk.arc(base, 110, 34), DemoInk.segment(apex, CGPoint(x: 930, y: 520)), DemoInk.segment(apex, CGPoint(x: 1150, y: 520))])
            if let cube = shapes.first(where: { if case .solid(let s) = $0.figure { return s.kind == .cube }; return false }) {
                selection = .shape(cube.id)
            }
        }
    }

    private func loadSolveDemo() {
        clear()
        let left: CGFloat = 120
        setDrawing(PKDrawing(strokes: DemoInk.strokes("f(x)=x^2-4", at: CGPoint(x: left, y: 200), height: 50)))
        guard let seg = segment(near: nil) else { return }
        finishFunction(seg, result: RecognitionResult(lineID: "F1", revision: 1, latex: "f\\left( x\\right) =x^{2}-4", engine: "MyScript", ms: 152),
                       target: nil, lineID: nextLineID("F"), revision: 1, ink: seg.strokeIDs.compactMap { pkByID[$0] })
        guard let f = functions.first else { return }
        // 笔迹只是占位（马上换成标准式子），识别结果直接给定
        let lines: [(ink: String, latex: String, y: CGFloat)] = [
            ("∫f(x)dx", "\\int _{0}^{2}f\\left( x\\right) dx", 390),
            ("x-2", "\\lim _{x\\rightarrow 0}\\dfrac{\\sin x}{x}", 520),
            ("2x", "\\sum _{k=1}^{n}k^{2}", 650),
        ]
        for (i, line) in lines.enumerated() {
            var d = drawing
            d.strokes.append(contentsOf: DemoInk.strokes(line.ink, at: CGPoint(x: left, y: line.y), height: 46,
                                                         start: Date(timeIntervalSinceReferenceDate: 800_000_100 + Double(i) * 60)))
            setDrawing(d)
            guard let s = segment(near: nil) else { continue }
            finishFunction(s, result: RecognitionResult(lineID: "D\(i + 1)", revision: 1, latex: line.latex, engine: "MyScript", ms: 138 + i * 11),
                           target: nil, lineID: nextLineID("D"), revision: 1, ink: s.strokeIDs.compactMap { pkByID[$0] }, kind: .solve)
        }
        if let integral = functions.first(where: { $0.solution?.operation == .integral }) { selection = .formula(integral.id) }
        f.card.size = CGSize(width: 430, height: 330)
        f.card.center = CGPoint(x: max(f.anchor.x, 640) + 24 + 215, y: max(f.anchor.y - 12 - 165, topInset + 175))
    }
}
