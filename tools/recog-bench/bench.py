"""识别实测（第 0–4 小时）：同一份墨迹，MyScript 在 iPad 示例 App 里认，Qwen 由本脚本对截图调用，
按开发方向报告的判定标准打分并给出选择。提示词、请求参数、回复解析都和 App 的 DashScopeRecognizer 一致（见 inkcore.py）。

用法：
    # 1. 截图放到 shots/，文件名 S01.png；黄金行连写三遍时用 S01-1.png、S01-2.png、S01-3.png
    # 2. MyScript 的结果手工记进 myscript.csv（列：id,rep,latex,ms），rep 从 1 开始
    # 3. 调模型并出报告（Key 只放环境变量，不进仓库）：
    export DASHSCOPE_API_KEY=sk-...
    python bench.py --shots shots --myscript myscript.csv
    # 换后备模型再测一遍：
    python bench.py --shots shots --model qwen3-vl-plus --out results-vl-plus.csv
    # 只重新打分（不调模型）：
    python bench.py --score-only results.csv --myscript myscript.csv

只依赖 Python 标准库。
"""

import argparse
import base64
import csv
import json
import os
import re
import statistics
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

from inkcore import APP_MODELS, BEIJING_ENDPOINT, chat_body, extract_latex, load_recognition_prompt, reply_text
from normalize import equivalent

HERE = Path(__file__).resolve().parent

# 判定标准（开发方向报告「识别实测 · 判定标准」）
GOLDEN_REPS = 3
OVERALL_MIN_CORRECT = 16
MYSCRIPT_MAX_MS = 500
QWEN_P90_MAX_MS = 2000


@dataclass
class Sample:
    id: str
    latex: str
    focus: str
    golden: bool


@dataclass
class Attempt:
    id: str
    rep: int
    latex: str
    ms: float | None
    error: str = ""


@dataclass
class EngineReport:
    name: str
    attempts: dict = field(default_factory=dict)  # id -> [Attempt]

    def add(self, attempt: Attempt):
        self.attempts.setdefault(attempt.id, []).append(attempt)


def load_samples() -> list[Sample]:
    with open(HERE / "samples.csv", encoding="utf-8") as f:
        return [Sample(r["id"], r["latex"], r["focus"], r["golden"] == "1") for r in csv.DictReader(f)]


def shot_files(shots: Path, sample_id: str) -> list[tuple[int, Path]]:
    found = []
    for p in sorted(shots.glob(f"{sample_id}*.png")):
        m = re.fullmatch(rf"{sample_id}(?:-(\d+))?\.png", p.name)
        if m:
            found.append((int(m.group(1) or 1), p))
    return found


def call_model(image: Path, prompt: str, model: str, endpoint: str, api_key: str, timeout: float) -> tuple[str, float]:
    body = chat_body(model, base64.b64encode(image.read_bytes()).decode(), prompt)
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.loads(resp.read())
    return reply_text(payload), (time.perf_counter() - started) * 1000


def run_model(samples, shots: Path, args) -> EngineReport:
    api_key = os.environ.get("DASHSCOPE_API_KEY")
    if not api_key:
        sys.exit("缺少环境变量 DASHSCOPE_API_KEY")
    prompt = load_recognition_prompt()
    report = EngineReport(args.model)
    for s in samples:
        files = shot_files(shots, s.id)
        if not files:
            print(f"  {s.id}: 没有截图，跳过")
            continue
        for rep, path in files:
            try:
                reply, ms = call_model(path, prompt, args.model, args.endpoint, api_key, args.timeout)
            except Exception as e:  # noqa: BLE001 — 实测脚本，记下网络错误继续跑，不计入耗时
                attempt = Attempt(s.id, rep, "", None, error=f"请求失败：{e}")
            else:
                try:
                    attempt = Attempt(s.id, rep, extract_latex(reply), ms)
                except ValueError as e:
                    attempt = Attempt(s.id, rep, "", ms, error=str(e))
            report.add(attempt)
            mark = "✓" if equivalent(attempt.latex, s.latex) else "✗"
            shown = f"{attempt.ms:6.0f} ms" if attempt.ms is not None else "     — ms"
            print(f"  {s.id}-{rep} {mark} {shown}  {attempt.latex or attempt.error}")
    return report


def load_attempts(path: Path, name: str) -> EngineReport:
    report = EngineReport(name)
    with open(path, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ms = float(r["ms"]) if r.get("ms") else None
            report.add(Attempt(r["id"], int(r.get("rep") or 1), r.get("latex", ""), ms, r.get("error", "")))
    return report


def save_attempts(report: EngineReport, path: Path):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "rep", "latex", "ms", "error"])
        for attempts in report.attempts.values():
            for a in attempts:
                w.writerow([a.id, a.rep, a.latex, "" if a.ms is None else f"{a.ms:.0f}", a.error])


