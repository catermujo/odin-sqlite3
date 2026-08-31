#!/usr/bin/env bash

set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$BASE/sqlite"
SQLITE_REPOSITORY="${SQLITE_REPOSITORY:-https://github.com/sqlite/sqlite.git}"
SQLITE_REVISION="${SQLITE_REVISION:-version-3.45.1}"
SQLITE_COMMIT="${SQLITE_COMMIT:-189e44dfecdc7868bb860dfb5d98eab371318c37}"
CC="${CC:-cc}"
MAKE="${MAKE:-make}"
TCLSH="${TCLSH:-tclsh}"

arch_dir() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "${1}_x64" ;;
        aarch64 | arm64) echo "${1}_arm64" ;;
        *) echo "${1}_$(uname -m)" ;;
    esac
}

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
    git clone --depth 1 --branch "$SQLITE_REVISION" "$SQLITE_REPOSITORY" "$SOURCE_DIR"
fi

if [ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" != "$SQLITE_COMMIT" ]; then
    echo "SQLite source checkout does not match pinned commit: $SQLITE_COMMIT" >&2
    exit 1
fi

require_command "$CC"
require_command "$MAKE"
require_command "$TCLSH"

(
    cd "$SOURCE_DIR"
    CC="$CC" ./configure --disable-tcl
    "$MAKE" sqlite3.c
)

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sqlite-shared.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

case "$(uname -s)" in
    Darwin)
        OUTPUT_DIR="$BASE/$(arch_dir darwin)"
        mkdir -p "$OUTPUT_DIR"
        "$CC" -O2 -DNDEBUG -DSQLITE_ENABLE_RTREE -dynamiclib \
            "$SOURCE_DIR/sqlite3.c" \
            -Wl,-install_name,@rpath/libsqlite3.dylib \
            -o "$OUTPUT_DIR/libsqlite3.dylib"
        ;;
    Linux)
        OUTPUT_DIR="$BASE/$(arch_dir linux)"
        mkdir -p "$OUTPUT_DIR"
        "$CC" -O2 -DNDEBUG -DSQLITE_ENABLE_RTREE -fPIC -shared \
            "$SOURCE_DIR/sqlite3.c" \
            -Wl,-soname,libsqlite3.so \
            -ldl -lpthread -lm \
            -o "$OUTPUT_DIR/libsqlite3.so"
        ;;
    *)
        echo "Unsupported host OS: $(uname -s)" >&2
        exit 1
        ;;
esac

echo "SQLite shared build completed successfully!"
