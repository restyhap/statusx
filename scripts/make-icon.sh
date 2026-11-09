#!/bin/bash
# 由 Assets/icon/AppIcon.svg 生成 Packaging/AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Packaging/AppIcon.icns"

command -v rsvg-convert >/dev/null 2>&1 || { echo "缺少 rsvg-convert（brew install librsvg）"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "缺少 python3"; exit 1; }

python3 "$ROOT/scripts/build-icns.py"