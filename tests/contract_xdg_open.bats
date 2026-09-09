#!/usr/bin/env bats
#
# xdg-open(1) command-line contract.
#
# Exit codes per xdg-open(1): 0 success, 1 syntax error, 2 file not found,
# 3 required tool not found, 4 action failed.

setup_file() {
    load helpers
    export SAMPLE="$BATS_FILE_TMPDIR/sample.txt"
    echo "test content" > "$SAMPLE"
}

setup() {
    load helpers
    SAMPLE="$BATS_FILE_TMPDIR/sample.txt"
}

@test "xdg-open --help exits 0 and prints a synopsis" {
    run "$XDG_OPEN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "xdg-open --version exits 0 and names the handlr backend" {
    run "$XDG_OPEN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *handlr* ]]
}

@test "xdg-open --manual exits 0 (man page, or a fallback synopsis)" {
    run "$XDG_OPEN" --manual
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "xdg-open --manual never dies with man's 'no entry' exit 16" {
    # Regression guard: exec'ing man unconditionally fails this way from a
    # source checkout, or where man pages are not installed.
    run env PATH="$(path_without man)" "$XDG_OPEN" --manual
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "xdg-open with no arguments is a syntax error (1)" {
    assert_exit 1 "$XDG_OPEN"
}

@test "xdg-open rejects an unrecognized option (1)" {
    assert_exit 1 "$XDG_OPEN" --bogus
}

@test "xdg-open rejects more than one argument (1)" {
    # Unlike xdg-mime, upstream xdg-open really does reject extras.
    assert_exit 1 "$XDG_OPEN" "$SAMPLE" "$SAMPLE"
}

@test "xdg-open reports a missing file as not found (2)" {
    assert_exit 2 "$XDG_OPEN" /nonexistent/does-not-exist
}

@test "xdg-open reports a missing handlr as tool-not-found (3)" {
    run env PATH="$(path_without handlr)" "$XDG_OPEN" "$SAMPLE"
    [ "$status" -eq 3 ]
}

@test "xdg-open treats a URI scheme as a URI, not a missing file" {
    # Must not exit 2: there is no such local file, but it is a valid URI
    # and handlr resolves it via x-scheme-handler/*.
    run "$XDG_OPEN" "https://example.invalid/nothing-here"
    [ "$status" -ne 2 ]
}

@test "xdg-open does not abort (134) when no handler exists and no D-Bus" {
    # handlr panics in its notification path with no session bus; the shim
    # must return the documented 'action failed' instead.
    run_without_dbus "$XDG_OPEN" "$SAMPLE"
    [ "$status" -ne 134 ]
    [ "$status" -eq 0 ] || [ "$status" -eq 4 ]
}
