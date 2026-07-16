# Odin SQLite

Root package provides typed SQLite helpers:

```odin
import sqlite "vendor/sqlite"
```

- `open` and `open_with_flags` open connections.
- `execute` runs statements with typed `Query_Param` values.
- `query` fills tagged structs into dynamic arrays.
- `prepare` and `read_all_rows` support manual statement ownership.

Query results own cloned strings and blobs. Delete those fields, then delete
the result array after use.

Raw C bindings live in `vendor/sqlite/raw`:

```odin
import sqlite_raw "vendor/sqlite/raw"
```

Use `SQLITE_LINK=shared`, `static`, or `system` to select the library. Build
scripts clone the official `sqlite/sqlite` source into the ignored `sqlite/`
checkout, generate the amalgamation there, and produce platform-specific
artifacts. No SQLite C source is tracked in this repository.
