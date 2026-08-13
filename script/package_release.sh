#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
METADATA="$ROOT_DIR/Config/ReleaseMetadata.plist"
ENTITLEMENTS="$ROOT_DIR/Config/Blackbox.entitlements"
VERIFY_INPUT="$ROOT_DIR/script/verify_release_input.sh"
PRIVACY_SCAN="$ROOT_DIR/script/release_privacy_scan.sh"
LIVE_HASHES="$ROOT_DIR/script/release_live_hashes.sh"

usage() {
    cat <<USAGE
Usage: $PROGRAM_NAME

Required environment:
  BLACKBOX_CI_ARCHIVE_PATH            Downloaded CI .xcarchive.zip
  BLACKBOX_CI_MANIFEST_PATH           Downloaded CI XML manifest plist
  BLACKBOX_DEVELOPER_ID_APPLICATION  Developer ID Application name or SHA-1 identity
  BLACKBOX_NOTARY_PROFILE            notarytool profile stored in the login Keychain
  BLACKBOX_LIVE_DATA_ROOT            Existing live Application Support/Blackbox root
  BLACKBOX_LIVE_HASH_MANIFEST        Baseline from release_live_hashes.sh capture

Optional environment:
  BLACKBOX_RELEASE_OUTPUT_DIR        Defaults to dist/release/1.0.0-build1

The verified CI archive and live data are never modified. Its app is extracted
to a temporary workspace, signed inside-out, notarized, stapled, reverified,
and placed in the final ZIP.
The stapled artifact is smoke-launched only from a quarantined temporary copy,
with deterministic fixtures under an isolated temporary data root.
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

absolute_existing_path() {
    local path="$1"
    local parent
    local leaf
    parent="$(dirname "$path")"
    leaf="$(basename "$path")"
    [[ -d "$parent" ]] || fail "Parent directory does not exist: $parent"
    parent="$(cd "$parent" && pwd -P)"
    printf '%s/%s\n' "$parent" "$leaf"
}

absolute_existing_directory() {
    local directory="$1"
    [[ -d "$directory" ]] || fail "Directory does not exist: $directory"
    (cd "$directory" && pwd -P)
}

verify_ci_manifest() {
    local manifest="$CI_MANIFEST"
    local archive_sha256
    local archive_bytes
    local event_name
    local pull_request_number
    local workflow_ref

    /usr/bin/plutil -lint "$manifest" >/dev/null
    [[ "$(plist_value product "$manifest")" == "$PRODUCT" ]] || fail "CI manifest product does not match release metadata."
    [[ "$(plist_value bundleIdentifier "$manifest")" == "$BUNDLE_ID" ]] || fail "CI manifest bundle identifier does not match release metadata."
    [[ "$(plist_value version "$manifest")" == "$VERSION" ]] || fail "CI manifest version does not match release metadata."
    [[ "$(plist_value build "$manifest")" == "$BUILD" ]] || fail "CI manifest build does not match release metadata."
    [[ "$(plist_value minimumSystemVersion "$manifest")" == "$MIN_SYSTEM" ]] || fail "CI manifest minimum system version does not match release metadata."
    [[ "$(plist_value sourceCommit "$manifest")" == "$SOURCE_COMMIT" ]] || fail "CI archive was not built from the checked-out commit."
    [[ "$(plist_value repository "$manifest")" == "JWLBOYCE/blackbox" ]] || fail "CI manifest repository is unexpected."
    [[ "$(plist_value workflow "$manifest")" == "Swift CI" ]] || fail "CI manifest workflow is unexpected."
    event_name="$(plist_value eventName "$manifest")"
    workflow_ref="$(plist_value workflowRef "$manifest")"
    case "$event_name" in
        push)
            [[ "$workflow_ref" == "JWLBOYCE/blackbox/.github/workflows/ci.yml@refs/heads/main" ]] || fail "Push release input is not from the workflow on main."
            [[ "$(plist_value sourceRef "$manifest")" == "refs/heads/main" ]] || fail "Push release input must come from the main branch."
            [[ -z "$(plist_value headRepository "$manifest")" && -z "$(plist_value headRef "$manifest")" && -z "$(plist_value headSHA "$manifest")" && -z "$(plist_value baseRef "$manifest")" && -z "$(plist_value pullRequestNumber "$manifest")" ]] || fail "Push release input unexpectedly contains pull-request provenance."
            ;;
        pull_request)
            pull_request_number="$(plist_value pullRequestNumber "$manifest")"
            [[ "$pull_request_number" =~ ^[1-9][0-9]*$ ]] || fail "CI manifest pull-request number is invalid."
            [[ "$(plist_value sourceRef "$manifest")" == "refs/pull/$pull_request_number/merge" ]] || fail "CI manifest pull-request trigger ref is inconsistent."
            case "$workflow_ref" in
                "JWLBOYCE/blackbox/.github/workflows/ci.yml@refs/pull/$pull_request_number/merge"|"JWLBOYCE/blackbox/.github/workflows/ci.yml@refs/heads/main") ;;
                *) fail "Pull-request release input has an unexpected workflow reference." ;;
            esac
            [[ "$(plist_value headRepository "$manifest")" == "JWLBOYCE/blackbox" ]] || fail "CI release-input PR must originate in the Blackbox repository."
            [[ "$(plist_value headRef "$manifest")" == "codex/blackbox-release-completion" ]] || fail "CI release-input PR has an unexpected head branch."
            [[ "$(plist_value headSHA "$manifest")" == "$SOURCE_COMMIT" ]] || fail "CI release-input PR head SHA does not match the checked-out commit."
            [[ "$(plist_value baseRef "$manifest")" == "main" ]] || fail "CI release-input PR must target main."
            ;;
        *)
            fail "CI release input has an unsupported workflow event."
            ;;
    esac
    [[ "$(plist_value runID "$manifest")" =~ ^[0-9]+$ ]] || fail "CI manifest run ID is invalid."
    [[ "$(plist_value runAttempt "$manifest")" =~ ^[1-9][0-9]*$ ]] || fail "CI manifest run attempt is invalid."
    [[ "$(plist_value workflowRunURL "$manifest")" == "https://github.com/JWLBOYCE/blackbox/actions/runs/$(plist_value runID "$manifest")" ]] || fail "CI manifest workflow URL does not match its repository and run ID."
    [[ "$(plist_value xcodeVersion "$manifest")" == "Xcode 26.6" ]] || fail "CI archive was not built with Xcode 26.6."
    [[ "$(plist_value xcodeBuild "$manifest")" == "17F113" ]] || fail "CI archive was not built with Xcode build 17F113."
    [[ "$(plist_value signing "$manifest")" == "unsigned-ci-release-input" ]] || fail "CI manifest does not describe an unsigned release input."
    [[ "$(plist_value archiveDirectory "$manifest")" == "Blackbox-Unsigned.xcarchive" ]] || fail "CI manifest archive directory is unexpected."
    [[ "$(plist_value artifactFilename "$manifest")" == "$(basename "$CI_ARCHIVE")" ]] || fail "CI archive filename does not match its manifest."
    [[ "$(plist_value architectures "$manifest")" == "2" ]] || fail "CI manifest must declare exactly two architectures."
    [[ "$(plist_value architectures.0 "$manifest")" == "arm64" ]] || fail "CI manifest first architecture must be arm64."
    [[ "$(plist_value architectures.1 "$manifest")" == "x86_64" ]] || fail "CI manifest second architecture must be x86_64."
    [[ "$(plist_value swiftPMTests "$manifest")" == "passed" ]] || fail "CI SwiftPM tests did not pass."
    [[ "$(plist_value executableUnitTests "$manifest")" == "passed" ]] || fail "CI executable unit tests did not pass."
    [[ "$(plist_value releasePerformanceGates "$manifest")" == "passed" ]] || fail "CI release performance gates did not pass."
    [[ "$(plist_value smokeTests "$manifest")" == "passed" ]] || fail "CI smoke tests did not pass."
    [[ "$(plist_value snapshotMatrix "$manifest")" == "passed-72" ]] || fail "CI snapshot matrix did not pass all 72 captures."
    [[ "$(plist_value uiTests "$manifest")" == "passed-13-workflows-x-4-configurations" ]] \
        || fail "CI did not pass all 13 workflows in Light/Dark at regular/compact widths."
    [[ "$(plist_value accessibilityUITests "$manifest")" == "passed-focused-workflow-x-3-configurations" ]] \
        || fail "CI did not pass the focused Increase Contrast, large-text, and Reduce Motion checks."
    [[ "$(plist_value privacyGate "$manifest")" == "passed" ]] || fail "CI privacy gate did not pass."
    [[ "$(plist_value dataPolicy "$manifest")" == "synthetic-temporary-roots-only" ]] || fail "CI manifest has an unexpected data policy."

    archive_sha256="$(/usr/bin/shasum -a 256 "$CI_ARCHIVE" | /usr/bin/awk '{print $1}')"
    archive_bytes="$(/usr/bin/stat -f '%z' "$CI_ARCHIVE")"
    [[ "$archive_sha256" == "$(plist_value artifactSHA256 "$manifest")" ]] || fail "CI archive SHA-256 does not match its manifest."
    [[ "$archive_bytes" == "$(plist_value artifactBytes "$manifest")" ]] || fail "CI archive size does not match its manifest."
}

