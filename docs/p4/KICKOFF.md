# 开赛后前 4 小时：P4 作战手册

> 这 4 小时决定后面 44 小时是"接线"还是"救火"。
> 目标不是写完引擎，是把两个不确定性清零：**①契约能不能签 ②Swift 包能不能编**。
>
> **2026-10-20 更新**：契约升到 `contracts/v3/`（direct 反馈模式 + `line_id`/`revision`），
> Swift 包已扩到 43 个测试、19 条与 Python 参考实现对账。
> 你的行动清单在 [`P4-TODO.md`](P4-TODO.md)，这份只讲前 4 小时。

---

## T+0:00 —— 同时开三条线（别排队）

| 谁 | 干什么 | 为什么现在 |
|---|---|---|
| P4 | 把 `contracts/v3/` 甩群里（7 份，由代码生成），同时把假后端跑起来 | 全队只有你手上是现成的 |
| P1 | 建 Xcode 工程，空壳装真机，Pencil 能写；UI 先连假后端 | 真机签名是唯一的硬外部依赖 |
| P3 | 注册 MyScript 开发者账号 + 申请 iOS SDK/key，同时申请百炼 API Key | **唯一会排队等待的事** |
| P2 | 拿 `function.response.json` 把曲线画出来（也可以直接连假后端） | 不依赖任何人 |

**假后端一条命令（P1/P2 立刻能用）**：

```bash
cd server && python -m uvicorn mock_v2:app --host 0.0.0.0 --port 8100
curl localhost:8100/demo/sequence      # 黄金路径的 5 个请求，照着点
```

iPad 与这台机器同一个热点，App 里填 `http://<本机局域网 IP>:8100`。
它还会故意搞事，让 P1 提前把兜底练熟：`?fail=timeout` / `?fail=http500` / `?fail=garbage` / `?delay_ms=1500`。

---

## T+0:00–0:30

### P4 做这三件

1. **发契约**（5 分钟）
   发 `contracts/v3/README.md` + `check.request.json` + `check.response.json` + `function.response.json`。
   一句话："`terms[i].param` 显式绑到 `params`，别靠下标；`expected_latex` **只在 `feedback_mode=direct`
   下出现**；`char_span` 相对 `checked.rhs_latex`。"

2. **自己跑一遍两套实现**（10 分钟）
   ```bash
   cd swift/MathEngine
   swift test                                                 # 43 tests, 0 failures
   swift run p4tool parity ../../contracts/parity_cases.json  # 对账 19/19 一致
   swift run p4tool demo                                      # 黄金路径的真实返回
   ```
   目的：确认你手上这套东西是活的，答辩时"我这套能跑"这句话有数字。

3. **把 Swift 包塞进 Xcode**（20 分钟）
   把 `swift/MathEngine/` 复制进 `InkTutor/MathEngine/`，在 Xcode 里 `File > Add Package Dependencies > Add Local`。
   **不要**等 P1 的工程结构定下来才开始 —— 用 `swift test` 独立跑。

---

## T+0:30–1:30 —— `swift test` 清零编译错误

```bash
cd MathEngine
swift test
```

**这一步的预期**：**大概率直接绿**。这份代码已经在 WSL + Swift 6.0.3 上跑过
`swift test`（11 个测试、41 条夹具全绿），实测只撞到一处编译错误（`abs` 与成员同名，已修）。
如果 Mac 上报错，多半是 macOS 与 Linux Foundation 的差异，看下面这张表。

### 按类别修，不要逐条修

| 错误长这样 | 大概率原因 | 怎么改 |
|---|---|---|
| `Cannot find type 'Bundle' in scope` / `cannot find 'Data'` | 测试文件漏了 Foundation | 加 `import Foundation` |
| `Type 'Rational' does not conform to 'Comparable'` | 运算符重载没写全 | 补 `<`；或先删掉 `Comparable` 只留 `Equatable` |
| `Ambiguous use of 'abs'` / `'max'` | 全局函数与成员同名 | 写成 `Swift.abs` / `Swift.max` |
| `Cannot convert value of type 'Character' to 'String'` | `String.contains(Character)` 用错 | 改成 `String(c).contains(...)` 或直接比较 Character |
| `Value of type 'X' has no member 'y'` | 字段名对不上（多半是我记错了） | 按报错改名，**顺手在 `golden_cases.json` 里也改**，两边一起 |
| `Constant 'x' used before being initialized` | `do/catch` 里提前 `continue` | 改成 `var` 并给初值 |
| `Missing argument for parameter 'x'` | memberwise init 参数顺序 | 只用构造器，别用位置参数 |
| `Static member 'module' cannot be used on instance` | `Bundle.module` 只在有 resources 的 target 里生成 | 确认 `Package.swift` 的 `resources: [.copy(...)]` 在**测试 target** 上 |

