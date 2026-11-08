#!/bin/bash
# 打包成可双击的 StatusX.app（菜单栏应用，无 Dock 图标）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/StatusX.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/StatusX" "$APP/Contents/MacOS/StatusX"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/assets"
cp "$ROOT/Assets/svg/"*.svg "$APP/Contents/Resources/assets/"
# 应用图标（没有它就显示系统通用图标）
[ -f "$ROOT/Packaging/AppIcon.icns" ] || "$ROOT/scripts/make-icon.sh"
cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "已生成：$APP"
echo "首次运行需在 系统设置 → 隐私与安全性 → 辅助功能 中勾选 StatusX"
