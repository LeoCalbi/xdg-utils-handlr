#!/usr/bin/env bats
#
# Differential tests against the genuine upstream xdg-mime script, which
# this package vendors at /usr/lib/xdg-utils-handlr/xdg-mime.upstream
# precisely so it can serve as an oracle.
#
# These are the tests that catch an upstream xdg-utils release changing
# behavior the shim is supposed to mirror. Where handlr and upstream
# legitimately disagree (MIME *detection* -- see docs/EDGE_CASES.md section
# H) the assertion is on the response *shape*, not the value.

setup_file() {
    load helpers
    export FIXTURES="$BATS_FILE_TMPDIR/fixtures"
    mkdir -p "$FIXTURES"
    echo "plain text"                 > "$FIXTURES/a.txt"
    printf '#!/bin/sh\necho hi\n'     > "$FIXTURES/b.sh"
    echo '<html><body>x</body></html>'> "$FIXTURES/c.html"
    printf '%%PDF-1.4\n'              > "$FIXTURES/d.pdf"
    echo "no extension"               > "$FIXTURES/noext"
}

setup() {
    load helpers
    FIXTURES="$BATS_FILE_TMPDIR/fixtures"
    skip_without_oracle
}

@test "oracle is present and executable" {
    [ -x "$ORACLE" ]
}

@test "query filetype output has the same SHAPE as upstream for every fixture" {
    # Both must emit exactly one bare mimetype token. Values may differ
    # (section H); the shape must not.
    local f ours theirs
    for f in "$FIXTURES"/*; do
        ours="$("$XDG_MIME" query filetype "$f" 2>/dev/null)"
        theirs="$("$ORACLE" query filetype "$f" 2>/dev/null)"
        assert_is_bare_mimetype "$ours"
        run assert_is_bare_mimetype "$theirs"
        [ "$status" -eq 0 ] || skip "upstream itself gave an odd answer for $f: [$theirs]"
        echo "$(basename "$f"): ours=$ours upstream=$theirs"
    done
}

@test "query filetype agrees with upstream on unambiguous plain text" {
    local f="$FIXTURES/a.txt"
    assert_stdout_is "$("$ORACLE" query filetype "$f")" "$XDG_MIME" query filetype "$f"
}

@test "query filetype matches upstream exit code for a missing file" {
    local ours theirs
    "$XDG_MIME" query filetype /nonexistent/nope >/dev/null 2>&1 && ours=0 || ours=$?
    "$ORACLE"   query filetype /nonexistent/nope >/dev/null 2>&1 && theirs=0 || theirs=$?
    [ "$ours" -eq "$theirs" ]
    [ "$ours" -eq 2 ]
}

@test "query filetype matches upstream exit code for an unreadable file" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root bypasses file permission bits"
    fi
    local f="$BATS_TEST_TMPDIR/secret"
    : > "$f"; chmod 000 "$f"
    local ours theirs
    "$XDG_MIME" query filetype "$f" >/dev/null 2>&1 && ours=0 || ours=$?
    "$ORACLE"   query filetype "$f" >/dev/null 2>&1 && theirs=0 || theirs=$?
    [ "$ours" -eq "$theirs" ]
    [ "$ours" -eq 5 ]
}

@test "query filetype matches upstream's tolerance of extra arguments" {
    local ours theirs
    "$XDG_MIME" query filetype "$FIXTURES/a.txt" /etc/hostname >/dev/null 2>&1 && ours=0 || ours=$?
    "$ORACLE"   query filetype "$FIXTURES/a.txt" /etc/hostname >/dev/null 2>&1 && theirs=0 || theirs=$?
    [ "$ours" -eq "$theirs" ]
}

@test "query default matches upstream when no default is set" {
    local mime="application/x-xdg-utils-handlr-nonexistent"
    local ours theirs ours_rc theirs_rc
    ours="$("$XDG_MIME" query default "$mime" 2>/dev/null)" && ours_rc=0 || ours_rc=$?
    theirs="$("$ORACLE" query default "$mime" 2>/dev/null)" && theirs_rc=0 || theirs_rc=$?
    [ "$ours_rc" -eq "$theirs_rc" ]
    [ "$ours" = "$theirs" ]
    [ -z "$ours" ]
}

@test "upstream's help surface still uses the exit codes we mirror" {
    # If an upstream release changed these, the shim's own codes would
    # silently diverge from the vendored scripts shipped beside it.
    assert_exit 0 "$ORACLE" --help
    assert_exit 1 "$ORACLE"
    assert_exit 1 "$ORACLE" query bogus
}

@test "upstream still accepts the install/uninstall syntax the shim hands off" {
    run "$ORACLE" install
    [ "$status" -eq 1 ]
    [[ "$output" == *mimetypes-file* ]]
    run "$ORACLE" uninstall
    [ "$status" -eq 1 ]
    [[ "$output" == *mimetypes-file* ]]
}

@test "install then uninstall a real mimetype definition round-trips" {
    local xml="$BATS_TEST_TMPDIR/x-handlr-test.xml"
    cat > "$xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-xdg-utils-handlr-test">
    <comment>xdg-utils-handlr test type</comment>
    <glob pattern="*.xuhtest"/>
  </mime-type>
</mime-info>
EOF
    run "$XDG_MIME" install --novendor "$xml"
    [ "$status" -eq 0 ]
    run "$XDG_MIME" uninstall "$xml"
    [ "$status" -eq 0 ]
}