**修完的标准**：`swift test` 输出 `Executed 43 tests, with 0 failures`
（夹具 48 条；一个测试覆盖多条夹具；此外还有 19 条与 Python 参考实现的对账）。

> 如果 1.5 小时还清不干净：**立刻降级**。把 `Core.swift` 砍到只支持 `ax^n` 单项、
> `Engine.swift` 只留 `DerivativeCheck`，矩阵/积分/几何全部 `throw .unsupported`。
> 先让 10 条求导用例绿，其余回头补。**不要为了"完整"把主线拖死。**

---

## T+1:30–2:00 —— 契约签字（10 分钟会）

只确认 5 件事，谁有异议当场说，说完冻结：

1. `terms[].param` 显式绑定，不靠下标。
2. `expected_latex` / `explanation` **只在 direct 模式**出现；socratic 下缺席。
3. `char_span` 相对 `checked.rhs_latex`，不是相对 OCR 原文。
4. 超时 3 秒切回放；回放命中键 = 规范化请求体的哈希，**请求体里不许有时间戳/UUID**。
5. 失败也返回 200 + `parse_error`，不许 5xx。

---

## T+2:00–4:00 —— 收真实 LaTeX，补进夹具

**这一步比写代码重要。** 解析器必须按识别器的真实输出写，不是按想象写。

### 做法

1. 自己手写 20 张（就写演示那 4 条 + 常见错法：`x³−5x`、`3x²−5x`、`3x²−5`），用 MyScript（或 Flash）转成 LaTeX。
2. **要字符串，不要截图**。让 P3 把结果贴给你，一行一个。
3. 贴进 `contracts/golden_cases.json` 的 `parse` 段：

   ```json
   { "id": "P16", "latex": "<贴进来的真实字符串>", "terms": [] }
   ```

4. 先让参考实现算一遍期望值：
   ```bash
   cd server && python - <<'PY'
   import json, sys
   from pathlib import Path
   sys.path.insert(0, ".")
   from math_engine.latex_norm import to_sympy
   from math_engine.terms import decompose
   ...
   PY
   ```
   或者直接用 `tests/test_golden_fixture.py` 的 `poly_terms` 函数（它和生成夹具用的是同一套口径）。
5. 跑 `pytest tests/test_golden_fixture.py`，**红了就是这条超范围**：
   要么改学生的写法（练熟固定写法），要么改范围（砍掉这条演示）。

### 判断标准（4 小时闸门）

| 情况 | 动作 |
|---|---|
| 20 条里 ≥17 条能解析且判对 | 继续，按计划走 |
| 12–16 条 | 砍矩阵/积分，只保求导；同时让 P1 把"识别结果可手改"做成显眼按钮 |
| <12 条 | **换路子**：不赌识别，演"手写只做视觉 + LaTeX 由学生确认"，主讲批改引擎 |
| MyScript 证书没下来 | 立刻切 Flash，别等。两条路都要能在 4 小时内出 20 条结果 |

---

## T+4:00 站会（10 分钟，你主持）

只问三个问题，答案只要"是/否 + 一个数字"：

1. `swift test` 绿了吗？（是/否 + 失败条数）
2. 20 条真实 LaTeX 里，能解析的有几条？（数字）
3. 空壳 App 装上 iPad 了吗？（是/否）

**任一为"否"，当场做决定**：
- 编译不绿 → 砍范围（矩阵/积分/几何全停），只保 `derivative` + `function`。
- 识别不够 → 见上表。
- 真机没上 → 全员帮 P1，**这是唯一能让整个演示归零的事**。

---

## 附：这一天结束时，你应该有的东西

- [ ] `contracts/v3/` 签字版（群里发过，没人反对）
- [ ] `swift test` 绿（或已按降级方案砍到只跑求导）
- [ ] `golden_cases.json` 里 ≥20 条**真实识别结果**的用例
- [ ] 一张表：识别准确率 + P50 耗时（MyScript / Flash 各一列）
- [ ] 演示脚本 v0.1（只要三幕的台词骨架，不用打磨）
