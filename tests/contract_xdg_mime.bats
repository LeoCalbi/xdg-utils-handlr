#!/usr/bin/env bats
#
# xdg-mime(1) command-line contract.
#
# Exit codes per xdg-mime(1): 0 success, 1 syntax error, 2 file not found,
# 3 required tool not found, 4 action failed, 5 permission denied.

setup_file() {
    load helpers
    export SAMPLE="$BATS_FILE_TMPDIR/sample.txt"
    echo "test content" > "$SAMPLE"
    export UNREADABLE="$BATS_FILE_TMPDIR/unreadable.txt"
    : > "$UNREADABLE"
    chmod 000 "$UNREADABLE"
}

setup() {
    load helpers
    SAMPLE="$BATS_FILE_TMPDIR/sample.txt"
    UNREADABLE="$BATS_FILE_TMPDIR/unreadable.txt"
}

# ------------------------------------------------------------ help surface

@test "xdg-mime --help exits 0 and prints a synopsis" {
    run "$XDG_MIME" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "xdg-mime --version exits 0 and names the handlr backend" {
    run "$XDG_MIME" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *handlr* ]]
}

@test "xdg-mime --manual exits 0 (man page, or upstream's embedded manual)" {
    run "$XDG_MIME" --manual
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "xdg-mime --manual falls back to the embedded manual without man" {
    run env PATH="$(path_without man)" "$XDG_MIME" --manual
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "xdg-mime with no arguments is a syntax error (1)" {
    assert_exit 1 "$XDG_MIME"
}

@test "xdg-mime rejects an unknown query subcommand (1)" {
    assert_exit 1 "$XDG_MIME" query bogus
}

@test "xdg-mime rejects an unknown top-level subcommand (1)" {
    assert_exit 1 "$XDG_MIME" frobnicate
}

# -------------------------------------------------------- query filetype

@test "query filetype returns a BARE mimetype, not handlr's table" {
    # The bug this suite exists for: `handlr mime` prints a padded table
    # with a path/mime header row, which broke mime=$(xdg-mime query ...).
    run "$XDG_MIME" query filetype "$SAMPLE"
    [ "$status" -eq 0 ]
    assert_is_bare_mimetype "$output"
}

@test "query filetype identifies a plain text file as text/plain" {
    # The one type every detector agrees on, so it is safe to pin exactly.
    assert_stdout_is "text/plain" "$XDG_MIME" query filetype "$SAMPLE"
}

@test "query filetype output is usable as a single shell argument" {
    local mime
    mime="$("$XDG_MIME" query filetype "$SAMPLE")"
    # Round-trips into the position `xdg-mime default` expects.
    run "$XDG_MIME" query default "$mime"
    [ "$status" -eq 0 ]
}

@test "query filetype reports a missing file as not found (2)" {
    assert_exit 2 "$XDG_MIME" query filetype /nonexistent/does-not-exist
}

@test "query filetype reports an unreadable file as permission denied (5)" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root bypasses file permission bits"
    fi
    assert_exit 5 "$XDG_MIME" query filetype "$UNREADABLE"
}

@test "query filetype with no file argument is a syntax error (1)" {
    assert_exit 1 "$XDG_MIME" query filetype
}

@test "query filetype ignores extra arguments, like upstream" {
    # Upstream reads only its FILE argument (filename=\$2) and never looks
    # at the rest. Being stricter would break callers upstream tolerated.
    run "$XDG_MIME" query filetype "$SAMPLE" /etc/hostname
    [ "$status" -eq 0 ]
    assert_is_bare_mimetype "$output"
}

@test "query filetype accepts a URL and returns a scheme handler type" {
    run "$XDG_MIME" query filetype "https://example.invalid/x"
    [ "$status" -eq 0 ]
    [ "$output" = "x-scheme-handler/https" ]
}

# ---------------------------------------------------------- query default

@test "query default exits 0 and prints nothing when no default is set" {
    # Upstream's answer for "no default": empty stdout, exit 0.
    run "$XDG_MIME" query default application/x-xdg-utils-handlr-nonexistent
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "query default requires exactly one mimetype (1)" {
    assert_exit 1 "$XDG_MIME" query default
    assert_exit 1 "$XDG_MIME" query default text/plain text/html
}

@test "query default does not abort (134) with no handler and no D-Bus" {
    run_without_dbus "$XDG_MIME" query default application/x-xdg-utils-handlr-nonexistent
    [ "$status" -ne 134 ]
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------- default

@test "default requires an application and at least one mimetype (1)" {
    assert_exit 1 "$XDG_MIME" default
    assert_exit 1 "$XDG_MIME" default only-one-argument.desktop
}

@test "default reports an invalid desktop entry as action failed (4)" {
    assert_exit 4 "$XDG_MIME" default \
        xdg-utils-handlr-nonexistent.desktop application/x-xdg-utils-handlr-nonexistent
}

@test "default does not abort (134) on an invalid entry without D-Bus" {
    run_without_dbus "$XDG_MIME" default \
        xdg-utils-handlr-nonexistent.desktop application/x-xdg-utils-handlr-nonexistent
    [ "$status" -ne 134 ]
    [ "$status" -eq 4 ]
}

# ------------------------------------------------- handlr dependency gating

@test "handlr-backed subcommands report a missing handlr as 3" {
    local shadow; shadow="$(path_without handlr)"
    run env PATH="$shadow" "$XDG_MIME" query filetype "$SAMPLE"
    [ "$status" -eq 3 ]
    run env PATH="$shadow" "$XDG_MIME" query default text/plain
    [ "$status" -eq 3 ]
    run env PATH="$shadow" "$XDG_MIME" default some.desktop text/plain
    [ "$status" -eq 3 ]
}

@test "install/uninstall do NOT require handlr" {
    # These only exec the vendored upstream script. Demanding handlr for
    # them would break package installers on a broken handlr install --
    # the exact failure mode this package exists to prevent.
    skip_without_oracle
    run env PATH="$(path_without handlr)" "$XDG_MIME" install
    # Upstream's own syntax error proves the handoff happened.
    [[ "$output" == *mimetypes-file* ]]
    [ "$status" -ne 3 ]
}

@test "the help surface works without handlr" {
    local shadow; shadow="$(path_without handlr)"
    run env PATH="$shadow" "$XDG_MIME" --help
    [ "$status" -eq 0 ]
    run env PATH="$shadow" "$XDG_MIME" --manual
    [ "$status" -eq 0 ]
}

@test "a broken install (no upstream fallback) reports tool-not-found (3)" {
    run env XDG_UTILS_HANDLR_UPSTREAM=/nonexistent/xdg-mime.upstream \
        "$XDG_MIME" install /dev/null
    [ "$status" -eq 3 ]
}
