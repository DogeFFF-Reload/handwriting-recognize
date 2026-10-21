# p3/merge-all：study-tools + for-p1 + no-pencil-pro 的合并分支（2026-10-21）

给 P1 在 Mac 上编译装机、再合进 main 用。

## 包含哪些分支

以 `origin/p1/study-tools`（c7099bd，已包含 main 05a8037）为底，依次合并：

1. `origin/p3/for-p1`（a691c0f）→ 452b03f：千问优先、识别链每个引擎 15 秒超时、打开草稿时重置回放、qwen-solve 提示词和 `canonicalLatex`，删掉 InkCore 临时的 `DerivativeCheck`。详见 `docs/p3/for-p1.md`。
2. `origin/p3/no-pencil-pro`（9770c8e）→ e700c9c：「完成一段」改名为醒目的「识别」键，`PencilProbe` 检测 Pencil Pro，设置里加「显示识别按键」开关。详见 `docs/p3/no-pencil-pro.md`。

四个分支（含 main）的最新提交都已在本分支里，没有漏掉的。

## 冲突怎么解的

- 合并 1：没有冲突。
- 合并 2：只有两处冲突，两边内容都保留。
  - `ci.yml` 截图列表：`… compact check transform compare recognize settings`。
  - README 第 1 步：保留 study-tools 的「函数 / 求解 / 检查 / 几何（认出矩阵时多一枚「矩阵」）」，后面接 no-pencil-pro 的「识别」键说明。
- Swift 代码全部是自动合并，没有手改。复核方法：用 `git merge-tree --write-tree` 把两次合并重做一遍。合并 1 的结果和 452b03f 完全一样；合并 2 的结果和 e700c9c 只差上面两个冲突文件。

## Linux 上的测试

Ubuntu 24.04 + Swift 6.0.3（和 CI 的 `swift:6.0` 同一版本线），在 e700c9c 上跑。GitHub Actions 目前分不到机器，所以是在云端机器上手动跑的。

| 命令 | 结果 |
| --- | --- |
| `swift test --package-path Packages/InkCore` | 145 条，0 失败 |
| `swift test --package-path Packages/MathEngine` | 43 条，0 失败 |
| `swift test --package-path Server` | 14 条，0 失败 |

InkCore 的 145 条 = for-p1 的 130 条 + study-tools 新加的 15 条（`NoteSummaryTests` 4、`StepReviewTests` 6、`TransformTests` 5）。

study-tools 新加的 `StepReview.swift` 用的是 `MathEngine.DerivativeCheck` 全称，不受 for-p1 删掉 InkCore 版 `DerivativeCheck` 的影响。上面 InkCore 能编过、测试全过，说明这一点没问题。

## App 静态核对（Linux 编不了 App，只读代码）

读了三次合并改到的 `AppModel.swift`、`TopBar.swift`、`ContentView.swift`、`PencilCanvas.swift`、`SegmentMenu.swift`、`BoardOverlay.swift`，还有新文件 `PencilProbe.swift`。

- **工具栏不会同时出现「完成一段」和「识别」**：
  - study-tools 没改 `TopBar.swift`，合并后这个文件和 no-pencil-pro 的一字不差。
  - 「完成一段」在 `app/` 里已经一处都没有了。
  - 「识别」只在一个地方出现，由 `showsRecognize` 决定：
    - 显示时：全屏在功能键里，窗口化在小胶囊里。
    - 不显示时：全屏在齿轮菜单里，窗口化在设置菜单里。
- **「检查」等菜单项和「识别」键能共存**：
  - 「识别」调 `confirmLatestSegment()` → `pencilDoubleTapped(at: nil)`，和双击是同一个函数，弹出的也是同一个 `SegmentMenu`。
  - 菜单内容是 study-tools 的：函数 / 求解 / 检查 / 几何，认出矩阵时多「矩阵」，2×2 矩阵的二级菜单里有「看变换」。
  - 没有落点时，菜单弹在最后一笔收笔的地方。
- **demo**：
  - `loadDemo` 里，study-tools 的 `check` / `transform` / `compare` 在 `clear()` 之前就返回了；no-pencil-pro 的 `recognize` / `settings` 在 `clear()` 之后，互不影响。
  - `BoardScreen` 收到 `-demo settings` 时会打开设置页。
- **编译风险**：没看到会编不过的地方。
  - 重名：`PencilProbe`、`PencilTouchProbe`、`RecognizeButton`、`ProminentPressStyle`、`notice(_:)` 在 App 和各个 Package 里都只有一处定义。
  - 缺符号：用到的 `app.toast(_:at:_:)`、`Toast.Style.info`、`visibleRect`、`topInset`、`showSettings`、`replayTracker` 在合并后都还在，签名没变。
  - switch：study-tools 新加的 `Solution.Operation.transform`、`MatrixAction.transform`、`SegmentKind.check`，App 里对应的 switch（`operationTitle`、`SegmentMenu` 的 `title` / `icon`）都有这个 case。另外两个分支没有新加 switch。
  - 访问控制：`resetReplay()` 是 `private`，在同一个文件的 `extension AppModel` 里的 `restore()` 调用它。Swift 允许这样调用。
  - 新文件：工程用的是 `PBXFileSystemSynchronizedRootGroup`，`PencilProbe.swift` 会自动编进去，不用改 pbxproj。
- **合并没有带来需要修的问题**：这个分支除了本文档，没有别的改动。

小问题，没改（不影响功能，留给 P1 决定）：no-pencil-pro 写的几句说明还是「函数 / 求解 / 几何」，没带上 study-tools 新加的「检查」。涉及设置页「识别按键」一节的 footer、`RecognizeButton` 的 accessibilityHint，还有 `docs/p3/no-pencil-pro.md` 第 2 步。

## 只能在 Mac 上验证的部分

整个 App 在合并后还没编过：for-p1 和 no-pencil-pro 的 App 改动都没有在 Mac 或 CI 上编过。**要 P1 在 Mac 上编译确认**。装机后建议看这几件事：

1. 编译：重点看 `PencilProbe.swift`（`UIGestureRecognizer` 子类、`@AppStorage` 存 `Bool?`）、`TopBar.swift`、`SettingsView`、`AppModel.restore()` 里调 `resetReplay()`。
2. 「识别」键：写 `f(x)=x^3-5x` 后点「识别」，弹出的菜单里应该有「检查」。写一个 2×2 矩阵再点「识别」，应该有「矩阵 › 看变换」。
3. 竖屏或台前调度的窄窗口：study-tools 放开了竖屏和窗口化，这时是小胶囊。开关开着时，小胶囊里有「识别」；关掉以后，设置菜单里有「识别」。
4. Pencil 检测：按 `docs/p3/no-pencil-pro.md` 的「真机上怎么验证」走一遍。重点看 `PencilTouchProbe` 会不会影响书写，还有认出 Pro 时键会不会收起。
5. for-p1 的两条：
   - 选「直连百炼」、MyScript 已就绪时断网，双击应该能落到 MyScript。
   - 彩排过一遍后，新开一份草稿走回放，F1 放出来的应该是 `f(x)=x^3-5x`。
6. CI 恢复后：`-demo check / transform / compare / recognize / settings` 这几张截图都能出来。
