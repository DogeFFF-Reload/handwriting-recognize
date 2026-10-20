# 识别实测脚本（S01–S20）

开发方向报告「识别实测（第 0–4 小时）」的打分脚本：同一份墨迹，MyScript 在 iPad 示例 App 里认、记进 CSV；Qwen 由脚本对同一份截图调用；最后按报告的判定标准出结论和引擎选择。只依赖 Python 3.10+ 标准库，不进 App。

**和 App 用的是同一套调用**：提示词运行时直接从 `Packages/InkCore/Sources/InkCore/Recognizers.swift` 的 `recognitionPrompt` 读；请求体（`max_tokens 200`、`temperature 0`、qwen3.8 关推理）和回复解析（`extractLatex`）照抄 `DashScopeRecognizer`，见 `inkcore.py`。App 那边改了，这里要跟着改，`test_bench.py` 会核对。

## 用法

1. iPad 上按 `samples.csv` 逐条手写，截整行白底图放到 `shots/`：`S01.png`…；黄金行（S01–S06）连写三遍用 `S01-1.png`、`S01-2.png`、`S01-3.png`。
2. 同一份墨迹在 MyScript 示例 App 里的结果手工记进 `myscript.csv`，列为 `id,rep,latex,ms`。
3. 跑：

```bash
cd tools/recog-bench
export DASHSCOPE_API_KEY=sk-...      # 只放环境变量，不进仓库
python bench.py --shots shots --myscript myscript.csv
python bench.py --shots shots --model qwen3-vl-plus --out results-vl-plus.csv   # 后备模型
python bench.py --score-only results.csv --myscript myscript.csv                 # 只重新打分
python -m unittest -v                                                            # 脚本自己的单测
```

默认走北京区接口（`DashScope.beijing`），要换区域设 `DASHSCOPE_ENDPOINT`。

## 判定标准（照报告）

- 黄金行 S01–S06：每条连写 3 遍都要对，该引擎才能当主路径。写错的式子（S03 的 `3x^2-3x`）被模型「改对」也算错。
- 整体：20 条对 16 条以上（一条样本的所有遍都对才算对）。
- 耗时：MyScript 低于 500 ms；Qwen 含网络 p90 低于 2 s。请求失败的那一遍算错，不计入耗时。
- 选择：MyScript 达标就用它；只有 Qwen 达标就用 Qwen；都不达标走回放（`ReplayRecognizer`），同时把黄金行的写法练熟。

比对前的归一化：去掉空格；`\cdot`、`\times` 和省略乘号视为相同；`^{2}` 和 `^2` 视为相同；全角的 − 和 - 视为相同（另外把 `\,` 这类间距命令当空格）。
