#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Blackbox"
PRODUCT_NAME="OpenPilotLogbook"
BUNDLE_ID="local.codex.Blackbox"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Sources/OpenPilotLogbook/Assets/AppIcon.icns"

cd "$ROOT_DIR"
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
find "$(dirname "$BUILD_BINARY")" -maxdepth 1 -name "*.bundle" -type d -exec cp -R {} "$APP_RESOURCES/" \;
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

render_snapshot() {
  local section="$1"
  local output="$2"
  local width="${3:-1440}"
  local height="${4:-980}"
  OPENPILOT_SNAPSHOT_SECTION="$section" OPENPILOT_SNAPSHOT_PATH="$output" OPENPILOT_SNAPSHOT_WIDTH="$width" OPENPILOT_SNAPSHOT_HEIGHT="$height" "$APP_BINARY"
  if [[ ! -s "$output" ]]; then
    echo "snapshot check failed: $output was not created" >&2
    exit 1
  fi
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
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PRODUCT_NAME" >/dev/null
    ;;
  --check|check)
    swift run OpenPilotLogbookCoreSmokeTests
    SNAPSHOT_DIR="$ROOT_DIR/outputs/check"
    mkdir -p "$SNAPSHOT_DIR"
    render_snapshot "dashboard" "$SNAPSHOT_DIR/dashboard.png"
    render_snapshot "flights" "$SNAPSHOT_DIR/flights.png"
    render_snapshot "analysis" "$SNAPSHOT_DIR/analysis.png"
    render_snapshot "map" "$SNAPSHOT_DIR/map.png"
    render_snapshot "comparison" "$SNAPSHOT_DIR/comparison.png"
    render_snapshot "imports" "$SNAPSHOT_DIR/imports.png"
    render_snapshot "dashboard" "$SNAPSHOT_DIR/dashboard-compact.png" 1180 820
    render_snapshot "flights" "$SNAPSHOT_DIR/flights-compact.png" 1180 820
    render_snapshot "analysis" "$SNAPSHOT_DIR/analysis-compact.png" 1180 820
    render_snapshot "map" "$SNAPSHOT_DIR/map-compact.png" 1180 820
    render_snapshot "comparison" "$SNAPSHOT_DIR/comparison-compact.png" 1180 820
    render_snapshot "imports" "$SNAPSHOT_DIR/imports-compact.png" 1180 820
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--check]" >&2
    exit 2
    ;;
esac
