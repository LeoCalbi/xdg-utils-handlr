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

`xdg-mime query filetype a b` behaves differently again — it uses `a` and
**ignores** `b`, exiting `0`. That asymmetry is intentional: each shim
matches what its own upstream counterpart does. Upstream `xdg-open` rejects
extra arguments, while upstream `xdg-mime` reads only its `FILE` argument
and never looks at the rest. Being stricter than upstream would break a
caller that upstream tolerated, which is the failure mode this package
exists to avoid.

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

## H. MIME *detection* differs from upstream, in both directions

`xdg-mime query filetype` is answered by `handlr mime`, not by upstream's
detection logic (`mimetype` from `perl-file-mimeinfo`, falling back to
`file --mime-type`). The two read the same `shared-mime-info` database but
weight extension and content sniffing differently, so they disagree on a
meaningful fraction of inputs — measured against handlr-regex 0.13.0:

| file           | this package (handlr) | plain `xdg-utils`        |
| -------------- | --------------------- | ------------------------ |
| `notes.md`     | `text/markdown`       | `text/plain`             |
| `data.json`    | `text/plain`          | `application/json`       |
| `image.png`    | `image/png`           | `text/plain`             |
| `main.c`       | `text/x-csrc`         | `text/x-c`               |
| empty file     | `application/x-zerosize` | `inode/x-empty`       |
| `a.txt`, `b.sh`, `c.html`, `d.pdf` | *(agree)* | *(agree)*   |

This is **deliberate, and the divergence is the correct choice.** handlr is
what resolves the handler for `xdg-open`, so `query filetype` has to report
handlr's view for the canonical idiom to work:

```sh
xdg-mime default myapp.desktop "$(xdg-mime query filetype notes.md)"
```

Reporting upstream's `text/plain` there would register the handler under a
mimetype `xdg-open` never consults — a silent misconfiguration strictly
worse than the disagreement itself. The cost is that a script comparing
`xdg-mime query filetype` output against a hardcoded expectation may see a
different (usually more specific) type than it did under plain `xdg-utils`.

**Mitigation:** compare mimetypes, don't hardcode them; if a script needs
upstream's answer specifically, call
`/usr/lib/xdg-utils-handlr/xdg-mime.upstream query filetype FILE` directly.

Note that `query filetype` also accepts URLs (`https://…` →
`x-scheme-handler/https`), which plain `xdg-utils` rejects with exit 2.
That is a superset, not a divergence.

## I. handlr aborts on its own error path when there is no D-Bus session

Up to and including handlr-regex 0.13.0, `handlr get`, `handlr open` and
`handlr set` raise a desktop notification when they fail — and if no session
bus is reachable, issuing that notification **panics**:

```
thread 'main' panicked at src/logging.rs:93:14:
handlr error: Could not issue dbus notification: ... NotFound ...
Aborted (core dumped)          # exit 134
```

That is the normal situation inside a `pacman` install hook, a systemd unit,
a cron job, an SSH session or a container build — precisely where package
installers call `xdg-mime`. An abort there is much worse than a wrong
answer, so the shims work around it: every handlr invocation passes
`-n`/`--disable-notifications`.

`-n` alone would trade the crash for a lie, because a handlr run with `-n`
**exits 0 even when it failed**. The shims therefore judge success from
handlr's output rather than its exit status:

- `xdg-open` and `xdg-mime default` capture stderr and map non-empty stderr
  to exit `4` ("action failed"). `stdout` is passed through untouched via a
  saved file descriptor, so a `Terminal=true` handler still reaches the
  terminal.
- `xdg-mime query default` treats empty stdout as "no default set" and exits
  `0`, which is exactly what plain `xdg-utils` does, and drops handlr's
  "No handlers found" diagnostic so the case stays as quiet as upstream.

**Mitigation / caveat:** keying failure detection off stderr is inference,
not a contract — a change to handlr's log format could weaken it. The
`build-and-test` workflow therefore asserts the documented exit codes for
every no-handler path and fails explicitly on exit `134`, so a regression
here surfaces in CI rather than in someone's install script. There is no
config-file equivalent for `-n` in 0.13.0, and setting a bogus
`DBUS_SESSION_BUS_ADDRESS` does not avoid the panic.
