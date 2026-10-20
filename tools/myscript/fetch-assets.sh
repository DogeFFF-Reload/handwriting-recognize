#!/bin/sh
# 下载 MyScript iink 4.5 的数学识别资源（math2，Math Recognizer 默认用它），解到 <目标目录>/recognition-assets。
#
#   tools/myscript/fetch-assets.sh            # 默认放到 app/MyScript/recognition-assets
#   tools/myscript/fetch-assets.sh <目标目录>
#
# Xcode 编译时的「MyScript Recognition Assets」一步发现没有资源会自动调它。
# 资源是 MyScript 给示例程序用的那一份（见 MyScript/interactive-ink-examples-ios 的 retrieve_recognition-assets.sh），
# 不进仓库；证书（MyCertificate.c）另外放，见 README。
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest=${1:-"$here/../../app/MyScript"}
url=https://download.myscript.com/iink/recognitionAssets_iink_4.5/myscript-iink-recognition-math2.zip

if [ -f "$dest/recognition-assets/conf/math2.conf" ]; then
  echo "MyScript 数学识别资源已经在 $dest/recognition-assets"
  exit 0
fi

mkdir -p "$dest"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "下载 $url"
curl -fL --retry 2 --connect-timeout 15 -o "$tmp/math2.zip" "$url"
unzip -oq "$tmp/math2.zip" -d "$dest"
test -f "$dest/recognition-assets/conf/math2.conf"
echo "已解到 $dest/recognition-assets"
