#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARCHIVE_PATH="${1:-}"
TEAM_ID="BSWQ8N2UB5"

fail() {
  echo "$PROGRAM_NAME: $*" >&2
  exit 2
}

[[ -n "$ARCHIVE_PATH" ]] || fail "usage: $PROGRAM_NAME <fresh-output-path.xcarchive>"
[[ "$ARCHIVE_PATH" = /* ]] || fail "Archive path must be absolute."
[[ ! -e "$ARCHIVE_PATH" ]] || fail "Archive path already exists: $ARCHIVE_PATH"
[[ -d "$(dirname "$ARCHIVE_PATH")" ]] || fail "Archive parent directory does not exist."

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"Apple Distribution:"*"($TEAM_ID)"* ]] \
  || fail "No valid Apple Distribution identity for team $TEAM_ID is available in the Keychain."

cd "$ROOT_DIR"
/usr/bin/xcodebuild \
  -project Blackbox.xcodeproj \
  -scheme Blackbox-AppStore \
  -configuration AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

"$ROOT_DIR/script/verify_app_store_archive.sh" "$ARCHIVE_PATH"
echo "Archive ready. Upload from Xcode Organizer, or export with Config/AppStoreExportOptions.plist after App Store Connect has an app record."
