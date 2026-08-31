# Odin SQLite

Root package provides typed SQLite helpers:

```odin
import sqlite "vendor/sqlite"
```

- `open` and `open_with_flags` open connections.
- `execute` runs statements with typed `Query_Param` values.
- `query` fills tagged structs into dynamic arrays. Pass `result_allocator` when results must have a lifetime that differs
  from the ambient context allocator.
- `prepare` and `read_all_rows` support manual statement ownership.

Query results own cloned strings and blobs in `result_allocator`. Delete those fields and the result array after use, or
release their shared arena when an arena allocator was supplied.

Raw C bindings live in `vendor/sqlite/raw`:

```odin
import sqlite_raw "vendor/sqlite/raw"
```

Use `SQLITE_LINK=shared`, `static`, or `system` to select the library. Build
scripts clone the official `sqlite/sqlite` source into the ignored `sqlite/`
checkout, generate the amalgamation there, and produce platform-specific
artifacts. No SQLite C source is tracked in this repository.

## WebAssembly runtime

`wasm/` contains the unmodified official SQLite 3.45.1 (`3045001`) JavaScript/WASM distribution files required by
the `sqlite3.oo1.OpfsDb` browser adapter. They come from:

```text
https://www.sqlite.org/2024/sqlite-wasm-3450100.zip
SHA-256: d496c97ec66ad1d4f73ef216f7ece611adac94f38f28a97a2f58cb6babe409a6
```

The extracted files and their SHA-256 digests are:

```text
053a9230ce44becbce2782c5efb6c22d00702a70c092d9dd35164881ef926ee3  wasm/sqlite3.js
69c4f043fbae0d35b9068c00c9885367ca739d79f9835be3e1beb8a7b8ae2d9b  wasm/sqlite3.wasm
871905da5666c48bb4e15405d86bb602da7ff819a1b7db6b8f31a38d2b23b76c  wasm/sqlite3-opfs-async-proxy.js
```

To regenerate them, download the pinned archive, verify its archive digest, and extract those three names from
`sqlite-wasm-3450100/jswasm/` into `wasm/` without rewriting them. SQLite dedicates its source code to the public
domain, and the upstream notices remain embedded in the distributed JavaScript files.

The OPFS VFS requires a secure browser context and cross-origin isolation so `SharedArrayBuffer` is available. Serve
`sqlite3-opfs-async-proxy.js` alongside `sqlite3.js` and `sqlite3.wasm`; SQLite loads the proxy in a dedicated Worker.
