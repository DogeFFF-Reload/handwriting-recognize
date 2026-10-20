# MathEngine 接入说明（P4 → P1 / P2 / P3）

一句话：我新增了 `Packages/MathEngine/`，**没有改动任何现有文件**。
以后的判分（对错、正确项、说明、极值点、中点）都只走它，App 里直接调，不走网络、不调模型。
各自要改的都不超过 10 行，见下。

先给三个背景，省得你们翻代码：

- `Packages/InkCore` 里的 `DerivativeCheck.swift` 是 P3 在 MathEngine 到之前写的**临时实现**，
  我会做逐用例兼容（见第 1 节），确认行为一致后由 P3 删。
- `Server` 没有 `/check`，判分本来就在 App 内 —— 这版继续这样，**不要**为它加 HTTP 接口。
- 我包里的 `Tests/.../contracts/v3/` 只是引擎自测夹具；团队契约仍是仓库根目录的 `contracts/*.json`，
  那个归 P3，我不动。

---

## 1. P3（InkCore / 识别 / Server）

### 1.1 接入只有三步

**① `Packages/InkCore/Package.swift` 加两行**

```swift
dependencies: [
    .package(path: "../MathEngine"),
],
targets: [
    .target(name: "InkCore", dependencies: [
        .product(name: "MathEngine", package: "MathEngine"),
    ]),
    …
]
```

**② 把接入样例拷进去**

```bash
cp Packages/MathEngine/Integration/MathEngineGrading.swift Packages/InkCore/Sources/InkCore/
```

这个文件我写在 `Integration/` 下是**故意不参与编译**的，所以现在加进来不会有任何影响。
拷贝过去之后它会编译；它只做翻译，不含判分逻辑。

**③ App 里换两个调用点（P1 也可以顺手改）**

```swift
// 之前
DerivativeCheck.annotation(line:functionLatex:derivativeLatex:mode:)
// 之后
MathEngineGrading.annotation(line:functionLatex:derivativeLatex:mode:)

// 门禁的项数
gate.expectedTermCount = { _ in
    MathEngineGrading.expectedTermCount(functionLatex: "f(x)=x^3-5x")
}
```

`annotation` 的入参、返回值（`Annotation`）完全不变，`nil` 的含义也不变（这一行读不出来）。

### 1.2 我已经做过的兼容验证

我把 `InkCoreTests.swift` 里判分相关的断言**原样搬到了 `MathEngineTests/InkCoreCompatibilityTests.swift`**，
一共 8 条，现在全绿。也就是说这些行为不会变：

| 行为 | 状态 |
|---|---|
| `f'(x)=3x^2-3x` → 圈 `-3x`、正确项 `-3`、说明「x 求导得 1，所以 −3x 求导后是 −3。」 | 逐字一致 |
| 圈的位置（用你的 `TermSegmenter`）→ `[196,105,270,145]` | 一致 |
| `f^{\\prime}(x)=3x^{2}-3`、`-3+3x^2` 判对（写法变体、项序颠倒） | 一致 |
| `x^2-3` → `wrong_coef` + `3x^2`；`2x+5` → `not_differentiated` + `0`；漏项 → `missing_term` + `-3` | 一致 |
| `\\int x` 读不出 → `nil` | 一致 |
| `f'(x)=3x^2-`（写一半）能解析出 1 项 | 一致 |

另外我修了一个两边都会踩的坑：`f'(x)=0` 以前会被当成「空行」读不出来，现在能正常解析。

### 1.3 需要你拍板的一件事：错误码词表

同一行 `f'(x)=3x^2-3x`，你们仓库里有两种说法：

- `contracts/annotation.sample.json` 写的是 `"kind": "wrong_term"`
- `DerivativeCheckTests` 断言的是 `"not_differentiated"`

我建议统一成 **`not_differentiated`**：它准确说的是「把原函数里的项抄下来没求导」，
正是学生最常犯的那一种，也和你已经写好的 `Explanation` 模板对得上。
完整建议词表（桥已经按这个实现）：

| 情况 | kind |
|---|---|
| 原函数的项原样抄下来没求导 | `not_differentiated` |
| 同次幂、系数不对 | `wrong_coef` |
| 少了一项 | `missing_term` |
| 多了一项 | `extra_term` |
| 整行抄了原函数 | `not_differentiated`（`wrong_latex` 为整行） |
| 读不出来 | 不返回 `Annotation`，走 `onUnreadable` |

如果同意，`annotation.sample.json` 那一处要改（`wrong_term` → `not_differentiated`）；
不同意也行，桥里改一行映射即可。

### 1.4 建议在 CI 里加一行

`.github/workflows/ci.yml` 的 `unit` job 里：

```yaml
      - name: MathEngine tests
        run: swift test --package-path Packages/MathEngine
```

不加也不阻塞 —— 我这边每次改都会跑，但云端有护栏更放心。

### 1.5 什么时候删临时实现

等 ②③ 上线、真机上第二幕跑通之后，删 `DerivativeCheck.swift` 和它的测试即可。
在那之前保留没有任何问题（两套代码不冲突，命名也不同）。

---

## 2. P2（SceneUI）

### 2.1 加依赖，直接用类型，不要解 JSON

```swift
// Packages/SceneUI/Package.swift
dependencies: [.package(path: "../MathEngine")],
.target(name: "SceneUI", dependencies: [.product(name: "MathEngine", package: "MathEngine")])
```

