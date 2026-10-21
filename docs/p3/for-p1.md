# p3/for-p1：给 P1 编译装机的合并分支（2026-10-21）

## 包含哪些分支

在 main（05a8037）上依次合并：

1. `p3/qwen-first`（fd69564）：设置里的「直连百炼」改成千问优先，千问失败或结果为空时退到 MyScript，再到 Server。
2. `p3/recog-hardening`（b70da4a）：`FallbackRecognizer` 每个引擎最多等 15 秒（`withDeadline`）；Server 回放兜底到点就放；打开草稿时也重置回放行状态（`resetReplay()`）；删掉 InkCore 临时的 `DerivativeCheck`。详见 `docs/p3/recog-review.md`。
3. `p3/qwen-solve`（c138045）：千问识别提示词加写法约定、`canonicalLatex` 兜底、`QwenSolveTests`。

## 合并冲突怎么解的

- 合并 1、2（10da5c5）：没有冲突。`AppModel.swift` 两边都改了，但不在同一处（qwen-first 改的是 `recognizerChain` 的 `"direct"` 那一行，recog-hardening 改的是 `clear()` / `restore()`），自动合并。
- 合并 3（0be6b70）：只有 `Packages/InkCore/Sources/InkCore/Recognizers.swift` 冲突。qwen-solve 在 `FallbackRecognizer` 前面插了 `canonicalLatex` 和 `unbraceCells`，两边又都改了 `FallbackRecognizer` 那行文档注释。解法：保留插进来的两个函数，注释用 recog-hardening 的版本（写了 `timeout`）。`FallbackRecognizer` 的代码本身是自动合并的，就是 recog-hardening 的版本。
- 复核：用 `git merge-tree` 把两次合并重做了一遍。合并 1 的结果和 10da5c5 完全一样；合并 3 的结果和 0be6b70 只差上面那处冲突，其他文件没有手改。

## Linux 上的测试

Ubuntu 24.04 + Swift 6.0.3（和 CI 的 `swift:6.0` 同一个版本线），在 0be6b70 上跑。GitHub Actions 目前分不到机器，所以是在云端机器上手动跑的。

| 命令 | 结果 |
| --- | --- |
| `swift test --package-path Packages/InkCore` | 130 条，0 失败（recog-hardening 上是 125 条，加 qwen-solve 的 `QwenSolveTests` 5 条） |
| `swift test --package-path Packages/MathEngine` | 43 条，0 失败 |
| `swift test --package-path Server` | 14 条，0 失败 |

合并没有带来需要修的问题，这个分支除了本文档没有别的改动。

## 只能在 Mac 上验证的部分

`app/InkTutor/AppModel.swift` 的两处改动，Linux 上编不了，也没有 CI 编过，**要 P1 在 Mac 上编译确认**：

- `resetReplay()`（recog-hardening）：从 `clear()` 里抽出来的私有方法，`clear()` 和 `restore()`（打开草稿）都调用它。
- `recognizerChain` 里 `case "direct"` 那一行（qwen-first）：从 `[qwen]` 改成 `[qwen, myscript, mac]`。

装机后建议顺手看两件事：设置里选「直连百炼」、MyScript 已就绪时，断网双击能落到 MyScript 认出来；彩排过一遍以后再开一份新草稿走回放演示，第一次写 F1 放出来的应该是 `f(x)=x^3-5x`，不是改正以后的 `f(x)=x^3-3x`。
