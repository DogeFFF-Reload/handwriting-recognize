# 笔迹 AI 家教：Swift 原生 48 小时方案

日期：2026-10-19。本文汇总 Opus 的《笔迹 AI 家教 · 48 小时黑客松开发方案》，并按下面三条改写：

- 只做 iPad + Apple Pencil。不做 Windows，不做 Android，不做联想平板。
- 客户端、数学引擎、后段服务都用 Swift。不使用 WKWebView、JSXGraph、Vite、FastAPI 或运行时里的 SymPy。
- 数据流固定为四段：手写，识别成数学语言，后段计算和大模型，再把反馈画回笔迹。

Opus 原文里的黄金路径、错误不直接给答案、流式提示和断网回放都保留。被删掉的是跨平台那一层。

---

## 1. 演示只做这一条

48 小时交付一个约 3 分钟、在真机上跑通的 SwiftUI App。横屏。左半是 PencilKit，右半是 SwiftUI Canvas。不在笔迹原位长出控件；左右分屏更稳。第 30 小时之后若主线已经真机跑通，才考虑把圈画在原笔迹上，这一项本来就是主线，不后移。

1. 函数图像。学生写 `f(x) = x^3 - 3x`。右侧立刻画出图像。把系数 3 改成 1，图像变形，系数变成滑条。
2. 导数批改。学生写下 `f'(x) = 3x^2 - 3x`（故意错）。错误的 `-3x` 被圈出，旁边只问：「x 这一项求导后还剩什么？」改正后，图像标出 `f'(x) = 0` 的极值点和切线。屏幕上始终不出现正确导数 `3x^2 - 3`，除非学生自己写出来。
3. 几何。学生手绘三角形和一条中线。画面变成动态几何：拖动顶点时，中线仍过对边中点。三条中线都画出来时，交于一点是构造的结果，不另做求解器。
4. 加分。2×2 矩阵乘法，或一个多项式的不定积分。错步圈出。主线没绿之前不做。

不做：物理和电路、任意题型的通用识别、账号和题库、公网部署、浏览器端、第二套手写画布。

| 级别 | 内容 | 到点没完成就 |
| --- | --- | --- |
| P0 | 第一幕、第二幕在 iPad 真机跑通；错项圈注加一句启发式提问 | 第 30 小时。几何和加分全部停 |
| P1 | 第三幕几何，仍是同一个 SwiftUI 画面 | 第 36 小时 |
| P2 | 矩阵或积分批改；提示语音 | 有余力才做 |

---

## 2. 四段数据流

```text
Apple Pencil
    |
    v
[1 手写]  PencilKit
    PKCanvasView，drawingPolicy = .pencilOnly
    笔画 id、PKStrokePoint（x, y, 时间, 压感）
    |
    v
[2 数学语言]  识别器，只输出 LaTeX
    优先 MyScript iink（设备上）
    4 小时实测不够准时，改 Qwen-Flash 看这一行的截图
    学生在笔迹下方看到 SwiftMath 排好的式子，点一下可改
    |
    v
[3 后段]  同一个 Swift Package：MathEngine
    计算：解析、求导逐项比对、等价、极值、中点
    大模型：只有计算已经判定「错」之后，Qwen-Max 把错误码说成一句问话
    |
    v
[4 反馈]  回到 SwiftUI
    圈在错项的笔画包围盒上
    问话用 SSE 逐字出现
    右侧 Canvas 按 MathEngine 的场景重画
```

对错不由大模型决定。大模型看不到「请判断学生是否正确」这种任务。它只拿到错误码、学生写的那一项、题目，输出 30 个字以内的反问。

正确导数可以留在 MathEngine 的测试和提示生成里。视图用的结构体里没有这个字段，避免调试时把它画出去。

### 为什么后段仍是一个 Mac 上的 Swift 进程

计算本身可以放在 App 里，MathEngine 是纯 Swift，不依赖服务器。密钥不能放进 iPad 安装包。因此仓库里有一个 Vapor 进程，跑在演示用的 Mac 上：

