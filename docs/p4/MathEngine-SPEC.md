# MathEngine（Swift）规格与移植说明

> 目的：让"在 Swift 里重写一遍数学引擎"变成**照抄算法**，而不是重新设计。
> 代码在 `swift/MathEngine/`，期望值在 `contracts/golden_cases.json`。
> 旧的 Python 实现（`server/math_engine/`）是**参考实现**：算法同源，已用 52 条测试验证过。

---

## 0. 先说清楚一件事

这份代码是在没有 Swift 的 Windows 机器上写的，但已经在 **WSL + Swift 6.0.3** 上编译并跑通
（`swift test`：11 个测试、41 条夹具全绿；另做变异测试确认断言有效）。
到 Mac 上第一件事仍然是一遍本地验证：

```bash
cd swift/MathEngine
swift test          # 41 条夹具，全绿才算移植完成
```

实测只撞到一处编译错误：`Rational.fromDouble` 里的 `abs(v)` 被同名成员遮蔽（改成 `Swift.abs`）。其余一次过。
逻辑错误优先查：`Compare.run` 的配对、`LatexRender.term` 的格式（夹具里带 `expected_latex` 的部分会直接报出来）。

---

## 1. 范围

**支持**（演示需要的全部）：

| 语法 | 例子 |
|---|---|
| 整数/小数系数 | `3x^2`、`1.5x` |
| 单变量幂 | `x`、`x^2`、`x^{3}`、`x^(2)`、`x²` |
| 加减乘、除以常数 | `-3x`、`2x(x+1)`、`x^2/2`、`\frac{1}{2}x^{2}` |
| 括号 | `\left( x+1 \right)\left( x-1 \right)` |
| 标签剥离 | `f(x)=`、`f'(x)=`、`f''(x)=`、`f^{\prime}(x)=`、`y=` |
| 等式（残差） | `2x+3=7` → `2x-4` |
| 矩阵 | `\begin{pmatrix}…\end{pmatrix}`，2×2 / 3×3 |
| 积分 | `\int 2x dx`、`\int_0^1 2x dx`、结果带 `+C` |

**不支持**（一律抛 `MathError.unsupported`，**不许假装算成功**）：

- 三角函数、指数、对数、根号、绝对值
- 负指数、分数指数（`x^{-1}`、`x^{1/2}`）
- 除以含 `x` 的式子
- 多变量
- 通用符号化简（`(x+1)/(x-1)` 这种不约分）

> 这条原则很重要：**看不清就报错让人改，比"悄悄算错"安全 10 倍。**
> 演示时学生点一下就能改 LaTeX，代价 1 秒；判错一次，整场演示的可信度就没了。

---

## 2. 数据模型

```swift
Rational      // 有理数 n/d，精确相等。不要用 Double 判等
Term          // coef + pow
Poly          // 降幂、同幂合并、去零项
SourceTerm    // 带 span 与原文 text 的项（画圈要用）
StudentLine   // poly + [SourceTerm] + body
```

`Poly` 的等式比较是精确的（`Rational` 相等），这就是"判对错"不抖的原因。

---

## 3. 解析流水线

```
原始 LaTeX
  │  LatexText.fixUnicode      全角符号、Unicode 上标（x² → x^(2)）
  │  LatexText.stripMacros     去掉 \left \right \, \! 等，统一 \cdot \times
  │  LatexText.expandFrac      \frac{a}{b} → ((a)/(b))，递归
  │  LatexText.normalizeCaret  { } → ( )，** → ^
  ▼
LineShape.split               按最外层 = 切开，判断左边是不是标签
  │   ├ .labelled(label, body)   f'(x)=… → body 就是右边
  │   ├ .equation(lhs, rhs)      → 两边分别解析后相减
  │   └ .expression(body)
  ▼
StudentLine.parse             按顶层 +/- 切块（chunkRanges），每块单独解析
  │                           → 每块带着原字符区间 [start, end)
  ▼
PolyParser.parse              递归下降：expr → term → unary → power → atom
                              tokenize 阶段补隐式乘号（2x、x(x+1)、)(）
```

**为什么要切块再解析**：因为错项要被圈出来。整行解析成一个多项式之后，
`-3x` 是哪几个字符就丢了；先切块，每块自带区间，画圈才有素材。

**区间的坑**：`span` 是相对**归一化后的 body** 的字符偏移。
如果原文里有 Unicode 上标（`x²` → `x^(2)`，1 字符变 4 字符）或 `**`，偏移就对不上原文。
所以契约里要同时返回 `rhs_latex`，客户端做字符映射时以它为准，不要拿自己手上的原始 OCR 串去对。

---

