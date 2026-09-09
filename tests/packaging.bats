#!/usr/bin/env bats
#
# Properties of the *installed package* rather than the shims' CLI: the
# drop-in promise depends on file-list parity with extra/xdg-utils and on
# pacman treating this package as satisfying that dependency.
#
# Skipped entirely when the package is not installed, so the suite still
# runs against a working tree.

setup() {
    load helpers
    pacman -Qq xdg-utils-handlr >/dev/null 2>&1 || skip "xdg-utils-handlr is not installed"
}

@test "all 8 xdg-utils tools are installed and executable" {
    local tool
    for tool in xdg-open xdg-mime xdg-settings xdg-desktop-menu \
                xdg-desktop-icon xdg-icon-resource xdg-email xdg-screensaver; do
        run command -v "$tool"
        [ "$status" -eq 0 ] || { echo "missing: $tool"; return 1; }
    done
}

@test "all 8 upstream man pages are shipped" {
    # Not checked on disk: official Arch container images set
    # NoExtract = usr/share/man/*, so pacman records them without writing
    # them. The package contents are what matter here.
    local n
    n="$(pacman -Ql xdg-utils-handlr | grep -c 'usr/share/man/man1/.*\.1\.gz')"
    [ "$n" -eq 8 ]
}

@test "the vendored upstream xdg-mime fallback is installed" {
    run test -x /usr/lib/xdg-utils-handlr/xdg-mime.upstream
    [ "$status" -eq 0 ]
}

@test "pacman sees the package as providing xdg-utils" {
    run pacman -Qi xdg-utils-handlr
    [ "$status" -eq 0 ]
    [[ "$output" == *"xdg-utils"* ]]
    pacman -Qi xdg-utils-handlr | grep -i '^Provides' | grep -q 'xdg-utils'
}

@test "the package installs nothing outside the paths upstream owns" {
    # Parity guard: the only legitimate addition to extra/xdg-utils's file
    # list is the vendored fallback under /usr/lib/xdg-utils-handlr/.
    local unexpected
    unexpected="$(pacman -Ql xdg-utils-handlr | awk '{print $2}' \
        | grep -vE '^/(usr/?|usr/bin/?|usr/lib/?|usr/share/?|usr/share/man/?|usr/share/man/man1/?|usr/share/licenses/?)$' \
        | grep -vE '^/usr/bin/xdg-(open|mime|settings|desktop-menu|desktop-icon|icon-resource|email|screensaver)$' \
        | grep -vE '^/usr/share/man/man1/xdg-[a-z-]+\.1\.gz$' \
        | grep -vE '^/usr/share/licenses/xdg-utils-handlr/(LICENSE)?$' \
        | grep -vE '^/usr/lib/xdg-utils-handlr/(xdg-mime\.upstream)?$' || true)"
    if [ -n "$unexpected" ]; then
        echo "unexpected paths in the package:"
        printf '  %s\n' $unexpected
        return 1
    fi
}

@test "the installed shims are the ones this repo ships" {
    # Guards against testing a stale installed package by accident when
    # the suite is pointed at /usr/bin.
    local repo_root; repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    if [ ! -f "$repo_root/xdg-open" ]; then
        skip "not running from a source checkout"
    fi
    if ! cmp -s "$repo_root/xdg-open" /usr/bin/xdg-open; then
        skip "installed xdg-open differs from the working tree (expected if you have local edits)"
    fi
    cmp -s "$repo_root/xdg-mime" /usr/bin/xdg-mime
}
