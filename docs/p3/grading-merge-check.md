# p4/grading 合进 main 的检查（P3，2026-10-21）

检查对象：`origin/p4/grading` = `46e1f9d`，`origin/main` = `05a8037`。分支 `p3/grading-merge-check` = main 合并 p4/grading 之后的结果，外加这份报告。

## 结论

**改完 X 再合。X = 只合批改那一个提交 `84d66a3`，并且在那台 Mac 上编译通过、真机按演示流程走一遍批改。p4/grading 整个分支（带双指缩放）不建议今晚合。** 今晚来不及在 Mac 上编译和上真机，就不合，演示用现在的 main。

依据：

1. p4/grading 不止有批改。比 main 多 5 个提交，其中只有 `84d66a3` 是批改：
   - `84d66a3` 批改（父提交就是 main 的 `05a8037`，单独合也是快进，不会有冲突）
   - `8126c94`、`39249cf`：P1 的窗口化提交（在 p1/redesign 上，还没进 main），经 merge 提交 `06a78de` 带进来
   - `46e1f9d` 双指缩放：新功能，和批改无关。改动了画布滚动、纸的宽度、草稿格式，还动了每一个浮层元素的大小和位置
2. **批改和缩放这两个提交从来没被 macOS 编译过。** 从 13:11 UTC 起，仓库所有 CI 都在 3–7 秒内失败，`runner_id=0`、没有日志，说明根本没分到机器（连只改文档的 p3/submission 也失败）。p4/grading 的两次 [mac]（run 46、48）都是这样。最后一次真正编译成功的是 `8126c94`（run 44）。Drkarmic 有没有在本地 Mac 上编过、上过真机，需要问本人。仓库是私有的，原因最可能是 Actions 分钟数或账单受限，需要仓库所有者到 Settings → Billing 查看。
3. 批改本身：Linux 单测全过；判分和画圈的逻辑我另外写了临时测试核对过，见下文。没找到会闪退的地方。主要风险是没编译过、没上过真机。
4. 双指缩放的风险大得多：它改的是所有演示场景都要用的画布交互，而且有几处会让批改的圈位置和分段变差（见问题 5、6）。今晚合进去，收益和风险不成比例。

P1 合批改的做法：`git checkout main && git merge --ff-only 84d66a3`（快进）。合进去以后，README 里「（`p4/grading` 分支）」这几个字要删掉。

## 冲突清单

**没有冲突。** p4/grading 的分叉点就是当前 main（`05a8037`），而且它已经自己合过 p1/redesign，所以 `git merge origin/p4/grading` 是快进。BoardItems / BoardOverlay / ContentView / SegmentMenu 都没有冲突，不需要手工处理。

需要拍板的不是冲突，是**合并范围**：整枝合会把 P1 还没合的两个窗口化提交（不再要求全屏、支持竖屏，见 `project.pbxproj`；CI 编译时用参数改回横屏全屏）和双指缩放一起带进 main。这件事请 P1 决定。

## 测试结果（Linux，Swift 6.0.3，代码 = `46e1f9d`）

| 包 | 结果 |
|---|---|
| `swift test --package-path Packages/MathEngine` | 43 个测试，0 失败 |
| `swift test --package-path Packages/InkCore` | 124 个测试，0 失败（含新加的 `GradeTests` 4 条） |
| `swift test --package-path Server` | 13 个测试，0 失败 |

另外做了几项临时验证（测试文件没有提交）：

- **圈的位置**：用合成笔画写了 `f'(x)=3x^2-3x`，圈正好落在 `−3x` 那一组笔画上（x 195–267）。整行平移 (2400, 3100)，也就是纸滚过很远之后，圈也跟着平移，没有偏。第一项写错（`x^2-3`）时圈在第一项。漏项（`missing_term`）时圈整行。现有的 `GradeTests` 用一笔盖住整行，没有覆盖圈的位置。
- **不闪退**：系数取 1/3、1e10、NaN、∞、x⁴⁰，导数取空串、`x^{-1}`、`=0`、超长数字、`\sqrt{x}`、`f''`、`f'(2)` 等，在 direct 和 socratic 两种模式下各调一遍 `MathEngineGrading.grade`，都没有 trap。Rational 运算有溢出检查（`Core.swift:92-130`）。
- **socratic 不泄题**：上面所有组合里，socratic 模式下 `explanation` 和 `expectedLatex` 都是 nil。