## 4. 比对算法（判分核心）

```
如果 student == correct            → 全对
否则按幂次对齐：
  两边都有的幂 p，系数不同        → wrong_sign（互为相反数）或 wrong_coefficient
  学生有、正确答案没有的幂        → extra
  正确答案有、学生没有的幂        → missing
  extra 与 missing 两两配对       → wrong_term（每一对配一次，按"幂次接近 + 同绝对值"打分）
```

配对为什么重要：`3x² - 3x` 这个错法，如果只报"多了一项、少了一项"，
学生和评委都听不懂；配上对就是"`-3` 写成了 `-3x`" —— 这才是产品。

**输出字段**：

| 字段 | 说明 |
|---|---|
| `kind` | 10 种错误码之一 |
| `wrongLatex` | 学生原文那一段（`SourceTerm.text`），给 Flash / 笔画框用 |
| `expectedLatex` | 正确项，**只留在后端**，不进客户端 Annotation |
| `span` | 相对 body 的字符区间 |
| `pow` | 哪一次幂 |

**兜底提示**：`Defect.fallbackHint()`，10 条模板，**不含正确答案**。
模型超时/断网时 iPad 直接用它 —— 这条是演示的保险，不是备选。

**提示守门员**：`HintGuard.safe(_:fallback:expected:wrong:full:)`。
模型生成的问句要先过三关（长度 ≤ 40 字、不含"答案是"这类句式、不含正确项的记号），
不过就换成兜底模板。**判定前必须先把学生自己写的那一项从提示里抹掉** ——
`-3x` 里含 `-3`，不抹掉会永远误报。Python 侧同一套规则在 `math_engine/hint_guard.py`，
两边测试用例是同一批。

---

## 5. 函数场景

按幂次**降序**参数化，符号折进运算符：

```
x^3 - 3x  →  terms [ (1,3), (-3,1) ]
             params [ a: value 1, sign +1, ±3
                      b: value 3, sign -1, ±6 ]
```

为什么符号要折：学生纸上写 `3`，滑条上就该是 `3`。
如果滑条显示 `-3`，演示"把 3 改成 1"就变成"把 -3 改成 1"，观感当场崩。

滑条范围：`max(|v| × 2, 3)` 的对称区间；步长 1（整数）或 0.1（非整数）。

**极值**：求导后解一次/二次方程（`realRoots`），用二阶导判断极大极小。
导数次数 > 2 时返回空 —— **这种情况要在响应里写 `degraded`**，不要静默。

**切线**：只在极值点处给（斜率为 0），第二幕改对之后才画。

---

## 6. 矩阵 / 积分 / 推导 / 几何

**矩阵**：只做乘法。抽出 3 个 `pmatrix` 块 → 逐元素 `Rational` → 相乘 → 逐元素比对，
报 `(row, col)` 从 1 开始。

**积分**：
- 不定积分：**对学生结果求导**，等于被积函数即对。所以 `x^2` 和 `x^2+C` 都算对（`+C` 在解析前被剥掉）。
- 定积分：Simpson 数值积分（200 段，三次以下精确），和学生答案比，容差 `1e-6`。
  不要为了定积分去写符号积分 —— 那是 3 小时的坑。

**推导等价**：`lhs - rhs` 化成多项式，相邻两步的多项式相等即等价。
`2x+3=7 → 2x=4`：两边残差都是 `2x-4` ✓。平方、开方这种会严格判不等价（可以接受，答辩时说明边界）。

**几何**：只做对象模型，不做约束求解。

```swift
GeoPoint { id, x, y, free }
GeoRelation { type: "midpoint", of: [B, C], point: M }
Geometry.resolve(points:relations:)   // 拖动后重算依赖点
```

三条中线交于一点**不需要求解器**：每条都是「顶点 → midpoint」，中点是关系算出来的，
交点自然重合。谁要是去写约束求解，那是 8 小时的坑。

---

## 7. Python → Swift 对照表

| 参考实现（Python） | 移植（Swift） |
|---|---|
| `latex_norm.to_sympy` | `LineShape.split` + `PolyParser.parse` |
| `latex_norm.split_labeled` | `LineShape.split` → `.labelled` |
| `latex_norm.as_equation` | `DerivativeCheck.residual` |
| `terms.split_top_level_terms` | `StudentLine.chunkRanges` |
| `terms.decompose` | `Poly`（构造时已归一） |
| `terms.compare` | `Compare.run` |
| `terms.hint_for` | `Defect.fallbackHint()` |
| `function_scene.build_function_scene` | `FunctionSceneBuilder.build` |
| `function_scene.build_marks` | `FunctionSceneBuilder.marks` + `realRoots` |
| `checker.check_derivative` | `DerivativeCheck.run` |
| `checker.check_matrix` | `MatrixCheck.run` |
| `checker.check_integral` | `IntegralCheck.run` |
| `checker.check_step` | `StepCheck.run` |
| `replay.ReplayStore` | Vapor 侧（P3），规则见 `PLAN-SWIFT.md` §3⑧ |

