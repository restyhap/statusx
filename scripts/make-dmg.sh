#!/bin/bash
# 生成可分发的 DMG：内含 StatusX.app + 「应用程序」软链（拖拽安装）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Packaging/Info.plist")}"
APP="$ROOT/build/StatusX.app"
DMG="$ROOT/build/StatusX-$VERSION.dmg"
VOL="StatusX"

[ -d "$APP" ] || { echo "缺少 $APP，先跑 ./scripts/build-app.sh"; exit 1; }

safedel() {
    case "$1" in
        /tmp/*|/var/folders/*) rm -rf "$1" ;;
        *) echo "拒绝删除非临时目录: $1" >&2; exit 1 ;;
    esac
}

# 1. 暂存目录：应用 + 指向 /Applications 的软链
WORK="$(mktemp -d -t statusx-XXXXXX)"
STAGE="$WORK/stage"; mkdir -p "$STAGE"
RW="$WORK/rw.dmg"
cp -R "$APP" "$STAGE/StatusX.app"
ln -s /Applications "$STAGE/Applications"

# 2. 先做可读写镜像，摆好图标位置，再压缩成只读
RW="$(mktemp -u -t statusx-XXXXXX).dmg"
hdiutil create -quiet -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" 2>/dev/null \
         | grep -o '/Volumes/[^ ]*' | head -1)"

if [ -n "$MOUNT" ]; then
    # 3. 窗口布局（Finder 不可用时忽略，不影响可安装性）
    osascript <<OSA >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 760, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "StatusX.app" of container window to {150, 200}
        set position of item "Applications" of container window to {420, 200}
        close
    end tell
end tell
OSA
    sync
    hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true
fi

# 4. 压缩
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
safedel "$WORK"

echo "已生成：$DMG"
shasum -a 256 "$DMG" | awk '{print "SHA256: " $1}'