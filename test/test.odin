package test

import "core:fmt"

import sqlite ".."

User :: struct {
    name:    string `sqlite:"name"`,
    score:   f64 `sqlite:"score"`,
    active:  bool `sqlite:"active"`,
    payload: []byte `sqlite:"payload"`,
}

main :: proc() {
    db, status := sqlite.open_with_flags(":memory:", {.Read_Write, .Create, .Memory})
    if status != .Ok {
        fmt.panicf("open failed: {}", sqlite.error_message(status))
    }
    defer sqlite.close(db)

    if result := sqlite.execute(db, "CREATE TABLE users (name TEXT, score REAL, active INTEGER, payload BLOB)");
       result != .Ok {
        fmt.panicf("create failed: {}", sqlite.last_error(db))
    }
    if result := sqlite.execute(
        db,
        "CREATE TABLE script_values (value INTEGER); INSERT INTO script_values VALUES (7);",
    ); result != .Ok {
        fmt.panicf("script execution failed: {}", sqlite.last_error(db))
    }
    if result := sqlite.execute(db, "INSERT INTO missing_table VALUES (1)"); result == .Ok {
        fmt.panicf("invalid insert unexpectedly succeeded")
    }
    if result := sqlite.execute(
        db,
        "INSERT INTO users (name, score, active, payload) VALUES (?, ?, ?, ?)",
        {
            {index = 1, value = "john"},
            {index = 2, value = f64(2.5)},
            {index = 3, value = true},
            {index = 4, value = []byte{1, 2, 3}},
        },
    ); result != .Ok {
        fmt.panicf("insert failed: {}", sqlite.last_error(db))
    }
    if result := sqlite.execute(
        db,
        "INSERT INTO users (name, score, active, payload) VALUES (?, ?, ?, ?)",
        {
            {index = 1, value = ""},
            {index = 2, value = f64(0)},
            {index = 3, value = false},
            {index = 4, value = []byte{}},
        },
    ); result != .Ok {
        fmt.panicf("empty string insert failed: {}", sqlite.last_error(db))
    }

    users: [dynamic]User
    if result := sqlite.query(
        db,
        &users,
        "SELECT name, score, active, payload FROM users WHERE active = ?",
        {{index = 1, value = true}},
    ); result != .Ok {
        fmt.panicf("query failed: {}", sqlite.last_error(db))
    }

    for &user in users {
        fmt.printfln("{} {} {} {}", user.name, user.score, user.active, len(user.payload))
        delete(user.name)
        delete(user.payload)
    }
    delete(users)

    empty_users: [dynamic]User
    if result := sqlite.query(
        db,
        &empty_users,
        "SELECT name, score, active, payload FROM users WHERE name = ''",
    ); result != .Ok || len(empty_users) != 1 || empty_users[0].name != "" {
        fmt.panicf("empty string did not round trip as text: {}", sqlite.last_error(db))
    }
    for &user in empty_users {
        delete(user.name)
        delete(user.payload)
    }
    delete(empty_users)
}