---

## 8. 已知差异（不要当成 bug）

| 项 | Python | Swift | 说明 |
|---|---|---|---|
| 特征点 | `real_roots` 支持任意次 | 只解 ≤ 2 次 | 演示题足够；超范围返回空 |
| 浮点 | SymPy 有理数 | `Rational` | 两边都精确，夹具用 `1e-9` 容差比 |
| `span` | 相对 Python 的 body | 相对 Swift 的 body | 两者在纯 ASCII 输入下一致；有上标/宏时不一致 |
| 提示文案 | 中文模板 | 同 | 逐字一致，改文案时两边一起改 |
| 求根 | `solve` 通用 | 二次公式 | 数值舍入到 6 位小数 |

---

## 9. 怎么验证

**Swift 侧**

```bash
cd swift/MathEngine
swift test
```

41 条夹具（`Tests/MathEngineTests/golden_cases.json`），分组：parse 15 / equation 4 / function 4 /
derivative 8 / matrix 2 / integral 5 / step 3。

**Python 侧（重新生成夹具）**

```bash
cd server && python -m pytest          # 52 条，含归一化与接口
```

`contracts/golden_cases.json` 由 `server/` 里的参考实现生成。
如果你在 Swift 里发现某条夹具"看起来不对"，先用 Python 跑一遍确认到底谁错 ——
这正是保留参考实现的意义。

**两边不一致时的处理顺序**：先看是不是 `span`/格式差异 → 再看配对顺序 → 最后才怀疑算法。
配对顺序我按 `span` 起点排序，两边一致；没有 span 的项排在最后。

---

## 10. v3 补充（2026-10-20）

### 10.1 溢出：这是真机闪退，不是"边界情况"

第一版里 `Rational` 的运算是 `l.n * r.d + …`，`PolyParser` 用 `Double → Int` 直接转换。
识别器把一行字读成 `99999999999999999999x`，或学生写 `(2x+3)^40`、空 `\begin{pmatrix}\end{pmatrix}`，
Swift 的 Int 溢出和浮点转整都会 **trap**（进程直接死）。演示现场这是最没救的一种失败。

现在的做法：

- `Rational` 有哨兵 `.invalid`（`d == 0`）。所有乘加走 `multipliedReportingOverflow`，
  溢出、除零、`Int.min` 取反一律得到 invalid，沿运算一路传下去。
- 解析器在出口（`PolyParser.parse`、`StudentLine.parse`、`DerivativeCheck.residual`）统一检查
  `isValid`，有就抛 `.unsupported`。**运算本身从不抛错，抛错只发生在出口**，所以递归下降不会半途炸。
- 上限（`Limits`）：数字 9 位、指数 12、次数 24。超了报「超出演示范围」，不硬算。
- `Rational` 没有 `precondition` 了；`Poly.raised(to:)` 收到负指数也不 trap。

回归测试在 `V3Tests.testGarbageNeverCrashes`：17 条垃圾输入 × 4 个模式，断言"不崩 + 不判全对"。

### 10.2 极值点：导数三次以上用数值求根

第一版 `realRoots` 只解一、二次，`x^4-2x^2` 的导数 `4x^3-4x` 是三次，会**静默返回空数组**
——图上不标点，看起来像"算对了但没画"。现在：

1. 一、二次用求根公式（精确、无误差）。
2. 三次以上：在视窗内扫 1200 个点找变号区间，二分到 1e-12；偶重根（不变号）用
   `p'(r) ≈ 0` 且 `|p(r)| < 1e-9·scale` 补。
3. 根的个数 > 8 时只取前 8 个，并给降级码 `marks_truncated`。

极大/极小**看导数在根两侧的符号**，不看二阶导：`x^4` 在 0 处二阶导也是 0，但它是极小。
（`extremumKind` 里有注释，别改回去。）

### 10.3 「两边同乘/同除」算等价

第一版 `StepCheck` 直接比残差多项式，`2x+3=7 → x=2`（两边同除 2）会被判 `not_equivalent`。
现在残差相差一个非零常数倍就算等价（`StepCheck.proportional`）。

注意：Python 参考实现这一步的判法不同，所以 `parity_cases.json` **没有放 step 用例**。
演示不用 step 模式，主线不受影响；如果要两边一致，改 `server/math_engine/checker.py` 的
`check_step`。

