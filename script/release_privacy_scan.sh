#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
REPOSITORY=""
APP_PATH=""

usage() {
    cat <<USAGE
Usage: $PROGRAM_NAME --repository <checkout> --app <Blackbox.app>

Fails if repository candidates or the distributable app contain likely private
logbook artifacts. The bundled airports.csv and the two SQLite source-integration
files are the only repository path exceptions.
USAGE
}

fail() {
    echo "$PROGRAM_NAME: $*" >&2
    exit 2
}

is_blocked_path() {
    local path="$1"
    local lower
    lower="$(printf '%s' "$path" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        sources/openpilotlogbookcore/resources/airports.csv|\
        sources/csqlite/module.modulemap|\
        sources/openpilotlogbookcore/services/sqliteconnection.swift|\
        .env.example)
            return 1
            ;;
        *logtencoredatastore*|*openpilotlogbook.sqlite*|*blackbox.sqlite*|*blackbox*backup*|*roster*|\
        *notary*credential*|*app-specific*password*)
            return 0
            ;;
        *.sqlite|*.sqlite3|*.sqlite-*|*.db|*.db3|*.db-*|*.sql|*.sql-*|*.pdf|*.csv|\
        *-wal|*-shm|*.blackboxbackup|*.numbers|*.xlsx|*.xls|*.heic|*.tiff|*.tif|\
        *.p12|*.pfx|*.p8|*.pem|*.key|*.cer|*.crt|*.mobileprovision|.env|.env.*)
            return 0
            ;;
    esac
    return 1
}

is_blocked_repository_image() {
    local path="$1"
    local lower
    lower="$(printf '%s' "$path" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        docs/assets/dashboard.jpg|docs/assets/map.jpg|docs/assets/analysis.jpg|\
        sources/openpilotlogbookcore/resources/earth-blue-marble.jpg|\
        sources/openpilotlogbook/assets/*)
            return 1
            ;;
        *.jpg|*.jpeg|*.png)
            return 0
            ;;
    esac
    return 1
}

is_bundled_airports_resource() {
    local path="$1"
    case "$path" in
        Contents/Resources/OpenPilotLogbook_OpenPilotLogbookCore.bundle/airports.csv|\
        Contents/Resources/OpenPilotLogbook_OpenPilotLogbookCore.bundle/Contents/Resources/airports.csv)
            return 0
            ;;
    esac
    return 1
}

[[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && { usage; exit 0; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repository)
            [[ $# -ge 2 ]] || fail "--repository requires a value."
            REPOSITORY="$2"
            shift 2
            ;;
        --app)
            [[ $# -ge 2 ]] || fail "--app requires a value."
            APP_PATH="$2"
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

/usr/bin/git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a Git checkout: $REPOSITORY"
REPOSITORY="$(/usr/bin/git -C "$REPOSITORY" rev-parse --show-toplevel)"
[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "App bundle does not exist or is a symbolic link: $APP_PATH"
APP_PATH="$(cd "$APP_PATH" && pwd -P)"

AIRPORTS_SOURCE="$REPOSITORY/Sources/OpenPilotLogbookCore/Resources/airports.csv"
[[ -f "$AIRPORTS_SOURCE" && ! -L "$AIRPORTS_SOURCE" ]] \
    || fail "The approved airport resource is missing, not regular, or a symbolic link."
AIRPORTS_SOURCE_SHA256="$(/usr/bin/shasum -a 256 "$AIRPORTS_SOURCE" | /usr/bin/awk '{print $1}')"

blocked_repository_path=""
while IFS= read -r -d '' candidate; do
    if is_blocked_path "$candidate" || is_blocked_repository_image "$candidate"; then
        blocked_repository_path="$candidate"
        break
    fi
done < <(/usr/bin/git -C "$REPOSITORY" ls-files --cached --others --exclude-standard -z)
[[ -z "$blocked_repository_path" ]] || fail "Private-data-like repository path is present: $blocked_repository_path"

blocked_app_path=""
bundled_airports_count=0
while IFS= read -r -d '' candidate; do
    relative="${candidate#"$APP_PATH"/}"
    if is_bundled_airports_resource "$relative"; then
        bundled_airports_count=$((bundled_airports_count + 1))
        [[ $bundled_airports_count -eq 1 ]] \
            || fail "The app contains more than one approved airport resource."
        candidate_sha256="$(/usr/bin/shasum -a 256 "$candidate" | /usr/bin/awk '{print $1}')"
        [[ "$candidate_sha256" == "$AIRPORTS_SOURCE_SHA256" ]] \
            || fail "The packaged airport resource does not match the approved repository resource: $relative"
        continue
    fi
    if is_blocked_path "$relative"; then
        blocked_app_path="$relative"
        break
    fi
    description="$(/usr/bin/file -b "$candidate")"
    case "$description" in
        *"SQLite 3.x database"*)
            blocked_app_path="$relative (SQLite content)"
            break
            ;;
    esac
done < <(/usr/bin/find "$APP_PATH" -type f -print0)
[[ -z "$blocked_app_path" ]] || fail "Private-data-like artifact is packaged: $blocked_app_path"
[[ $bundled_airports_count -eq 1 ]] \
    || fail "The app does not contain its single approved airport resource."

unsafe_symlink=""
while IFS= read -r -d '' candidate; do
    link_target="$(/usr/bin/readlink "$candidate")"
    case "$link_target" in
        /*|..|../*|*/../*|*/..)
            unsafe_symlink="${candidate#"$APP_PATH"/}"
            break
            ;;
    esac
done < <(/usr/bin/find "$APP_PATH" -type l -print0)
[[ -z "$unsafe_symlink" ]] || fail "The app contains an absolute or escaping symbolic link: $unsafe_symlink"

absolute_home_reference=""
while IFS= read -r -d '' candidate; do
    description="$(/usr/bin/file -b "$candidate")"
    case "$description" in
        *Mach-O*)
            if /usr/bin/strings -a "$candidate" | /usr/bin/grep -Eq '/Users/[^/[:space:]]+/'; then
                absolute_home_reference="${candidate#"$APP_PATH"/}"
                break
            fi
            ;;
        *text*|*XML*|*JSON*|*ASCII*|*Unicode*|*UTF-8*)
            if /usr/bin/grep -Eq '/Users/[^/[:space:]]+/' "$candidate"; then
                absolute_home_reference="${candidate#"$APP_PATH"/}"
                break
            fi
            ;;
    esac
done < <(/usr/bin/find "$APP_PATH" -type f -print0)
[[ -z "$absolute_home_reference" ]] || fail "A packaged file contains an absolute user-home path: $absolute_home_reference"

echo "Repository and app artifact privacy gates passed."
