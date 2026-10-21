# 识别链体检（2026-10-21，演示当天）

范围：`app/InkTutor/AppModel.swift` 的识别部分（makeRecognizer / makePreviewRecognizer / recognizerChain、recognizeMath / finishFunction / finishFromRecognition）、`app/InkTutor/MyScript/MyScriptMath.swift`、InkCore 的 `Recognizers.swift` / `NetworkRecognizers.swift` / `Replay.swift`、Server 的 `/recognize` 和回放。

原则：只改能说清「什么情况下出事」的 bug，改动尽量小；其余写在「没改」里。文中的行号都是 main（05a8037）上的。

## 一、已修

| # | 严重程度 | 位置 | 什么情况下出事 | 怎么改 |
| --- | --- | --- | --- | --- |
| 1 | 高 | `Server/Sources/InkTutorServer/Replay.swift:132` `withTimeout` | Server 默认 fallback 模式写的是「3 秒没返回就放录好的」，但用的是 TaskGroup：TaskGroup 退出前要等所有子任务收尾，而 Vapor client 的 async 接口底下是 `EventLoopFuture.get()`，不理会取消。百炼慢、或热点连上了但外网不通时，要等到 `Model.swift:54` 的 20 秒超时（两个模型最多约 40 秒）才放回放；App 的 `ServerRecognizer` 15 秒（`NetworkRecognizers.swift:24`）就放弃了，**回放根本到不了 App**。`/hint`（`App.swift:98`）同样。 | InkCore 新增 `withDeadline(seconds:_:)`：到点直接返回并取消操作，不等它收尾。Server 的 `withTimeout` 改用它，超时仍抛 `ReplayError.timeout`。 |
| 2 | 中（触发条件没实测；一旦触发，这一段就卡死） | `Packages/InkCore/Sources/InkCore/Recognizers.swift:32` `FallbackRecognizer` | 链里的引擎逐个 `await`，没有总时限。MyScript 的 `latex(for:)`（`MyScriptMath.swift:110`）是不可取消的 continuation，等的是串行队列上的 `waitForIdle()`（`:119`）。iink 一旦不返回（断网授权、SDK 卡住），这一段就一直转圈，「这一段正在识别」挡住重试，也落不到百炼 / Server。网络引擎的 `timeoutInterval` 是空闲超时，百炼两个模型加 Server 串起来最多要 55 秒左右。 | `FallbackRecognizer` 加 `timeout`，默认每个引擎 15 秒：到点取消这个引擎、换下一个；最后一个也超时，就提示「没认出来：超时（15 秒没有结果）」。`AppModel` 用的是默认参数，不用改。 |
| 3 | 中（回放演示） | `AppModel.swift:1126` `static let replayTracker`、`:1331` `restore()` | 回放的行状态整个 App 只有一份，但每份草稿都新建一个 `AppModel`（`ContentView.swift:52`），行号（新草稿从 F1 起）和笔画 id（新 `IDTable` 从 s1 起）都从头数，而 `restore()` 不重置行状态（只有「清空」会）。彩排完开一份新草稿演示，新的 F1 会被当成上一份的 F1 又擦了一轮，回放**直接放改正以后的 `f(x)=x^3-3x`**，第二幕也一样；开着「录制回放」时还会录到错的位置。 | 把 `clear()` 里重置回放的那段（本机 tracker + POST Server 的 `/replay/reset`）抽成 `resetReplay()`，`restore()` 里也调一次。 |
| 4 | 清理 | `Packages/InkCore/Sources/InkCore/DerivativeCheck.swift` | P3 的临时求导判分。App 从 10-20 起就不再调用。 | 删掉这个文件和 `InkCoreTests.swift` 里的 `DerivativeCheckTests`（4 条）。删之前查过：main，以及 p1/redesign、p3/submission、p4/grading、solve/matrix 这几个分支上，除了 InkCore 自己的文件和测试，没有任何地方引用它。MathEngine 里同名的 `DerivativeCheck` 是 MathEngine 自己的类型，InkCore 的 `MathEngineGrading` 用的是 `MathEngine.DerivativeCheck` 全称。App、Server、xcodeproj 都没有引用。p4/grading 对 `InkCoreTests.swift` 的改动只在文件末尾追加，不会冲突。顺手改了 `MathEngineGrading.swift` 头注释和《P2-P3 交付说明》里的两句。 |

#3 的代价：重新打开旧草稿后，再对旧行「改笔迹」，回放的擦除轮次从 0 数，放的是第 0 轮的最后一步。**回放演示请在一份草稿里连着演完**（中途要从头来就点「清空」）。

新增 / 改动的测试：

- `InkCoreTests/RecognizerChainTests.swift`（新，8 条）：抛错、空结果都会落到下一个引擎；最后一个的空结果照样返回；卡住的引擎（模拟不理会取消的 SDK 调用）0.2 秒后落到下一个；最后一个超时会报出来；`timeout: nil` 时不限时；`withDeadline` 原样传结果和错、到点取消操作、调用方取消时也不再等。
- `ReplayTests.testNewDraftReusingLineAndStrokeIDsNeedsAReset`：复现 #3（不 reset 时放的是改正以后的式子，reset 以后对）。App 里那一行调用只能靠 `[mac]` CI 编译验证。
- `RecognizeReplayTests.testFallbackDoesNotWaitForALiveCallThatIgnoresCancellation`：复现 #1。改前这条测试失败（等了 3.0 秒），改后通过。

## 二、没改（以及为什么）