### 10.4 积分：定积分精确，系数错单独分类

- 定积分用**牛顿-莱布尼茨 + 有理数**（`Poly.antiderivative` + `Poly.evaluate(Rational)`），
  不再是 Simpson 近似。Simpson 保留作非多项式兜底。
- 不定积分：对学生结果求导回验。若只差一个常数倍（`∫2x dx = x²/2`），报
  `wrong_coefficient` 并给出原函数，而不是笼统的 `integrand_mismatch`
  —— 和 Python 参考实现一致（对账 C14）。

### 10.5 direct 模式的一句话说明

`Explain` 里的模板只做一件事：**把计算得到的正确项嵌进一句人话**。例如

```
x 求导得 1，所以 −5x 求导后是 −5。
x³ 求导得 3x²，所以 −3x³ 求导后是 −9x²。
原式里的 3x² 求导后是 6x，这一项漏写了。
```

- 用 `PlainRender`（`x²`、`−3`）而不是 LaTeX —— 说明是给人读的，不是给 SwiftMath 排的。
  测试里有断言：说明里不许出现 `\frac`。
- 模板靠 `Defect.expectedPow` 找回原式里的那一项，所以 `wrong_term`/`wrong_coefficient`/
  `missing_term` 都能说出"从哪来、到哪去"，不是干巴巴一个答案。
- 不调模型、不走网络，所以**没有延迟**。Max 的润色流是可选叠加，3 秒没到就保留模板。

### 10.6 错项框：估算 + 吸附

1. `TermBox.estimate`：按字符宽度权重（`(` 0.5、`'` 0.35、上标 0.6、`^` 0）把 `char_span`
   映射到整行框的横向区间，把标签（`f'(x)`）也算进去；两侧各留 12%（≤10 pt），夹在整行框内。
2. `TermBox.snap`：中心落在这个区间里的笔画，取它们的外接矩形，外扩 6 pt。
   一笔都没有就返回 nil，调用方退回估算框。
3. 没有 `char_span` 的错误（`missing_term`、`not_derivative`）直接圈整行，`bbox_source = "line"`。

为什么不用 Flash 定位：多一次网络往返、多一个失败点，而横排中文/数学的一行里，字符宽度估算
的误差通常小于一个字符。**先圈出来**比圈得准更重要。

### 10.7 就绪判断（CheckGate）

`CheckGateSupport` 三个函数，P3 直接调，别自己写一套：

| 模式 | 判据 |
|---|---|
| `derivative` | 能解析 **且** 学生这一行的项数 ≥ 正确导数的项数 |
| `function` | 能解析且不是常数 0（双击 = 刷新图像，不批改） |
| `matrix` | 三个矩阵都写出来（能拆出 ≥ 3 个矩阵体） |
| `integral` | 有积分号、`dx`、等号，且等号右边能解析 |

**演示时的陷阱**（务必写进彩排清单）：学生写到 `3x^2-5` 时已经有 2 项、而且**是对的**；
停 1.5 秒它会当场判对并画切线。所以 `-5x` 要一笔连着写完。

### 10.8 代码地图

| 文件 | 内容 |
|---|---|
| `Core.swift` | `Rational`（带 invalid 哨兵）、`Poly`、LaTeX 清洗、词法、递归下降、`StudentLine`（带字符区间） |
| `Engine.swift` | 错误码、逐项比对、求导批改、函数场景（滑条/极值/切线/采样）、矩阵、积分、推导、几何、`HintGuard` |
| `Feedback.swift` | `FeedbackMode`、`PlainRender`、`Explain`（说明模板）、`CheckReadiness`/`CheckGateSupport`、`Box`/`InkStroke`/`TermBox` |
| `API.swift` | 契约的 Codable 类型、三个门面函数（`check`/`function`/`geometry`）、JSON 编解码策略 |
| `Parity.swift` | 与 Python 参考实现逐条对账 |
| `Sources/p4tool` | 命令行：生成契约 / 对账 / 打印黄金路径 |

### 10.9 验证（更新）

```bash
cd swift/MathEngine
swift test                                                 # 43 tests, 0 failures
swift run p4tool parity ../../contracts/parity_cases.json  # 对账 19/19 一致
```

夹具 48 条：parse 25 / equation 4 / function 7 / derivative 12 / matrix 2 / integral 5 / step 3。
对账 19 条：15 条批改 + 4 条场景。

**变异测试**（证明断言不是空转）：把夹具里 D01 的 `-3` 改成 `-3y` → 立刻红；
去掉「同乘常数算等价」→ step 测试红；去掉吸附外扩 → 错项框测试红。
