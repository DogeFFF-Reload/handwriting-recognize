# 接口契约 v3（Swift 原生 + direct 反馈模式）

> 2026-10-20。这份契约 = v2 + P2/P3 报告里已拍板的 D1／D5 两条决策。
> **样例不是我手写的**：`swift run p4tool contracts --out contracts/v3` 用 Swift 引擎现算，
> 所以文件一定和代码一致。改契约的流程不变：**先改这里 → 再改代码 → 重新生成样例**。

```
contracts/v3/
  check.request.json              check.response.json（feedback_mode=direct，第一版）
  check.response.socratic.json    （feedback_mode=socratic，后续再开）
  function.request.json           function.response.json
  geometry.request.json           geometry.response.json
```

生成命令（Mac 上，10 秒）：

```bash
cd swift/MathEngine && swift run p4tool contracts --out ../../contracts/v3
```

---

## 0. 和 v2 的差别一览

| 决策 | 契约变化 | 谁要用 |
|---|---|---|
| **D5 第一版直接给答案** | 响应新增 `feedback_mode`、`errors[].expected_latex`（恢复）、`errors[].explanation` | P2 画结果、P3 决定要不要调模型、P4 出说明 |
| **D1 停顿只识别，条件成立才批改** | 请求新增 `lines[].revision`；判定逻辑在 Swift 的 `CheckGateSupport`，不占契约字段 | P3 的 CheckGate 调它、P1 只管把 Pencil 事件交上去 |
| **D3 擦除后整行重识别** | 请求新增 `lines[].line_id`（= 客户端按 y 带分好的行号）、`revision`；`strokes` 仍然是**整行现存笔画** | P1 上行号；P3 丢过期结果 |
| 待定建议 A1 | 响应 `terms[].param` 显式绑定滑条名（v2 已有，这里固化） | P2 |

v2 的通用规则继续有效，只有三处被这次明确覆盖：

1. **`expected_latex` 现在会下发** —— 但**只在 `feedback_mode=direct`**。socratic 模式下它必须缺席，
   客户端也不许自己补。这是「不回答案」承诺的唯一开关。
2. **`char_span` 相对 `checked.rhs_latex[i]`** —— 这串是**归一化后的正文**（例如 `f^{\prime}(x)=3x^{2}-3x`
   的正文是 `3x^(2)-3x`）。P1 做字符→笔画映射时用它，不要用自己上传的原文去算下标。
3. **失败一律 200 + `ok:false`** —— Swift 侧由 `MathEngineAPI.check` 保证，任何输入都不抛。实测喂
   `99999999999999999999999x`、`(2x+3)^40`、空矩阵都不会崩。

---

## 1. `POST /check`

### 请求

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `mode` | `derivative｜step｜matrix｜integral｜function｜geometry｜auto` | ✔ | 界面分段按钮已经知道是哪一幕，**不要传 auto**。`function` 模式不批改，只出图 |
| `feedback_mode` | `direct｜socratic` | ✗ | 缺省 `direct` |
| `lines[].line_id` | string | ✔ | 客户端按 y 带分好的行号（`L1`、`L2`…），生成后不变 |
| `lines[].revision` | int | ✗ | 该行每变一次 +1。**客户端收到更小的 revision 就丢弃** |
| `lines[].latex` | string | ✔ | 识别结果或学生手改后的 LaTeX |
| `lines[].bbox` | `[x,y,w,h]` | ✗ | 整行的框（画布 point）；错项框由它算出来 |
| `context.function_latex` | string | derivative 必填 | 题目的原函数 |
| `context.variable` | string | ✗ | 默认 `x` |
| `options.with_scene` | bool | ✗ | 判对时顺带返回函数场景，默认 true |
| `options.max_errors` | int | ✗ | 默认 3；超出时降级码 `errors_truncated` |
| `strokes[]` | array | ✗ | **这一行现存的全部笔画**（不是增量）：`{id, points:[[x,y,t,pressure]]}`。用来把错项框吸附到真实笔画 |
| `region` | object | ✗ | 该行区域，含 `scale`；`lines[].bbox` 缺省时用它 |

### 响应

