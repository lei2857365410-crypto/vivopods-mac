#!/bin/bash
# 把 SwiftPM 产出的可执行文件组装成 macOS .app bundle 并 ad-hoc 签名。
#
# 之所以手工组装而不用 xcodebuild：本机只装了 Command Line Tools，没有完整
# Xcode，无法构建 .xcodeproj。SwiftPM + 手工 bundle + codesign 完全够用。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/VivoPods.app"

echo "▸ 编译 ($CONFIG)…"
swift build -c "$CONFIG" --product VivoPods

BIN="$(swift build -c "$CONFIG" --product VivoPods --show-bin-path)/VivoPods"
if [ ! -f "$BIN" ]; then
    echo "✗ 没找到可执行文件：$BIN" >&2
    exit 1
fi

echo "▸ 组装 bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VivoPods"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ ad-hoc 签名…"
# 签名让 TCC 能按 bundle id 稳定记住蓝牙授权；ad-hoc 对本机自用足够
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'

echo
echo "✓ 完成：$APP"
echo
echo "启动：  open '$APP'"
echo "首次运行会弹蓝牙授权，允许后图标出现在菜单栏右侧。"

# 传入 --install 时安装到 /Applications。
# SMAppService 的登录项注册绑定 App 的绝对路径，装到固定位置才不会因为
# 重新构建（build/ 目录被覆盖）或移动位置而失效。
if [ "${2:-}" = "--install" ] || [ "${1:-}" = "--install" ]; then
    DEST="/Applications/VivoPods.app"
    echo "▸ 安装到 $DEST …"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    codesign --force --sign - --timestamp=none "$DEST"
    echo "✓ 已安装：$DEST"
fi
