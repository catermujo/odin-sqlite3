package sqlite3

import "core:strings"
import "core:testing"
import "core:text/regex"

Capture_Error :: enum {
    None,
    No_Capture,
}

Regex_Error :: union #shared_nil {
    Capture_Error,
    regex.Error,
}

@(private)
match_and_return_capture :: proc(pattern: string, str: string) -> (string, Regex_Error) {
    // DUMBAI: The caller owns context.temp_allocator; clearing it here corrupts request state held in the same arena.
    regexp, err := regex.create(pattern)
    if err != nil {
        return "", err
    }
    defer regex.destroy(regexp)

    capture, ok := regex.match_and_allocate_capture(regexp, str)
    if !ok {
        return "", .No_Capture
    }
    defer regex.destroy(capture)


    return strings.clone(capture.groups[1]), nil
}

@(test)
match_and_return_capture_preserves_caller_temporary_allocations :: proc(t: ^testing.T) {
    marker := strings.clone("route-parameter", context.temp_allocator)
    capture, err := match_and_return_capture(`\<(.*)\>`, "<hello world>")
    defer delete(capture)
    testing.expect(t, err == nil)
    testing.expect_value(t, capture, "hello world")
    for _ in 0 ..< 64 do _ = strings.clone("allocator churn", context.temp_allocator)
    testing.expect_value(t, marker, "route-parameter")
}

@(test)
match_and_return_capture_test__no_capture :: proc(t: ^testing.T) {
    _, err := match_and_return_capture(`\<(.*)\>`, "hello world")
    testing.expect_value(t, err, Capture_Error.No_Capture)
}

@(test)
match_and_return_capture_test__malformed_regex :: proc(t: ^testing.T) {
    _, err := match_and_return_capture(`?\<(.*)\>`, "<hello world>")
    testing.expect(t, err != nil)
}

@(test)
match_and_return_capture_test :: proc(t: ^testing.T) {
    capture, err := match_and_return_capture(`\<(.*)\>`, "<hello world>")
    testing.expect(t, err == nil)
    testing.expect(t, capture == "hello world")
    delete(capture)
}
