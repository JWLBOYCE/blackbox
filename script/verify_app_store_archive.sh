#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
EXPECTED_TEAM_ID="BSWQ8N2UB5"
EXPECTED_BUNDLE_ID="uk.co.blackbox.logbook"
ARCHIVE_PATH="${1:-}"

fail() {
  echo "$PROGRAM_NAME: $*" >&2
  exit 2
}

[[ -n "$ARCHIVE_PATH" ]] || fail "usage: $PROGRAM_NAME <path-to-Blackbox.xcarchive>"
[[ -d "$ARCHIVE_PATH" && ! -L "$ARCHIVE_PATH" ]] || fail "Archive is missing, not a directory, or a symbolic link: $ARCHIVE_PATH"

APP_PATH="$ARCHIVE_PATH/Products/Applications/Blackbox.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Blackbox"
ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/blackbox-app-store-entitlements.XXXXXX")"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT

[[ -f "$INFO_PLIST" ]] || fail "Archived Info.plist is missing."
[[ -x "$EXECUTABLE" ]] || fail "Archived executable is missing or not executable."
/usr/bin/codesign --verify --strict --verbose=2 "$APP_PATH"
/usr/bin/codesign -d --entitlements "$ENTITLEMENTS_FILE" --xml "$APP_PATH" 2>/dev/null
/usr/bin/plutil -lint "$INFO_PLIST" "$ENTITLEMENTS_FILE" >/dev/null

[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")" == "$EXPECTED_BUNDLE_ID" ]] \
  || fail "Unexpected bundle identifier."
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")" == "1.0.0" ]] \
  || fail "Unexpected marketing version."
[[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")" == "1" ]] \
  || fail "Unexpected build number."

for entitlement in \
  com.apple.security.app-sandbox \
  com.apple.security.files.bookmarks.app-scope \
  com.apple.security.files.user-selected.read-write; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$ENTITLEMENTS_FILE")" == true ]] \
    || fail "Required entitlement is missing: $entitlement"
done
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_FILE" >/dev/null 2>&1; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_FILE")" == false ]] \
    || fail "Distribution archive must not allow debugger attachment."
fi

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_PATH" 2>&1)"
[[ "$SIGNING_DETAILS" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]] \
  || fail "Archived app is not signed by the approved Apple team."

ARCHITECTURES="$(/usr/bin/lipo -archs "$EXECUTABLE")"
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]] \
  || fail "Archived app must contain arm64 and x86_64 slices."

echo "Verified sandboxed Blackbox App Store archive for team $EXPECTED_TEAM_ID."
