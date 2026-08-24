#!/usr/bin/env bash
# make_dmg.sh — 制作 Linger DMG 安装包（分发用）
# 用法：先 ./script/build_and_run.sh --release 打好 app，再运行本脚本。
# 产物：项目根目录 Linger-{版本}.dmg —— 用户下载后打开，把 Linger.app 拖入 Applications 即装。
#
# ⚠️ 必须在用户自己的终端运行：hdiutil 需要访问 /dev/disk* 裸设备，
#    AI 终端沙箱会拦截（TRAE/IDE 内置终端均不行）。
set -euo pipefail

APP_NAME="Linger"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 版本号唯一真源：Sources/Linger/AppVersion.swift（与 build_and_run.sh 同源）
APP_VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$ROOT_DIR/Sources/Linger/AppVersion.swift")"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
STAGING="$ROOT_DIR/dist/dmg-staging"
DMG="$ROOT_DIR/$APP_NAME-$APP_VERSION.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "❌ 未找到 $APP_BUNDLE，先运行 ./script/build_and_run.sh --release" >&2
  exit 1
fi

# 组装安装视图：app + Applications 文件夹替身（拖拽安装的两侧）
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -sfn /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG"

rm -rf "$STAGING"
echo "✅ $DMG"
