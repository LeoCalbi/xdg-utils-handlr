# Edge cases and discrepancies: `xdg-utils-handlr` vs. plain `xdg-utils` / plain `handlr-regex`

This document summarizes the known behavioral differences created by mixing
handlr-backed `xdg-open`/`xdg-mime` with vendored upstream scripts for the
rest of the `xdg-utils` toolset.

## A. Split state between handlr and vendored scripts

`handlr` and the vendored `xdg-settings` / `xdg-desktop-menu` / etc. scripts
both read and write `~/.config/mimeapps.list` (and the equivalent system
paths), but via independent code paths with different resolution/priority
logic. Setting a default via `xdg-mime default` (handlr) and via
`xdg-settings set default-web-browser` (vendored) can, in edge cases,
disagree about the current default if the two tools interpret the file's
`[Default Applications]` / `[Added Associations]` sections differently.

**Mitigation:** prefer one tool consistently for a given mimetype/purpose;
avoid mixing `xdg-mime default` / `handlr set` and `xdg-settings set` for
the same association.

## B. `xdg-mime install`/`uninstall` and handlr detection share a database, but not atomically

`xdg-mime install` (vendored) writes an XML description into
`~/.local/share/mime/packages/` (or the system equivalent) and calls
`update-mime-database` to rebuild the compiled cache. `handlr`'s mime
detection (via the `xdg-mime` Rust crate) reads from the same
`$XDG_DATA_HOME/mime` / `$XDG_DATA_DIRS/mime` trees, so a newly installed
MIME type *does* become visible to handlr — but only **after** the
database rebuild completes, and only on handlr's next invocation (no cache
invalidation happens automatically for already-running processes).

**Mitigation:** if a package installer calls `xdg-mime install` and then
immediately depends on `xdg-open`/`handlr` recognizing the new type in the
same script, add a short delay or explicitly confirm via
`xdg-mime query filetype` before proceeding.

## C. `xdg-open`'s single-argument contract vs. handlr's native multi-file support

Real `xdg-open` (and this shim, to stay compatible) accepts exactly one
file/URL argument. `handlr open` natively accepts multiple. Anything that
calls `handlr open` directly (bypassing the `xdg-open` shim) gets
multi-open behavior with no equivalent when going through `xdg-open`.

**Not a bug**, but worth knowing when debugging: `xdg-open a b`
intentionally fails with exit code `1`; `handlr open a b` succeeds.

## D. `Terminal=true` desktop entries

`handlr` resolves `Terminal=true` entries via
`x-scheme-handler/terminal` (or a `TerminalEmulator`-categorised app), and
can run outside interactive terminals. The vendored scripts use the legacy
`xdg-utils` terminal-detection logic, which differs in behavior and in
some cases requires an interactive terminal to work at all. An app
launched via `xdg-open` may therefore behave differently (e.g. spawn a
different terminal emulator, or succeed non-interactively) than the same
`.desktop` entry launched via a code path that uses the vendored scripts.

## E. Multi-handler selector (rofi/dmenu) has no vendored equivalent

`handlr`'s `enable_selector = true` config lets you pick between multiple
registered handlers for one mimetype at runtime. The vendored
`xdg-settings` / `xdg-mime install` scripts have no concept of multiple
candidates — writing a new default via those tools will overwrite/collapse
whatever multi-handler configuration `handlr` was tracking down to a
single entry.

**Mitigation:** if you rely on `handlr`'s multi-handler selector for a
given mimetype, avoid also calling `xdg-settings set` for the same
mimetype.

## F. Version drift / maintenance burden

The vendored `xdg-utils` scripts are pinned to the `pkgver` fetched at
package-build time. Unlike the official `xdg-utils` package, these
vendored copies do **not** automatically receive upstream bugfixes or
security patches via `pacman -Syu` — this package's `pkgver` must be
manually bumped and rebuilt to pick those up.

**Mitigation:** subscribe to [xdg-utils release notifications](https://gitlab.freedesktop.org/xdg/xdg-utils/-/tags)
and periodically diff against the pinned version.

## G. `xdg-icon-resource` / `xdg-desktop-menu` writes are invisible to handlr

These vendored tools write to `~/.local/share/icons`,
`~/.local/share/applications`, etc., which `handlr` does not read for its
own `handlr list` output. This is expected and not risky, but can be
confusing: `handlr list` will not reflect applications installed purely
via `xdg-desktop-menu` / `xdg-icon-resource` unless they are also
registered as a default via `handlr set` / `xdg-mime default`.