sign_code() {
    local code_path="$1"
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$IDENTITY" "$code_path"
}

sign_inside_out() {
    local app="$1"
    local info_plist="$app/Contents/Info.plist"
    local executable_name
    local main_executable
    local candidate
    local description

    executable_name="$(plist_value CFBundleExecutable "$info_plist")"
    main_executable="$app/Contents/MacOS/$executable_name"

    while IFS= read -r -d '' candidate; do
        [[ "$candidate" == "$main_executable" ]] && continue
        description="$(/usr/bin/file -b "$candidate")"
        case "$description" in
            *Mach-O*) sign_code "$candidate" ;;
        esac
    done < <(/usr/bin/find "$app" -type f -print0)

    while IFS= read -r -d '' candidate; do
        [[ "$candidate" == "$app" ]] && continue
        sign_code "$candidate"
    done < <(/usr/bin/find "$app" -depth -type d \( \
        -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o \
        -name '*.appex' -o -name '*.plugin' \) -print0)

    /usr/bin/codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$app"
}

stop_smoke_process() {
    local executable_path="$1"
    local data_root_path="$2"
    local process_id
    local command_line

    while read -r process_id command_line; do
        [[ "$process_id" =~ ^[0-9]+$ ]] || continue
        case "$command_line" in
            "$executable_path"|"$executable_path "*|*"BLACKBOX_DATA_ROOT=$data_root_path"*)
                /bin/kill -TERM "$process_id" 2>/dev/null || true
                ;;
        esac
    done < <(/bin/ps -Aeww -o pid=,command=)
}