| # | 严重程度 | 位置 | 情况 | 为什么没改 / 建议 |
| --- | --- | --- | --- | --- |
| a | 中，要在真机上看 | `MyScriptMath.swift:76`、`:61`、`:35` | 建 `IINKEngine` 是在主线程上（`AppModel.init` → `MyScriptMath.shared`）。如果 iink 在这里同步联网查授权，断网冷启动可能卡住。`status` 只在启动时算一次，之后网络恢复了也不会变。授权失败如果表现成 `IINKEngine` 返回 nil，设置页显示的是「证书无效（和 App 的 Bundle ID 对不上？）」，容易误导。官方说激活过一次后可以离线 30 天（`docs/p4/MyScript-INTEGRATION.md:31`）。 | 手上没有 SDK，Linux 上也验证不了，不敢盲改。**演示前**：iPad 开飞行模式冷启动一次，看启动卡不卡、设置页显示什么状态、双击能不能认出来。 |
| b | 中 | `MyScriptMath.swift:68` 串行队列 | MyScript 卡住一次以后，后面的 MyScript 调用都排在它后面。修了 #2 以后不会再卡死，但每次都要等满 15 秒才落到下一个引擎。 | 如果真机上碰到：可以在 App 里超时一次就把 MyScript 标成不可用（是 P1 的代码，不在这次范围）。 |
| c | 中，属于产品决定 | `AppModel.swift:1071-1086` | 断网时识别链**不会自动退到回放**：只有链是空的（一个引擎都没配）或者选了「回放」才走回放。配了百炼 Key 或 Server 地址、但断网时，结果是「没认出来：…」。`README.md:66` 写「识别链会退回百炼 / Server / 回放」，容易让人以为会自动退。 | 不改：自动退到回放的话，会把黄金路径的式子当成识别结果放出来，评委随手写的东西也会变成 `f(x)=x^3-5x`。按 DEMO_SCRIPT 的做法，断网时手动在设置里切「回放」。 |
| d | 低–中 | `BoardItems.swift:36`、InkCore `Replay.swift:53-58` | 回放按菜单的选项分模式：「求解」记在 derivative 下。回放模式下，`f'(x)` 那一行要选「求解」；选了「函数」，会按「函数第 2 行」去找，退回第 1 行，放出来的是 `f(x)=x^3-5x`。 | 脚本按「模式 + 行号」取是设计如此。演示时注意选「求解」。 |
| e | 低 | Server `RecognizeReplay` | Server 的回放行号只数到达 Server 的那些行：App 的链是 MyScript → 百炼 → Server，MyScript 认出来的行 Server 看不到，所以退到 Server 的那一行，在 Server 那边可能算「第 1 行」。 | App 自己的回放不受影响。Server 回放只是最后一道兜底，不改。 |
| f | 低 | Server `Replay.swift:110`（默认 3 秒） | 如果会场上百炼稳定地慢于 3 秒，Server 会一直放录好的式子（改前也是放回放，只是放得更晚）。`off` / `record` 模式下 Server 最多要等约 40 秒，而 App 15 秒就放弃了。 | 想要真识别就设 `INKTUTOR_REPLAY=off`，或者把阈值调大。 |
| g | 低 | `AppModel.swift:175`、`:296` | 每次识别都在主线程上把这一段渲染成 PNG，即使引擎是 MyScript 或回放、根本用不到这张图。 | 一段大约几十毫秒，不影响演示。 |
| h | 低 | `Recognizers.swift` `FallbackRecognizer` | 前面的引擎给了空结果、最后一个又抛错时，提示的是最后那个的错（比如「网络错误」），而不是「写清楚一点」。 | 不影响功能。 |
| i | 低 | `MyScriptMath.swift:120` | iink 的 `onError` 如果在 `waitForIdle` 之后才到，会被下一次识别的 `take()` 取到，那一次被误判成失败、落到下一个引擎。 | 没有 SDK，验证不了。 |

## 三、查过、没发现问题

- **旧结果盖到新笔迹上**：`finishFunction` 先比 `target.revision`（`AppModel.swift:311`），再查这一段的笔画是不是都还在（`:313`）。新的一段（没有 target）靠 `choose` 里的 `busy` 拦住重叠的第二次识别。预识别的结果靠 `previewID`，加上「画布一改就收起菜单」作废。没找到能把旧结果盖到改过的笔迹上的路径。
- **强制解包、越界**：`MyScriptMath` 的 `baseAddress!` 和 `points[count - 1]`、`ReplayTracker` 的 `ordinals[lineID]!`、`ReplayScript` 的 `passes[0]`、Server 原来的 `group.next()!`，前面都有保证；`extractLatex` 取下标前检查了 `start < end`。没找到会闪退的地方。
- **网络请求本身的超时**：`ServerRecognizer` 15 秒、`DashScope` 20 秒（都是 URLRequest 的空闲超时）、Server 调百炼 20 秒（Vapor 的 `ClientRequest.timeout`），都设了。问题在于单个上限偏长、几个串起来更长，见已修 #2。

## 四、测试

Ubuntu 24.04 + Swift 6.0.3（和 CI 的 `swift:6.0` 同一个大版本）：

- `swift test --package-path Packages/InkCore`：125 条全过（原来 120 条，删掉 4 条，新增 8 + 1 条）
- `swift test --package-path Packages/MathEngine`：43 条全过
- `swift test --package-path Server`：14 条全过（新增 1 条）

App 的改动（`AppModel.resetReplay`）由分支最后一个带 `[mac]` 的 commit 触发 CI，在 macOS 上编整个 App 来验证。
