#!/usr/bin/env bash

set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$BASE/sqlite"
SQLITE_REPOSITORY="${SQLITE_REPOSITORY:-https://github.com/sqlite/sqlite.git}"
CC="${CC:-cc}"
AR="${AR:-ar}"
TCLSH="${TCLSH:-tclsh}"

arch_dir() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "${1}_x64" ;;
        aarch64 | arm64) echo "${1}_arm64" ;;
        *) echo "${1}_$(uname -m)" ;;
    esac
}

case "$(uname -s)" in
    Darwin)
        OUTPUT_DIR="$BASE/$(arch_dir darwin)"
        LIB_NAME=sqlite3.darwin.a
        ;;
    Linux)
        OUTPUT_DIR="$BASE/$(arch_dir linux)"
        LIB_NAME=sqlite3.linux.a
        ;;
    *)
        echo "Unsupported host OS: $(uname -s)" >&2
        exit 1
        ;;
esac

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

if [ -e "$SOURCE_DIR" ] && [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "SQLite source path exists but is not a git checkout: $SOURCE_DIR" >&2
    exit 1
fi

if [ ! -d "$SOURCE_DIR/.git" ]; then
    require_command git
    git clone --depth 1 "$SQLITE_REPOSITORY" "$SOURCE_DIR"
fi

require_command "$CC"
require_command "$AR"
require_command "$TCLSH"

(
    cd "$SOURCE_DIR"
    "$TCLSH" tool/mksqlite3c.tcl
)

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sqlite-static.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
mkdir -p "$OUTPUT_DIR"
"$CC" -O2 -DNDEBUG -fPIC -c \
    "$SOURCE_DIR/sqlite3.c" \
    -o "$BUILD_DIR/sqlite3.o"
"$AR" rcs "$OUTPUT_DIR/$LIB_NAME" "$BUILD_DIR/sqlite3.o"

echo "SQLite static build completed successfully!"
