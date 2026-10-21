# 千问识别「求解」类式子（积分、极限、求和、矩阵）的测试：生成手写风格图 → 用 App 同一套请求调 qwen → 对比
# 用法：DASHSCOPE_API_KEY=sk-... python solve_bench.py <输出目录> [提示词文件，缺省读 Recognizers.swift]
# 图是字体渲染加抖动的「手写风格」，不是真人笔迹：用来查提示词和写法约定；真人手写仍按 README 的 S01–S20 测。
# 需要 matplotlib 和 Pillow。手写风格字体用 INK_FONT 指定（默认 Windows 的 Ink Free）。
import base64, io, json, os, random, sys, time, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
BENCH = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCH))
import inkcore  # noqa: E402
from normalize import normalize  # noqa: E402

import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import font_manager  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: E402

OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
PROMPT = Path(sys.argv[2]).read_text(encoding="utf-8") if len(sys.argv) > 2 else inkcore.load_recognition_prompt()
KEY = os.environ["DASHSCOPE_API_KEY"]  # 只放环境变量，不进仓库
INK = os.environ.get("INK_FONT", r"C:\Windows\Fonts\Inkfree.ttf")
font_manager.fontManager.addfont(INK)
INK_NAME = font_manager.FontProperties(fname=INK).get_name()
plt.rcParams.update({"mathtext.fontset": "custom", "mathtext.rm": INK_NAME, "mathtext.it": INK_NAME,
                     "mathtext.bf": INK_NAME, "mathtext.fallback": "stix"})
random.seed(3)

# (id, 画图用的 mathtext 或矩阵, 期望 LaTeX)
CASES = [
    ("F1", r"$f(x)=x^{3}-5x$", r"f(x)=x^{3}-5x"),
    ("F2", r"$f'(x)=3x^{2}-3x$", r"f'(x)=3x^{2}-3x"),
    ("F3", r"$\int_{0}^{1} 2x\,dx = 2$", r"\int_{0}^{1}2xdx=2"),
    ("I1", r"$\int_{0}^{1} x^{2}\,dx$", r"\int_{0}^{1}x^{2}dx"),
    ("I2", r"$\int x e^{x}\,dx$", r"\int xe^{x}dx"),
    ("I3", r"$\int_{0}^{\infty} e^{-x}\,dx$", r"\int_{0}^{\infty}e^{-x}dx"),
    ("I4", r"$\int_{1}^{e} \frac{1}{x}\,dx$", r"\int_{1}^{e}\frac{1}{x}dx"),
    ("L1", r"$\lim_{x \to 0} \frac{\sin x}{x}$", r"\lim_{x\to0}\frac{\sin x}{x}"),
    ("L2", r"$\lim_{x \to \infty} \left(1+\frac{1}{x}\right)^{x}$", r"\lim_{x\to\infty}(1+\frac{1}{x})^{x}"),
    ("L3", r"$\lim_{x \to 2} \frac{x^{2}-4}{x-2}$", r"\lim_{x\to2}\frac{x^{2}-4}{x-2}"),
    ("L4", r"$\lim_{x \to 0^{+}} x \ln x$", r"\lim_{x\to0^{+}}x\ln x"),
    ("S1", r"$\sum_{k=1}^{n} k^{2}$", r"\sum_{k=1}^{n}k^{2}"),
    ("S2", r"$\sum_{n=1}^{\infty} \frac{1}{n^{2}}$", r"\sum_{n=1}^{\infty}\frac{1}{n^{2}}"),
    ("S3", r"$\prod_{k=1}^{5} k$", r"\prod_{k=1}^{5}k"),
    ("S4", r"$\sum_{k=1}^{10} 2k$", r"\sum_{k=1}^{10}2k"),
    ("D1", r"$\frac{d}{dx}(x^{2} \sin x)$", r"\frac{d}{dx}(x^{2}\sin x)"),
    ("E1", r"$x^{2}-5x+6=0$", r"x^{2}-5x+6=0"),
    ("M1", ("p", [["1", "2"], ["3", "4"]], [["5", "6"], ["7", "8"]]), r"\begin{pmatrix}1&2\\3&4\end{pmatrix}\begin{pmatrix}5&6\\7&8\end{pmatrix}"),
    ("M2", ("p", [["2", "1"], ["1", "1"]], None), r"\begin{pmatrix}2&1\\1&1\end{pmatrix}"),
    ("M3", ("v", [["1", "2", "3"], ["0", "1", "4"], ["5", "6", "0"]], None), r"\begin{vmatrix}1&2&3\\0&1&4\\5&6&0\end{vmatrix}"),
    ("M4", ("b", [["1", "0", "2"], ["-1", "3", "1"]], None), r"\begin{bmatrix}1&0&2\\-1&3&1\end{bmatrix}"),
]


