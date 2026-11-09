#!/bin/bash
# 由 Assets/icon/AppIcon.svg 生成 Packaging/AppIcon.icns
# 优先用系统 iconutil（会额外写入 info 条目，Finder/Launchpad 兼容性最好），
# 失败再退回按规范手写的 build-icns.py。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Assets/icon/AppIcon.svg"
OUT="$ROOT/Packaging/AppIcon.icns"
SET="$ROOT/build/AppIcon.iconset"

command -v rsvg-convert >/dev/null 2>&1 || { echo "缺少 rsvg-convert（brew install librsvg）"; exit 1; }

rm -rf "$SET"
mkdir -p "$SET"

# iconutil 要求的文件名：icon_<边长>x<边长>[@2x].png
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$SET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$SVG" -o "$SET/icon_${size}x${size}@2x.png"
done

if iconutil -c icns "$SET" -o "$OUT" 2>/dev/null && python3 "$ROOT/scripts/check-icns.py" "$OUT"; then
    echo "已生成：${OUT}（iconutil）"
else
    echo "iconutil 失败，改用 build-icns.py"
    python3 "$ROOT/scripts/build-icns.py"
    python3 "$ROOT/scripts/check-icns.py" "$OUT"
fi

rm -rf "$SET"
