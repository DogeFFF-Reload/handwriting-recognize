import XCTest
@testable import InkCore

/// 矩阵带名字（A = …）、「看变换」、2×2 线性变换。
final class TransformTests: XCTestCase {
    private let a = "\\begin{pmatrix}2 & 0 \\\\ 0 & 1\\end{pmatrix}"

    func testNamedMatrixKeepsItsName() {
        let plain = MatrixMath.solve("A=" + a, action: .calculate)
        XCTAssertEqual(plain.input, "A = " + a)
        XCTAssertNil(plain.result, "只写了一个矩阵：不再「= 同一个矩阵」")
        XCTAssertNil(plain.note)

        let inv = MatrixMath.solve("A=" + a, action: .inverse)
        XCTAssertEqual(inv.input, "A = " + a)
        XCTAssertEqual(inv.relation, ",\\; A^{-1} =")
        XCTAssertEqual(inv.result, "\\begin{pmatrix}\\frac{1}{2} & 0 \\\\ 0 & 1\\end{pmatrix}")

        let det = MatrixMath.solve("A = " + a, action: .determinant)
        XCTAssertEqual(det.relation, ",\\; \\det A =")
        XCTAssertEqual(det.result, "2")

        // 名字可以带下标；右边是算式时照样算出来
        let product = MatrixMath.solve("M_{1}=" + a + a, action: .calculate)
        XCTAssertEqual(product.input, "M_{1} = " + a + " " + a)
        XCTAssertEqual(product.result, "\\begin{pmatrix}4 & 0 \\\\ 0 & 1\\end{pmatrix}")
        XCTAssertEqual(MatrixMath.name("M_{1}=" + a), "M_{1}")
        XCTAssertNil(MatrixMath.name(a + "+" + a + "=" + a), "等号左边不是名字：右边是学生写的答案")
    }

    func testTransformAction() {
        let s = MatrixMath.solve("A=" + a, action: .transform)
        XCTAssertEqual(s.operation, .transform)
        XCTAssertEqual(s.input, "A = " + a)
        XCTAssertNil(s.result)
        XCTAssertNil(s.note)
        XCTAssertEqual(MatrixMath.action(for: .transform), .transform)

        let wide = MatrixMath.solve("\\begin{pmatrix}1&2&3\\\\4&5&6\\end{pmatrix}", action: .transform)
        XCTAssertNil(wide.result)
        XCTAssertTrue(wide.conclusive)
        XCTAssertEqual(wide.note, "看变换只支持 2×2 矩阵（这是 2×3）")

        XCTAssertEqual(MatrixMath.linearMap("A=" + a), LinearMap2(a: 2, b: 0, c: 0, d: 1))
        XCTAssertEqual(MatrixMath.linearMap(a + "^{-1}"), LinearMap2(a: 0.5, b: 0, c: 0, d: 1))
        XCTAssertNil(MatrixMath.linearMap("\\begin{pmatrix}1&2&3\\end{pmatrix}"))
        XCTAssertNil(MatrixMath.linearMap("f(x)=x^2"))
    }

    func testRewriteAfterDraggingBasisVectors() {
        let moved = LinearMap2(a: 1, b: 0.5, c: 0, d: 1)
        XCTAssertEqual(MatrixMath.rewrite("A=" + a, with: moved),
                       "A = \\begin{pmatrix}1 & \\frac{1}{2} \\\\ 0 & 1\\end{pmatrix}")
        XCTAssertEqual(MatrixMath.rewrite(a, with: .identity), "\\begin{pmatrix}1 & 0 \\\\ 0 & 1\\end{pmatrix}")
        // 改写出来的式子还能再算
        XCTAssertEqual(MatrixMath.linearMap(MatrixMath.rewrite("A=" + a, with: moved)), moved)
    }

    func testLinearMapBasics() throws {
        let m = LinearMap2(a: 2, b: 1, c: 1, d: 1)
        XCTAssertEqual(m.determinant, 1)
        let inv = try XCTUnwrap(m.inverse)
        XCTAssertEqual(m.then(inv), .identity)
        XCTAssertEqual(m.apply(1, 0).x, 2)
        XCTAssertEqual(m.apply(0, 1).y, 1)
        XCTAssertNil(LinearMap2(a: 1, b: 2, c: 2, d: 4).inverse)
        XCTAssertEqual(LinearMap2.identity.interpolated(to: LinearMap2(a: 3, b: 0, c: 0, d: 1), 0.5), LinearMap2(a: 2, b: 0, c: 0, d: 1))
        XCTAssertEqual(LinearMap2(a: 1.24, b: -0.2, c: 0.76, d: 2.01).snapped(), LinearMap2(a: 1, b: 0, c: 1, d: 2))
    }

    func testDescriptions() {
        XCTAssertEqual(LinearMap2(a: 2, b: 0, c: 0, d: 1).areaText, "det = 2：面积 ×2")
        XCTAssertEqual(LinearMap2(a: 2, b: 0, c: 0, d: 1).kindText, "横向 ×2，纵向 ×1")
        XCTAssertEqual(LinearMap2(a: 0, b: -1, c: 1, d: 0).kindText, "逆时针旋转 90°")
        XCTAssertEqual(LinearMap2(a: 1, b: 1, c: 0, d: 1).kindText, "水平剪切：ĵ 往横向偏了 1")
        XCTAssertEqual(LinearMap2(a: 1, b: 0, c: 0, d: -1).kindText, "关于 x 轴反射")
        XCTAssertEqual(LinearMap2(a: 1, b: 0, c: 0, d: -1).areaText, "det = −1：面积 ×1，方向翻转")
        XCTAssertEqual(LinearMap2(a: 1, b: 2, c: 2, d: 4).kindText, "压成一条直线（不可逆）")
        XCTAssertEqual(LinearMap2(a: 1, b: 2, c: 2, d: 4).areaText, "det = 0：面积变成 0")
        XCTAssertEqual(LinearMap2(a: 0.5, b: 0, c: 0, d: 0.5).kindText, "整体缩小为 0.5 倍")
        XCTAssertEqual(LinearMap2(a: 0, b: 1, c: 1, d: 0).kindText, "关于倾斜 45° 的直线反射")
    }
}