| 字段 | 类型 | 说明 |
|---|---|---|
| `ok` | bool | 全对 |
| `feedback_mode` | string | 回显本次用的模式 |
| `errors[].line_id` | string | 回注 |
| `errors[].kind` | string | 10 种错误码（见 v2 §4） |
| `errors[].wrong_latex` | string | 学生原文那一段 |
| `errors[].char_span` | `[start,end)` | 相对 `checked.rhs_latex[i]` |
| `errors[].bbox` | `[x,y,w,h]` | **有 `char_span` 时是那一项的框**，否则是整行框 |
| `errors[].bbox_source` | `term｜line` | P1 可以据此决定圈的粗细；`term` 就是「圈住那一项」 |
| `errors[].hint_fallback` | string | 确定性反问，不含答案。**两种模式都有**，模型超时就用它 |
| `errors[].expected_latex` | string | **只在 direct**：正确项 |
| `errors[].expected_pow` | int | **只在 direct**：正确项的幂次，P3 生成说明时用 |
| `errors[].explanation` | string | **只在 direct**：一句说明，模板生成、不调模型、没有延迟 |
| `function` | object｜null | `ok:true` 且 `with_scene` 时带回 |
| `checked.line_count` / `checked.rhs_latex` | int / [string] | `char_span` 的坐标系 |
| `degraded` | [string] | `errors_truncated`、`marks_unsupported`、`scene_unavailable`、`geometry_not_captured` |
| `replayed` / `engine` | bool / string | 回放标记与引擎版本，答辩时敢说 |

### direct 与 socratic 的差别（**只差三个字段**）

| 字段 | direct（第一版） | socratic（后续） |
|---|---|---|
| `expected_latex` | 有 | **必须缺席** |
| `explanation` | 有（模板：`x 求导得 1，所以 −3x 求导后是 −3。`） | 缺席 |
| `hint_fallback` | 有 | 有（这就是气泡的内容） |
| `hint_url` | 可选，Max 润色流 | 必有，反问流 |

`check.response.socratic.json` 是防泄漏的自检样本：文件里不许出现 `expected_latex` 和 `explanation`。
XCTest 里有对应的断言，谁把它加回去，测试会红。

---

## 2. `POST /function`

请求与 v2 相同（`latex`、`variable`、`view`、`lines[]`），响应字段也相同，两处补充：

| 字段 | 说明 |
|---|---|
| `scene.function.params[].step` | 滑条步长：整数系数 1、1/2 系数 0.5、其余 0.1 |
| `scene.function.terms[].param` | 显式绑定到滑条名，**不要靠下标** |
| `degraded` | `marks_truncated`（极值点超过 8 个时只标前 8 个） |

**拖滑条不要在网络上往返。** 场景 JSON 到手后，P2 在 App 内调：

```swift
var scene: FunctionScene = ...          // 第一次 /function 拿到的
scene = scene.updated(values: ["b": 3]) // 把 b 从 5 拖到 3
scene.marks                             // 极值点已经跟着重算
```

`a = 0` 时曲线变直线，极值点自动清空（不静默画错）。

---

## 3. `POST /geometry`

和 v2 相同。这次只补了两点：

- 请求可以只发 `points` + `relations`，`objects` 由引擎按「三角形 + 中线」模板补全。
- 认不出时不硬收：返回 `ok:false` 让 P1/P3 保留原墨迹（`geometry_not_captured`）。

---

## 4. 回放

规则不变：命中键 = `SHA1(endpoint + 规范化 JSON)`，请求体里**不许有时间戳、UUID**。
`lines[].revision` 会变，所以录回放时用**固定的 revision**（演示脚本里那几条路径的 revision 是
录制时的值）。这条要在演出前实测一次，别到台上才发现回放不命中。

---

## 5. 变更记录

| 日期 | 改动 |
|---|---|
| 2026-10-19 v1 | Python/SymPy 版：`expr_js`、`expected_latex` |
| 2026-10-19 v2 | 去 `expr_js`；`expected_latex` 不上线；加 `char_span`/`param`/`sign`/`degraded`/`hint_fallback` |
| 2026-10-20 v3 | direct 模式恢复 `expected_latex` + 新增 `explanation`/`feedback_mode`/`expected_pow`；`lines[].line_id`/`revision`；`bbox_source`；`check.response.socratic.json` 作为防泄漏样本 |
