import SwiftUI

/// 右半屏。P1 在 ContentView 里放 `SceneHost(model: sceneModel)`；
/// 没有传 model 时（空壳阶段）显示 contracts 里的假场景 x³ − 3x。
public struct SceneHost: View {
    @Bindable var model: SceneModel

    public init(model: SceneModel) {
        self.model = model
    }

    /// 空壳阶段用：自带一个假场景。
    public init() {
        let m = SceneModel()
        m.show(function: SceneModel.sampleFunction())
        self.model = m
    }

    public var body: some View {
        Group {
            switch model.content {
            case .empty:
                ContentUnavailableView("在左边第一行写一个函数", systemImage: "pencil.and.scribble",
                                       description: Text("例如 f(x) = x³ − 5x，停笔后这里会画出图像"))
            case .function:
                FunctionSceneView(model: model)
            case .geometry(let g):
                GeometryView(model: model, scene: g)
                    .padding(16)
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// 公式 + 图像 + 每个系数一条滑条。
public struct FunctionSceneView: View {
    @Bindable var model: SceneModel

    public init(model: SceneModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                MathLabel("f(x) = " + Poly.latex(model.terms), fontSize: 24)
                    .fixedSize(horizontal: false, vertical: true)
                if model.reveal {
                    MathLabel("f'(x) = " + Poly.latex(Poly.derivative(model.terms)), fontSize: 20, color: .systemGreen)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FunctionPlotView(model: model)
            ParamSliders(model: model)
        }
        .padding(16)
        .animation(.easeOut(duration: 0.25), value: model.reveal)
    }
}

/// 每个数字系数一条滑条（第一幕：擦掉 5 写 3 后，b 滑条跳到 3）。
/// 名字按次数从高到低取 a、b、c…，和 contracts 里 params 的 a、b 对上。
public struct ParamSliders: View {
    @Bindable var model: SceneModel

    public init(model: SceneModel) {
        self.model = model
    }

    public var body: some View {
        let order = model.terms.indices.sorted { model.terms[$0].pow > model.terms[$1].pow }
        VStack(spacing: 6) {
            ForEach(Array(order.enumerated()), id: \.element) { rank, i in
                let t = model.terms[i]
                let span = max(5.0, (abs(t.coef) * 2).rounded(.up))
                HStack(spacing: 12) {
                    Text(Self.name(rank)).font(.headline.monospaced()).frame(width: 20)
                    Text(t.pow == 0 ? "常数项" : t.pow == 1 ? "x 的系数" : "x\(Self.sup(t.pow)) 的系数")
                        .font(.subheadline).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                    Slider(value: Binding(get: { model.terms[i].coef },
                                          set: { model.terms[i].coef = ($0 * 2).rounded() / 2 }),
                           in: -span...span)
                    Text(Poly.format(abs(t.coef)) == "0" ? "0" : Poly.format(t.coef))
                        .font(.body.monospacedDigit().weight(.semibold)).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    static func name(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + min(i, 25)))) }

    static func sup(_ n: Int) -> String {
        let m: [Character: String] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return String(n).map { m[$0] ?? "" }.joined()
    }
}

#Preview("函数") {
    let m = SceneModel()
    m.show(function: SceneModel.sampleFunction())
    m.reveal = true
    return SceneHost(model: m)
}

#Preview("几何") {
    let m = SceneModel()
    let g = GeometryScene(kind: "geometry",
                          points: [.init(id: "A", role: "free", x: 180, y: 80), .init(id: "B", role: "free", x: 40, y: 280),
                                   .init(id: "C", role: "free", x: 320, y: 280), .init(id: "M", role: "constrained", x: 180, y: 280)],
                          objects: [.init(type: "segment", id: "AB", points: ["A", "B"]), .init(type: "segment", id: "BC", points: ["B", "C"]),
                                    .init(type: "segment", id: "CA", points: ["C", "A"]), .init(type: "segment", id: "median_A", points: ["A", "M"])],
                          relations: [.init(type: "midpoint", of: ["B", "C"], point: "M")])
    m.show(geometry: g)
    return SceneHost(model: m)
}
