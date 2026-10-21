# 没有 Pencil Pro 也能打开识别菜单

分支 `p3/no-pencil-pro`。只改 App 壳（工具栏、设置页、空白纸提示、demo），识别、求解、几何的逻辑没动。

## 改了什么

- **「完成一段」改成「识别」**。还是同一个入口，没有加第二个：它原来就调 `AppModel.confirmLatestSegment()` → `pencilDoubleTapped(at: nil)`，和 Pencil 双击走同一个函数。现在改成实心强调色的胶囊，比别的键醒目。
  - 双击时有 `hoverPose` 落点，菜单弹在笔尖旁。按钮没有落点，菜单弹在**最近写的那一段**里最后一笔收笔的地方。双击不带落点时也是这样。
  - 菜单开着时再点一次就收起，和再双击一次一样。纸上没有笔迹时不能点。
- **窗口化的小胶囊**：笔、橡皮 ｜ **识别**、清空、设置。
- **「识别」键不显示时**（认出了 Pencil Pro，或者在设置里关了）：
  - 全屏：设置键（齿轮）从「直接打开设置页」改成菜单，里面是「识别 / 设置…」。这样双击不灵时还有地方点。
  - 窗口化：设置键的菜单里多一项「识别」。
  - 键显示时，这两个地方都不放「识别」，不重复。
- **设置页最上面加一节「识别按键」**：
  - 开关「显示识别按键」。
  - 「检测到的笔」：显示检测结论。
  - 「重新检测（开关回到自动）」：清掉检测结论和用户的手动选择。
- **关闭警告**：还没认出 Pro 时关掉开关，先弹一个确认框：「一代、USB-C Pencil 和手指不能双击，关掉后只能从工具栏设置键（齿轮）的菜单里点「识别」；二代 Pencil 和 Pencil Pro 双击笔身也行」。认出 Pro 后关掉不问。
- **自动收起时提示一次**：用户没拨过开关，而 App 刚认出 Pro、把键收起来了，提示一次「认出 Pencil Pro，「识别」收进了设置键」。
- **空白纸提示**：有「识别」键时写「写完双击笔身或点「识别」」。
- **新 demo**：
  - `-demo recognize`：写完 f(x)=x³−5x 点「识别」后的样子。
  - `-demo settings`：同一画面上盖着设置页。
  - 两个都加进了 `ci.yml` 的截图列表，CI 截浅色、深色各一张。现有的 `-demo compact` 截图里会带上小胶囊里的「识别」。

代码位置：
- `app/InkTutor/PencilProbe.swift`（新文件）：检测、持久化
- `TopBar.swift`：按键、菜单
- `PencilCanvas.swift`：在回调里记录检测结果
- `ContentView.swift`：设置页、demo
- `AppModel.swift`：只加了 demo 场景和注释
- `BoardOverlay.swift`：空白纸提示

## 默认值和持久化（UserDefaults）

| 键 | 含义 |
| --- | --- |
| `pencilEvidence` | 检测结论 0–3，只升不降 |
| `showRecognizeButton` | 用户拨过开关才有这个键；没拨过时不存在 |

键显不显示 = `showRecognizeButton ?? (pencilEvidence < 3)`。也就是说：用户拨过开关，就一直按用户的；没拨过，按检测结果，只有认出 Pro 才默认关。

## 检测怎么做（查到的事实）

iPadOS **没有**公开 API 能直接查「配对的是哪一支 Pencil」，只能从收到过的输入推断：
- `UITouch` 只有 `type == .pencil`、压力、倾角、`rollAngle` 等触摸属性，没有型号。
- `UIPencilInteraction` 只有双击 / 捏压回调，以及几个用户偏好（`preferredTapAction`、`preferredSqueezeAction`、`prefersPencilOnlyDrawing`、`prefersHoverToolPreview`）。文档没说这些偏好能反映配没配过某支笔，所以不拿它们推断。

| 收到过 | 依据 | 结论 | 值 |
| --- | --- | --- | --- |
| 捏压 `pencilInteraction(_:didReceiveSqueeze:)` | 文档原话：“Only Apple Pencil Pro supports squeeze interactions.” | 确定是 Pro | 3 |
| 写字时 `UITouch.rollAngle ≠ 0` | 文档原话：“For models of Apple Pencil that don’t support barrel-roll angle data, the value of this property is 0.”；apple.com 对比页上 barrel roll 只有 Pro 支持（USB-C 不支持），二代的规格页里没有这一项 | 推断是 Pro | 3 |
| 双击 `pencilInteraction(_:didReceiveTap:)` | 二代和 Pro 支持双击，USB-C 不支持 | 二代或 Pro | 2 |
| 只见过 `touch.type == .pencil` | — | 一代、USB-C，或者还没双击、没捏过的二代 / Pro | 1 |

- 写字时的触摸由画布上一个只看不拦的手势（`PencilTouchProbe`）读取：只收 Pencil 的触摸，自己从不识别成功，不取消、不推迟别的触摸；`canBePrevented(by:)` 返回 false，这样 PencilKit 的画笔手势开始画时不会把它判成失败。真机上有没有影响书写还要看。
- 双击和捏压在原来的 `UIPencilInteraction` 回调里顺手记下。

