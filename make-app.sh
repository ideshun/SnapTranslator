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

echo "==> ad hoc 签名"
codesign --force --sign - "$APP"

echo "==> 校验"
codesign --verify --verbose "$APP"

SIZE=$(du -sh "$APP" | cut -f1)
echo "完成：${APP}（${SIZE}）"
echo "安装：cp -R ${APP} /Applications/ && open /Applications/SnapTranslator.app"
