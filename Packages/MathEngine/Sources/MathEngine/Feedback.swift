//
//  Feedback.swift
//  MathEngine
//
//  v3（2026-10-20），对应 P2/P3 报告里的决策：
//    D1 CheckGate —— 「能解析 + 项数达到预期」由这里判断（CheckReadiness）
//    D5 direct 模式 —— 直接给正确项 + 一句说明（Explain，确定性模板，不调模型）
//  另外：错项在行内的横向位置估算 + 吸附到真实笔画（TermBox），给"圈住那一项"兜底。
//

import Foundation

// MARK: - 反馈模式

/// 第一版用 direct：圈错项 + 直接写正确项 + 一句说明。socratic 以后再开。
public enum FeedbackMode: String, Codable, Equatable {
    case direct
    case socratic
}

// MARK: - 纯文本渲染（说明气泡里用，不是 LaTeX）

public enum PlainRender {

    static let sup: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]

    public static func superscript(_ n: Int) -> String {
        String(String(n).map { sup[$0] ?? $0 })
    }

    /// 3、−3、1/2（用真正的减号 −，和学生的墨迹区分开也更好看）
    public static func number(_ r: Rational) -> String {
        if !r.isValid { return "?" }
        let sign = r.isNegative ? "−" : ""
        let a = r.abs
        return sign + (a.d == 1 ? "\(a.n)" : "\(a.n)/\(a.d)")
    }

    /// −3x、3x²、x³、(1/2)x²
    public static func term(_ coef: Rational, _ pow: Int) -> String {
        if pow == 0 { return number(coef) }
        let body = pow == 1 ? "x" : "x" + superscript(pow)
        if coef == .one { return body }
        if coef == -Rational.one { return "−" + body }
        let sign = coef.isNegative ? "−" : ""
        let a = coef.abs
        let c = a.d == 1 ? "\(a.n)" : "(\(a.n)/\(a.d))"
        return sign + c + body
    }

    /// 3x² − 3
    public static func poly(_ p: Poly) -> String {
        if p.isZero { return "0" }
        var out = ""
        for (i, t) in p.terms.enumerated() {
            let body = term(t.coef.abs, t.pow)
            if i == 0 {
                out += (t.coef.isNegative ? "−" : "") + body
            } else {
                out += (t.coef.isNegative ? " − " : " + ") + body
            }
        }
        return out
    }
}

// MARK: - 一句说明（direct 模式）

/// 按错误码套模板。正确项来自 MathEngine 的计算，所以不会算错、没有延迟。
/// P3 可以改措辞，但**错误码和占位的数学内容以这里为准**。
public enum Explain {

    public static let parseError = "这一行没看清，点一下识别结果可以手动改。"

    public static func notDerivative(correct: Poly) -> String {
        "这一行还是原函数，没有求导。导数应是 \(PlainRender.poly(correct))。"
    }

    /// 「x 求导得 1」「x³ 求导得 3x²」
    static func powerRule(_ n: Int) -> String {
        if n == 1 { return "x 求导得 1" }
        let lower = n - 1 == 1 ? "x" : "x" + PlainRender.superscript(n - 1)
        return "x\(PlainRender.superscript(n)) 求导得 \(n)\(lower)"
    }

