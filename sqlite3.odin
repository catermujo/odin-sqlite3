package sqlite3

import "core:strings"
import raw "raw"

Connection :: raw.Sqlite3
Statement :: raw.Stmt
Result_Code :: raw.Status
Open_Flags :: raw.Open_Flags

open :: proc(filename: string) -> (^Connection, Result_Code) {
    return open_with_flags(filename, {.Read_Write, .Create})
}

open_with_flags :: proc(filename: string, flags: Open_Flags) -> (^Connection, Result_Code) {
    c_filename, c_filename_err := strings.clone_to_cstring(filename)
    if c_filename_err != nil {
        return nil, .No_Mem
    }
    defer delete(c_filename)

    db: ^Connection
    status := raw.open_v2(c_filename, &db, flags, nil)
    return db, status
}

close :: proc(db: ^Connection) -> Result_Code {
    if db == nil {
        return .Ok
    }
    return raw.close_v2(db)
}

finalize :: proc(stmt: ^Statement) -> Result_Code {
    if stmt == nil {
        return .Ok
    }
    return raw.finalize(stmt)
}

error_message :: proc(status: Result_Code) -> cstring {
    return raw.errstr(status)
}

last_error :: proc(db: ^Connection) -> cstring {
    if db == nil {
        return nil
    }
    return raw.errmsg(db)
}
