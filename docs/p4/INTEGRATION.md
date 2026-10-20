# 怎么和队友的东西接上（P1 / P2 / P3）

> 适用：`MathEngine/` 已作为本地 Swift Package 放进主仓（做法见 [`GIT-STEPS.md`](GIT-STEPS.md)）。
> 三个人各自的接入点都在这里，代码可以直接抄。

```
P1 手写 ──┐                                    ┌── P2 画面（Canvas）
          ├─→ MathEngine（P4，纯 Swift） ──────┤
P3 识别 ──┘   /check  /function  /geometry     └── P1 圈 + 气泡
```

**一个前提**：判定对错、算正确项、算极值点、算中点，全部在 MathEngine 里，**不要在 App 或 Server 里再写一遍**。
这也是答辩时唯一要讲清楚的技术点。

---

## 0. 三种接法，先选一种

| 接法 | 做法 | 什么时候用 |
|---|---|---|
| **A. 进程内直调（推荐）** | `import MathEngine` 后直接 `MathEngineAPI.check(req)`，几微秒 | 主线。断网、断热点都不影响判分，少一个失败点 |
| B. 走 P3 的 Vapor | HTTP `POST /check`，Server 里 decode → 调同一个门面 | 你要录回放、或者想用 Mac 上的模型做润色 |
| C. 混着来 | 判分走 A，`/hint` 润色流走 B | 最稳：圈和说明先出，模型的话后到，超时就丢掉 |

三种接法的**数据结构完全一样**（`CheckRequest` / `Annotation`），所以随时能从 A 换成 B，不用改 UI。

---

## 1. P1（笔迹）：你要的三样东西

### 1.1 一次批改只要 8 行

```swift
import MathEngine

// InkModel 维护：lineId（按 y 带分组，生成后不变）、revision（该行每变一次 +1）
let req = CheckRequest(
    mode: "derivative",                              // 界面分段按钮决定，不要传 auto
    lines: [.init(id: lineId,
                  latex: recognizedLatex,            // MyScript / Flash 的 LaTeX
                  bbox: lineBox,                     // [x,y,w,h]，画布 point、左上原点
                  revision: revision)],
    context: .init(functionLatex: "f(x)=x^3-5x"),     // 题目原函数
    strokes: inkModel.strokes(in: lineId),            // 整行现存笔画，用来吸附错项框
    feedbackMode: .direct
)

let annotation = MathEngineAPI.check(req)   // 同步；不需要 async，不要放主线程之外再等
```

**为什么可以同步调**：它是一次多项式解析 + 比对，微秒级。放进 `Task` 里只会让你多一层并发问题。

### 1.2 圈哪儿、写什么

```swift
for e in annotation.errors {
    let box = e.bbox ?? lineBox                    // 一定非 nil 的话直接用
    drawCircle(around: box)                        // e.bbox_source == "term" 时是那一项的框
    if let expected = e.expectedLatex {            // 只在 direct 模式有
        showBubble(at: box, math: expected)        // 用 SwiftMath 排版，颜色和墨迹区分
    }
    if let why = e.explanation {                   // 模板生成，0 延迟
        bubble.appendText(why)
    } else {
        bubble.appendText(e.hintFallback)          // socratic 模式 / 润色超时
    }
}
```

- `char_span` 是相对 `annotation.checked.rhsLatex[i]` 的，**不要**拿你上传的原文去算下标。
- 圈一定先出现：**先画 `bbox`，再等文字**。文字部分（Max 润色）是可选的，超时就丢掉。
- `annotation.ok == true` 时 `function` 字段可能带回来了场景，直接交给 P2，省一次往返。

### 1.3 双击与 CheckGate

```swift
// D2：双击统一语义为「确认」，不切橡皮。别显示 PKToolPicker。
func pencilDoubleTapped() {
    switch mode {
    case .function:  refreshSceneNow()                       // 函数模式：立即刷新图像
    case .derivative: runCheck(reason: .doubleTap)            // 跳过 1.5 s 等待
    case .geometry:  resolveGeometryNow()
    }
}

// 停顿时的判断（D1）
let readiness = CheckGateSupport.derivative(functionLatex: "f(x)=x^3-5x",
                                            lineLatex: recognizedLatex)
switch readiness {
case .ready:                         scheduleAutoCheck(after: 1.5)   // 再等 1.5 s 无新笔画
case .incomplete(_, let want):       showQuietHint("还差 \(want) 项") // 只回显，不批改
case .unparsable:                    showQuietHint("这一行没看清，点一下可以改")
}
```

**彩排陷阱**（务必写进 P1 的清单）：`f'(x)=3x^2-5` 已经是 2 项、而且是**对的**，
停 1.5 秒会当场判对并画切线。所以 `-5x` 要一笔连着写，别写一半停。

### 1.4 丢掉过期结果

```swift
if annotation.errors.first?.lineId == nil || revision <= lastAppliedRevision[lineId] { return }
```
引擎会把 `line_id` 原样回注；版本号比你当前的小，就是慢请求，丢掉。

---

## 2. P2（画面）：场景是结构，不是字符串

### 2.1 拖滑条不能发网络请求