资料：
- [UIPencilInteraction](https://developer.apple.com/documentation/uikit/uipencilinteraction)
- [Handling squeezes from Apple Pencil](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil)
- [UITouch.rollAngle](https://developer.apple.com/documentation/uikit/uitouch/rollangle)
- [Apple Pencil 对比（apple.com）](https://www.apple.com/apple-pencil/)
- [Apple Pencil（第二代）技术规格](https://support.apple.com/en-us/111889)
- [2023-10 新闻稿：USB-C 与二代的功能](https://www.apple.com/newsroom/2023/10/apple-introduces-new-apple-pencil-bringing-more-value-and-choice-to-the-lineup/)

## 局限

- **刚装好、还没用 Pencil 写过时，什么都不知道**：按「不是 Pro」处理，键是显示的。
  - Pro 用户第一次落笔，如果读到滚转角，键就收起。
  - 读不到的话，要等捏一下。
- **滚转角这条没在真机上验证过**。它靠的是文档里「不支持就是 0」这句话，Pro 落笔时这个值是不是真的不为 0 还没确认。如果实际读到的一直是 0，就只能靠捏压认出 Pro。
- **一代、USB-C 和「还没双击过的二代 / Pro」分不开**。二代双击过之后能认成「二代或 Pro」，但开关仍然默认开：按需求，只有 Pro 才默认关。
- **只升不降**：同一台 iPad 换笔（比如 Pro 换成 USB-C）不会自动降回去，要点「重新检测」。「重新检测」也会清掉用户的手动选择。
- **只看画布上的笔画**：用 Pencil 点工具栏、卡片、菜单不算。
- **键会在用着用着时收起**：认出 Pro 的那一刻（用户没拨过开关）键会消失，有一次提示。
- **Pro 用户进设置多一步**：全屏时键收起，设置键变成菜单，要先点菜单里的「设置…」。
- **段落滚出屏幕时菜单会挤到屏幕边上**：「最近写的那一段」如果已经滚到看不见的地方，菜单的圆钮会被挤到屏幕边上。这是原来就有的行为，没改。
- **CI 只验证了编译和截图**：模拟器没有 Pencil，检测逻辑和警告框都要在真机上看。

## 真机上怎么验证

先删掉 App 重装，或者在设置里点「重新检测」。结果填进 [docs/device.md](../device.md) 新加的三行。

1. 打开设置 › 识别按键：
   - 应该是：检测到的笔「还没用 Apple Pencil 写过」，开关是开的，工具栏上有「识别」。
2. **识别键**：写 `f(x)=x^3-5x`，点「识别」。
   - 应该是：菜单弹在这一段旁边，选项和双击时一样（函数 / 求解 / 几何；写矩阵时多一枚「矩阵」）。
   - 再点一次，菜单收起。
   - 写两段后点「识别」，应该选中后写的那段。
3. **Pencil Pro**：
   1. 只写字、不捏，看设置里有没有变成「Apple Pencil Pro」。这一步验证滚转角那条路，结果记进 device.md。
   2. 没变的话，捏一下。
   - 应该是：认出 Pro 的那一刻，「识别」键收起，提示一次。
   - 全屏点齿轮：出现「识别 / 设置…」菜单。
   - 双击：菜单在笔尖旁，行为不变。
4. **二代**：双击一次。
   - 应该是：显示「能双击的 Apple Pencil」，开关还开着。
5. **一代 / USB-C / 手指**（手指要先打开「允许手指书写」）：
   - 应该是：一代 / USB-C 写字后显示「Apple Pencil，还没双击过」；用手指时一直是「还没用 Apple Pencil 写过」。开关一直开着。
6. **关闭警告**（没认出 Pro 时）：把开关拨到关。
   - 应该是：弹出警告。点「取消」开关还开着；点「关掉」键消失，齿轮变成菜单。
   - 杀掉 App 再开，应该还是关着。之后再捏、再写，也不会自己打开。
7. **窗口化**（台前调度 / 分屏）：
   - 应该是：开关开时，小胶囊里有「识别」；开关关时，设置键的菜单里有「识别」。
8. 点「重新检测」：
   - 应该是：检测结果和手动选择都清掉，开关回到自动。

## 状态（2026-10-21）

- **还没编译验证过**。从 13:11 UTC（run 45）起，这个仓库所有分支的 CI 都没分到机器。GitHub 的提示是 “The job was not started because recent account payments have failed or your spending limit needs to be increased”，要仓库所有者到 Billing & plans 处理。处理好之后，重跑这个分支最新的 run，或者手动触发 `ci`（workflow_dispatch，选 `p3/no-pencil-pro`），确认 ios-build 是 BUILD SUCCEEDED，再看 `recognize`、`settings`、`compact` 三组截图。
- **合并**：
  - 和 `p1/redesign`：试合并没有冲突。
  - 和 `p1/study-tools`：只有两处一行的冲突，两边的内容都留下就行。
    - `ci.yml` 截图列表：两边都加了场景，合并后是 `… compact check transform compare recognize settings`。
    - README 第 1 步那一句：保留「函数 / 求解 / 检查 / 几何」，再接上「识别」键的说明。