run_quarantined_synthetic_smoke() {
    local source_app="$1"
    local smoke_folder="$WORK_DIR/quarantined-synthetic-smoke"
    local smoke_app="$smoke_folder/$PRODUCT.app"
    local smoke_data_root="$WORK_DIR/Blackbox-XCUITest-ReleaseSmoke"
    local smoke_snapshot="$WORK_DIR/quarantined-synthetic-smoke.png"
    local smoke_stdout="$WORK_DIR/quarantined-synthetic-smoke.stdout.log"
    local smoke_stderr="$WORK_DIR/quarantined-synthetic-smoke.stderr.log"
    local smoke_preferences_root="$WORK_DIR/quarantined-synthetic-preferences"
    local smoke_info="$smoke_app/Contents/Info.plist"
    local smoke_executable_name
    local quarantine_timestamp
    local quarantine_value
    local launcher_pid
    local deadline
    local integrity
    local flight_count
    local state_counts
    local temp_root
    local canonical_work_dir

    temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
    canonical_work_dir="$(cd "$WORK_DIR" && pwd -P)"
    case "$canonical_work_dir" in
        "$temp_root"/*) ;;
        *) fail "Synthetic smoke workspace is not inside the system temporary directory." ;;
    esac
    [[ ! -e "$smoke_folder" ]] || fail "Synthetic smoke folder unexpectedly exists."
    [[ ! -e "$smoke_data_root" ]] || fail "Synthetic smoke data root must not exist before launch."

    /bin/mkdir -p "$smoke_folder"
    /bin/mkdir -p "$smoke_preferences_root"
    /usr/bin/ditto "$source_app" "$smoke_app"
    smoke_executable_name="$(plist_value CFBundleExecutable "$smoke_info")"
    SMOKE_EXECUTABLE_PATH="$smoke_app/Contents/MacOS/$smoke_executable_name"
    SMOKE_DATA_ROOT_PATH="$smoke_data_root"
    [[ -x "$SMOKE_EXECUTABLE_PATH" ]] || fail "Synthetic smoke executable is missing."

    printf -v quarantine_timestamp '%x' "$(/bin/date +%s)"
    quarantine_value="0083;$quarantine_timestamp;BlackboxReleaseSmoke;"
    /usr/bin/xattr -w com.apple.quarantine "$quarantine_value" "$smoke_app"
    [[ "$(/usr/bin/xattr -p com.apple.quarantine "$smoke_app")" == "$quarantine_value" ]] \
        || fail "Could not apply quarantine metadata to the synthetic smoke copy."

    /usr/bin/open -n -W -j \
        --stdout "$smoke_stdout" \
        --stderr "$smoke_stderr" \
        --env "BLACKBOX_DATA_ROOT=$smoke_data_root" \
        --env "BLACKBOX_SYNTHETIC_FIXTURE=deterministic" \
        --env "HOME=$smoke_preferences_root" \
        --env "CFFIXED_USER_HOME=$smoke_preferences_root" \
        --env "OPENPILOT_SNAPSHOT_PATH=$smoke_snapshot" \
        --env "OPENPILOT_SNAPSHOT_SECTION=dashboard" \
        --env "OPENPILOT_SNAPSHOT_WIDTH=900" \
        --env "OPENPILOT_SNAPSHOT_HEIGHT=760" \
        --env "OPENPILOT_SNAPSHOT_APPEARANCE=light" \
        "$smoke_app" --args --ui-testing &
    launcher_pid=$!
    deadline=$((SECONDS + 60))
    while /bin/kill -0 "$launcher_pid" 2>/dev/null; do
        if (( SECONDS >= deadline )); then
            /bin/kill -TERM "$launcher_pid" 2>/dev/null || true
            wait "$launcher_pid" 2>/dev/null || true
            stop_smoke_process "$SMOKE_EXECUTABLE_PATH" "$SMOKE_DATA_ROOT_PATH"
            fail "Quarantined synthetic smoke launch did not finish within 60 seconds."
        fi
        /bin/sleep 1
    done
    if ! wait "$launcher_pid"; then
        stop_smoke_process "$SMOKE_EXECUTABLE_PATH" "$SMOKE_DATA_ROOT_PATH"
        if [[ -s "$smoke_stderr" ]]; then /usr/bin/tail -n 40 "$smoke_stderr" >&2; fi
        fail "LaunchServices rejected or failed the quarantined synthetic smoke launch."
    fi

    [[ -s "$smoke_snapshot" ]] || fail "Synthetic smoke launch did not produce its expected snapshot."
    [[ -f "$smoke_data_root/.blackbox-synthetic-ui-test-root" ]] \
        || fail "Synthetic smoke launch did not create its protected test-root marker."
    [[ -f "$smoke_data_root/Blackbox.sqlite" ]] \
        || fail "Synthetic smoke launch did not create its isolated database."
    [[ -f "$smoke_data_root/Import Sources/LogTenCoreDataStore.sql" ]] \
        || fail "Synthetic smoke launch did not create its isolated LogTen fixture."
    integrity="$(/usr/bin/sqlite3 -readonly "$smoke_data_root/Blackbox.sqlite" 'PRAGMA integrity_check;')"
    [[ "$integrity" == "ok" ]] || fail "Synthetic smoke database failed SQLite integrity_check."
    flight_count="$(/usr/bin/sqlite3 -readonly "$smoke_data_root/Blackbox.sqlite" 'SELECT COUNT(*) FROM flights;')"
    [[ "$flight_count" == "5" ]] || fail "Synthetic smoke database contains an unexpected flight count: $flight_count"
    state_counts="$(/usr/bin/sqlite3 -readonly "$smoke_data_root/Blackbox.sqlite" \
        "SELECT group_concat(record_state || ':' || count, ',') FROM (SELECT record_state, COUNT(*) AS count FROM flights GROUP BY record_state ORDER BY record_state);")"
    [[ "$state_counts" == "draft:2,finalised:1,trashed:2" ]] \
        || fail "Synthetic smoke database contains unexpected record states: $state_counts"

    SMOKE_EXECUTABLE_PATH=""
    SMOKE_DATA_ROOT_PATH=""
    SYNTHETIC_SMOKE_STATUS="passed"
}

[[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && { usage; exit 0; }
[[ $# -eq 0 ]] || fail "This command accepts configuration through environment variables only."

CI_ARCHIVE="${BLACKBOX_CI_ARCHIVE_PATH:-}"
CI_MANIFEST="${BLACKBOX_CI_MANIFEST_PATH:-}"
IDENTITY="${BLACKBOX_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${BLACKBOX_NOTARY_PROFILE:-}"
LIVE_DATA_ROOT="${BLACKBOX_LIVE_DATA_ROOT:-}"
LIVE_HASH_MANIFEST="${BLACKBOX_LIVE_HASH_MANIFEST:-}"

[[ -n "$CI_ARCHIVE" ]] || fail "Set BLACKBOX_CI_ARCHIVE_PATH to the downloaded CI .xcarchive.zip."
[[ -n "$CI_MANIFEST" ]] || fail "Set BLACKBOX_CI_MANIFEST_PATH to the downloaded CI XML manifest plist."
[[ -n "$IDENTITY" ]] || fail "Set BLACKBOX_DEVELOPER_ID_APPLICATION to a Developer ID Application identity."
[[ -n "$NOTARY_PROFILE" ]] || fail "Set BLACKBOX_NOTARY_PROFILE to a notarytool Keychain profile name."
[[ -n "$LIVE_DATA_ROOT" ]] || fail "Set BLACKBOX_LIVE_DATA_ROOT explicitly."
[[ -n "$LIVE_HASH_MANIFEST" ]] || fail "Set BLACKBOX_LIVE_HASH_MANIFEST to the approved pre-work baseline."

for required_file in "$METADATA" "$ENTITLEMENTS" "$VERIFY_INPUT" "$PRIVACY_SCAN" "$LIVE_HASHES"; do
    [[ -f "$required_file" ]] || fail "Required release file is missing: $required_file"
done
/usr/bin/plutil -lint "$METADATA" "$ENTITLEMENTS" >/dev/null

PRODUCT="$(plist_value ProductName "$METADATA")"
BUNDLE_ID="$(plist_value BundleIdentifier "$METADATA")"
VERSION="$(plist_value Version "$METADATA")"
BUILD="$(plist_value Build "$METADATA")"
MIN_SYSTEM="$(plist_value MinimumSystemVersion "$METADATA")"
OUTPUT_DIR="${BLACKBOX_RELEASE_OUTPUT_DIR:-$ROOT_DIR/dist/release/$VERSION-build$BUILD}"
FINAL_BASENAME="$PRODUCT-$VERSION-macOS-universal"

CI_ARCHIVE="$(absolute_existing_path "$CI_ARCHIVE")"
CI_MANIFEST="$(absolute_existing_path "$CI_MANIFEST")"
LIVE_HASH_MANIFEST="$(absolute_existing_path "$LIVE_HASH_MANIFEST")"
LIVE_DATA_ROOT="$(absolute_existing_directory "$LIVE_DATA_ROOT")"
[[ -f "$CI_ARCHIVE" && ! -L "$CI_ARCHIVE" ]] || fail "CI archive is missing, not regular, or a symbolic link."
[[ -f "$CI_MANIFEST" && ! -L "$CI_MANIFEST" ]] || fail "CI manifest is missing, not regular, or a symbolic link."
[[ -f "$LIVE_HASH_MANIFEST" && ! -L "$LIVE_HASH_MANIFEST" ]] || fail "Live hash manifest is missing, not regular, or a symbolic link."
case "$LIVE_HASH_MANIFEST" in
    "$ROOT_DIR"/*) fail "Keep the live hash manifest outside the repository." ;;
esac
for release_input in "$CI_ARCHIVE" "$CI_MANIFEST"; do
    case "$release_input" in
        "$LIVE_DATA_ROOT"|"$LIVE_DATA_ROOT"/*) fail "A release input cannot be inside the live data root." ;;
    esac
done

if [[ -n "$(/usr/bin/git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    fail "The Git worktree must be clean before a release is signed."
fi
SOURCE_COMMIT="$(/usr/bin/git -C "$ROOT_DIR" rev-parse --verify HEAD)"
verify_ci_manifest

identity_line="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -F -- "$IDENTITY" \
    | /usr/bin/grep 'Developer ID Application:' \
    | /usr/bin/head -n 1 || true)"
[[ -n "$identity_line" ]] || fail "The selected Keychain identity is not a valid Developer ID Application identity."
if ! /usr/bin/xcrun notarytool history \
    --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null; then
    fail "The selected notarytool Keychain profile could not be authenticated."
fi

case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac
case "$OUTPUT_DIR" in
    *'/../'*|*'/./'*|*'/..'|*'/.') fail "Release output must not contain . or .. path components." ;;
    "$LIVE_DATA_ROOT"|"$LIVE_DATA_ROOT"/*) fail "Release output cannot be inside the live data root." ;;
esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
case "$OUTPUT_DIR" in
    "$LIVE_DATA_ROOT"|"$LIVE_DATA_ROOT"/*) fail "Release output cannot be inside the live data root." ;;
esac

FINAL_ZIP="$OUTPUT_DIR/$FINAL_BASENAME.zip"
CHECKSUM_FILE="$FINAL_ZIP.sha256"
RELEASE_MANIFEST="$OUTPUT_DIR/$FINAL_BASENAME.manifest.json"
NOTARY_RESULT="$OUTPUT_DIR/$FINAL_BASENAME.notary-result.json"
NOTARY_LOG="$OUTPUT_DIR/$FINAL_BASENAME.notary-log.json"
for output in "$FINAL_ZIP" "$CHECKSUM_FILE" "$RELEASE_MANIFEST" "$NOTARY_RESULT" "$NOTARY_LOG"; do
    [[ ! -e "$output" ]] || fail "Refusing to overwrite release output: $output"
done

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/blackbox-release.XXXXXX")"
CI_EXTRACTED_DIR="$WORK_DIR/ci-release-input"
STAGED_APP="$WORK_DIR/$PRODUCT.app"
NOTARY_ZIP="$WORK_DIR/$FINAL_BASENAME-notarization.zip"
EXTRACTED_DIR="$WORK_DIR/extracted-final"
LIVE_GATE_ARMED=0
SMOKE_EXECUTABLE_PATH=""
SMOKE_DATA_ROOT_PATH=""
SYNTHETIC_SMOKE_STATUS="not-run"

cleanup_and_verify() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "${SMOKE_EXECUTABLE_PATH:-}" ]]; then
        stop_smoke_process "$SMOKE_EXECUTABLE_PATH" "$SMOKE_DATA_ROOT_PATH"
    fi
    if [[ $LIVE_GATE_ARMED -eq 1 ]]; then
        if ! /bin/bash "$LIVE_HASHES" verify --root "$LIVE_DATA_ROOT" --manifest "$LIVE_HASH_MANIFEST"; then
            echo "$PROGRAM_NAME: LIVE DATA HASH GATE FAILED after release processing." >&2
            status=70
        fi
    fi
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        /bin/rm -rf "$WORK_DIR"
    fi
    exit "$status"
}
trap cleanup_and_verify EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

/bin/mkdir -p "$CI_EXTRACTED_DIR"
/usr/bin/ditto -x -k "$CI_ARCHIVE" "$CI_EXTRACTED_DIR"
APP_PATH="$CI_EXTRACTED_DIR/Blackbox-Unsigned.xcarchive/Products/Applications/$PRODUCT.app"
[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "Verified CI archive does not contain the expected $PRODUCT.app."
/bin/bash "$VERIFY_INPUT" --app "$APP_PATH" --require-unsigned

/bin/bash "$LIVE_HASHES" verify --root "$LIVE_DATA_ROOT" --manifest "$LIVE_HASH_MANIFEST"
LIVE_GATE_ARMED=1
/bin/bash "$PRIVACY_SCAN" --repository "$ROOT_DIR" --app "$APP_PATH"

/usr/bin/ditto "$APP_PATH" "$STAGED_APP"
sign_inside_out "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
/bin/bash "$VERIFY_INPUT" --app "$STAGED_APP"
/bin/bash "$PRIVACY_SCAN" --repository "$ROOT_DIR" --app "$STAGED_APP"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$NOTARY_ZIP"
if ! /usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$NOTARY_RESULT"; then
    submission_id="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
        /usr/bin/xcrun notarytool log --keychain-profile "$NOTARY_PROFILE" \
            "$submission_id" "$NOTARY_LOG" || true
    fi
    fail "Notarization submission failed. Review $NOTARY_RESULT and the notary log when available."
fi

notary_status="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT")"
submission_id="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT")"
/usr/bin/xcrun notarytool log --keychain-profile "$NOTARY_PROFILE" \
    "$submission_id" "$NOTARY_LOG"
[[ "$notary_status" == "Accepted" ]] || fail "Notarization status is $notary_status; review $NOTARY_LOG."

/usr/bin/xcrun stapler staple "$STAGED_APP"
/usr/bin/xcrun stapler validate "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
/usr/sbin/spctl --assess --type execute --verbose=4 "$STAGED_APP"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$FINAL_ZIP"
mkdir -p "$EXTRACTED_DIR"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$EXTRACTED_DIR"
EXTRACTED_APP="$EXTRACTED_DIR/$PRODUCT.app"
/bin/bash "$VERIFY_INPUT" --app "$EXTRACTED_APP"
/bin/bash "$PRIVACY_SCAN" --repository "$ROOT_DIR" --app "$EXTRACTED_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
/usr/bin/xcrun stapler validate "$EXTRACTED_APP"
/usr/sbin/spctl --assess --type execute --verbose=4 "$EXTRACTED_APP"

/bin/bash "$LIVE_HASHES" verify --root "$LIVE_DATA_ROOT" --manifest "$LIVE_HASH_MANIFEST"
run_quarantined_synthetic_smoke "$EXTRACTED_APP"
/bin/bash "$LIVE_HASHES" verify --root "$LIVE_DATA_ROOT" --manifest "$LIVE_HASH_MANIFEST"

final_sha256="$(/usr/bin/shasum -a 256 "$FINAL_ZIP" | /usr/bin/awk '{print $1}')"
final_bytes="$(/usr/bin/stat -f '%z' "$FINAL_ZIP")"
printf '%s  %s\n' "$final_sha256" "$(basename "$FINAL_ZIP")" > "$CHECKSUM_FILE"

team_identifier="$(/usr/bin/codesign --display --verbose=4 "$STAGED_APP" 2>&1 \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ "$team_identifier" =~ ^[A-Z0-9]{10}$ ]] || fail "Signed app has no valid TeamIdentifier."
baseline_sha256="$(/usr/bin/shasum -a 256 "$LIVE_HASH_MANIFEST" | /usr/bin/awk '{print $1}')"
created_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"

MANIFEST_PLIST="$WORK_DIR/release-manifest.plist"
/usr/bin/plutil -create xml1 "$MANIFEST_PLIST"
/usr/bin/plutil -insert product -string "$PRODUCT" "$MANIFEST_PLIST"
/usr/bin/plutil -insert bundleIdentifier -string "$BUNDLE_ID" "$MANIFEST_PLIST"
/usr/bin/plutil -insert version -string "$VERSION" "$MANIFEST_PLIST"
/usr/bin/plutil -insert build -string "$BUILD" "$MANIFEST_PLIST"
/usr/bin/plutil -insert minimumSystemVersion -string "$MIN_SYSTEM" "$MANIFEST_PLIST"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$MANIFEST_PLIST"
/usr/bin/plutil -insert sourceCommit -string "$SOURCE_COMMIT" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciWorkflowRunURL -string "$(plist_value workflowRunURL "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciRepository -string "$(plist_value repository "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciWorkflow -string "$(plist_value workflow "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciWorkflowRef -string "$(plist_value workflowRef "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciEventName -string "$(plist_value eventName "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciSourceRef -string "$(plist_value sourceRef "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciHeadRepository -string "$(plist_value headRepository "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciHeadRef -string "$(plist_value headRef "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciHeadSHA -string "$(plist_value headSHA "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciBaseRef -string "$(plist_value baseRef "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciPullRequestNumber -string "$(plist_value pullRequestNumber "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciRunID -string "$(plist_value runID "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciRunAttempt -string "$(plist_value runAttempt "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciXcodeVersion -string "$(plist_value xcodeVersion "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciXcodeBuild -string "$(plist_value xcodeBuild "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciInputArtifactFilename -string "$(basename "$CI_ARCHIVE")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciInputArtifactSHA256 -string "$(plist_value artifactSHA256 "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciSwiftPMTests -string "$(plist_value swiftPMTests "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciExecutableUnitTests -string "$(plist_value executableUnitTests "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciReleasePerformanceGates -string "$(plist_value releasePerformanceGates "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciSmokeTests -string "$(plist_value smokeTests "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciSnapshotMatrix -string "$(plist_value snapshotMatrix "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciUITests -string "$(plist_value uiTests "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciAccessibilityUITests -string "$(plist_value accessibilityUITests "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciPrivacyGate -string "$(plist_value privacyGate "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert ciDataPolicy -string "$(plist_value dataPolicy "$CI_MANIFEST")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert createdAt -string "$created_at" "$MANIFEST_PLIST"
/usr/bin/plutil -insert artifactFilename -string "$(basename "$FINAL_ZIP")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert artifactSHA256 -string "$final_sha256" "$MANIFEST_PLIST"
/usr/bin/plutil -insert artifactBytes -integer "$final_bytes" "$MANIFEST_PLIST"
/usr/bin/plutil -insert signingTeamIdentifier -string "$team_identifier" "$MANIFEST_PLIST"
/usr/bin/plutil -insert hardenedRuntime -bool true "$MANIFEST_PLIST"
/usr/bin/plutil -insert notarizationStatus -string "$notary_status" "$MANIFEST_PLIST"
/usr/bin/plutil -insert notarizationSubmissionID -string "$submission_id" "$MANIFEST_PLIST"
/usr/bin/plutil -insert staplerValidation -string passed "$MANIFEST_PLIST"
/usr/bin/plutil -insert gatekeeperAssessment -string passed "$MANIFEST_PLIST"
/usr/bin/plutil -insert quarantinedSyntheticSmoke -string "$SYNTHETIC_SMOKE_STATUS" "$MANIFEST_PLIST"
/usr/bin/plutil -insert privacyGate -string passed "$MANIFEST_PLIST"
/usr/bin/plutil -insert liveDataHashGate -string passed-before-and-after "$MANIFEST_PLIST"
/usr/bin/plutil -insert liveHashBaselineSHA256 -string "$baseline_sha256" "$MANIFEST_PLIST"
/usr/bin/plutil -convert json -r -o "$WORK_DIR/release-manifest.json" "$MANIFEST_PLIST"

/bin/bash "$LIVE_HASHES" verify --root "$LIVE_DATA_ROOT" --manifest "$LIVE_HASH_MANIFEST"
/usr/bin/ditto "$WORK_DIR/release-manifest.json" "$RELEASE_MANIFEST"
LIVE_GATE_ARMED=0

echo "Release complete: $FINAL_ZIP"
echo "Checksum: $CHECKSUM_FILE"
echo "Manifest: $RELEASE_MANIFEST"