- `/check`、`/function`、`/geometry` 只是把 MathEngine 的函数包成 HTTP，方便换模型和做回放。
- `/hint` 持有阿里云百炼的 Key，向 iPad 推 SSE。
- iPad 和 Mac 连同一个热点。不部署到公网。

识别若走 MyScript，LaTeX 在设备上就产生，iPad 把 LaTeX 而不是整页图发给后段。只有 Flash 后备路径才上传该行 PNG。

---

## 3. 数学语言长什么样

识别器的产物只有 LaTeX 和这一行在画布上的框。坐标用 iPad 画布的 point，原点在左上角。模型若返回的是图片像素，后段用上传时带的裁剪偏移换算回画布坐标，再把框吸附到框内真实笔画的外接矩形。吸附失败就圈整行。

学生抬笔并停约 700 ms，发送一次。界面顶部用分段按钮指定模式：函数、推导、几何。不让模型猜当前在做什么。

```json
{
  "mode": "derivative",
  "region": { "x": 40, "y": 320, "w": 600, "h": 140, "scale": 2 },
  "latex": "f'(x)=3x^2-3x",
  "strokes": [
    { "id": "s17", "points": [[318.0, 350.0, 1.20, 0.62]] }
  ],
  "context": { "function_latex": "x^3-3x" }
}
```

`points` 的四元组是 `[x, y, 时间秒, 压感]`，来自 `PKStrokePoint`。Flash 后备路径才附加 `image_base64`。

计算之后给画面的是场景，不是 JavaScript 字符串。Opus 方案里的 `expr_js` 删掉，改成 Swift 能直接求值的结构。

```json
{
  "kind": "function",
  "lines": [
    { "id": "L1", "latex": "f(x)=x^3-3x", "bbox": [40, 120, 420, 180] }
  ],
  "function": {
    "terms": [
      { "coef": 1, "pow": 3 },
      { "coef": -3, "pow": 1 }
    ],
    "params": [
      { "name": "a", "value": 1, "min": -3, "max": 3 },
      { "name": "b", "value": 3, "min": -5, "max": 5 }
    ],
    "marks": [
      { "type": "extremum", "x": -1, "y": 2 },
      { "type": "extremum", "x": 1, "y": -2 }
    ]
  }
}
```

几何场景不用函数字段，改成：

- `points`：id、是自由点还是受约束点、坐标
- `objects`：线段或圆，引用点的 id
- `relations`：例如 `{"type":"midpoint","of":["B","C"],"point":"M"}`

自由点可以被拖。受约束点每次拖动后由关系重算。中线是「顶点到对边中点」的线段。三条中线都用这个关系构造，交点会自己出现。这是 GeoGebra 里自由对象和依赖对象的分法，不是把 GeoGebra 嵌进来。

批注：

```json
{
  "ok": false,
  "errors": [
    {
      "line_id": "L2",
      "kind": "wrong_term",
      "wrong_latex": "-3x",
      "bbox": [318, 336, 372, 380]
    }
  ],
  "hint_url": "/hint/7f3a"
}
```

这里没有 `expected_latex`。正确项只存在于后段内存，供提示模型使用。客户端画圈，然后订阅 `hint_url`。

---

## 4. 后段计算

MathEngine 只保证黄金路径和加分题。超出范围就返回「这一步的形式不在演示范围内」，不要假装化简成功。

| 任务 | 谁做 | 做法 |
| --- | --- | --- |
| 当前是哪一幕 | 界面分段按钮 | 不交给模型 |
| 笔迹到 LaTeX | MyScript iink，不够准再换 Flash | 一行一个 LaTeX，加坐标框 |
| 哪一项错 | MathEngine | 见下 |
| 错项在纸上的位置 | 笔画包围盒；Flash 只在有截图时做一次定位 | 框吸附到真实笔画 |
| 问句 | Qwen-Max，流式 | 30 字以内的反问；输出里若出现正确项就丢弃并重试 |
| 函数到图像 | MathEngine | 数字系数变成滑条；Canvas 采样画线 |
| 草图到几何 | Flash 输出点和关系，MathEngine 校验关系是否成立 | Canvas 按关系重画，不照抄草图坐标 |

