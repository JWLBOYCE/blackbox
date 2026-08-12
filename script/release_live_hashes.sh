#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
EXPECTED_FILES="Blackbox.sqlite Blackbox.sqlite-wal Blackbox.sqlite-shm"
MANIFEST_HEADER="# blackbox-live-hash-manifest-v1"

usage() {
    cat <<USAGE
Usage:
  $PROGRAM_NAME capture --root <live-data-root> --manifest <new-manifest>
  $PROGRAM_NAME verify  --root <live-data-root> --manifest <baseline-manifest>

Hashes the three live Blackbox SQLite files as opaque bytes. It never opens
SQLite and never writes inside the live data root. Missing WAL or SHM files are
recorded as MISSING; the main Blackbox.sqlite file must exist.
USAGE
}

fail() {
    echo "$PROGRAM_NAME: $*" >&2
    exit 2
}

absolute_existing_directory() {
    local directory="$1"
    [[ -d "$directory" ]] || fail "Data root is not a directory: $directory"
    (cd "$directory" && pwd -P)
}

absolute_output_path() {
    local path="$1"
    local parent
    local leaf
    parent="$(dirname "$path")"
    leaf="$(basename "$path")"
    [[ -d "$parent" ]] || fail "Manifest parent directory does not exist: $parent"
    parent="$(cd "$parent" && pwd -P)"
    printf '%s/%s\n' "$parent" "$leaf"
}

ensure_blackbox_is_closed() {
    if /usr/bin/pgrep -x Blackbox >/dev/null 2>&1 \
        || /usr/bin/pgrep -x OpenPilotLogbook >/dev/null 2>&1; then
        fail "Blackbox is running. Quit it before capturing or verifying live hashes."
    fi
}

hash_file() {
    local path="$1"
    /usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}'
}

manifest_value() {
    local manifest="$1"
    local filename="$2"
    local count
    count="$(/usr/bin/awk -v expected="$filename" '$2 == expected { count += 1 } END { print count + 0 }' "$manifest")"
    [[ "$count" == "1" ]] || fail "Manifest must contain exactly one entry for $filename."
    /usr/bin/awk -v expected="$filename" '$2 == expected { print $1 }' "$manifest"
}

[[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && { usage; exit 0; }
[[ $# -ge 1 ]] || { usage >&2; exit 2; }

ACTION="$1"
shift
DATA_ROOT=""
MANIFEST_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 ]] || fail "--root requires a value."
            DATA_ROOT="$2"
            shift 2
            ;;
        --manifest)
            [[ $# -ge 2 ]] || fail "--manifest requires a value."
            MANIFEST_PATH="$2"
            shift 2
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

[[ "$ACTION" == "capture" || "$ACTION" == "verify" ]] || fail "Action must be capture or verify."
[[ -n "$DATA_ROOT" ]] || fail "--root is required."
[[ -n "$MANIFEST_PATH" ]] || fail "--manifest is required."

DATA_ROOT="$(absolute_existing_directory "$DATA_ROOT")"
MANIFEST_PATH="$(absolute_output_path "$MANIFEST_PATH")"
[[ "$DATA_ROOT" != "/" ]] || fail "Refusing to use the filesystem root as the data root."
[[ "$(basename "$DATA_ROOT")" == "Blackbox" ]] || fail "The data root must be the Blackbox directory itself."
case "$MANIFEST_PATH" in
    "$DATA_ROOT"/*)
        fail "The hash manifest must be stored outside the live data root."
        ;;
esac

ensure_blackbox_is_closed

if [[ "$ACTION" == "capture" ]]; then
    [[ ! -e "$MANIFEST_PATH" ]] || fail "Refusing to overwrite an existing baseline: $MANIFEST_PATH"
    [[ -f "$DATA_ROOT/Blackbox.sqlite" && ! -L "$DATA_ROOT/Blackbox.sqlite" ]] \
        || fail "The live Blackbox.sqlite file is missing, not regular, or a symbolic link."

    TEMP_MANIFEST="$(/usr/bin/mktemp "${MANIFEST_PATH}.tmp.XXXXXX")"
    cleanup_capture() {
        local status=$?
        if [[ -n "${TEMP_MANIFEST:-}" && -f "$TEMP_MANIFEST" ]]; then
            /bin/rm -f "$TEMP_MANIFEST"
        fi
        exit "$status"
    }
    trap cleanup_capture EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    {
        printf '%s\n' "$MANIFEST_HEADER"
        for filename in $EXPECTED_FILES; do
            candidate="$DATA_ROOT/$filename"
            if [[ -e "$candidate" ]]; then
                [[ -f "$candidate" && ! -L "$candidate" ]] \
                    || fail "$filename is not a regular file or is a symbolic link."
                printf '%s  %s\n' "$(hash_file "$candidate")" "$filename"
            else
                printf 'MISSING  %s\n' "$filename"
            fi
        done
    } > "$TEMP_MANIFEST"
    ensure_blackbox_is_closed
    /bin/chmod 600 "$TEMP_MANIFEST"
    /bin/ln "$TEMP_MANIFEST" "$MANIFEST_PATH" \
        || fail "Refusing to overwrite a baseline created concurrently: $MANIFEST_PATH"
    /bin/rm -f "$TEMP_MANIFEST"
    TEMP_MANIFEST=""
    trap - EXIT INT TERM
    echo "Captured opaque live-data hashes in $MANIFEST_PATH"
    exit 0
fi

[[ -f "$MANIFEST_PATH" && ! -L "$MANIFEST_PATH" ]] || fail "Baseline manifest is missing, not regular, or a symbolic link."
[[ "$(/usr/bin/sed -n '1p' "$MANIFEST_PATH")" == "$MANIFEST_HEADER" ]] || fail "Unrecognized baseline manifest format."
[[ "$(/usr/bin/awk 'END { print NR + 0 }' "$MANIFEST_PATH")" == "4" ]] || fail "Baseline manifest must contain only the header and three file entries."
if ! /usr/bin/awk 'NR == 1 { next } NF != 2 { exit 1 }' "$MANIFEST_PATH"; then
    fail "Each baseline file entry must contain exactly a hash state and filename."
fi

for filename in $EXPECTED_FILES; do
    expected="$(manifest_value "$MANIFEST_PATH" "$filename")"
    case "$expected" in
        MISSING)
            [[ "$filename" != "Blackbox.sqlite" ]] || fail "The main Blackbox.sqlite file cannot be MISSING in a valid baseline."
            [[ ! -e "$DATA_ROOT/$filename" ]] || fail "$filename was absent at baseline but now exists."
            ;;
        *[!0-9a-f]*|'')
            fail "Invalid SHA-256 value for $filename."
            ;;
        *)
            [[ ${#expected} -eq 64 ]] || fail "Invalid SHA-256 length for $filename."
            [[ -f "$DATA_ROOT/$filename" && ! -L "$DATA_ROOT/$filename" ]] \
                || fail "$filename is missing, not regular, or a symbolic link."
            actual="$(hash_file "$DATA_ROOT/$filename")"
            [[ "$actual" == "$expected" ]] || fail "$filename changed from the approved baseline."
            ;;
    esac
done

ensure_blackbox_is_closed
echo "Live SQLite, WAL, and SHM bytes match the approved baseline."
