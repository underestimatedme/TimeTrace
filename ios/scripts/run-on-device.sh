#!/bin/bash
set -euo pipefail

# 在真机上安装并运行刻迹。需要先装好开发者证书，并传入 Team ID：
#   DEVELOPMENT_TEAM=ABCDE12345 bash ios/scripts/run-on-device.sh
# 查 Team ID：Xcode → Settings → Accounts → 选中账号 → Manage Certificates，
# 或 https://developer.apple.com/account 右上角。
#
# 工程默认关闭签名（为了跑模拟器测试），这里用命令行参数临时打开，不改 project.yml。

team="${DEVELOPMENT_TEAM:-}"
if [ -z "$team" ]; then
  echo "缺少 DEVELOPMENT_TEAM。用法：DEVELOPMENT_TEAM=<你的 Team ID> bash ios/scripts/run-on-device.sh" >&2
  exit 1
fi

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$dir"
xcodegen generate

echo "=== 已连接的设备 ==="
xcrun devicectl list devices 2>/dev/null | sed -n '1,12p' || true

out="${BUILD_DIR:-$dir/qa-artifacts/device-build}"
xcodebuild -project KeJi.xcodeproj -scheme KeJi \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$out" \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  -allowProvisioningUpdates \
  build

app="$out/Build/Products/Debug-iphoneos/KeJi.app"
echo "构建产物：$app"
echo
echo "安装到设备（把 <device-id> 换成上面列出的设备）："
echo "  xcrun devicectl device install app --device <device-id> \"$app\""
echo "启动："
echo "  xcrun devicectl device process launch --device <device-id> com.atlaspaces.timetrace"
