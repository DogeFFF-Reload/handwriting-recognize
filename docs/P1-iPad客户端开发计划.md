# 笔迹 AI 家教 · P1 iPad 客户端开发计划

日期：2026-10-20。

这份报告补在 @DogeFFF 的《笔迹 AI 家教 · 开发方向报告》（2026-10-20，11 页）后面。那份 PDF 定了 D1–D5，并写完了 P2（右半屏画面）和 P3（识别与反馈逻辑）。P1 在里面只作为「真机风险点」出现，没有自己的时间行。

P1 由我做，不能再拆给别人。原因就一条：团队里只有我这一台 MacBook 能装 Xcode、签名、装到设备上；演示机是我的 iPad Pro，笔是 Pencil Pro。仓库用已经建好、目前还是空的私有库：

[DogeFFF-Reload/handwriting-recognize](https://github.com/DogeFFF-Reload/handwriting-recognize)

基线仍是 [笔迹AI家教-Swift原生48小时方案.md](笔迹AI家教-Swift原生48小时方案.md)。更早那份含 Web 和联想平板的方案作废。本文不重写 P2、P3、P4 的算法，只规定客户端怎么接、什么时候在真机上必须绿。

---

## 1. 已核对的事实

2026-10-20 用本机 `gh` 看过这个仓库，不是猜测：

| 项 | 状态 |
| --- | --- |
| 地址 | `https://github.com/DogeFFF-Reload/handwriting-recognize` |
| 可见性 | 私有 |
| 内容 | 空。`size = 0`，没有任何分支和提交，`main` 还没被第一次 push 创建出来 |
| 创建时间 | 2026-10-19 16:29 UTC |
| 有 push 权限的人 | `RuikAn-n`（本机账号）、`DogeFFF-Reload`、`Drkarmic`、`Interphynity` |

PDF 最后一条未勾选项因此可以划掉一半：装有 Xcode 的 Mac 只有这一台。P2、P3 可以在自己的编辑器里写 Swift 源文件并推到自己的分支，但不能在自己的电脑上编译，更不能装到 iPad 上。每一次「能跑」都要回到这台 MacBook。

设备也只有这一套，时间要错开，不能两个人同时占用：

- 第 0–2 小时：iPad 在我这里，装空壳，做下面第 5 节的三项真机验证。
- 第 2–4 小时：iPad 交给写 20 条样本的人，在 MyScript 官方示例里手写。第 4 小时必须还回来。
- 第 4 小时之后：iPad 留在我这里，直到第 30 小时的硬线。别人要看效果，看我装上去的那一版，不把线拔走。

MyScript 的设备证书已经在本机 `~/Downloads/MyCertificate.c`。那是 iOS 本地引擎的证书，不是 HTTP API key。证书正文不进仓库，不进这份报告。云端识别 key 目前没有，P1 也不依赖它。

---

## 2. P1 做什么，不做什么

P1 是 App 壳、笔、签名和装机。逻辑和右半屏画面仍按 PDF 的分工写，但是只有我能把它们编进同一个 App。

| 归我 | 不归我 |
| --- | --- |
| Xcode 工程、签名、装到这台 iPad Pro | `FunctionPlotView`、滑条、极值点、切线、`GeometryView` 的绘制（P2） |
| `PKCanvasView`、不显示 `PKToolPicker`、笔/橡皮按钮 | `InkModel`、`CheckGate`、`InkRecognizer`、说明模板、Vapor（P3） |
| `UIPencilInteraction`：双击 = 确认，Pencil Pro 捏一下 = 切橡皮 | `MathEngine` 的求导、项数、极值（P4） |
| 笔画回调里调用 `InkModel`，把 Pencil 事件交给 `CheckGate` | 20 条样本的 Flash 脚本和对答案 |
| 左半屏上的回显、圈、正确项、说明、双击闪边 | 百炼的模型名、额度和 Key |
| 右半屏只留一个容器，喂进 P2 的视图 | 把 GeoGebra、JSXGraph、WKWebView 嵌进来 |
| 第 20 小时把 P3 的包换上，编不过就退回占位实现 | 在笔迹原位长出滑条或按钮 |
| 第 30 小时宣布前两幕是否在真机上绿 | |

PDF 里 P2 的 `MathLabel`（SwiftMath）我只留位置。包没到的时候，回显先用等宽字体把 LaTeX 原文画出来，不让排版挡住装机。SwiftMath 的仓库是 [mgriebling/SwiftMath](https://github.com/mgriebling/SwiftMath)。

圈画在错项包围盒上，这是前两幕的主线，不放到第 30 小时以后。往后推的只有「笔迹上长出控件」这一件。PDF 的 A10 还标着待定，客户端按已经写进演示脚本的那条做：圈、正确项、一句话都在左半屏。

---

## 3. 空仓库的第一笔提交

仓库现在没有 `main`。第一笔提交只能从这台 Mac 推，因为要确认工程能签上这台 iPad。别人不要往一个还不存在的历史上推第一笔。

第一笔只包含能编译的空壳和契约，不包含识别引擎：

```text
handwriting-recognize/
  README.md                         指向本报告，写明谁有 Mac
  .gitignore                        见下
  contracts/
    upload.sample.json              PDF 第 6 页那份上传 JSON
    annotation.sample.json          PDF 第 6 页那份批注 JSON
    scene-function.sample.json      右半屏假场景，P2 和 P1 共用
    scene-geometry.sample.json
  app/                              Xcode 工程，横屏，左右分屏
  Packages/InkCore/                 空包，放 P1 的占位协议；P3 之后往这里补
  Packages/SceneUI/                 空包，P2 的视图以后放这里
  docs/device.md                    第 0 小时填：iPad 型号、iPadOS 版本、三项验证的结果
```

`.gitignore` 至少有这些，第一笔提交之前就放进去：

```text
MyCertificate.c
**/MyScriptCertificate/
.env
*.mobileprovision
xcuserdata/
DerivedData/
```

分支：

- `main`：只有我合并。含义是「这一版已经装在 iPad 上跑过」，不是「源码看起来对」。
- `p2/scene`、`p3/ink`、`p4/math`：其他人推。我在这台 Mac 上拉下来编译。编不过，我把编译错误贴回去，不在他们的分支里改算法。

证书的用法：官方示例和以后我们自己的 App，都从 `~/Downloads/MyCertificate.c` 复制到工程里的 gitignore 路径。不把这份文件 `git add`。

---

## 4. App 的形状

横屏。左半是笔，右半是场景。模式用顶上的分段按钮：函数、推导、几何。不让识别器猜现在在做哪一幕。

```text
iPad Pro + Pencil Pro
        |
        v
PKCanvasView          drawingPolicy = .pencilOnly
无 PKToolPicker       笔/橡皮是 SwiftUI 按钮
        |
        |  canvasViewDrawingDidChange
        v
InkModel.note(strokes)     第 20 小时前用 App 内的同名占位
        |
        +---- 抬笔 700 ms ----> 只识别，笔迹下方回显 LaTeX
        |
        +---- 条件 a 或双击 --> CheckGate --> 批注
        |
        v
左半屏叠层：圈、正确项、说明、行边框闪烁
右半屏容器：吃 scene JSON，P2 的视图没到就画假场景
```

占位类型现在就定死，避免第 20 小时换包时改画布。P3 的包要满足这几个入口，而不是反过来让画布去迁就他们的类名：

```swift
struct InkLine: Equatable {
    var id: String           // "L2"，生成后不变，删光也不复用
    var revision: Int        // 这一行每增删一次笔画 +1
    var mode: InkMode        // 建行时的分段：函数 / 推导 / 几何
    var band: CGRect         // 画布 point，原点左上
    var strokes: [InkStroke] // 这一行现存的全部笔画，不是增量
    var removedStrokeIDs: [String]
}

protocol InkModeling {
    func apply(strokes: [InkStroke]) -> [InkLine]
}

protocol CheckGating {
    func strokeChanged(line: InkLine, at: Date)
    func recognitionReturned(lineID: String, revision: Int, latex: String, termCount: Int, parseable: Bool)
    func doubleTapped(lineID: String)
}
```

`CheckGate` 的判定仍按 PDF，P1 不重写规则，只保证事件真的送到：

- 停 700 ms：只回显，不圈。
- 条件 a 必须三条同时成立：这一行能解析、项数达到 `MathEngine` 给出的预期、1.5 秒没有新笔画。第二幕 `x^3-3x` 的导数预期是 2 项；写成 `3x^2 -` 时只有 1 项，不批改。
- 任何新笔画或擦除：1.5 秒计时清零，该行 `revision + 1`。
- 同一 `revision` 只批改一次。
- 双击跳过等待和项数判断。解析失败就不批，气泡写「这一行没看清，点一下识别结果可以手动改」。
- 函数模式不批改。双击等于立即刷新右半屏。

项数在 `MathEngine` 到达之前，占位实现只认第二幕：预期项数写死为 2。这只为了第 20 小时前能在真机上看到触发，不把它当成批改器。

坐标在 App 内部只用画布 point 的 `CGRect`。PDF 的上传是 `{x,y,w,h}`，批注的 `bbox` 是 `[x1,y1,x2,y2]`。转换放在一个文件里。A3 还没拍板之前，线上两种都收，不在联调时现改画布。

过期结果丢掉：回显、圈、说明都带 `line_id + revision`。比当前行小的版本直接丢，避免圈闪在已经擦掉的字上。

`feedback_mode` 第一版固定 `direct`。正确项用和墨迹不同的颜色，经 `MathLabel` 或等宽文本画在圈旁边。`socratic` 的开关留在模型里，界面不做。

---

## 5. 第 0–4 小时，真机上必须先做完的事

下面前三项不成立，D2、D3 就要改。所以它们发生在装业务逻辑之前。结果写进 `docs/device.md`，三行就够：型号、系统版本、通过或失败。

Pencil Pro 装在 iPad Pro 上，捏压这条按有来做。系统版本仍以「设置 › 通用 › 关于本机」为准，不凭记忆写死。

1. 不显示 `PKToolPicker`。画布上加 `UIPencilInteraction`。iPadOS 17.5 及以后实现 `pencilInteraction(_:didReceiveTap:)` 和 `pencilInteraction(_:didReceiveSqueeze:)`。系统更旧才补已经弃用的 `pencilInteractionDidTap(_:)`。设置里的「轻点两下」保持默认「在当前工具和橡皮擦之间切换」，不要设成「运行快捷指令」。`preferredTapAction` 只读，执不执行由 App 定。通过标准：双击不把画布切成橡皮，回调进我们的 delegate，当前行边框闪一次。失败：双击不再当确认，屏幕上加一个「批改」按钮顶上；捏压如果还在，仍用来切橡皮。
2. 双击回调里有没有落点，打印一次。有 `hoverPose` 就用落点选行；没有就作用在最近改过的那一行。不要猜。
3. 橡皮只用 `PKEraserTool(.vector)`。擦掉一整笔之后，`drawing.strokes` 里该笔消失，用 `stroke.path.creationDate` 加包围盒能找到它，并记进所在行的 `removed_stroke_ids`。不用 `.bitmap`，那会把一笔切成几段，id 对不上。失败：不改用 bitmap；退回到「每次变更保存一份笔画快照」，用整笔路径相等来找被删的那一笔。

同一段时间把官方示例装上，但不把 MyScript 编进我们的 App。PDF 的 D4 就是这条。

1. 克隆 [MyScript/interactive-ink-examples-ios](https://github.com/MyScript/interactive-ink-examples-ios)。
2. 把 `~/Downloads/MyCertificate.c` 复制到示例里的 `Examples/GetStarted/GetStarted/MyScriptCertificate/MyCertificate.c` 和 `Examples/Demo/Demo/MyScriptCertificate/MyCertificate.c`。
3. 用这台 Mac 的个人团队签名，装到这台 iPad。免费描述文件够 48 小时；示例如果拒签，再换付费团队，不开工前就去办。
4. 打开数学示例，确认导出的是 LaTeX。示例里如果带求解或直接给出数值结果，关掉，我们只要识别。数学识别资源是证书之外的另一份资源，示例装完却不能识别公式时，缺的是这份资源，不是证书坏了。
5. 第 2 小时把 iPad 交出去写 S01–S20。第 4 小时拿回来。选引擎是 P3 的表：黄金行连写 3 遍都对，20 条里至少 16 条，MyScript 低于 500 ms 才当主路径。

我们自己的 App 在这 4 小时里只要求：横屏分屏、能写、能整笔擦、双击闪边、捏一下切换笔和橡皮。右半屏放 `contracts/scene-function.sample.json` 的假曲线。识别结果用手动改过的 LaTeX，或一份录好的回放。

---

## 6. 第 4 小时之后才把识别接进 App

引擎选定之前，App 里的 `InkRecognizer` 只有两个实现：手动改回显、回放。这样前两幕的圈和右半屏不靠网络，也不靠 MyScript 的集成进度。

选定之后仍然只有我能接，因为要改签名工程：

- 主路径是 MyScript：用 [MyScript/interactive-ink-packages-ios](https://github.com/MyScript/interactive-ink-packages-ios) 加进我们的工程，证书仍走 gitignore 的那份副本。送进识别器的是这一行现存的全部笔画。只要 LaTeX 和这一行的框。求解保持关闭。
- 只有 Flash 达标：上传才带整行截图。图从这一行的 `band` 裁，坐标换算回画布 point 再吸附到真实笔画的外接矩形。吸附失败就圈整行。
- 两个都不达标：演示走回放。回放开关第 4 小时就要在 App 里，不临时加。

擦除后的行为已经定了，客户端不要做增量识别。每次都把这一行还在的笔画整行送出去。几何模式和矩阵题不分行，整块区域是一个 `line_id`。

---

## 7. 补上 PDF 时间线里缺的 P1 行

PDF 的五段不动。P2、P3 仍按他们的表交。下面只是我这台机器上的顺序。

| 时段 | 我在 iPad 上要看到的 | 到点没有就 |
| --- | --- | --- |
| 0–4 小时 | 空壳装上；三项笔验证有记录；MyScript 示例能导出 LaTeX；假场景出现在右半屏 | 第 4 小时还写不了字，就停掉后面全部业务，先修画布 |
| 4–20 小时 | 占位 `InkModel` 能分行、能记 `removed_stroke_ids`；占位门禁能在双击和第 2 幕「写满 2 项再停 1.5 秒」时各触发一次；圈能画在假 `bbox` 上 | 继续用占位。不把手头的画布停下来等 P3 的包 |
| 第 20 小时 | 拉 `p3/ink`。能编译就换成他们的 `InkModel` 和 `CheckGate`，画布回调不改。不能编译就留占位，把错误退回 | 不在这一小时重写他们的规则 |
| 20–30 小时 | 第一幕、第二幕在真机上连着走完，脚本见下 | 这是硬线 |
| 30–40 小时 | 只有前两幕已经绿，才把 `GeometryView` 装进右半屏，双击把草图收成动态几何 | 几何和加分不做 |
| 40–48 小时 | 只修装在 iPad 上的那一版。回放开关留着。彩排按下面的脚本走两遍 | 不加新入口 |

第 30 小时的通过标准，就是 PDF 改过的演示脚本，在这台 iPad 上不看电脑就能做完：

1. 写 `f(x) = x^3 - 5x`。停笔后左下回显，右半屏出曲线和 a、b 滑条。点橡皮擦掉 `5`，切回笔写 `3`。整行重新识别，曲线变形，b 到 3。双击能不等那 700 ms 就刷新。
2. 写 `f'(x) = 3x^2 - 3x`。项数到 2 并且 1.5 秒没有新笔画，自动圈出 `-3x`，旁边是 `-3` 和一句说明。双击也能立刻批。擦掉 `-3x` 改成 `-3`，再批通过，右半屏标出 `(-1, 2)`、`(1, -2)` 和切线。屏幕上的 `-3` 来自 `expected_latex`，不是口头报出来的。
3. 第一幕用 `5x` 而不是把 `3` 改成 `1`，是为了结束时正好是 `x^3 - 3x`，第二幕接得上。客户端不要改回旧脚本。

第 30 小时这两幕没有连着跑通：我在仓库里留一句，几何和加分从 `main` 拿掉。P2、P3 回到前两幕。这一条不是建议。

---

## 8. 和还没拍板的建议怎么共存

A1–A10 仍是待定。P1 不等它们。临时约定只影响客户端，他们拍板以后改一个文件，不改画布结构。

| 建议 | 客户端现在怎么做 |
| --- | --- |
| A2，计算放进 App，Server 只留提示、Flash 和回放 | 画布只调 `CheckGating` 和右半屏的场景对象。这两个对象先用进程内的占位。以后要走 HTTP，换实现，不改 Pencil 回调 |
| A3，坐标格式统一 | 内部只用 `CGRect`。边界上两种 JSON 都读 |
| A4，用 JIIX 把错项对到笔画 | 第一版圈 `bbox`。JIIX 如果后来给了更紧的框，还是这个字段 |
| A10，圈是主线 | 已经算进第 4–20 小时，不单列 |

直接给答案是 D5，已经定了。`direct` 模式下批注里有 `expected_latex` 和 `explanation`。说明先用错误码模板，那句话立刻出现。`/hint` 的润色 3 秒没到就保持模板。Server 没开，前两幕仍然能圈、能写出 `-3`。

---

## 9. 开工时我实际做的第一串动作

不在这份报告里写 App。仓库保持空，直到我按下面的顺序推第一笔：

1. 在这台 Mac 上 `git clone` 那个私有空库。
2. 先提交 `.gitignore`，再复制证书到示例工程，避免证书进历史。
3. 做第 5 节的三项验证，把结果写进 `docs/device.md`。
4. 空壳装上 iPad，右半屏用假场景。
5. 把 iPad 交出去两小时写样本。
6. 拿回来之后，`main` 上应该有一版不依赖 P2、P3 源码也能写、能擦、能双击闪边的 App。
