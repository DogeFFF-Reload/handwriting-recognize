# P4 · 文档索引

> 这一页只解决一件事：**你想找哪份，点哪个。**
> 代码在 `Packages/MathEngine/`，契约在 `Packages/MathEngine/Tests/MathEngineTests/contracts/`。

## 现在该做什么

| 文档 | 给谁 | 内容 |
|---|---|---|
| [P4-TODO.md](P4-TODO.md) | **P4 本人** | 行动清单：现在做什么、T+0/2/4/20/30/40 各阶段做什么、要跟队友确认什么 |
| [KICKOFF.md](KICKOFF.md) | P4 + 全队 | 开赛后前 4 小时：谁做什么、编译错误怎么修、4 小时闸门判据 |

## 技术说明

| 文档 | 内容 |
|---|---|
| [MathEngine-SPEC.md](MathEngine-SPEC.md) | 引擎算法、支持的语法边界、Python→Swift 对照表 |
| [INTEGRATION.md](INTEGRATION.md) | 队友怎么接：P1 圈与气泡、P2 滑条与场景、P3 的 `/check` |
| [TEAM-ACTIONS.md](TEAM-ACTIONS.md) | 发给队友的那份：每人不超过 10 行改动 |
| [PLAN-SWIFT.md](PLAN-SWIFT.md) | Swift 原生方案下的可行性复判、工作量重估、48 小时计划 |

## 演示

| 文档 | 内容 |
|---|---|
| [DEMO_SCRIPT.md](DEMO_SCRIPT.md) | 3 分钟脚本、出事怎么说、答辩 Q&A、演出前检查清单 |

## 识别（MyScript）

| 文档 | 内容 |
|---|---|
| [MyScript-INTEGRATION.md](MyScript-INTEGRATION.md) | 证书条款（2000 次免费、设备 license 永久、离线 30 天）、引擎创建、math 配置 |
| [MyScript-COLLECT.md](MyScript-COLLECT.md) | SDK 在哪（SPM 4.5.1）、识别资源包体积、10 条真实 LaTeX 怎么采 |

---

## 两条硬数据

- **测试**：`swift test` 43 个测试；Python 参考实现 139 条；两套实现 19/19 对账一致。
- **边界**：只支持单变量多项式；三角/对数/根号一律 `parse_error` —— 宁让学生改一次，不静默算错。