求导的比对，针对 `x^3 - 3x` 这种多项式：

1. 解析学生写出的右端，收成「系数 × x 的幂」。
2. 对原函数逐项求导，也收成同样的项。
3. 按幂对齐。学生多出来的项、系数不对的项，记为 `wrong_term`。`-3x` 对上的正确项是常数 `-3`，错误码就是这个。
4. 提示禁止包含 `-3` 作为单独答案，也禁止包含 `3x^2-3`。

连续推导若以后加题：两项都解析成多项式后，系数逐项相减，全为 0 才算等价。不引入通用 CAS。

积分加分题：对学生的结果再求导，看是否回到被积函数。做不到的换元题直接不做。

矩阵加分题：只做 2×2 乘法，逐元素比对。

极值点：对 `a x^3 - b x` 手写二次公式。`a = 0` 时当直线处理，不标极值。切线只在第二幕改对之后才画。

几何不跑数值约束求解。模板只有一个：三角形加中点。Flash 认不出中线，就保留原墨迹并说明收不进去，不要硬收成一个错误的三角形。

### 大模型怎么接

开工前在阿里云百炼控制台核对，不要凭教程里的模型名直接写死。Opus 依据的教程是：

- 兼容 OpenAI 的接口。新加坡区域 `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`，该教程称这是当时唯一有免费额度的区域。大陆区域是 `https://dashscope.aliyuncs.com/compatible-mode/v1`。
- Max 的名字写成 `qwen3.8-max`。Flash 的名字以控制台为准。
- 生成提示时关闭或调低推理：`extra_body` 里 `enable_thinking=false`，或 `reasoning_effort=low`。教程称默认 `xhigh` 会把这一句问话拖慢。
- 教程中的价格大约是 Max 每百万 token 输入 2 美元、输出 6 美元，Flash 约 0.15 / 0.47 美元。整场黑客松费用不是风险，额度不够才是风险。价格以控制台为准。

Roboflow 对 Qwen3.8-Max 的评测认为它读手写偏弱。所以 Max 不负责识别。第 0–4 小时用手写 20 张黄金题目，分别记 Flash 和 MyScript 的准确率和耗时。MyScript 能导出 LaTeX，并覆盖公式和矩阵，还有官方 iOS 示例工程。证书当天申请。两边都不可用时，演示改走录好的 LaTeX 回放，不当场换第三家。

Mathpix 的 Strokes API 也能从坐标出 LaTeX，但是 HTTP 服务，不是 Swift 库。只在 MyScript 证书下不来、Flash 又不稳时作为第二后备。

---

## 5. 相关仓库：用什么，不用什么

### GeoGebra，只作行为参照