def jitter(img: Image.Image) -> Image.Image:
    img = img.convert("L").rotate(random.uniform(-3, 3), expand=True, fillcolor=255, resample=Image.BICUBIC)
    img = img.filter(ImageFilter.MinFilter(3))   # 笔画加粗一点，像笔迹
    return img.filter(ImageFilter.GaussianBlur(0.6)).convert("RGB")


def render_math(tex: str) -> Image.Image:
    fig = plt.figure(figsize=(0.01, 0.01))
    fig.text(0, 0, tex, fontsize=34, color="#1e2a4a")
    buf = io.BytesIO()
    fig.savefig(buf, dpi=110, bbox_inches="tight", pad_inches=0.3, facecolor="white")
    plt.close(fig)
    return Image.open(buf).convert("RGB")


def render_matrix(kind, a, b) -> Image.Image:
    f = ImageFont.truetype(INK, 46)
    cw, ch = 70, 66

    def one(d, x0, rows):
        n, m = len(rows), len(rows[0])
        h = n * ch
        for i, r in enumerate(rows):
            for j, v in enumerate(r):
                d.text((x0 + 26 + j * cw + random.randint(-4, 4), 30 + i * ch + random.randint(-4, 4)), v, font=f, fill=(30, 42, 74))
        w = 26 + m * cw + 6
        top, bot = 26, 36 + h
        if kind == "p":
            d.arc([x0 - 4, top, x0 + 30, bot], 100, 260, fill=(30, 42, 74), width=4)
            d.arc([x0 + w - 30, top, x0 + w + 4, bot], -80, 80, fill=(30, 42, 74), width=4)
        elif kind == "b":
            for xx, dx in ((x0 + 6, 12), (x0 + w - 6, -12)):
                d.line([(xx + dx, top), (xx, top), (xx, bot), (xx + dx, bot)], fill=(30, 42, 74), width=4)
        else:
            d.line([(x0 + 8, top), (x0 + 6, bot)], fill=(30, 42, 74), width=4)
            d.line([(x0 + w - 8, top), (x0 + w - 6, bot)], fill=(30, 42, 74), width=4)
        return x0 + w + 24

    W = 60 + (len(a[0]) + (len(b[0]) if b else 0)) * cw + 160
    H = 80 + len(a) * ch
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    x = one(d, 20, a)
    if b:
        one(d, x, b)
    return img


def call(model, png):
    body = inkcore.chat_body(model, base64.b64encode(png).decode(), PROMPT)
    req = urllib.request.Request(inkcore.BEIJING_ENDPOINT, json.dumps(body).encode(),
                                 {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=40) as r:
        reply = inkcore.reply_text(json.load(r))
    return inkcore.extract_latex(reply), round(time.time() - t, 2)


results = []
for cid, src, expected in CASES:
    img = render_matrix(*src) if isinstance(src, tuple) else render_math(src)
    img = jitter(img)
    p = OUT / f"{cid}.png"
    img.save(p)
    png = p.read_bytes()
    for model in ["qwen3.8-flash"]:
        try:
            got, sec = call(model, png)
        except Exception as e:  # noqa: BLE001
            got, sec = f"ERROR {e}", None
        ok = normalize(got) == normalize(expected)
        results.append({"id": cid, "model": model, "ok": ok, "sec": sec, "got": got, "expected": expected})
        print(f"{'OK ' if ok else 'BAD'} {cid} {sec}s  got={got!r}" + ("" if ok else f"  want={expected!r}"))
(OUT / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
print("pass", sum(r["ok"] for r in results), "/", len(results))
