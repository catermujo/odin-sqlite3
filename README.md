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