    public static func derivative(_ d: Defect, function f: Poly) -> String? {
        switch d.kind {
        case .parseError: return parseError
        case .notDerivative: return notDerivative(correct: f.derivative())
        case .extraTerm: return extraTerm(d, function: f)
        default: break
        }
        guard let p = d.expectedPow else { return nil }
        let n = p + 1
        let origCoef = f.coef(of: n)
        guard !origCoef.isZero else { return nil }
        let orig = PlainRender.term(origCoef, n)
        let expected = PlainRender.term(origCoef * Rational(n), p)
        let rule = powerRule(n)
        switch d.kind {
        case .wrongTerm:
            // PDF 原句：「x 求导得 1，所以 −3x 求导后是 −3。」
            if origCoef == .one { return "\(rule)，所以这一项应是 \(expected)。" }
            return "\(rule)，所以 \(orig) 求导后是 \(expected)。"
        case .wrongCoefficient:
            if n == 1 { return "\(rule)，所以 \(orig) 求导后是 \(expected)。" }
            return "\(rule)：指数 \(n) 要乘到系数上，\(orig) 求导后是 \(expected)。"
        case .wrongSign:
            let sign = origCoef.isNegative ? "负" : "正"
            return "\(orig) 前面是\(sign)号，求导不改变符号，结果是 \(expected)。"
        case .missingTerm:
            return "原式里的 \(orig) 求导后是 \(expected)，这一项漏写了。"
        default:
            return nil
        }
    }

    static func extraTerm(_ d: Defect, function f: Poly) -> String {
        let wrong = d.wrongLatex ?? "这一项"
        if let pw = d.pow {
            if pw == 0, !f.coef(of: 0).isZero {
                return "常数 \(PlainRender.number(f.coef(of: 0))) 求导得 0，\(wrong) 这一项应当去掉。"
            }
            if !f.coef(of: pw).isZero {
                return "\(wrong) 和原式里的项一样，还没求导；它求导后应变成低一次的项。"
            }
        }
        return "\(wrong) 在导数里没有对应的项，应当去掉。"
    }
}

// MARK: - CheckGate 支持（D1）

/// P3 的 CheckGate 在「停顿 1.5 s」之前问一句：这一行够不够格批改？
///  - unparsable：读不出来 → 不批改（双击时气泡提示「这一行没看清」）
///  - incomplete：能读，但项数没到预期（写到 `3x^2` 只有 1 项，正确导数有 2 项）→ 不批改
///  - ready：可以批改
public enum CheckReadiness: Equatable {
    case unparsable(String)
    case incomplete(have: Int, want: Int)
    case ready

    public var state: String {
        switch self {
        case .unparsable: return "unparsable"
        case .incomplete: return "incomplete"
        case .ready: return "ready"
        }
    }
}

public enum CheckGateSupport {

    /// 推导模式。注意演示时的陷阱：学生写到 `3x^2-3` 停顿超过 1.5 s，它已经是 2 项而且是**对的**，
    /// 会被判对、画出切线；接着再补一个 x 才变错。彩排时 `-3x` 要一笔连着写完。
    public static func derivative(functionLatex: String, lineLatex: String) -> CheckReadiness {
        guard let want = DerivativeCheck.expectedTermCount(functionLatex: functionLatex) else {
            return .unparsable("原函数读不出来")
        }
        do {
            let line = try StudentLine.parse(lineLatex)
            let have = line.terms.count
            return have >= want ? .ready : .incomplete(have: have, want: want)
        } catch {
            return .unparsable("\(error)")
        }
    }

    /// 函数模式：不批改，只看能不能出图（双击 = 立即刷新）
    public static func function(latex: String) -> CheckReadiness {
        FunctionSceneBuilder.isPlottable(latex) ? .ready : .unparsable("读不出可画的函数")
    }

    /// 矩阵：三个矩阵都写出来才批
    public static func matrix(latex: String) -> CheckReadiness {
        let n = MatrixCheck.matrixBodies(latex).count
        return n >= 3 ? .ready : .incomplete(have: n, want: 3)
    }

    /// 积分：要有积分号、dx、等号，且等号右边能解析
    public static func integral(latex: String) -> CheckReadiness {
        do {
            _ = try IntegralCheck.parse(latex)
            return .ready
        } catch {
            return .unparsable("\(error)")
        }
    }
}

// MARK: - 错项框：按字符位置估算 + 吸附到笔画