```swift
// 第一次：拿到场景（可以来自 /function，也可以 App 内直接算）
var scene = try FunctionSceneBuilder.build("f(x)=x^3-5x")

// 拖 b 滑条（5 → 3）：本地重算，毫秒级
scene = scene.updated(values: ["b": 3])      // terms / 极值点 / 切线全部跟着变
```

- `scene.terms[i].param` 显式绑定滑条名，**不要靠下标**猜。
- `a = 0` 时曲线变直线，极值点自动清空；不要自己再判断一次。
- 要发给别人（或录回放）时用 `scene.payload`（就是契约里那段 `function`）。

### 2.2 曲线、极值、切线

```swift
let pts = scene.samples(count: 241)          // [(x, y)]，按 scene.view 均匀采样
for m in scene.marks where m.type == "extremum" { drawDot(m.x, m.y) }
for m in scene.marks where m.type == "tangent"  { drawHorizontalTangent(m.x, m.y) }

// 改对之后的可拖切点（A9，有余力再做）
let t = scene.tangent(at: 2, derivative: studentDerivative)  // slope 用学生写对的导数算
```

### 2.3 公式排版用 SwiftMath

| 要排的 | 来源 |
|---|---|
| 识别回显 | `checked.rhsLatex[i]`（或你手上的 LaTeX） |
| direct 模式的正确项 | `errors[].expectedLatex` |
| 坐标轴刻度、说明 | 用 `PlainRender.poly` / `PlainRender.number` 的文本就够，别排 LaTeX |

### 2.4 几何

```swift
// 每次拖动自由点，重算依赖点；中线是「顶点 → 对边中点」，交点自己会出现
let pts = Geometry.resolve(points: points, relations: relations)
```

`relations` 由 P3 从草图识别出来（`midpoint`）；认不出时就**保留原墨迹**，不要硬凑一个三角形。

---

## 3. P3（识别 + Server）

### 3.1 `/check` 只写三行

```swift
import MathEngine
import Vapor

app.post("check") { req -> Annotation in
    let body = try req.content.decode(CheckRequest.self, using: MathEngineJSON.decoder())
    return MathEngineAPI.check(body)
}
```

不要在这里再写一遍逐项比对 —— 那就是两套实现，联调时你会花几个小时找"到底谁错"。

### 3.2 你负责的边界

| 你负责 | 不要你来 |
|---|---|
| 识别（MyScript / Flash）→ LaTeX + 整行框 | 判对错、算正确项、算极值 |
| `InkModel` / `CheckGate` 的触发计时（可调 `CheckGateSupport`） | 说明文案的内容（`explanation` 已给） |
| `/hint` 的反问流（socratic）、Max 润色流 | direct 模式下等模型（模板说明已经够用） |
| 回放（录制真实返回） | 构造假返回当主线 |

`/hint` 在 direct 模式是**可选润色**：先显示 `explanation`，Max 的流式结果到了再替换，**3 秒没到就丢掉**。
这条要写死在客户端：不许等。

### 3.3 回放的两个坑

1. 命中键是规范化 JSON 的哈希 —— 请求体里**不能有**时间戳、UUID、随机 id。
2. `lines[].revision` 每次都会变。录制和回放必须用同一组 revision（把演示路径的 revision 固定下来），
   否则回放永远命中不了。演出前**一定要实测一次**。

### 3.4 识别协议（P3 实现，P4 只消费）

```swift
public protocol InkRecognizer {
    func recognize(strokes: [InkStroke], region: Box, mode: String) async throws -> (latex: String, bbox: Box)
}
```
三个实现：MyScript（设备上）、Flash（经 Server）、回放（录好的字符串）。
引擎不关心是谁给的 LaTeX，只要求**字符串和整行框**。

---

## 4. 接缝清单（联调时按这个表查，30 秒定位）

| 现象 | 先查这里 | 谁的锅 |
|---|---|---|
| 圈在整行、没圈到那一项 | `errors[].bbox_source`：是 `line` 说明没有 `char_span`（`missing_term` / `not_derivative` 本来就圈整行） | 不是 bug |
| 圈偏了一截 | 传没传 `strokes`？传了才会吸附；没传就是按字符宽度估算 | P1 传笔画 |
| `expected_latex` 是 `null` | 请求里 `feedback_mode` 是不是 `socratic` | 契约就是如此 |
| 拖滑条卡 | 是不是把 `updated(values:)` 写成了一次 `/function` 请求 | P2 |
| 说明等很久才出现 | 是不是在等 Max；`explanation` 本地就有，应该先显示 | P3 |
| 回放不命中 | revision 变了 / 请求体里有时间戳 | P3 |
| 判对错和 Python 版不一致 | 跑 `swift run p4tool parity contracts/parity_cases.json` | P4 |

---

## 5. 十分钟联调清单（谁先 green 谁先跑）

1. `cd MathEngine && swift test` → 43 tests, 0 failures
2. `swift run p4tool parity ../../contracts/parity_cases.json` → 19/19
3. P2：解 `contracts/v3/function.response.json` 能画出 `x^3-5x` 的曲线和两个极值点
4. P1：解 `contracts/v3/check.request.json`，用它的字段拼一个请求，拿到 `wrong_term` + 圈
5. P3：`/check` 返回的 JSON 与 `contracts/v3/check.response.json` 字段一一对上
6. 三方都绿，才允许开始改各自的逻辑
