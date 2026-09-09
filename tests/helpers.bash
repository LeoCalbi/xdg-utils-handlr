# Shared helpers for the xdg-utils-handlr bats suite.
#
# The suite can run against either the shims in a working tree or the ones
# an installed package put in /usr/bin -- see tests/run.sh. Which pair is
# under test comes from XDG_OPEN_BIN / XDG_MIME_BIN.

# Shims under test. These are consumed by the .bats files that `load` this
# file, so the uses are not visible to a linter reading it standalone.
# shellcheck disable=SC2034
XDG_OPEN="${XDG_OPEN_BIN:-xdg-open}"
XDG_MIME="${XDG_MIME_BIN:-xdg-mime}"

# The genuine upstream xdg-mime script, used as a differential oracle.
ORACLE="${XDG_UTILS_HANDLR_UPSTREAM:-/usr/lib/xdg-utils-handlr/xdg-mime.upstream}"

# ---------------------------------------------------------------- assertions

# assert_exit <expected> <command...>
assert_exit() {
    local expected="$1"; shift
    local out rc
    out="$("$@" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" != "$expected" ]; then
        echo "expected exit $expected, got $rc"
        echo "command: $*"
        echo "output : $out"
        return 1
    fi
}

# assert_stdout_is <expected> <command...>  (stderr ignored)
assert_stdout_is() {
    local expected="$1"; shift
    local out
    out="$("$@" 2>/dev/null)"
    if [ "$out" != "$expected" ]; then
        echo "expected stdout [$expected], got [$out]"
        echo "command: $*"
        return 1
    fi
}

# A mimetype must be a single bare token -- no header row, no padding, no
# whitespace -- or callers doing mime=$(xdg-mime query filetype f) break.
assert_is_bare_mimetype() {
    local value="$1"
    if [ "$(printf '%s\n' "$value" | wc -l)" -ne 1 ]; then
        echo "expected one line, got $(printf '%s\n' "$value" | wc -l): [$value]"
        return 1
    fi
    case "$value" in
        *[[:space:]]*) echo "contains whitespace, unusable as one argument: [$value]"; return 1 ;;
        *path*)        echo "contains handlr's table header: [$value]"; return 1 ;;
    esac
    case "$value" in
        */*) ;;
        *) echo "not a type/subtype mimetype: [$value]"; return 1 ;;
    esac
}

# ------------------------------------------------------------------ oracle

have_oracle() { [ -x "$ORACLE" ]; }

skip_without_oracle() {
    have_oracle || skip "upstream oracle not available at $ORACLE"
}

# ------------------------------------------------- degraded environments

# A PATH with every /usr/bin entry symlinked except the named ones, so a
# tool can be made to "not exist" without touching the system. Built once
# per bats run and cached in BATS_SUITE_TMPDIR.
#
#   run env PATH="$(path_without handlr)" "$XDG_MIME" query default text/plain
path_without() {
    local key="$*" dir
    dir="${BATS_SUITE_TMPDIR:-${BATS_TMPDIR:-/tmp}}/shadow-$(printf '%s' "$key" | tr -c 'a-zA-Z0-9' '_')"
    if [ ! -d "$dir" ]; then
        cp -as /usr/bin "$dir" 2>/dev/null || return 1
        local tool
        for tool in "$@"; do rm -f "$dir/$tool"; done
    fi
    printf '%s' "$dir"
}

# handlr panics (SIGABRT, exit 134) when it tries to raise a failure
# notification with no session bus reachable. This reproduces that without
# disturbing the caller's real session.
run_without_dbus() {
    run env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR=/nonexistent "$@"
}
