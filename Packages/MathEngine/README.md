# MathEngine（P4）

纯 Swift 的判分引擎：LaTeX 多项式解析、求导逐项比对、函数场景（滑条/极值/切线）、矩阵、积分、
推导等价、几何关系、说明模板、门禁支持。**没有网络、没有模型、没有 UIKit**，App 里直接调，
Linux 上也能 `swift test`。

> 这个目录整块由 P4 维护。`Packages/InkCore`、`Packages/SceneUI`、`Server`、`app` 是别人的，
> 改它们要先说一声。

## 跑

```bash
swift test --package-path Packages/MathEngine                 # 43 个用例
swift run --package-path Packages/MathEngine p4tool demo      # 打印黄金路径的返回
swift run --package-path Packages/MathEngine p4tool parity \
    Packages/MathEngine/Tests/MathEngineTests/contracts/parity_cases.json   # 与 Python 参考实现对账
```

43 = 11 个黄金夹具 + 24 个 v3 行为 + **8 个与 InkCore 的兼容性回归**
（`InkCoreCompatibilityTests.swift`，把 P3 现有测试的断言原样搬过来跑在新引擎上）。
那 8 条的意思是：**把临时实现换成 MathEngine，App 看到的行为不变**。

## 给别人用的三样东西

| 谁 | 用什么 | 怎么用 |
|---|---|---|
| P1 / P3 | `MathEngineAPI.check(_:)` | 传 `CheckRequest`，拿 `Annotation`。同步、微秒级，不需要 await |
| P1 / P3 | `CheckGateSupport.derivative(functionLatex:lineLatex:)` 或 `DerivativeCheck.expectedTermCount(functionLatex:)` | 停顿后够不够格批改，别自己写判断 |
| P2 | `FunctionSceneBuilder.build(_:)`、`scene.updated(values:)`、`scene.tangent(at:)`、`scene.samples()` | 拖滑条在本地重算，**不要发网络请求** |

契约字段和 `Packages/InkCore/Sources/InkCore/Contracts.swift` 的对应关系（只有三处不一样）：

| InkCore 契约 | MathEngine | 处理 |
|---|---|---|
| `bbox: [x1,y1,x2,y2]` | `Box(x:y:w:h:)`，编码是 `[x,y,w,h]` | 桥里换算 |
| `Annotation.explanation`（整行一个） | `errors[].explanation`（每条一个） | 桥取第一条 |
| `kind`: `not_differentiated` / `wrong_coef` | `wrong_term` / `wrong_coefficient` / `wrong_sign` / `not_derivative` | 桥做映射 |

桥在 `Integration/MathEngineGrading.swift`。**它不在 `Sources/` 下，不参与编译**——
等 P3 决定把 `Packages/InkCore/Package.swift` 加上依赖后，再把它拷进 `InkCore/Sources/InkCore/`。
在那之前，谁都不用动自己的包。

## 这一版做了什么

- **不会闪退**：整数溢出、除零、超长数字（9 位以上）、超高次幂（>12）、空矩阵都返回 `ok:false`，
  不再 trap。旧版在 `99999999999999999999x` 和 `(2x+3)^40` 上会让进程直接死。
- **极值点**：导数三次以上用数值求根（`x^4-2x^2` 三个极值点验证过），旧版静默返回空。
- **direct 模式**：每条错误带 `expected_latex` + 一句模板说明，不调模型、0 延迟。
- **错项框**：按字符宽度估算 → 吸附到该范围的笔画 → 夹在整行框内。桥里优先用 P3 的
  `TermSegmenter`（笔画切分更准），切不出来才用引擎的估算。
- **对账**：与 `server/`（Python + SymPy 参考实现）跑同一批 19 条输入，逐条比较
  ok / kind / wrong_latex / expected_latex，19/19 一致。
- **平台**：`iOS 17 / macOS 14`，与 `InkCore` 一致（低版本平台会让本地包依赖报警告）。

## 边界（别对评委吹过头）

只支持单变量多项式；三角、对数、根号一律 `parse_error`（故意的）。除以含 x 的式子不支持。
矩阵只做 2×2 / 3×3 乘法。积分做不定积分（对结果求导回验）和多项式定积分（精确有理数）。
推导等价允许两边同乘/同除一个非零常数，平方/开方不算等价。

## 目录

```
Sources/MathEngine/Core.swift      Rational（带 invalid 哨兵）、Poly、LaTeX 清洗、递归下降、StudentLine
Sources/MathEngine/Engine.swift    错误码、逐项比对、求导批改、函数场景、矩阵、积分、推导、几何、HintGuard
Sources/MathEngine/Feedback.swift  FeedbackMode、PlainRender、Explain 说明模板、CheckGateSupport、TermBox
Sources/MathEngine/API.swift       契约 Codable 类型、MathEngineAPI 三个门面、JSON 策略（snake_case）
Sources/MathEngine/Parity.swift    与 Python 参考实现对账
Sources/p4tool/main.swift          命令行：contracts / parity / demo
Tests/MathEngineTests/             43 个用例；golden_cases.json（48 条）+ contracts/（对账 19 条）
Integration/MathEngineGrading.swift 给 InkCore 的接入样例（不参与编译）
```