[geogebra/geogebra](https://github.com/geogebra/geogebra) 是 GeoGebra 数学应用的源码镜像，语言是 Java。README 给出的跑法是 Gradle：网页版 `./gradlew -p source/web :web:run`，桌面版 Classic 5 走 `source/desktop`。开发环境写的是 IntelliJ 和 Java 8。官方许可说明里，源码是 EUPL 1.2；安装包、网页服务和界面资源是另一套条款，非商业使用也要保留署名。嵌入网页用的是 `deployggb.js`，见 [geogebra/integration](https://github.com/geogebra/integration)。商业或深度集成要单独联系 GeoGebra。[geogebra/solver-engine](https://github.com/geogebra/solver-engine) 是他们的求解器，GPL-3.0-or-later，同样不是 Swift。

48 小时内不要克隆这个仓库，不要把 App 嵌进 WebView 去加载 GeoGebra。原因有四条：它不是 Swift；仓库和构建链是 Java / GWT；许可不是「拷进商业演示就不用管」；黄金路径的中点关系用几十行 Swift 就能维持。

要从它拿走的只有对象模型：

- 自由点可以被用户拖动。
- 依赖点由关系定义，不单独存储「真坐标」。
- 拖动自由点后，依赖对象重算。中点关系因此不会丢。
- 代数和几何是同一条表达式的两种视图。本方案里，这条表达式是 MathEngine 的 `terms`，右半边 Canvas 只是视图。

### 要放进工程的

| 仓库或框架 | 放在哪 | 原因 |
| --- | --- | --- |
| PencilKit / SwiftUI / Canvas | App | 手写、掌托、圈、滑条、图像、几何都在这里 |
| [MyScript/interactive-ink-examples-ios](https://github.com/MyScript/interactive-ink-examples-ios) | 识别 | 官方 iOS 示例。数学笔迹导出 LaTeX、MathML。需要证书 |
| [mgriebling/SwiftMath](https://github.com/mgriebling/SwiftMath) | 回显 | 纯 Swift 排版 LaTeX，SwiftUI 可用，不需要 WebView。MIT。回显「我读成了这个」 |
| [vapor/vapor](https://github.com/vapor/vapor) | Mac 上的后段 | Swift 的 HTTP 和 SSE。只为了扣住 API Key 和回放 |

[kostub/iosMath](https://github.com/kostub/iosMath) 是 SwiftMath 的前身，Objective-C，也能排版。已经选了 SwiftMath 就不要两套一起链。若 SwiftMath 排不了演示里的矩阵，再评估 [PhraseHQ/SwaTex](https://github.com/PhraseHQ/SwaTex)。它是纯 Swift 的 KaTeX 风格渲染器，要求大约 iOS 18 和 Xcode 16.3。主线多项式用不到它。

### 明确不放进 App 的

- JSXGraph。Opus 用它是因为要和 Windows 共用一个网页。这个前提已经取消。
- GeoGebra 源码和 `deployggb.js`。
- SymPy、latex2sympy2、FastAPI。多项式求导不值得为了它们带一个 Python 运行时。赛前可以用任何计算机代数系统生成 10 条用例的期望项，把期望写进 XCTest，比赛时不再调用。

---

## 6. 工程和分工

一个仓库，三个 Swift 目标：

```text
InkTutor/
  App/            SwiftUI + PencilKit + Canvas
  MathEngine/     Swift Package，App 和 Server 都链接它
  Server/         Vapor
  contracts/      三份 JSON 样例
```

第 0–2 小时四人一起定这三份 JSON。之后各自对假数据开发。

| 角色 | 负责 | 第 20 小时要交出 | 技术 |
| --- | --- | --- | --- |
| P1 笔迹 | 画布、700 ms 提交、模式按钮、圈和气泡、回放开关 | 真机写字，发出请求，把假批注画成圈 | SwiftUI、PencilKit |
| P2 画面 | 函数曲线、滑条、极值、切线、三角形和中线 | 喂假场景就能拖 | SwiftUI Canvas |
| P3 识别和提示 | MyScript 或 Flash、提示词、SSE、缓存 | 20 张样本有一份可用的 LaTeX；`/hint` 能逐字输出 | Swift、URLSession 或 Vapor |
| P4 计算和路演 | MathEngine、10 条 XCTest、脚本、备用视频 | `/function` 和 `/check` 对 10 条全部判对 | Swift、XCTest |

P4 决定砍什么。P1 是唯一的真机风险：第 4 小时前空壳必须装上 iPad。免费个人证书在 48 小时内够用。P2 提前做完，就去帮 P1 接场景渲染，而不是新开一个平台。

协作：P3 在第 2 小时给出只返回假 JSON 的 Server。每 6 小时站会 10 分钟。接口只许先改 `contracts/` 再改代码。

---

## 7. 48 小时

第 30 小时是硬线。第一幕和第二幕没有在真机上连着跑通，所有人回到这两幕。

| 时段 | P1 笔迹 | P2 画面 | P3 识别和提示 | P4 计算和路演 |
| --- | --- | --- | --- | --- |
| 0–4h | 建工程，空壳上真机，Pencil 能写 | Canvas 画出写死的 `x^3-3x` | 申请 Key 和 MyScript 证书；20 张样本实测 | 定题，写 10 条期望项的测试 |
| 4–20h | 停笔提交、圈的动画、请求编码 | 滑条、极值、切线、中点三角形 | `/recognize` 或设备上的 iink；`/hint` 流式 | `/function`、`/check` 和那 10 条测试 |
| 20–30h | 接真后段，跑通前两幕 | 接真场景 | 错项框吸附；缓存和回放 | 记录每次失败并改期望或解析 |
| 30–40h | 只打磨手感 | 接入第三幕 | 有余力再做矩阵或积分的识别样本 | 路演稿 |
| 40–48h | 只修 bug | 只修 bug | 确认额度，回放开关演练 | 彩排 5 遍，录本地备用视频 |

---

## 8. 风险

| 风险 | 应对 |
| --- | --- |
| 手写转 LaTeX 错 | 前 4 小时实测后选定 MyScript 或 Flash。笔迹下用 SwiftMath 回显，点一下改。演示题固定，事先把那几种写法练熟 |
| Max 慢 | 提示请求关掉长推理；先画圈，字后到。圈不依赖 Max |
| 框偏了 | 吸附到框内笔画的外接矩形；失败就圈整行 |
| LaTeX 解析失败 | 只接受演示里出现的写法：多项式、`f(x)=`、`f'(x)=`、乘号写成 `\cdot` 或省略。每条黄金用例一条 XCTest |
| 提示把答案说出来了 | 生成后做子串检查，包含正确项就重试一次，再失败就换成写死的问句：「x 这一项求导后还剩什么？」 |
| 会场网络差 | Mac 跑 Vapor，iPad 连同一热点。不从网上加载字体或脚本。SwiftMath 的字体打进包 |
| 接口超时 | 黄金路径每一步的真实响应存在 Server 里。先真跑，3 秒没返回再切回放。评委问起就说明这是录好的返回 |
| 只有一个人会 Swift | 第 4 小时前 App 上真机。画面和 MathEngine 也是 Swift，不能再把工作丢给网页 |
| 主办方临时要求联想平板 | 本方案不覆盖。不要在比赛中途改回网页版 |

演示前：黄金路径真机连续成功 5 次；回放在 Mac 热点关闭外网时仍能跑完；备用视频在 iPad 和 Mac 本地各一份；iPad 满电，关自动锁屏和通知；Key 的余额看过一眼。

---

## 9. 和 Opus 方案的差异

保留：三幕脚本、700 ms 提交、场景和批注分开、提示流式、先圈后字、回放、第 30 小时砍范围、Qwen 的 Flash / Max 分工、识别结果允许手改。

改掉：

- Windows 列、浏览器手写、WKWebView 桥、JSXGraph、KaTeX、Vite，全部去掉。右半边是 SwiftUI Canvas。
- `expr_js` 改成系数和幂的列表，避免后段生成脚本。
- 批注 JSON 不再带 `expected_latex`。
- 运行时不再调用 SymPy。多项式和中点由 MathEngine 计算。
- 识别的第一选择改成 MyScript 的 iOS SDK，因为后段要的是数学语言，而 Max 不被用来读手写。
- 仓库从 `ios/`、`web/`、`server/` 改成 `App/`、`MathEngine/`、`Server/`，后两个都是 Swift。

---

## 10. 材料

1. Opus，《笔迹 AI 家教 · 48 小时黑客松开发方案》，2026-10-19。本文的脚本、时间和模型分工来自这份 PDF，平台决策已改。
2. GeoGebra 源码镜像：https://github.com/geogebra/geogebra
3. GeoGebra 许可说明：https://www.geogebra.org/license 以及 https://github.com/geogebra/legal/blob/main/geogebra_license.md
4. GeoGebra 网页嵌入示例：https://github.com/geogebra/integration
5. GeoGebra solver-engine：https://github.com/geogebra/solver-engine
6. MyScript iOS 示例：https://github.com/MyScript/interactive-ink-examples-ios
7. MyScript SDK 产品说明：https://www.myscript.com/sdk/
8. SwiftMath：https://github.com/mgriebling/SwiftMath
9. Vapor：https://github.com/vapor/vapor
10. Qwen3.8 的模型名、区域和价格，以阿里云百炼控制台为准。Opus 引用了 Roboflow 对 Max 手写能力的评测、OrcaRouter 的型号说明和 DEV Community 的 API 教程；开工前对照控制台，不照搬教程里的模型字符串。
