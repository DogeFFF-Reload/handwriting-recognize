import XCTest
@testable import InkCore

final class MatrixTests: XCTestCase {
    private func m(_ rows: String) -> String { "\\begin{pmatrix}\(rows)\\end{pmatrix}" }
    private let a = "\\begin{pmatrix}1 & 2 \\\\ 3 & 4\\end{pmatrix}"
    private let b = "\\begin{pmatrix}5 & 6 \\\\ 7 & 8\\end{pmatrix}"

    private func solve(_ latex: String, _ action: MatrixAction,
                       file: StaticString = #filePath, line: UInt = #line) -> Solution {
        let s = MatrixMath.solve(latex, action: action)
        return s
    }

    func testContainsOnlyRealMatrices() {
        XCTAssertTrue(MatrixMath.contains(a))
        XCTAssertTrue(MatrixMath.contains("\\begin{bmatrix}1\\\\2\\end{bmatrix}"))
        XCTAssertTrue(MatrixMath.contains("\\begin{array}{cc}1&2\\\\3&4\\end{array}"))
        XCTAssertFalse(MatrixMath.contains("f(x)=x^2"))
        XCTAssertFalse(MatrixMath.contains("\\begin{array}{c}x\\end{array}"))
        XCTAssertNil(MatrixMath.action(for: .integral))
        XCTAssertEqual(MatrixMath.action(for: .inverse), .inverse)
    }

    func testAdditionAndProduct() {
        let sum = solve(a + "+" + b, .calculate)
        XCTAssertEqual(sum.result, m("6 & 8 \\\\ 10 & 12"))
        XCTAssertEqual(sum.operation, .matrix)
        let prod = solve(a + b, .calculate)
        XCTAssertEqual(prod.result, m("19 & 22 \\\\ 43 & 50"))
        let times = solve(a + "\\times " + b, .calculate)
        XCTAssertEqual(times.result, prod.result)
        let ignored = solve(a + "+" + b + "=" + m("0 & 0 \\\\ 0 & 0"), .calculate)
        XCTAssertEqual(ignored.result, sum.result, "等号右边的答案不参与计算")
    }

    func testScalarParenthesesAndTranspose() {
        XCTAssertEqual(solve("2" + a, .calculate).result, m("2 & 4 \\\\ 6 & 8"))
        XCTAssertEqual(solve("-" + a, .calculate).result, m("-1 & -2 \\\\ -3 & -4"))
        let twice = "(\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix}+\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix})" + a
        XCTAssertEqual(solve(twice, .calculate).result, m("2 & 4 \\\\ 6 & 8"))
        XCTAssertEqual(solve(a + "^{T}", .calculate).result, m("1 & 3 \\\\ 2 & 4"))
    }

    func testInverseAndDeterminant() {
        let inv = solve(a, .inverse)
        XCTAssertEqual(inv.result, m("-2 & 1 \\\\ \\frac{3}{2} & -\\frac{1}{2}"))
        XCTAssertEqual(inv.operation, .inverse)
        XCTAssertTrue(inv.input.contains("^{-1}"))
        let byPower = solve(a + "^{-1}", .calculate)
        XCTAssertEqual(byPower.result, inv.result)
        let det = solve(a, .determinant)
        XCTAssertEqual(det.result, "-2")
        XCTAssertTrue(det.input.hasPrefix("\\det"))
        let singular = solve(m("1 & 2 \\\\ 2 & 4"), .inverse)
        XCTAssertNil(singular.result)
        XCTAssertTrue(singular.conclusive)
        XCTAssertEqual(singular.note, "行列式为 0，没有逆矩阵")
        XCTAssertEqual(solve(m("1 & 2 \\\\ 2 & 4"), .determinant).result, "0")
    }

    func testShapeErrorsAndFractions() {
        let wide = m("1 & 2 & 3 \\\\ 4 & 5 & 6")
        let inv = solve(wide, .inverse)
        XCTAssertNil(inv.result)
        XCTAssertEqual(inv.note, "不是方阵，没有逆矩阵")
        let det = solve(wide, .determinant)
        XCTAssertNil(det.result)
        XCTAssertEqual(det.note, "不是方阵，没有行列式")
        let mismatch = solve(a + "+" + wide, .calculate)
        XCTAssertNil(mismatch.result)
        XCTAssertTrue(mismatch.conclusive)
        XCTAssertTrue(mismatch.note?.contains("不能相加") ?? false)
        let frac = solve("\\begin{pmatrix}\\frac{1}{2}&1\\\\0&2\\end{pmatrix}", .determinant)
        XCTAssertEqual(frac.result, "1")
        let bmatrix = solve("\\begin{bmatrix}1&0\\\\0&1\\end{bmatrix}", .inverse)
        XCTAssertEqual(bmatrix.result, m("1 & 0 \\\\ 0 & 1"))
        let rect = solve("\\begin{pmatrix}1&2\\end{pmatrix}\\begin{pmatrix}3\\\\4\\end{pmatrix}", .calculate)
        XCTAssertEqual(rect.result, m("11"))
    }

    func testStrayCommasInsideMatrixAreIgnored() {
        let messy = "\\begin{pmatrix}1 & 2 \\\\ ,3 & 4\\end{pmatrix}"
        let det = solve(messy, .determinant)
        XCTAssertEqual(det.result, "-2")
        XCTAssertFalse(det.input.contains(","))
        let inv = solve(messy, .inverse)
        XCTAssertEqual(inv.result, m("-2 & 1 \\\\ \\frac{3}{2} & -\\frac{1}{2}"))
        XCTAssertFalse(inv.input.contains(","))
        XCTAssertFalse(inv.result?.contains(",") ?? true)
    }

    func testThreeByThreeAndLeftRight() {
        let g = "\\begin{pmatrix}1&2&3\\\\0&1&4\\\\5&6&0\\end{pmatrix}"
        XCTAssertEqual(solve(g, .determinant).result, "1")
        let wrapped = "\\left(\\begin{matrix}4&7\\\\2&6\\end{matrix}\\right)"
        XCTAssertEqual(solve(wrapped, .determinant).result, "10")
        XCTAssertEqual(solve(wrapped, .inverse).result, m("\\frac{3}{5} & -\\frac{7}{10} \\\\ -\\frac{1}{5} & \\frac{2}{5}"))
    }
}