```swift
import MathEngine

var scene = try FunctionSceneBuilder.build("f(x)=x^3-5x")   // 第一幕
scene.params          // [a, b]，b 的 value 是 5，sign 是 -1
scene.marks           // 极值点 + 极值处的水平切线

// 拖滑条：本地重算，毫秒级，**不要发网络请求**
scene = scene.updated(values: ["b": 3])   // 曲线、极值点、切线一起变

// 采样画线
for (x, y) in scene.samples(count: 241) { … }

// 改对之后的可拖切点（A9，有余力再做）
scene.tangent(at: 2, derivative: studentDerivative)
```

### 2.2 和你们 `contracts/scene-function.sample.json` 的字段差异

你们样例是**最小集**，我这份是超集，多的字段都有默认值，不影响你按样例画：

| 字段 | 你们样例 | MathEngine | 为什么要 |
|---|---|---|---|
| `terms[].param` | 无 | `"a"` / `"b"` | 滑条改哪一项不能靠下标（A1） |
| `terms[].sign` | 无 | `-1` | `value` 恒正，符号单独给，滑条上显示 5 而不是 −5 |
| `params[].step` | 无 | `1` / `0.5` / `0.1` | 分数系数的步长 |
| `params[].pow` | 无 | `1` / `3` | 参数绑定哪一次幂 |
| `marks[].kind` | 无 | `max` / `min` | 画「极大/极小」标签用 |
| `marks[].slope` | 无 | `0` | 切线斜率；任意点切线也走这个字段 |
| `view` | 无 | `{x_min,x_max,y_min,y_max}` | 采样范围，别写死 −6…6 |

两条硬规定：`terms` **按幂次降序**；`sign` 折进去、`value` 恒正。

### 2.3 一个演示细节

把 `a` 拖到 0（`x^3-5x` → `-5x`）时，曲线变直线，**极值点会自动清空**，你不要自己再判断一次。
函数模式不批改，双击 = 立即刷新图像（这条 P1 那边也一样）。

---

## 3. P1（Pencil / App）

### 3.1 门禁接一行

```swift
gate.expectedTermCount = { _ in MathEngineGrading.expectedTermCount(functionLatex: currentProblem) }
```

`CheckGate` 其它逻辑不用动，你现有的双计时、revision、双击都工作得很好。

### 3.2 批改调用（如果由你接）

```swift
let a = MathEngineGrading.annotation(line: line,
                                     functionLatex: "f(x)=x^3-5x",
                                     derivativeLatex: latex)   // nil = 没看清
for e in a?.errors ?? [] {
    drawCircle(e.rect)                 // 已经是 [x1,y1,x2,y2] → CGRect，画布 point
    showBubble(e.expectedLatex)        // direct 模式才有；SwiftMath 排版
}
showText(a?.explanation)               // 整行一句说明，本地算的，0 延迟
```

**先画圈，再写字**。圈依赖的数据在 `annotation` 返回时就有了；文字如果走 Max 润色才可能超时。

### 3.3 两个彩排坑（务必写进你的清单）

- **`-5x` 要一笔连着写完。** 写到 `-5` 就停 1.5 秒，它已经是 2 项、而且是对的，会当场判对并画切线。
- **双击不切橡皮**（D2）：双击 = 批改/确认；橡皮用左侧按钮；整笔擦除用 `.vector`，别用 `.bitmap`。

---

## 4. 全员约定（三条）

1. **分支**：我推 `p4/math-engine`；你们的按 `p1/**`、`p2/**`、`p3/**`。`main` 只在「这一版装进那台 iPad」之后才更新。
2. **契约只有 P4 改**：谁要加字段，先在群里说，我改 `contracts/*.json` 和对应的 Codable，再通知两端。
3. **换行符**：现在这个 clone 里有 **47 个文件显示已修改，全是 CRLF**（我比对过，44 行对 44 行、
   161 对 161，内容没变）。提交前把这些全部 Discard 掉，否则整个仓库会被换行符刷一遍。
   根治：仓库根加一个 `.gitattributes`（`* text=auto`、`*.swift text eol=lf`），下次谁 clone 都干净。
   这条涉及全仓，谁提谁决定，我不动。

---

## 5. 十分钟验收清单（谁先合谁先跑）

```bash
swift test --package-path Packages/MathEngine        # 43 tests, 0 failures
swift test --package-path Packages/InkCore           # 现有 26 条仍绿
```

然后跑这个脚本，确认桥在你们真实类型上没问题：

```bash
swift run --package-path Packages/MathEngine p4tool demo
# 依次打印：函数场景 / 写错 / 改对 / 矩阵 / 积分 的返回
```

四条数据必须对上：

1. `f(x)=x^3-5x` → `params` 里 `b.value == 5`、`sign == -1`，极值点在 `±1.290994`；
2. `f'(x)=3x^2-5x` → 一条 `wrong_term`，`wrong_latex == "-5x"`、`expected_latex == "-5"`；
3. `f'(x)=3x^2-5` → `ok == true`；
4. 任何垃圾输入（`f'(x)=???`）→ `ok == false`、不崩、HTTP/调用不抛。

---

## 6. 边界（答辩时别吹过头）

只支持单变量多项式；三角/对数/根号一律「读不出来」（故意的，让学生改一次，别静默算错）。
除以含 `x` 的式子不支持。矩阵只做 2×2 / 3×3 乘法。积分做不定积分（对结果求导回验）和多项式定积分。
推导等价允许两边同乘/同除，平方/开方不算等价。
数字超过 9 位、指数超过 12、次数超过 24 会明确报「超出演示范围」——这是保护，不是缺陷。
