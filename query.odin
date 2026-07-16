package sqlite3

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strings"

import "raw"

Runtime_Config :: struct {
    extra_runtime_checks: bool,
    log_level:            Maybe(log.Level),
}

config: Runtime_Config

Query_Error :: Maybe(string)

Query_Param_Value :: union {
    i32,
    i64,
    f64,
    []byte,
    bool,
    string,
}

Query_Param :: struct {
    index: int,
    value: Query_Param_Value,
}

query :: proc(
    db: ^Connection,
    out: ^[dynamic]$T,
    sql: string,
    params: []Query_Param = {},
    loc := #caller_location,
) -> Result_Code {
    stmt: ^Statement

    prepare(db, &stmt, sql, params, loc) or_return
    return read_all_rows(stmt, out)
}

// Allocates. Make sure to free results even when the return value is not .Ok
@(require_results)
read_all_rows :: proc(stmt: ^Statement, out: ^[dynamic]$T) -> Result_Code {
    defer raw.finalize(stmt)

    fields, err := get_type_fields(T)
    if err != nil {
        log.error(err)
        return .Internal
    }

    defer delete_field_types(fields)

    field_map: map[string]^Field_Type
    defer delete(field_map)
    for &field in fields {
        field_map[field.tag] = &field
    }

    if raw.column_count(stmt) != c.int(len(fields)) {
        log.errorf("column count does not match {}", typeid_of(T))
        return .Internal
    }

    status := raw.step(stmt)
    for status == .Row {
        item: T
        cols := raw.column_count(stmt)
        for i in 0 ..< cols {
            column := strings.clone_from(raw.column_name(stmt, i))
            defer delete(column)

            field_type, ok := field_map[column]
            if !ok {
                log.errorf("could not find tag {} in {}", column, typeid_of(T))
                return .Internal
            }

            if field_err := write_struct_field_from_statement(&item, field_type, stmt, c.int(i)); field_err != nil {
                log.error(field_err)
                free_query_error(field_err)
                return .Internal
            }
        }

        append(out, item)
        status = raw.step(stmt)
    }

    return status == .Done ? .Ok : status
}

@(require_results)
execute :: proc(db: ^Connection, sql: string, params: []Query_Param = {}, loc := #caller_location) -> Result_Code {
    if len(params) == 0 {
        return execute_script(db, sql)
    }

    stmt: ^Statement
    prepare(db, &stmt, sql, params, loc) or_return
    defer raw.finalize(stmt)
    status := raw.step(stmt)
    for status == .Row {
        // consume all rows
        status = raw.step(stmt)
    }

    return status == .Done ? .Ok : status
}

execute_script :: proc(db: ^Connection, sql: string) -> Result_Code {
    csql, csql_err := strings.clone_to_cstring(sql)
    if csql_err != nil {
        return .No_Mem
    }
    defer delete(csql)

    message: cstring
    status := raw.exec(db, csql, nil, nil, &message)
    if message != nil {
        raw.free(rawptr(message))
    }
    return status
}

