#!/bin/bash
#
# build_ipa.sh —— 在 macOS 上一条命令产出 TrollStore 可安装的未签名 IPA
#
#   用法:  ./build_ipa.sh
#   依赖:  Xcode (含 iPhoneOS SDK)、可选 ldid (brew install ldid)
#
set -euo pipefail

PROJECT="TrollBattery.xcodeproj"
SCHEME="TrollBattery"
BIN_NAME="TrollBattery"
ENTITLEMENTS="TrollBattery/TrollBattery.entitlements"
WIDGET_ENTITLEMENTS="TrollBatteryWidget/TrollBatteryWidget.entitlements"
DERIVED="build/DerivedData"
IPA_NAME="TrollBattery.ipa"

echo "==> 1/4 编译（不签名）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "==> 2/4 定位 .app"
APP=$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP" ]; then
  echo "错误：未找到编译产物 .app" >&2
  exit 1
fi
echo "    $APP"

echo "==> 3/4 注入 entitlements"
if command -v ldid >/dev/null 2>&1; then
  ldid -S"$ENTITLEMENTS" "$APP/$BIN_NAME"
  echo "    已注入："
  ldid -e "$APP/$BIN_NAME" | head -n 20 || true
else
  echo "    警告：未找到 ldid，跳过注入（brew install ldid）"
  echo "    TrollStore 安装时仍会自动赋予 platform-application 权限。"
fi

echo "==> 4/4 打包 IPA"
rm -rf Payload "$IPA_NAME"
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$IPA_NAME" Payload
rm -rf Payload

echo ""
echo "完成 ✔  $IPA_NAME  ($(du -h "$IPA_NAME" | cut -f1))"
echo "把 IPA 传到 iPhone，用 TrollStore 打开并安装。"
