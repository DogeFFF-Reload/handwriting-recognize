#!/usr/bin/env bash
# 把 docs/项目说明/index.html 打印成 docs/项目说明.pdf（A4）。
# 需要：Chromium（或 Chrome）、中文字体 fonts-noto-cjk（apt-get install fonts-noto-cjk）。
# 用法：docs/项目说明/build.sh [chromium 路径]
#
# img/ 里的截图取自 CI 的 screenshots artifact（run #43，main 05a8037 那一版，浅色）：
# CI 存的是竖着的原图，逆时针转 90° 成横屏 2752×2064，裁掉下面的空白，缩到 1800 宽存 JPEG。
# docs/screenshots/ 里的旧截图是 10-20 的版本（菜单还是「推导」、卡片上有已去掉的批改），没用。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../项目说明.pdf"
chrome="${1:-${CHROME:-}}"
if [ -z "$chrome" ]; then
  for c in chromium chromium-browser google-chrome /opt/pw-browsers/chromium-*/chrome-linux/chrome; do
    if command -v "$c" >/dev/null 2>&1; then chrome="$c"; break; fi
  done
fi
[ -n "$chrome" ] || { echo "找不到 Chromium，把路径作为第一个参数传进来" >&2; exit 1; }
fc-list :lang=zh family | grep -q "Noto Sans CJK SC" || { echo "缺中文字体：apt-get install fonts-noto-cjk" >&2; exit 1; }

"$chrome" --headless --no-sandbox --disable-gpu --allow-file-access-from-files \
  --no-pdf-header-footer --print-to-pdf="$out" "file://$here/index.html" 2>/dev/null
echo "$out"
