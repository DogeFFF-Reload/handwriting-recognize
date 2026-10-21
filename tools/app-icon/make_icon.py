"""笔迹 AI 家教的应用图标：横线纸上同一笔 x^3-3x，左边是铅笔手写的墨迹，往右变成 App 里的标准曲线，
极小值处一段绿色水平切线（App 求导后画的就是这个）。

输出 1024x1024 三张：浅色（默认）、深色、单色（iOS 18 的 tinted，灰度，系统再上色），再拼一张预览。
颜色取自 app/InkTutor/Theme.swift（纸、横线、页边线、第一条曲线的蓝、Theme.ok 的绿）。

用法（要 Pillow：pip install pillow）：
    python tools/app-icon/make_icon.py app/InkTutor/Assets.xcassets/AppIcon.appiconset
会覆盖那里的 AppIcon.png / AppIcon-Dark.png / AppIcon-Tinted.png，另外多写一张 preview.png，那张别提交。
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
SS = 4                      # 超采样倍数
N = 1024
S = N * SS


def rgb(r, g, b):
    return (round(r * 255), round(g * 255), round(b * 255))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# App 的 Theme.swift
LIGHT = dict(
    paper=rgb(0.985, 0.979, 0.965),
    rule=mix(rgb(0.985, 0.979, 0.965), rgb(0.33, 0.46, 0.70), 0.20),
    margin=mix(rgb(0.985, 0.979, 0.965), rgb(0.86, 0.35, 0.35), 0.42),
    ink=(38, 40, 52),               # 铅笔墨色
    curve=rgb(0.16, 0.42, 0.86),    # Theme.curves[0]
    ok=rgb(0.13, 0.62, 0.38),       # Theme.ok
    dot_fill=rgb(0.985, 0.979, 0.965),
)
DARK = dict(
    paper=(24, 26, 34),
    rule=(44, 49, 66),
    margin=(92, 48, 50),
    ink=(196, 200, 214),
    curve=(110, 160, 255),
    ok=(70, 200, 135),
    dot_fill=(24, 26, 34),
)
TINT = dict(                         # 灰度：系统按亮度上色，越亮颜色越足
    paper=(0, 0, 0),
    rule=(46, 46, 46),
    margin=(70, 70, 70),
    ink=(150, 150, 150),
    curve=(255, 255, 255),
    ok=(255, 255, 255),
    dot_fill=(0, 0, 0),
)

# 版面（1024 坐标）
RULE_GAP = 142
RULE_W = 7
MARGIN_X = 176
MARGIN_W = 7
X_RANGE = (-2.08, 2.08)            # x^3-3x 在 ±2.08 处约 ±2.76
BOX = (262, 262, 822, 790)         # 曲线占的框：左、上、右、下（四角留给系统圆角）


def fx(x):
    return x ** 3 - 3 * x


def to_px(x, y):
    l, t, r, b = BOX
    ymax = fx(X_RANGE[1])
    px = l + (x - X_RANGE[0]) / (X_RANGE[1] - X_RANGE[0]) * (r - l)
    py = t + (ymax - y) / (2 * ymax) * (b - t)
    return px * SS, py * SS


def curve_points(n=2400):
    pts = []
    for i in range(n + 1):
        x = X_RANGE[0] + (X_RANGE[1] - X_RANGE[0]) * i / n
        pts.append((x, *to_px(x, fx(x))))
    return pts


def draw_icon(p, wobble=True):
    img = Image.new("RGB", (S, S), p["paper"])
    d = ImageDraw.Draw(img)

    # 横线纸：上下各留一点，线条要粗到小图标上还看得见
    y = 166
    while y < N:
        d.rectangle([0, (y - RULE_W / 2) * SS, S, (y + RULE_W / 2) * SS], fill=p["rule"])
        y += RULE_GAP
    d.rectangle([(MARGIN_X - MARGIN_W / 2) * SS, 0, (MARGIN_X + MARGIN_W / 2) * SS, S], fill=p["margin"])

    # 极小值 (1, -2) 的水平切线：先画，曲线压在上面，看起来是贴着曲线底部的一条切线
    cx, cy = to_px(1.0, -2.0)
    half = 168 * SS
    lw = 15 * SS
    d.rounded_rectangle([cx - half, cy - lw / 2, cx + half, cy + lw / 2], radius=lw / 2, fill=p["ok"])

    # 同一笔：x < -0.55 是铅笔手写（压感起伏、轻微抖动、起笔收尖），-0.55..0.25 渐变，之后是标准曲线
    rnd = random.Random(7)
    pts = curve_points()
    # 抖动：几段低频正弦叠加，只作用在手写那部分
    phases = [rnd.uniform(0, 2 * math.pi) for _ in range(3)]
    ink_end, crisp_start = -0.55, 0.25
    full_w = 58 * SS
    for i, (x, px, py) in enumerate(pts):
        t = smooth((x - ink_end) / (crisp_start - ink_end))   # 0 手写 → 1 标准
        hand = 1 - t
        # 压感：起笔细，中段粗细起伏
        start = smooth((x - X_RANGE[0]) / 0.32)
        pressure = 0.72 + 0.22 * math.sin(x * 5.3 + 1.1) + 0.08 * math.sin(x * 13.0)
        w_hand = full_w * (0.42 + 0.58 * start) * pressure
        w = w_hand * hand + full_w * t
        if wobble and hand > 0:
            j = sum(math.sin(x * f + ph) for f, ph in zip((9.0, 17.0, 31.0), phases)) / 3
            py += j * 4.5 * SS * hand
            px += j * 2.0 * SS * hand
        color = mix(p["ink"], p["curve"], t)
        r = w / 2
        d.ellipse([px - r, py - r, px + r, py + r], fill=color)

    # 铅笔颗粒：手写那段上撒一点和纸色混合的细点（大图上看得出，小图上不碍事）
    if wobble:
        grain = Image.new("L", (S, S), 0)
        g = ImageDraw.Draw(grain)
        for x, px, py in pts[::3]:
            t = smooth((x - ink_end) / (crisp_start - ink_end))
            if t >= 0.6:
                continue
            for _ in range(2):
                gx = px + rnd.gauss(0, 8 * SS)
                gy = py + rnd.gauss(0, 8 * SS)
                rr = rnd.uniform(1.0, 2.0) * SS
                g.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=int(110 * (1 - t)))
        grain = grain.filter(ImageFilter.GaussianBlur(SS * 0.6))
        paper_layer = Image.new("RGB", (S, S), p["paper"])
        img = Image.composite(paper_layer, img, grain.point(lambda v: int(v * 0.35)))
        d = ImageDraw.Draw(img)

    # 极小值点
    ro, ri = 38 * SS, 20 * SS
    d.ellipse([cx - ro, cy - ro, cx + ro, cy + ro], fill=p["ok"])
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=p["dot_fill"])

    return img.resize((N, N), Image.LANCZOS)


def rounded_mask(size):
    """iOS 图标的圆角（近似连续曲率，半径约 22.37%）。只用于预览，交给 Xcode 的图要方的。"""
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.2237), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def preview(light, dark, tint):
    """一张预览：三种外观的大图，加上主屏幕常见尺寸（浅色、深色壁纸上各一排）。"""
    W, H = 1500, 980
    sheet = Image.new("RGB", (W, H), (236, 237, 242))
    d = ImageDraw.Draw(sheet)
    d.rectangle([0, 560, W, H], fill=(28, 30, 38))
    x = 60
    for im in (light, dark, tint):
        big = im.resize((420, 420), Image.LANCZOS)
        sheet.paste(big, (x, 70), rounded_mask(420))
        x += 470
    sizes = [180, 152, 120, 87, 76, 58, 40]
    for row, (im, y) in enumerate(((light, 600), (dark, 790))):
        x = 60
        for s in sizes:
            small = im.resize((s, s), Image.LANCZOS)
            sheet.paste(small, (x, y + (180 - s) // 2), rounded_mask(s))
            x += s + 46
    return sheet


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    light = draw_icon(LIGHT)
    dark = draw_icon(DARK)
    tint = draw_icon(TINT, wobble=True)
    light.save(OUT / "AppIcon.png")
    dark.save(OUT / "AppIcon-Dark.png")
    tint.convert("L").convert("RGB").save(OUT / "AppIcon-Tinted.png")
    preview(light, dark, tint.convert("L").convert("RGB")).save(OUT / "preview.png")
    print("ok", OUT)