def percentile(values: list[float], q: int) -> float:
    if not values:
        return float("nan")
    if len(values) == 1:
        return values[0]
    return statistics.quantiles(values, n=100, method="inclusive")[q - 1]


@dataclass
class Score:
    correct_samples: int
    tested_samples: int
    golden_ok: bool
    golden_detail: dict
    p50: float
    p90: float
    passes: bool


def score(report: EngineReport, samples: list[Sample], max_ms: float) -> Score:
    """一条样本的所有遍都对才算对；黄金行（S01–S06）每条至少 3 遍且全对；耗时看 p90。"""
    correct = 0
    tested = 0
    golden_detail = {}
    for s in samples:
        attempts = report.attempts.get(s.id, [])
        if not attempts:
            if s.golden:
                golden_detail[s.id] = "没测"
            continue
        tested += 1
        right = sum(equivalent(a.latex, s.latex) for a in attempts)
        correct += right == len(attempts)
        if s.golden:
            golden_detail[s.id] = f"{right}/{len(attempts)}"
    golden_ok = all(
        len(report.attempts.get(s.id, [])) >= GOLDEN_REPS
        and all(equivalent(a.latex, s.latex) for a in report.attempts[s.id])
        for s in samples if s.golden
    )
    times = [a.ms for attempts in report.attempts.values() for a in attempts if a.ms is not None]
    p50, p90 = percentile(times, 50), percentile(times, 90)
    passes = golden_ok and correct >= OVERALL_MIN_CORRECT and bool(times) and p90 < max_ms
    return Score(correct, tested, golden_ok, golden_detail, p50, p90, passes)


def choose(myscript: Score | None, qwen: Score | None) -> str:
    """选择规则：MyScript 达标就优先用它（设备上运行，不依赖网络）；只有 Qwen 达标就用 Qwen；
    两边都不达标，演示走录好的 LaTeX 回放，同时把黄金行的写法练熟。"""
    if myscript and myscript.passes:
        return "MyScript"
    if qwen and qwen.passes:
        return "Qwen（DashScopeRecognizer / ServerRecognizer）"
    return "回放（ReplayRecognizer）"


def print_score(title: str, s: Score):
    print(f"\n{title}")
    print(f"  整体：{s.correct_samples}/{s.tested_samples} 条全对（要求 ≥ {OVERALL_MIN_CORRECT}/20）")
    print(f"  黄金行（每条 {GOLDEN_REPS} 遍全对）：{'达标' if s.golden_ok else '不达标'}  {s.golden_detail}")
    print(f"  耗时：p50 {s.p50:.0f} ms，p90 {s.p90:.0f} ms")
    print(f"  结论：{'达标' if s.passes else '不达标'}")


def main(argv=None):
    # Windows 终端默认不是 UTF-8，输出中文会报错。
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shots", type=Path, help="截图目录")
    ap.add_argument("--myscript", type=Path, help="MyScript 手工记录的 CSV（id,rep,latex,ms）")
    ap.add_argument("--score-only", type=Path, help="不调模型，直接给已有的结果 CSV 打分")
    ap.add_argument("--out", type=Path, default=HERE / "results.csv", help="模型结果写到这里")
    ap.add_argument("--model", default=APP_MODELS[0], help=f"App 里的顺序是 {' → '.join(APP_MODELS)}")
    ap.add_argument("--endpoint", default=os.environ.get("DASHSCOPE_ENDPOINT", BEIJING_ENDPOINT))
    ap.add_argument("--timeout", type=float, default=20, help="和 App 的 timeoutInterval 一样")
    args = ap.parse_args(argv)

    samples = load_samples()
    qwen = None
    if args.score_only:
        qwen = load_attempts(args.score_only, args.model)
    elif args.shots:
        print(f"调用 {args.model} …")
        qwen = run_model(samples, args.shots, args)
        save_attempts(qwen, args.out)
        print(f"结果已写入 {args.out}")

    myscript = load_attempts(args.myscript, "MyScript") if args.myscript else None
    if not qwen and not myscript:
        ap.error("至少给 --shots、--score-only 或 --myscript 之一")

    my_score = score(myscript, samples, MYSCRIPT_MAX_MS) if myscript else None
    qwen_score = score(qwen, samples, QWEN_P90_MAX_MS) if qwen else None
    if my_score:
        print_score("MyScript（设备上，要求 < 500 ms）", my_score)
    if qwen_score:
        print_score(f"{qwen.name}（含网络，要求 p90 < 2 s）", qwen_score)
    print(f"\n选择：{choose(my_score, qwen_score)}")


if __name__ == "__main__":
    main()
