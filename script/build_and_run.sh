#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Blackbox"
PRODUCT_NAME="OpenPilotLogbook"
BUNDLE_ID="uk.co.blackbox.logbook"
MARKETING_VERSION="1.0.0"
BUILD_NUMBER="1"
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
SAFE_DATA_ROOT="${BLACKBOX_DATA_ROOT:-${TMPDIR:-/tmp}/Blackbox-XCUITest-Development-$$}"
SWIFT_SCRATCH_PATH="${BLACKBOX_SWIFT_SCRATCH_PATH:-${TMPDIR:-/tmp}/Blackbox-SwiftPM-Scratch-$$}"
TESTING_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
TESTING_LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
FALLBACK_GIT_DIR="${BLACKBOX_FALLBACK_GIT_DIR:-}"

if [[ -n "$FALLBACK_GIT_DIR" && -x "$FALLBACK_GIT_DIR/git" ]]; then
  export PATH="$FALLBACK_GIT_DIR:$PATH"
fi

validate_fresh_temporary_scratch_path() {
  local scratch_parent
  local canonical_scratch_path
  local canonical_temp_root

  [[ "$SWIFT_SCRATCH_PATH" = /* ]] || {
    echo "BLACKBOX_SWIFT_SCRATCH_PATH must be an absolute path." >&2
    exit 2
  }
  [[ ! -e "$SWIFT_SCRATCH_PATH" ]] || {
    echo "BLACKBOX_SWIFT_SCRATCH_PATH must be a fresh path that does not yet exist." >&2
    exit 2
  }
  scratch_parent="$(dirname "$SWIFT_SCRATCH_PATH")"
  [[ -d "$scratch_parent" ]] || {
    echo "BLACKBOX_SWIFT_SCRATCH_PATH parent does not exist: $scratch_parent" >&2
    exit 2
  }
  canonical_scratch_path="$(cd "$scratch_parent" && pwd -P)/$(basename "$SWIFT_SCRATCH_PATH")"
  canonical_temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  case "$canonical_scratch_path" in
    "$canonical_temp_root"/*) ;;
    *)
      echo "BLACKBOX_SWIFT_SCRATCH_PATH must be inside the system temporary directory." >&2
      exit 2
      ;;
  esac
}

validate_fresh_temporary_scratch_path
cd "$ROOT_DIR"

swift build --scratch-path "$SWIFT_SCRATCH_PATH"
BUILD_BINARY="$(swift build --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)/$PRODUCT_NAME"

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
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
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
  require_fresh_temporary_data_root
  env BLACKBOX_DATA_ROOT="$SAFE_DATA_ROOT" \
    BLACKBOX_SYNTHETIC_FIXTURE=deterministic \
    "$APP_BINARY" --ui-testing >/dev/null 2>&1 &
}

require_fresh_temporary_data_root() {
  local data_parent
  local canonical_data_root
  local canonical_temp_root

  [[ "$SAFE_DATA_ROOT" = /* ]] || {
    echo "BLACKBOX_DATA_ROOT must be an absolute path." >&2
    exit 2
  }
  [[ ! -e "$SAFE_DATA_ROOT" ]] || {
    echo "BLACKBOX_DATA_ROOT must be a fresh path that does not yet exist." >&2
    exit 2
  }
  data_parent="$(dirname "$SAFE_DATA_ROOT")"
  [[ -d "$data_parent" ]] || {
    echo "BLACKBOX_DATA_ROOT parent does not exist: $data_parent" >&2
    exit 2
  }
  canonical_data_root="$(cd "$data_parent" && pwd -P)/$(basename "$SAFE_DATA_ROOT")"
  canonical_temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  case "$canonical_data_root" in
    "$canonical_temp_root"/*) ;;
    *)
      echo "BLACKBOX_DATA_ROOT must be inside the system temporary directory." >&2
      exit 2
      ;;
  esac
}

render_snapshot() {
  local section="$1"
  local output="$2"
  local width="${3:-1440}"
  local height="${4:-980}"
  local appearance="${5:-dark}"
  OPENPILOT_SNAPSHOT_SECTION="$section" OPENPILOT_SNAPSHOT_PATH="$output" OPENPILOT_SNAPSHOT_WIDTH="$width" OPENPILOT_SNAPSHOT_HEIGHT="$height" OPENPILOT_SNAPSHOT_APPEARANCE="$appearance" "$APP_BINARY"
  if [[ ! -s "$output" ]]; then
    echo "snapshot check failed: $output was not created" >&2
    exit 1
  fi
  local byte_count
  local pixel_width
  local pixel_height
  byte_count="$(/usr/bin/stat -f '%z' "$output")"
  pixel_width="$(/usr/bin/sips -g pixelWidth "$output" 2>/dev/null | /usr/bin/awk '/pixelWidth:/{print $2}')"
  pixel_height="$(/usr/bin/sips -g pixelHeight "$output" 2>/dev/null | /usr/bin/awk '/pixelHeight:/{print $2}')"
  if [[ "$byte_count" -lt 10000 || -z "$pixel_width" || -z "$pixel_height" || "$pixel_width" -lt "$width" || "$pixel_height" -lt "$height" ]]; then
    echo "snapshot content check failed: $output is too small or has unexpected dimensions" >&2
    exit 1
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    require_fresh_temporary_data_root
    env BLACKBOX_DATA_ROOT="$SAFE_DATA_ROOT" BLACKBOX_SYNTHETIC_FIXTURE=deterministic lldb -- "$APP_BINARY" --ui-testing
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
    swift build --build-tests --scratch-path "$SWIFT_SCRATCH_PATH" \
      -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS" \
      -Xlinker -F"$TESTING_FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$TESTING_FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$TESTING_LIBS"
    testing_interop="$TESTING_LIBS/lib_TestingInterop.dylib"
    test_binary_dir="$(swift build --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)"
    if [[ -f "$testing_interop" ]]; then
      cp "$testing_interop" "$test_binary_dir/lib_TestingInterop.dylib"
    fi
    swift test --scratch-path "$SWIFT_SCRATCH_PATH" --skip-build \
      -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS" \
      -Xlinker -F"$TESTING_FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$TESTING_FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$TESTING_LIBS"
    swift run --scratch-path "$SWIFT_SCRATCH_PATH" OpenPilotLogbookCoreUnitTests
    swift run --scratch-path "$SWIFT_SCRATCH_PATH" OpenPilotLogbookCoreSmokeTests
    SNAPSHOT_DIR="$ROOT_DIR/outputs/check"
    mkdir -p "$SNAPSHOT_DIR"
    for appearance in light dark contrast; do
      for viewport in regular compact; do
        if [[ "$viewport" == "regular" ]]; then
          snapshot_width=1440
          snapshot_height=980
        else
          snapshot_width=900
          snapshot_height=760
        fi
        for section in dashboard flights pages aircraft people analysis map comparison imports compliance reports history; do
          render_snapshot "$section" "$SNAPSHOT_DIR/${section}-${appearance}-${viewport}.png" "$snapshot_width" "$snapshot_height" "$appearance"
        done
      done
    done
    snapshot_count="$(find "$SNAPSHOT_DIR" -type f -name '*.png' | wc -l | tr -d ' ')"
    unique_snapshot_count="$(find "$SNAPSHOT_DIR" -type f -name '*.png' -exec shasum -a 256 {} + | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
    if [[ "$snapshot_count" -ne 72 || "$unique_snapshot_count" -lt 24 ]]; then
      echo "snapshot matrix check failed: expected 72 images and at least 24 distinct renders; found $snapshot_count / $unique_snapshot_count" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--check]" >&2
    exit 2
    ;;
esac
