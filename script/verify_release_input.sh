#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
METADATA="$ROOT_DIR/Config/ReleaseMetadata.plist"
APP_PATH=""
REQUIRE_UNSIGNED=0

usage() {
    cat <<USAGE
Usage: $PROGRAM_NAME --app <path-to-Blackbox.app> [--require-unsigned]

Validates release metadata and requires every packaged Mach-O binary to contain
exactly the arm64 and x86_64 slices expected of a Universal 2 artifact.
When --require-unsigned is present, every Mach-O item must also have no embedded
code signature. This is intended for the CI-to-local signing handoff.
USAGE
}

fail() {
    echo "$PROGRAM_NAME: $*" >&2
    exit 2
}

plist_value() {
    local key="$1"
    local plist="$2"
    /usr/bin/plutil -extract "$key" raw -o - "$plist"
}

[[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && { usage; exit 0; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || fail "--app requires a value."
            APP_PATH="$2"
            shift 2
            ;;
        --require-unsigned)
            REQUIRE_UNSIGNED=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "App bundle is missing, not a directory, or a symbolic link: $APP_PATH"
[[ -f "$METADATA" ]] || fail "Release metadata is missing: $METADATA"
/usr/bin/plutil -lint "$METADATA" >/dev/null

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] || fail "App Info.plist is missing, not regular, or a symbolic link."
/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

EXPECTED_PRODUCT="$(plist_value ProductName "$METADATA")"
EXPECTED_BUNDLE_ID="$(plist_value BundleIdentifier "$METADATA")"
EXPECTED_VERSION="$(plist_value Version "$METADATA")"
EXPECTED_BUILD="$(plist_value Build "$METADATA")"
EXPECTED_MIN_SYSTEM="$(plist_value MinimumSystemVersion "$METADATA")"
[[ "$(plist_value Architectures "$METADATA")" == "2" ]] || fail "Release metadata must declare exactly two architectures."
[[ "$(plist_value Architectures.0 "$METADATA")" == "arm64" ]] || fail "First release architecture must be arm64."
[[ "$(plist_value Architectures.1 "$METADATA")" == "x86_64" ]] || fail "Second release architecture must be x86_64."

[[ "$(basename "$APP_PATH")" == "$EXPECTED_PRODUCT.app" ]] || fail "Expected bundle name $EXPECTED_PRODUCT.app."
[[ "$(plist_value CFBundleIdentifier "$INFO_PLIST")" == "$EXPECTED_BUNDLE_ID" ]] || fail "CFBundleIdentifier must be $EXPECTED_BUNDLE_ID."
[[ "$(plist_value CFBundleShortVersionString "$INFO_PLIST")" == "$EXPECTED_VERSION" ]] || fail "CFBundleShortVersionString must be $EXPECTED_VERSION."
[[ "$(plist_value CFBundleVersion "$INFO_PLIST")" == "$EXPECTED_BUILD" ]] || fail "CFBundleVersion must be $EXPECTED_BUILD."
[[ "$(plist_value LSMinimumSystemVersion "$INFO_PLIST")" == "$EXPECTED_MIN_SYSTEM" ]] || fail "LSMinimumSystemVersion must be $EXPECTED_MIN_SYSTEM."
[[ "$(plist_value CFBundlePackageType "$INFO_PLIST")" == "APPL" ]] || fail "CFBundlePackageType must be APPL."

ICON_FILE="$(plist_value CFBundleIconFile "$INFO_PLIST")"
[[ -n "$ICON_FILE" && "$ICON_FILE" != */* ]] || fail "CFBundleIconFile must name one bundled icon resource."
[[ "$ICON_FILE" == *.icns ]] || ICON_FILE="$ICON_FILE.icns"
ICON_PATH="$APP_PATH/Contents/Resources/$ICON_FILE"
[[ -f "$ICON_PATH" && ! -L "$ICON_PATH" ]] || fail "Declared application icon is missing, not regular, or a symbolic link: $ICON_FILE"
case "$(/usr/bin/file -b "$ICON_PATH")" in
    *"Mac OS X icon"*) ;;
    *) fail "Declared application icon is not an ICNS file: $ICON_FILE" ;;
esac

EXECUTABLE_NAME="$(plist_value CFBundleExecutable "$INFO_PLIST")"
[[ -n "$EXECUTABLE_NAME" && "$EXECUTABLE_NAME" != */* ]] || fail "CFBundleExecutable is invalid."
MAIN_EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
[[ -f "$MAIN_EXECUTABLE" && -x "$MAIN_EXECUTABLE" && ! -L "$MAIN_EXECUTABLE" ]] || fail "Main executable is missing, not executable, or a symbolic link."

native_count=0
while IFS= read -r -d '' candidate; do
    description="$(/usr/bin/file -b "$candidate")"
    case "$description" in
        *Mach-O*)
            native_count=$((native_count + 1))
            if [[ $REQUIRE_UNSIGNED -eq 1 ]] && /usr/bin/codesign --display "$candidate" >/dev/null 2>&1; then
                fail "Unsigned release input contains signed native code: ${candidate#"$APP_PATH"/}"
            fi
            architectures="$(/usr/bin/lipo -archs "$candidate")"
            architecture_count=0
            has_arm64=0
            has_x86_64=0
            for architecture in $architectures; do
                architecture_count=$((architecture_count + 1))
                [[ "$architecture" == "arm64" ]] && has_arm64=1
                [[ "$architecture" == "x86_64" ]] && has_x86_64=1
            done
            [[ $architecture_count -eq 2 && $has_arm64 -eq 1 && $has_x86_64 -eq 1 ]] \
                || fail "Native code is not exactly Universal 2 (arm64 + x86_64): ${candidate#"$APP_PATH"/} [$architectures]"
            ;;
    esac
done < <(/usr/bin/find "$APP_PATH" -type f -print0)

[[ $native_count -gt 0 ]] || fail "The app contains no Mach-O executable code."
main_description="$(/usr/bin/file -b "$MAIN_EXECUTABLE")"
case "$main_description" in
    *Mach-O*) ;;
    *) fail "The declared main executable is not Mach-O code." ;;
esac

# Unsigned CI inputs have no entitlement blob. Once signed, direct-distribution
# builds must remain unsandboxed and must not carry development or sandbox-only
# file-access entitlements.
if /usr/bin/codesign --display "$APP_PATH" >/dev/null 2>&1; then
    entitlements="$(/usr/bin/codesign --display --entitlements :- "$APP_PATH" 2>/dev/null || true)"
    if printf '%s' "$entitlements" | /usr/bin/grep -Eq \
        'com\.apple\.security\.get-task-allow|com\.apple\.security\.app-sandbox|com\.apple\.security\.files\.'; then
        fail "Signed app contains development or sandbox-only entitlements."
    fi
fi

echo "Release input passed: $EXPECTED_BUNDLE_ID $EXPECTED_VERSION ($EXPECTED_BUILD), Universal 2, $native_count native code item(s)."
