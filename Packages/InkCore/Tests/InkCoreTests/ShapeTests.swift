import XCTest
@testable import InkCore

/// 几何：手画的平面 / 立体草图认成图形，拖节点，立体图形的投影和虚线。
final class ShapeRecognizerTests: XCTestCase {
    // MARK: 造笔画（带手抖）

    private var seed: UInt64 = 7

    private func noise() -> CGFloat {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(seed >> 33) / Double(1 << 31)) - 0.5
    }

    private func shake(_ pts: [CGPoint], _ amp: CGFloat = 2) -> [CGPoint] {
        pts.map { CGPoint(x: $0.x + noise() * amp, y: $0.y + noise() * amp) }
    }

    private func line(_ a: CGPoint, _ b: CGPoint, n: Int = 24) -> [CGPoint] {
        (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    private func path(_ vs: [CGPoint], closed: Bool = true) -> [CGPoint] {
        var out: [CGPoint] = []
        let ends = closed ? vs + [vs[0]] : vs
        for i in 1..<ends.count { out += line(ends[i - 1], ends[i]).dropFirst(i == 1 ? 0 : 1) }
        return out
    }

    private func arc(_ c: CGPoint, _ a: CGFloat, _ b: CGFloat, angle: CGFloat = 0,
                     from t0: CGFloat = 0, to t1: CGFloat = 2 * CGFloat.pi, n: Int = 90) -> [CGPoint] {
        var out: [CGPoint] = []
        let ca: CGFloat = cos(angle), sa: CGFloat = sin(angle)
        for i in 0...n {
            let t: CGFloat = t0 + (t1 - t0) * CGFloat(i) / CGFloat(n)
            let x: CGFloat = a * cos(t), y: CGFloat = b * sin(t)
            let rx: CGFloat = x * ca - y * sa, ry: CGFloat = x * sa + y * ca
            out.append(CGPoint(x: c.x + rx, y: c.y + ry))
        }
        return out
    }

    /// 以 c 为中心、半径 r、角度 t（弧度）的点。
    private func polar(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> CGPoint {
        let dx: CGFloat = r * cos(t), dy: CGFloat = r * sin(t)
        return CGPoint(x: c.x + dx, y: c.y + dy)
    }

    private var clock = 0.0

    private func s(_ pts: [CGPoint], amp: CGFloat = 1.5) -> InkStroke {
        let p = shake(pts, amp)
        clock += 1
        let b = Geo.bounds(p)
        return InkStroke(id: "s\(Int(clock))", bounds: b, createdAt: Date(timeIntervalSince1970: clock), points: p)
    }

    private func recognize(_ strokes: [InkStroke]) -> [Figure] { ShapeRecognizer.recognize(strokes: strokes) }

    private func only(_ strokes: [InkStroke], file: StaticString = #filePath, line: UInt = #line) -> Figure? {
        let figs = recognize(strokes)
        XCTAssertEqual(figs.count, 1, "\(figs)", file: file, line: line)
        return figs.first
    }

    // MARK: 平面图形

    func testCircle() throws {
        guard case .ellipse(let e)? = only([s(arc(CGPoint(x: 300, y: 300), 80, 76))]) else { return XCTFail() }
        XCTAssertTrue(e.isCircle)
        XCTAssertEqual(e.a, 78, accuracy: 4)
        XCTAssertEqual(e.center.x, 300, accuracy: 4)
        XCTAssertEqual(Figure.ellipse(e).name, "圆")
    }

    func testRotatedEllipse() throws {
        let t: CGFloat = 30 * .pi / 180
        guard case .ellipse(let e)? = only([s(arc(CGPoint(x: 400, y: 300), 130, 62, angle: t))]) else { return XCTFail() }
        XCTAssertFalse(e.isCircle)
        XCTAssertEqual(e.a, 130, accuracy: 6)
        XCTAssertEqual(e.b, 62, accuracy: 5)
        XCTAssertEqual(e.angle, t, accuracy: 0.06)
        XCTAssertEqual(Figure.ellipse(e).name, "椭圆")
    }

    func testNearlyLevelEllipseIsLevelled() throws {
        guard case .ellipse(let e)? = only([s(arc(CGPoint(x: 400, y: 300), 120, 60, angle: 0.05))]) else { return XCTFail() }
        XCTAssertEqual(e.angle, 0, accuracy: 1e-6)
    }

    func testSquareInOneStroke() throws {
        // 稍微歪了 3°、从一个角起笔
        let c = CGPoint(x: 300, y: 300)
        let corners = [CGPoint(x: c.x - 70, y: c.y - 70), CGPoint(x: c.x + 70, y: c.y - 70),
                       CGPoint(x: c.x + 70, y: c.y + 70), CGPoint(x: c.x - 70, y: c.y + 70)]
        let vs = corners.map { Geo.rotate($0, about: c, by: 0.05) }
        guard case .polygon(let p)? = only([s(path(vs))]) else { return XCTFail() }
        XCTAssertEqual(p.rule, .square)
        XCTAssertEqual(Figure.polygon(p).name, "正方形")
        // 放平了
        XCTAssertEqual(p.vertices[0].y, p.vertices[1].y, accuracy: 0.5)
        XCTAssertEqual(Geo.dist(p.vertices[0], p.vertices[1]), 140, accuracy: 8)
    }

    func testRectangleInFourStrokes() throws {
        let a = CGPoint(x: 100, y: 100), b = CGPoint(x: 400, y: 104), c = CGPoint(x: 398, y: 260), d = CGPoint(x: 102, y: 256)
        guard case .polygon(let p)? = only([s(line(a, b)), s(line(b, c)), s(line(c, d)), s(line(d, a))]) else { return XCTFail() }
        XCTAssertEqual(p.rule, .rectangle)
        XCTAssertEqual(Figure.polygon(p).facts.first, "长 7.5")
    }

    func testRightTriangleIsSnapped() throws {
        let a = CGPoint(x: 100, y: 100), b = CGPoint(x: 104, y: 300), c = CGPoint(x: 360, y: 300)
        guard case .polygon(let p)? = only([s(path([a, b, c]))]) else { return XCTFail() }
        XCTAssertEqual(Figure.polygon(p).name, "直角三角形")
        XCTAssertTrue(Geo.angles(p.vertices).contains { abs($0 - 90) < 0.01 })
        XCTAssertEqual(Set(p.labels), ["A", "B", "C"])
    }

    func testEquilateralTriangle() throws {
        let c = CGPoint(x: 300, y: 300)
        let degrees: [CGFloat] = [-90, 30, 150]
        // 稍微歪一点：一个顶点往右偏 4
        var vs = degrees.map { polar(c, 100, $0 * CGFloat.pi / 180) }
        vs[0].x += 4
        guard case .polygon(let p)? = only([s(path(vs))]) else { return XCTFail() }
        XCTAssertEqual(p.rule, .regular)
        XCTAssertEqual(Figure.polygon(p).name, "等边三角形")
        // 尖朝上，A 在最上面
        let top = p.vertices.indices.min { p.vertices[$0].y < p.vertices[$1].y }!
        XCTAssertEqual(p.labels[top], "A")
    }

    func testIsoscelesTriangle() throws {
        let vs = [CGPoint(x: 205, y: 80), CGPoint(x: 100, y: 320), CGPoint(x: 300, y: 318)]
        guard case .polygon(let p)? = only([s(path(vs))]) else { return XCTFail() }
        XCTAssertEqual(Figure.polygon(p).name, "等腰三角形")
    }

    func testRegularHexagon() throws {
        let c = CGPoint(x: 300, y: 300)
        let vs = (0..<6).map { (k: Int) -> CGPoint in polar(c, 90, CGFloat(k) * CGFloat.pi / 3) }
        guard case .polygon(let p)? = only([s(path(vs))]) else { return XCTFail() }
        XCTAssertEqual(p.rule, .regular)
        XCTAssertEqual(Figure.polygon(p).name, "正六边形")
    }

    func testParallelogramAndTrapezoid() throws {
        let para = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 360, y: 240), CGPoint(x: 160, y: 240)]
        guard case .polygon(let p)? = only([s(path(para))]) else { return XCTFail() }
        XCTAssertEqual(p.rule, .parallelogram)
        let trap = [CGPoint(x: 160, y: 100), CGPoint(x: 300, y: 104), CGPoint(x: 380, y: 260), CGPoint(x: 80, y: 260)]
        guard case .polygon(let q)? = only([s(path(trap))]) else { return XCTFail() }
        XCTAssertTrue(Figure.polygon(q).name.hasSuffix("梯形"), Figure.polygon(q).name)
    }

    func testSegmentAndScribble() throws {
        guard case .segment(let a, let b)? = only([s(line(CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 160)))]) else { return XCTFail() }
        XCTAssertEqual(Geo.dist(a, b), 306, accuracy: 6)
        // 乱涂的曲线：认不出
        var scribble: [CGPoint] = []
        for i in 0..<120 {
            let k = CGFloat(i)
            let wave: CGFloat = sin(k * 0.35) * cos(k * 0.11)
            scribble.append(CGPoint(x: 100 + k * 2, y: 200 + 40 * wave))
        }
        XCTAssertTrue(recognize([s(scribble)]).isEmpty)
    }

    func testSquareWithDiagonalsStaysPlanar() throws {
        let vs = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 300), CGPoint(x: 100, y: 300)]
        let figs = recognize([s(path(vs)), s(line(vs[0], vs[2])), s(line(vs[1], vs[3]))])
        XCTAssertEqual(figs.count, 3, "\(figs)")
        XCTAssertTrue(figs.contains { $0.name == "正方形" })
        XCTAssertEqual(figs.filter { if case .segment = $0 { return true }; return false }.count, 2)
    }

    // MARK: 立体图形

    /// 圆柱下底看不见的后半圈：一串短弧。
    private func dashedBackHalf(_ c: CGPoint) -> [InkStroke] {
        var out: [InkStroke] = []
        var t: CGFloat = CGFloat.pi + 0.1
        while t < 2 * CGFloat.pi {
            out.append(s(arc(c, 100, 30, from: t, to: t + 0.22, n: 6), amp: 0.6))
            t += 0.42
        }
        return out
    }

    func testCylinder() throws {
        let top = CGPoint(x: 300, y: 150), bottom = CGPoint(x: 300, y: 400)
        let strokes = [
            s(arc(top, 100, 30)),
            s(line(CGPoint(x: 200, y: 152), CGPoint(x: 201, y: 398))),
            s(line(CGPoint(x: 400, y: 150), CGPoint(x: 399, y: 401))),
            // 下底：前半个椭圆实线，后半个画成虚线
            s(arc(bottom, 100, 30, from: 0, to: .pi)),
        ] + dashedBackHalf(bottom)
        guard case .solid(let c)? = only(strokes) else { return XCTFail() }
        XCTAssertEqual(c.kind, .cylinder)
        XCTAssertEqual(c.dims[0], 100, accuracy: 8)
        XCTAssertEqual(c.center.y, 275, accuracy: 10)
        XCTAssertEqual(sin(c.pitch), 0.3, accuracy: 0.08)
    }

    /// 演示里那几张草图，换 30 种手抖都要认得出（扁的半个椭圆不能被当成直线）。
    func testSolidsAcrossManyHands() throws {
        for k in 1...30 {
            seed = UInt64(k) * 7919
            let top = CGPoint(x: 640, y: 290), bottom = CGPoint(x: 640, y: 520)
            let cyl = [s(arc(top, 105, 32)), s(line(CGPoint(x: 535, y: 292), CGPoint(x: 536, y: 518))),
                       s(line(CGPoint(x: 745, y: 290), CGPoint(x: 744, y: 521))), s(arc(bottom, 105, 32, from: 0, to: CGFloat.pi))]
            XCTAssertEqual(solidKind(cyl), .cylinder, "hand \(k)")
            let base = CGPoint(x: 1040, y: 520), apex = CGPoint(x: 1042, y: 270)
            let cone = [s(arc(base, 110, 34)), s(line(apex, CGPoint(x: 930, y: 520))), s(line(apex, CGPoint(x: 1150, y: 520)))]
            XCTAssertEqual(solidKind(cone), .cone, "hand \(k)")
            let f = [CGPoint(x: 140, y: 340), CGPoint(x: 310, y: 340), CGPoint(x: 310, y: 510), CGPoint(x: 140, y: 510)]
            let back = f.map { CGPoint(x: $0.x + 80, y: $0.y - 70) }
            let cube = [s(path(f)), s(path(back))] + (0..<4).map { s(line(f[$0], back[$0])) }
            XCTAssertEqual(solidKind(cube), .cube, "hand \(k)")
            // 平面图形也一样
            let c = CGPoint(x: 400, y: 400)
            let sq = [CGPoint(x: 300, y: 300), CGPoint(x: 500, y: 302), CGPoint(x: 498, y: 500), CGPoint(x: 302, y: 498)]
            XCTAssertEqual(recognize([s(path(sq), amp: 2.5)]).first?.name, "正方形", "hand \(k)")
            XCTAssertEqual(recognize([s(arc(c, 90, 88), amp: 2.5)]).first?.name, "圆", "hand \(k)")
            XCTAssertEqual(recognize([s(arc(c, 150, 70, angle: 0.3), amp: 2.5)]).first?.name, "椭圆", "hand \(k)")
            let rect = [CGPoint(x: 100, y: 100), CGPoint(x: 420, y: 100), CGPoint(x: 420, y: 260), CGPoint(x: 100, y: 260)]
            XCTAssertEqual(recognize((0..<4).map { s(line(rect[$0], rect[($0 + 1) % 4]), amp: 2.5) }).first?.name, "矩形", "hand \(k)")
            let tri = [CGPoint(x: 220, y: 90), CGPoint(x: 80, y: 330), CGPoint(x: 400, y: 300)]
            XCTAssertEqual(recognize([s(path(tri), amp: 2.5)]).first?.name.hasSuffix("三角形"), true, "hand \(k)")
        }
    }

    private func solidKind(_ strokes: [InkStroke]) -> Solid3.Kind? {
        let figs = recognize(strokes)
        guard figs.count == 1, case .solid(let s) = figs[0] else { return nil }
        return s.kind
    }

    func testCone() throws {
        let base = CGPoint(x: 300, y: 400), apex = CGPoint(x: 302, y: 120)
        let strokes = [s(arc(base, 110, 32)), s(line(apex, CGPoint(x: 190, y: 400))), s(line(apex, CGPoint(x: 410, y: 400)))]
        guard case .solid(let c)? = only(strokes) else { return XCTFail() }
        XCTAssertEqual(c.kind, .cone)
        XCTAssertEqual(c.dims[0], 110, accuracy: 8)
    }

    func testSphere() throws {
        let c = CGPoint(x: 300, y: 300)
        guard case .solid(let sp)? = only([s(arc(c, 120, 118)), s(arc(c, 118, 34))]) else { return XCTFail() }
        XCTAssertEqual(sp.kind, .sphere)
        XCTAssertEqual(sp.dims[0], 119, accuracy: 6)
    }

    func testCubeWithHiddenEdges() throws {
        // 前面一个正方形、后面一个错开的正方形、四条连线
        let f = [CGPoint(x: 100, y: 200), CGPoint(x: 260, y: 200), CGPoint(x: 260, y: 360), CGPoint(x: 100, y: 360)]
        let back = f.map { CGPoint(x: $0.x + 70, y: $0.y - 60) }
        let strokes = [s(path(f)), s(path(back))] + (0..<4).map { s(line(f[$0], back[$0])) }
        guard case .solid(let c)? = only(strokes) else { return XCTFail() }
        XCTAssertEqual(c.kind, .cube)
        XCTAssertEqual(c.dims[0], 168, accuracy: 15)
    }

    func testCubeOnlyVisibleEdges() throws {
        // 不画看不见的三条棱：7 个顶点、9 条棱，一笔一条
        let a = CGPoint(x: 100, y: 360), b = CGPoint(x: 260, y: 360), b1 = CGPoint(x: 260, y: 200), a1 = CGPoint(x: 100, y: 200)
        let d = CGPoint(x: 70, y: -60)
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.x, y: p.y + d.y) }
        let edges = [(a, b), (b, b1), (b1, a1), (a1, a), (a1, m(a1)), (b1, m(b1)), (b, m(b)), (m(a1), m(b1)), (m(b1), m(b))]
        guard case .solid(let c)? = only(edges.map { s(line($0.0, $0.1)) }) else { return XCTFail() }
        XCTAssertEqual(c.kind, .cube)
    }

    func testTetrahedronNeedsADashedEdge() throws {
        let p = CGPoint(x: 260, y: 80), a = CGPoint(x: 100, y: 300), b = CGPoint(x: 230, y: 380), c = CGPoint(x: 400, y: 290)
        var strokes = [(p, a), (p, b), (p, c), (a, b), (b, c)].map { s(line($0.0, $0.1)) }
        // AC 是看不见的棱：画成虚线
        let dashes = stride(from: 0.0, to: 1.0, by: 0.12).map { t -> InkStroke in
            let t0 = CGFloat(t), t1 = CGFloat(t + 0.06)
            return s(line(CGPoint(x: a.x + (c.x - a.x) * t0, y: a.y + (c.y - a.y) * t0),
                          CGPoint(x: a.x + (c.x - a.x) * t1, y: a.y + (c.y - a.y) * t1), n: 4), amp: 0.5)
        }
        strokes += dashes
        guard case .solid(let t)? = only(strokes) else { return XCTFail() }
        XCTAssertEqual(t.kind, .tetrahedron)
    }

    func testSizesAndShakierHands() throws {
        for (size, amp) in [(CGFloat(45), CGFloat(1)), (220, 3), (420, 4)] {
            let c = CGPoint(x: 600, y: 500)
            // 正方形从一条边的中间起笔
            let sq = [CGPoint(x: c.x, y: c.y - size), CGPoint(x: c.x + size, y: c.y - size), CGPoint(x: c.x + size, y: c.y + size),
                      CGPoint(x: c.x - size, y: c.y + size), CGPoint(x: c.x - size, y: c.y - size), CGPoint(x: c.x, y: c.y - size)]
            XCTAssertEqual(only([s(path(sq, closed: false), amp: amp)])?.name, "正方形", "size \(size)")
            // 圆：多画了一点，收尾越过了起点
            XCTAssertEqual(only([s(arc(c, size, size * 0.97, from: 0.3, to: 0.3 + 2.25 * CGFloat.pi), amp: amp)])?.name, "圆", "size \(size)")
            let tri = [CGPoint(x: c.x, y: c.y - size), CGPoint(x: c.x - size * 1.1, y: c.y + size * 0.7), CGPoint(x: c.x + size * 0.9, y: c.y + size * 0.8)]
            XCTAssertTrue(only([s(path(tri), amp: amp)])?.name.hasSuffix("三角形") ?? false, "size \(size)")
        }
    }

    func testPyramidAndPrism() throws {
        // 四棱锥 P-ABCD：底面是平行四边形，P 在上面
        let a = CGPoint(x: 100, y: 360), b = CGPoint(x: 280, y: 360), c = CGPoint(x: 350, y: 300), d = CGPoint(x: 170, y: 300)
        let p = CGPoint(x: 225, y: 100)
        let pyr = [(a, b), (b, c), (c, d), (d, a), (p, a), (p, b), (p, c), (p, d)].map { s(line($0.0, $0.1)) }
        guard case .solid(let py)? = only(pyr) else { return XCTFail() }
        XCTAssertEqual(py.kind, .pyramid)
        // 三棱柱：上下两个三角形 + 三条竖的侧棱
        let t = [CGPoint(x: 100, y: 150), CGPoint(x: 220, y: 170), CGPoint(x: 300, y: 130)]
        let bt = t.map { CGPoint(x: $0.x, y: $0.y + 200) }
        let prism = [s(path(t)), s(path(bt))] + (0..<3).map { s(line(t[$0], bt[$0])) }
        guard case .solid(let pr)? = only(prism) else { return XCTFail() }
        XCTAssertEqual(pr.kind, .prism)
        XCTAssertEqual(pr.dims[1], 200, accuracy: 12)
    }

    // MARK: 拖节点

    func testDraggingASquareCornerKeepsItSquare() throws {
        let sq = Figure.polygon(Polygon2(vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200)], rule: .square))
        guard case .polygon(let p) = sq.dragging(.vertex(2), to: CGPoint(x: 260, y: 240)) else { return XCTFail() }
        let s = Geo.sides(p.vertices)
        XCTAssertEqual(s[0], s[1], accuracy: 0.01)
        XCTAssertEqual(s[1], s[2], accuracy: 0.01)
        XCTAssertEqual(p.vertices[0], CGPoint(x: 100, y: 100))   // 对角不动
        XCTAssertEqual(Geo.angles(p.vertices)[0], 90, accuracy: 0.01)
    }

    func testRectangleEdgeAndRotation() throws {
        let rect = Figure.polygon(Polygon2(vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 200)], rule: .rectangle))
        // 拖右边往右 50
        guard case .polygon(let p) = rect.dragging(.edge(1), to: CGPoint(x: 350, y: 150)) else { return XCTFail() }
        XCTAssertEqual(Geo.dist(p.vertices[0], p.vertices[1]), 250, accuracy: 0.01)
        XCTAssertEqual(Geo.dist(p.vertices[1], p.vertices[2]), 100, accuracy: 0.01)
        // 旋转手柄转 90°（吸附到整角）
        let h = rect.handles.first { $0.role == .rotate }!.point
        let c = CGPoint(x: 200, y: 150)
        let target = Geo.rotate(h, about: c, by: .pi / 2 + 0.03)
        guard case .polygon(let q) = rect.dragging(.rotate, to: target) else { return XCTFail() }
        XCTAssertEqual(q.orientation, .pi / 2, accuracy: 1e-6)
        XCTAssertEqual(Figure.polygon(q).name, "矩形")
    }

    func testFreeTriangleRenamesWhileDragging() throws {
        let tri = Figure.polygon(Polygon2(vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 260, y: 300), CGPoint(x: 100, y: 300)], rule: .free))
        XCTAssertEqual(tri.name, "直角三角形")
        let moved = tri.dragging(.vertex(0), to: CGPoint(x: 160, y: 120))
        XCTAssertNotEqual(moved.name, "直角三角形")
    }

    func testRegularPolygonVertexRotatesAndScales() throws {
        let c = CGPoint(x: 300, y: 300)
        let corners = (0..<6).map { (k: Int) -> CGPoint in polar(c, 100, CGFloat(k) * CGFloat.pi / 3) }
        let hex = Figure.polygon(Polygon2(vertices: corners, rule: .regular))
        guard case .polygon(let p) = hex.dragging(.vertex(0), to: CGPoint(x: 300, y: 450)) else { return XCTFail() }
        for v in p.vertices { XCTAssertEqual(Geo.dist(v, c), 150, accuracy: 0.01) }
        XCTAssertEqual(Figure.polygon(p).name, "正六边形")
    }

    func testParallelogramStaysParallel() throws {
        let par = Figure.polygon(Polygon2(vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 360, y: 240), CGPoint(x: 160, y: 240)], rule: .parallelogram))
        guard case .polygon(let p) = par.dragging(.vertex(0), to: CGPoint(x: 60, y: 80)) else { return XCTFail() }
        let v = p.vertices
        XCTAssertLessThan(Geo.directionGap(v[0], v[1], v[2], v[3]), 0.01)
        XCTAssertLessThan(Geo.directionGap(v[1], v[2], v[3], v[0]), 0.01)
    }

    func testEllipseHandlesAndFoci() throws {
        let e = Figure.ellipse(Ellipse2(center: CGPoint(x: 200, y: 200), a: 100, b: 60, angle: 0, isCircle: false))
        XCTAssertEqual(e.facts, ["a = 2.5", "b = 1.5", "c = 2", "e = 0.80"])
        guard case .ellipse(let f) = e.dragging(.axisB, to: CGPoint(x: 230, y: 280)) else { return XCTFail() }
        XCTAssertEqual(f.b, 80, accuracy: 0.01)
        XCTAssertEqual(f.a, 100)
        let (f1, f2) = f.foci
        XCTAssertEqual(Geo.dist(f1, f2), 2 * 60, accuracy: 0.01)
        let circle = Figure.ellipse(Ellipse2(center: .zero, a: 80, b: 80, angle: 0, isCircle: true))
        XCTAssertEqual(circle.facts.first, "半径 2")
        guard case .ellipse(let r) = circle.dragging(.axisA, to: CGPoint(x: 0, y: 120)) else { return XCTFail() }
        XCTAssertEqual(r.a, 120, accuracy: 0.01)
        XCTAssertEqual(r.b, 120, accuracy: 0.01)
    }

    // MARK: 立体图形的投影

    func testCubeHasThreeHiddenEdgesInTheDefaultView() {
        let cube = Solid3(kind: .cube, center: CGPoint(x: 300, y: 300), dims: [120])
        let p = cube.projection()
        XCTAssertEqual(p.edges.count, 12)
        XCTAssertEqual(p.edges.filter { !$0.visible }.count, 3)
        XCTAssertEqual(p.faces.count, 3)
        XCTAssertEqual(Set(p.labels.map(\.text)), ["A", "B", "C", "D", "A₁", "B₁", "C₁", "D₁"])
        // 主视图：只看得见前面一个面
        XCTAssertEqual(cube.viewed(.front).projection().faces.count, 1)
    }

    func testCylinderOutlineAndHiddenBackRim() {
        let cyl = Solid3(kind: .cylinder, center: CGPoint(x: 300, y: 300), dims: [80, 160])
        let p = cyl.projection()
        let vertical = p.edges.filter { abs($0.a.x - $0.b.x) < 30 && abs($0.a.y - $0.b.y) > 100 }
        XCTAssertEqual(vertical.filter(\.visible).count, 2, "左右两条母线")
        XCTAssertTrue(p.edges.contains { !$0.visible }, "下底面的后半圈是虚线")
        XCTAssertEqual(Set(p.labels.map(\.text)), ["O", "O₁"])
    }

    func testSolidHandlesResize() throws {
        let cube = Figure.solid(Solid3(kind: .cube, center: CGPoint(x: 300, y: 300), dims: [100]))
        let h = cube.handles.first { if case .size = $0.role { return true }; return false }!
        let far = CGPoint(x: 300 + (h.point.x - 300) * 1.5, y: 300 + (h.point.y - 300) * 1.5)
        guard case .solid(let s) = cube.dragging(h.role, to: far) else { return XCTFail() }
        XCTAssertEqual(s.dims[0], 150, accuracy: 0.5)
        guard case .solid(let r) = cube.dragging(.orbit, to: CGPoint(x: cube.handles.last!.point.x + 50, y: cube.handles.last!.point.y)) else { return XCTFail() }
        XCTAssertEqual(r.yaw, Solid3.defaultYaw + 0.6, accuracy: 1e-9)
        XCTAssertEqual(Figure.solid(Solid3(kind: .cylinder, center: .zero, dims: [40, 80])).facts.first, "r = 1")
    }

    func testExtrudeSquareToCube() throws {
        let sq = Figure.polygon(Polygon2(vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200)], rule: .square))
        XCTAssertEqual(sq.solidOptions, [.cube, .pyramid])
        guard case .solid(let c)? = sq.extruded(.cube) else { return XCTFail() }
        XCTAssertEqual(c.kind, .cube)
        XCTAssertEqual(c.center, CGPoint(x: 150, y: 150))
        XCTAssertEqual(Figure.ellipse(Ellipse2(center: .zero, a: 50, b: 50, angle: 0, isCircle: true)).solidOptions, [.cylinder, .cone, .sphere])
    }
}