iOS App 在 Linux 上编不了。我只做了静态核对：批改用到的 `Theme.ok/wrong`、`pinned`、`Explanation.generic`、`FunctionDefinition.polynomial`、`DemoInk.strokes(start:)`、`MathLabel` 构造器等符号都存在，`SegmentKind` 的 switch 都补了 `.check`。这不能代替真正的编译。

## 审查发现

### 圈的位置用的是哪套切项逻辑

多项式、一阶、`f'(x)` 的情况走 `MathEngineGrading.annotation`（`Packages/InkCore/Sources/InkCore/MathEngineGrading.swift:57-73`），按下面的顺序退：

1. P3 的 `TermSegmenter.termBoxes`：按笔画外框从左到右排，先找等号（两条上下叠着的短横），再按行中线附近的扁平笔画（加减号）切项。用 MathEngine 的 `StudentLine.termIndex(forCharSpan:)` 把错项对到第几项。
2. 切出来的项数和识别结果对不上时，用 MathEngine 的 `TermBox.estimate`：按字符宽度估算位置，再吸附到真实笔画上。
3. 再不行就圈整行。

非多项式、二阶、`f'(2)` 走数值比较（`AppModel.swift:753-771`），只判整行，圈的是整段笔画 `seg.bounds`。所有坐标都是画布坐标（PencilKit 的 `renderBounds`），圈画在随纸滚动的那一层里，所以纸滚动以后对得上。

### 和 main 的草稿保存、窗口化、滚动

- **滚动**：没有冲突。圈和勾用画布坐标，那句话按 `visibleRect` 放置，见上面的平移验证。
- **草稿保存**：批改不存盘（`AppModel.swift:1573` 打开草稿时清空，代码里写明是故意的），草稿格式没有变化。每份草稿各有一个 AppModel，识别到一半离开草稿，结果不会画到别的草稿上。卡片的 `reveal` 会存盘，所以批改对了以后重开草稿，导函数还在、勾没了。
- **窗口化**：那句话在 compact 下缩到 0.86。窗口极窄时有个小问题，见问题 7。

### 问题清单（按严重程度排）

1. **未编译**（阻塞）：`84d66a3`、`46e1f9d`（以及 P1 的 `39249cf`）没有任何一次 macOS 编译记录，原因见结论第 2 条。
2. **双指缩放改变了 main 现有的行为**（`46e1f9d`，要 P1 拍板）：
   - 纸至少三屏宽，`alwaysBounceHorizontal = true`（`PencilCanvas.swift:29`，`AppModel.swift:155-158`），于是不缩放时一根手指拖也会左右滚，演示时容易误滑。
   - 草稿多存了 `scrollX` 和 `zoom` 两项，向后兼容。
   - 捏合的每一帧，浮层里所有元素都会重算（它们都读 `app.zoom`），真机性能没测过。
3. **断网回放和批改**（演示风险）：回放不看笔迹内容，App 用整行模式（`AppModel.swift:1285` 的 `wholeLine: true`），所以按 `Replay.swift:113-124` 的剧本，第一次批改一律当作 `f'(x)=3x^2-3x`。断网时学生第一次就写对，也会被判错、被圈。批改和「求解」共用 `derivative` 这一档剧本。
4. **答案提前出现的边角情况**：
   - 卡片默认 `reveal=false`，写错时也会关掉（`AppModel.swift:785-788`）。但同一个 f 之前用「求解」算过 `f'(x)` 或 `f'(2)` 的话，导函数那一项还在，`reveal` 保持打开，卡片里的导函数曲线等于答案。
   - 批改对了以后再拖滑条、改式子，批改变成「改好后双击」，卡片却立刻画出新函数的导函数。
   - socratic 模式下符号错（`MathEngineGrading.swift:108`）问的是「先只看符号：+3 该是正还是负？」，基本等于告诉了答案。
   - direct 模式（**默认**）本来就会给出正确项，这是设计，和提交文案「写出正确项和原因」一致。
