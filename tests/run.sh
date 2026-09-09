#!/bin/sh
# Run the xdg-utils-handlr test suite.
#
#   tests/run.sh                 test the shims in this working tree
#   tests/run.sh --installed     test the shims in /usr/bin
#   tests/run.sh --container     build and test in an Arch container
#
# Working-tree mode needs handlr on PATH; the oracle and packaging tests
# additionally need the package installed, and skip themselves if it is not.
#
# Requires bats (pacman -S bats).

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(dirname -- "$here")
mode=working

for arg in "$@"; do
    case "$arg" in
        --installed) mode=installed ;;
        --container) mode=container ;;
        -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ "$mode" = container ]; then
    engine=$(command -v podman || command -v docker) || {
        echo "need podman or docker for --container mode" >&2; exit 1; }
    work=$(mktemp -d)
    # Copy the sources out rather than mounting the worktree: the build
    # chowns its workspace, which would rewrite ownership of the repo.
    cp "$repo/PKGBUILD" "$repo/.SRCINFO" "$repo/xdg-open" "$repo/xdg-mime" \
       "$repo/xdg-utils-handlr.install" "$work/"
    mkdir -p "$work/tests"
    cp "$here"/*.bats "$here"/helpers.bash "$here"/run.sh "$work/tests/"
    echo "==> building and testing in archlinux:base-devel"
    "$engine" run --rm -v "$work:/pkg" -w /pkg archlinux:base-devel bash -eu -c '
        pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null
        pacman -S  --noconfirm --needed base-devel sudo handlr-regex bats >/dev/null
        useradd -m builder
        echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        chown -R builder:builder /pkg
        su builder -c "makepkg -sf --noconfirm" >/dev/null
        pacman -U --noconfirm ./*.pkg.tar.zst >/dev/null
        exec tests/run.sh --installed
    '
    rc=$?
    # The container wrote as its own uid; clean up through the userns.
    if [ "${engine##*/}" = podman ]; then podman unshare rm -rf "$work" || true
    else rm -rf "$work" || true; fi
    exit "$rc"
fi

command -v bats >/dev/null 2>&1 || {
    echo "bats is not installed (pacman -S bats)" >&2; exit 1; }

if [ "$mode" = installed ]; then
    XDG_OPEN_BIN=$(command -v xdg-open) || { echo "xdg-open not on PATH" >&2; exit 1; }
    XDG_MIME_BIN=$(command -v xdg-mime) || { echo "xdg-mime not on PATH" >&2; exit 1; }
else
    XDG_OPEN_BIN="$repo/xdg-open"
    XDG_MIME_BIN="$repo/xdg-mime"
    [ -x "$XDG_OPEN_BIN" ] && [ -x "$XDG_MIME_BIN" ] || {
        echo "shims not found or not executable in $repo" >&2; exit 1; }
fi
export XDG_OPEN_BIN XDG_MIME_BIN

echo "==> mode:      $mode"
echo "==> xdg-open:  $XDG_OPEN_BIN"
echo "==> xdg-mime:  $XDG_MIME_BIN"
echo "==> oracle:    ${XDG_UTILS_HANDLR_UPSTREAM:-/usr/lib/xdg-utils-handlr/xdg-mime.upstream}"
echo "==> handlr:    $(handlr --version 2>/dev/null || echo 'NOT FOUND')"
echo

exec bats "$here"
