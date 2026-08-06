#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Linger"
BUNDLE_ID="com.linger.app"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# 统一用完整 Xcode 工具链（xcode-select 可能仍指向 CommandLineTools）
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --disable-sandbox
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>LingerIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCalendarsUsageDescription</key>
  <string>将计时记录写入系统日历</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>将计时记录写入系统日历</string>
</dict>
</plist>
PLIST

# 打包应用图标：优先用铺满版（无透明留白边），回退原版 → Resources/LingerIcon.png + LingerIcon.icns
APP_RESOURCES="$APP_CONTENTS/Resources"
ICON_SRC="$ROOT_DIR/Support/LingerIcon-Fullbleed.png"
[ -f "$ICON_SRC" ] || ICON_SRC="$ROOT_DIR/Support/LingerIcon.png"
if [ -f "$ICON_SRC" ]; then
  mkdir -p "$APP_RESOURCES"
  cp "$ICON_SRC" "$APP_RESOURCES/LingerIcon.png"
  ICONSET="$ROOT_DIR/dist/Linger.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    sips -z $d $d "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/LingerIcon.icns" 2>/dev/null || true
  rm -rf "$ICONSET"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR subsystem == \"com.linger.timer\""
    ;;
  --verify|verify)
    open_app
    sleep 1.5
    pgrep -x "$APP_NAME" >/dev/null && echo "OK: $APP_NAME is running (pid $(pgrep -x $APP_NAME))"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