5. **缩放后批改的圈和分段变差**（只有合了缩放才有）：`TermSegmenter`（`TermSegmenter.swift:15`，宽度 > 8 才算横）和 `InkSegmenter`（`InkSegmenter.swift:26`，gapX 64、gapY 22）的阈值都是画布坐标。
   - 放大到 2.5–3 倍时，减号和等号在画布上太短、认不出来，项数对不上，圈退回估算或整行。
   - 缩小到 0.5 倍时，字间距在画布上变成两倍，一行可能被切成几段。
6. **同名函数**：`AppModel.swift:727` 用 `functionTable()[parent.name]` 取定义，表里同名的是后写的那条。画板上有两个 f 时，判分对照的 f 和亮起导函数的 f 可能不是同一条。
7. **窄窗口**：`BoardOverlay.swift:325-330` 那句话约 340pt 宽，窗口比约 356pt 窄（例如 320pt 的侧拉窗口）时会伸出右边。
8. **参数滑条带来的浮点误差**：`MathEngineGrading.polynomialLatex` 直接写出 Double。参数代入后系数如果是 `0.30000000000000004` 这种值，MathEngine 按精确有理数比较，学生写的正确答案会被判错。只在带参数、系数要经过乘法的函数上出现；多项式系数滑条按 0.5 取整，不受影响。

没有发现闪退。批改没改动草稿、窗口化、滚动的现有代码路径，只在 `drawingChanged`、`choose`、`apply`、`coefficientsChanged`、`delete`、`clear`、`restore` 里各加了一两行。

## 合进去之后演示要注意

1. 批改那一行写在对应的 `f(x)` 下面，`f(x)` 先用「函数」收成式子；函数名要对得上（写 `y'` 时纸上要有 `y=…`）。
2. 设置里「批改只提问」默认关着，写错会直接给出正确项。如果讲「不直接给答案」，就先打开它。
3. 同一个 f 演示批改之前，不要先用「求解」算它的导数，否则写错时卡片里已经有导函数曲线。
4. 断网回放只认剧本：先写错（`3x^2-3x`），擦掉 `-3x` 改成 `-3`，再批改。不要第一次就写对。
5. 批改之后改了笔迹，圈会收起来，要再双击选「批改」。
6. 非多项式、`f'(2)` 只判整行、圈整行。这是预期行为，不是 bug。
7. 批改不存盘：重开草稿后圈没了，要重新双击批改。
8. 如果合了双指缩放：批改前点右下角按钮回到 100% 再写；注意单指误滑。

## CI 结果

- 推送 `bce9756`（带 [mac]）后触发了 [run 50](https://github.com/DogeFFF-Reload/handwriting-recognize/actions/runs/39609909841)：unit、server、ios-build 三个任务都在 2–3 秒内失败，`runner_id=0`、没有日志。和 13:11 UTC 以来其他分支的情况一样，**没分到机器，不是代码的问题，也就没有编译结果**。
- 所以「整个 App 能不能编过」目前**没有任何验证**。Linux 单测的结果见上文，是在本地跑的。
- 补这份结果的提交同样带 [mac]：CI 恢复以后再推一个提交、或者手动 Run workflow，就能编到这棵树。
- CI 恢复之前，只能在那台 Mac 上编。命令和 CI 一样：
  `xcodebuild -project app/InkTutor.xcodeproj -scheme InkTutor -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`。
  只合批改的话，先 `git checkout 84d66a3` 再编。
- 仓库所有者需要到 GitHub → Settings → Billing / Actions 看一下为什么不分配机器：私有仓库，macOS 分钟按 10 倍计费，额度很可能用完了。
