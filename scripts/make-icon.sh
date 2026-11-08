#!/bin/bash
# 由 Assets/icon/AppIcon.svg 生成 Packaging/AppIcon.icns（需要 rsvg-convert + iconutil）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Assets/icon/AppIcon.svg"
OUT="$ROOT/Packaging/AppIcon.icns"
SET="$(mktemp -d)/AppIcon.iconset"

command -v rsvg-convert >/dev/null || { echo "缺少 rsvg-convert（brew install librsvg）"; exit 1; }

mkdir -p "$SET"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$SRC" -o "$SET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$SRC" -o "$SET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$SET" -o "$OUT"
rm -rf "$(dirname "$SET")"
echo "已生成：$OUT"