/// 画布坐标的矩形（point，原点左上）。JSON 里是 `[x, y, w, h]`。
public struct Box: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        w = try c.decode(Double.self)
        h = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
        try c.encode(w)
        try c.encode(h)
    }

    public func union(_ o: Box) -> Box {
        let x0 = Swift.min(x, o.x)
        let y0 = Swift.min(y, o.y)
        return Box(x: x0, y: y0, w: Swift.max(maxX, o.maxX) - x0, h: Swift.max(maxY, o.maxY) - y0)
    }
}

/// 一笔的点：`[x, y, t, pressure]`
public struct InkStroke: Codable, Equatable {
    public var id: String
    public var points: [[Double]]

    public init(id: String, points: [[Double]]) {
        self.id = id
        self.points = points
    }

    public var bounds: Box? {
        let xs = points.compactMap { $0.count >= 2 ? $0[0] : nil }
        let ys = points.compactMap { $0.count >= 2 ? $0[1] : nil }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return Box(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}

public enum TermBox {

    /// 每个字符在手写里大约占多宽（相对一个普通字符）。上标、括号、撇号窄；`^` 本身不占宽
    static func weights(_ s: String) -> [Double] {
        let chars = Array(s)
        var out: [Double] = []
        var inSup = false
        var supDepth = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            var w: Double
            if c == "^" {
                w = 0
                inSup = true
                supDepth = 0
                out.append(w)
                i += 1
                continue
            }
            switch c {
            case " ": w = 0
            case "(", ")": w = 0.5
            case "'": w = 0.35
            case "*": w = 0.4
            case "+", "-", "=": w = 0.9
            default: w = 1.0
            }
            if inSup {
                w *= 0.6
                if c == "(" { supDepth += 1 }
                if c == ")" { supDepth -= 1 }
                // 上标是一个字符，或一对括号包起来的一段
                if supDepth <= 0 { inSup = false }
            }
            out.append(w)
            i += 1
        }
        return out
    }

    /// 按字符宽度比例，估算 body[span] 在整行框里的横向位置。
    /// `label` 是 `f'(x)` 这类等号左边的部分（它也写在这一行里，要算进去）。
    public static func estimate(line: Box, label: String?, body: String, span: Range<Int>) -> Box {
        let prefix = label.map { weights($0 + "=").reduce(0, +) } ?? 0
        let bw = weights(body)
        guard span.lowerBound >= 0, span.upperBound <= bw.count, span.lowerBound < span.upperBound else {
            return line
        }
        let before = bw[0..<span.lowerBound].reduce(0, +)
        let inside = bw[span].reduce(0, +)
        let total = prefix + bw.reduce(0, +)
        guard total > 0 else { return line }
        let x0 = line.x + line.w * (prefix + before) / total
        let w = line.w * inside / total
        // 两侧各留 12%（最多 10 pt），最少 28 pt 宽，避免圈太紧；再夹在整行框里别越界
        let pad = Swift.min(Swift.max(w * 0.12, 3), 10)
        var bx = Box(x: x0 - pad, y: line.y, w: w + 2 * pad, h: line.h)
        if bx.w < 28 { bx.x -= (28 - bx.w) / 2; bx.w = 28 }
        if bx.x < line.x { bx.x = line.x }
        if bx.maxX > line.maxX { bx.w = Swift.max(line.maxX - bx.x, 1) }
        return bx
    }

    /// 吸附：中心落在估算框里的笔画，取它们的外接矩形。一笔都没有就返回 nil（调用方退回估算框）
    public static func snap(_ estimate: Box, strokes: [InkStroke]) -> Box? {
        var acc: Box? = nil
        for s in strokes {
            guard let b = s.bounds else { continue }
            if b.midX >= estimate.x && b.midX <= estimate.maxX {
                acc = acc.map { $0.union(b) } ?? b
            }
        }
        guard let a = acc else { return nil }
        // 外扩 6 pt，圈画在笔画外面而不是压在笔画上
        return Box(x: a.x - 6, y: a.y - 6, w: a.w + 12, h: a.h + 12)
    }
}
