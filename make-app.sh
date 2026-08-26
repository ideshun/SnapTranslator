#!/bin/bash
# 组装 SnapTranslator.app 并完成 ad hoc 签名（自用分发）
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build (release)"
# --disable-sandbox：本机 CLT 环境下 SwiftPM 内置 sandbox-exec 与外层沙箱冲突
swift build -c release --disable-sandbox

APP="build/SnapTranslator.app"
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/SnapTranslator "$APP/Contents/MacOS/SnapTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ---- 生成 AppIcon.icns（程序坞图标）----
# 从 Resources/AppIcon.png 用 sips 生成多尺寸 iconset，再用 iconutil 打包为 icns
ICONSET="build/AppIcon.iconset"
ICON_SRC="Resources/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    echo "==> 生成程序坞图标 AppIcon.icns"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    sips -z 16 16    "$ICON_SRC" --out "$ICONSET/icon_16x16.png"    >/dev/null
    sips -z 32 32    "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
    sips -z 32 32    "$ICON_SRC" --out "$ICONSET/icon_32x32.png"     >/dev/null
    sips -z 64 64    "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128  "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256  "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256  "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512  "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512  "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    cp "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "!! 未找到 $ICON_SRC，跳过程序坞图标生成"
fi

echo "==> ad hoc 签名"
codesign --force --sign - "$APP"

echo "==> 校验"
codesign --verify --verbose "$APP"

SIZE=$(du -sh "$APP" | cut -f1)
echo "完成：${APP}（${SIZE}）"
echo "安装：cp -R ${APP} /Applications/ && open /Applications/SnapTranslator.app"