@(require_results)
prepare :: proc(
    db: ^Connection,
    stmt: ^^Statement,
    sql: string,
    params: []Query_Param = {},
    loc := #caller_location,
) -> Result_Code {
    prepared := false
    defer if !prepared && stmt^ != nil {
        raw.finalize(stmt^)
    }
    raw.prepare_v2(db, raw_data(sql), c.int(len(sql)), stmt, nil) or_return

    for &param in params {
        idx := c.int(param.index)

        if param.value == nil {
            raw.bind_null(stmt^, idx) or_return
        } else if v, is_i32 := param.value.(i32); is_i32 {
            raw.bind_int(stmt^, idx, c.int(v)) or_return
        } else if v, is_i64 := param.value.(i64); is_i64 {
            raw.bind_int64(stmt^, idx, c.int64_t(v)) or_return
        } else if v, is_f64 := param.value.(f64); is_f64 {
            raw.bind_double(stmt^, idx, c.double(v)) or_return
        } else if v, is_blob := param.value.([]byte); is_blob {
            raw.bind_blob64(stmt^, idx, slice.as_ptr(v), c.int64_t(len(v)), raw.TRANSIENT) or_return
        } else if v, is_bool := param.value.(bool); is_bool {
            raw.bind_int(stmt^, idx, c.int(v ? 1 : 0)) or_return
        } else if v, is_string := param.value.(string); is_string {
            // Sqlite treats our parameter as a "cstring" if we pass a negative length.
            // Explicitly it's just a slice.
            // https://sqlite.org/c3ref/bind_blob.html.
            raw.bind_text(stmt^, idx, raw_data(v), c.int(len(v)), raw.TRANSIENT) or_return
        } else {
            log.errorf("unhandled parameter type {}", param.value)
            return .Internal
        }

    }
    prepared = true

    exp_statement := raw.expanded_sql(stmt^)
    // `expanded_sql` can return NULL(nil) as explained here: https://www.sqlite.org/c3ref/expanded_sql.html
    if exp_statement != nil {
        defer raw.free(cast(rawptr)exp_statement)
        do_log("SQL: {}", exp_statement, loc = loc)
    } else {
        // Not going to return an error here because everything else worked fine,
        // but it should be logged regardless.
        log.errorf("Unable to allocate memory while expanding the sql statement")
    }
    return .Ok
}

@(private)
do_log :: #force_inline proc(format_str: string, args: ..any, loc := #caller_location) {
    level, ok := config.log_level.?
    if !ok do return

    if context.logger.procedure != log.nil_logger_proc {
        log.logf(level, format_str, ..args, location = loc)
        return
    }

    logger := log.create_console_logger()
    defer log.destroy_console_logger(logger)
    {
        context.logger = logger
        log.logf(level, format_str, ..args, location = loc)
    }
}

@(private)
free_query_error :: #force_inline proc(err: Query_Error) {
    delete(err.(string), context.temp_allocator)
}

@(private)
@(require_results)
write_struct_field_from_statement :: proc(
    obj: ^$T,
    field: ^Field_Type,
    stmt: ^raw.Stmt,
    col_idx: c.int,
) -> Query_Error {
    switch field.type.id {
    case typeid_of(string):
        text := raw.column_text(stmt, col_idx)
        if text == nil {
            return fmt.tprintf("cannot read NULL into {}", field.type.id)
        }
        value := strings.clone_from(text)
        write_struct_field(obj, field^, value) or_return

    case typeid_of(bool):
        value := raw.column_int(stmt, col_idx) != 0
        write_struct_field(obj, field^, value) or_return

    case typeid_of(int):
        value := int(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(uint):
        value := uint(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(i8):
        value := i8(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(u8):
        value := u8(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(i16):
        value := i16(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(u16):
        value := u16(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(i32):
        value := i32(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(u32):
        value := u32(raw.column_int(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(i64):
        value := i64(raw.column_int64(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(u64):
        value := u64(raw.column_int64(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(f32):
        value := f32(raw.column_double(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of(f64):
        value := f64(raw.column_double(stmt, col_idx))
        write_struct_field(obj, field^, value) or_return

    case typeid_of([]byte):
        length := int(raw.column_bytes(stmt, col_idx))
        value := make([]byte, length)
        if length > 0 {
            mem.copy(raw_data(value), raw.column_blob(stmt, col_idx), length)
        }
        write_struct_field(obj, field^, value) or_return

    case:
        if reflect.is_enum(field.type) {
            enum_values := reflect.enum_field_values(field.type.id)

            value := i64(raw.column_int64(stmt, col_idx))

            if config.extra_runtime_checks {
                found := false

                for it in enum_values {
                    if i64(it) == value {
                        found = true
                        break
                    }
                }

                if !found {
                    return fmt.tprintf("expected to find enum value {} in {}", value, field.type.id)
                }
            }

            write_struct_field(obj, field^, value) or_return
        } else {
            return fmt.tprintf("unhandled data type {}", field.type.id)
        }
    }

    return nil
}
