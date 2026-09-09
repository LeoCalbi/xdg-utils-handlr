# Developing `xdg-utils-handlr`

Maintainer and contributor notes. For what the package is and how to use it, see the
[README](../README.md); for behavioral differences versus plain `xdg-utils`, see
[`EDGE_CASES.md`](EDGE_CASES.md).

## Layout

| Path | What it is |
| --- | --- |
| `PKGBUILD` / `.SRCINFO` | the Arch package definition; `.SRCINFO` is generated, never hand-edited |
| `xdg-open` | POSIX `sh` shim over `handlr open` |
| `xdg-mime` | POSIX `sh` shim over `handlr mime`/`get`/`set`, falling back to the vendored upstream script |
| `xdg-utils-handlr.install` | pacman post-install/upgrade message |
| `docs/EDGE_CASES.md` | behavioral divergence analysis (user-facing) |
| `tests/` | bats test suite; see [Testing](#testing). Not shipped to the AUR |
| `.github/workflows/` | CI (three workflows, see below) |

Everything else in a working tree — `src/`, `pkg/`, `*.pkg.tar.zst`, the upstream tarball — is
build output and gitignored.

## Building

```sh
makepkg -sf                             # build (installs makedepends via sudo)
makepkg -si                             # build and install
makepkg --printsrcinfo > .SRCINFO       # regenerate .SRCINFO after any PKGBUILD change
namcap PKGBUILD && namcap ./*.pkg.tar.zst
shellcheck -s sh xdg-open xdg-mime tests/run.sh
shellcheck -s bash tests/helpers.bash
tests/run.sh --installed                # the behavioral suite (see Testing)
```

Commit `PKGBUILD` and `.SRCINFO` together — CI fails if they disagree.

Two `namcap` warnings on the built package are **known false positives**:

- *Referenced library 'sh' is an uninstalled dependency* — the shims use `#!/bin/sh`, provided
  by `bash` in `base`, which namcap doesn't model.
- *Dependency included, but may not be needed ('handlr-regex')* — namcap only inspects library
  links, never shell-level `command -v handlr` / `handlr open` calls.

`namcap` exits `0` even when it reports problems, so CI greps for `' E: '` rather than trusting
its exit status. Bear that in mind when running it by hand.

## The two contracts that must not break

Everything else is detail; these two are why the package works at all.

**1. File-list parity with `extra/xdg-utils`.** Every path the official package installs must be
installed here too — 8 binaries, 8 man pages, the license. The only legitimate addition is
`/usr/lib/xdg-utils-handlr/xdg-mime.upstream`. Verify with:

```sh
pacman -Ql xdg-utils-handlr | awk '{print $2}' | sed 's|^/||' | sort
# compare against https://archlinux.org/packages/extra/any/xdg-utils/files/
```

**2. Command-line fidelity of the shims — exit codes *and* stdout.** Documented codes are `0`
ok, `1` syntax error, `2` file not found, `3` required tool missing, `4` action failed, and for
`xdg-mime` also `5` permission denied. Callers parse stdout, so
`mime=$(xdg-mime query filetype "$f")` must yield a bare mimetype and nothing else.

The genuine upstream script ships alongside precisely so it can be used as an oracle:

```sh
/usr/lib/xdg-utils-handlr/xdg-mime.upstream query filetype FILE
```

**Match upstream's observed behavior, not its man page.** Two bugs here came from writing to the
documented synopsis: upstream `xdg-mime query filetype` silently *ignores* extra arguments rather
than erroring, and prints nothing while exiting `0` when no default is set. Being stricter than
upstream breaks callers that upstream tolerated — the exact failure this package exists to
prevent. Run the oracle; don't infer.

## handlr quirks the shims work around

Both are load-bearing. Don't "simplify" them away.

**`handlr mime` output is not upstream-compatible.** It prints a padded table with a
`path`/`mime` header row. `--json` is handlr's documented output contract; the table is display
formatting whose padding can change between releases. Parse the JSON.

**handlr aborts on its own error path without a D-Bus session.** `get`, `open` and `set` try to
raise a desktop notification when they fail, and issuing it panics (`SIGABRT`, exit `134`) when
no session bus is reachable — a pacman hook, a systemd unit, cron, SSH, a container build. So
every handlr call passes `-n`. But a handlr run with `-n` then **exits 0 even when it failed**,
so the shims judge success from output rather than exit status: non-empty stderr means failure,
mapped to exit `4`. `xdg-open` routes the child's stdout to the real stdout through a saved file
descriptor (`exec 3>&1` … `2>&1 1>&3 3>&-`) so a `Terminal=true` handler still reaches the
terminal while stderr is captured. Full detail in [`EDGE_CASES.md`](EDGE_CASES.md) section I.

## Why the local sources use `sha256sums=SKIP`

`xdg-open`, `xdg-mime` and `xdg-utils-handlr.install` are `source=()` entries with `SKIP`.
They live in this repo beside the `PKGBUILD`, so a checksum over them guarantees nothing —
anyone able to change a shim can change its recorded sum in the same commit — while forcing an
`updpkgsums` run after every edit, or `makepkg` fails with what reads like a corrupt-download
error. Only the remote upstream tarball carries a real checksum.

Consequence: **editing a shim needs no `updpkgsums`.** A `pkgver` bump still does.

## CI

Three workflows — see [What guards what](#what-guards-what) for which threat each covers. The
governing principle, learned the hard way:

> **The container is for what needs Arch. The host runner is for what needs git and GitHub.**

`archlinux:base-devel` ships **no `git`**, and `actions/checkout` silently degrades to a
REST-API tarball download — producing no `.git` directory and no push credentials — when git
≥ 2.18 is missing from `PATH`. Installing git in the first `run` step is too late; the checkout
already happened. Symptoms are `fatal: not a git repository`, which looks nothing like the
actual cause and sent this repo on a multi-commit detour through `safe.directory` and ownership
fixes that were treating a non-problem.

**`build-and-test.yml`** — pushes to `main`, pull requests, manual. This one genuinely wants to
*be* inside Arch (it builds and installs a pacman package), so it keeps
`container: archlinux:base-devel` and installs git **before** `actions/checkout`. It runs
`shellcheck`, `namcap` on both the PKGBUILD and the built package, the `.SRCINFO` sync check,
and then `tests/run.sh --installed`. The behavioral assertions live in `tests/`, not inline in
the workflow, so CI runs exactly what a contributor runs locally.

**`check-upstream-version.yml`** — Mondays 06:00 UTC, or manual. Runs on the **host**
(`runs-on: ubuntu-latest`, no `container:`) so git, Node actions and the token all behave
normally, and reaches into Arch via an explicit `docker run` for just `updpkgsums` and
`makepkg --printsrcinfo`. It polls the `gitlab.freedesktop.org` API for the newest `vX.Y.Z` tag
of `xdg/xdg-utils` and, if it's newer than `pkgver`, opens a PR — falling back to an
`upstream-update` issue if the PR can't be created. The container writes as its own uid, so the
tree is `chown`ed back to the runner user before any git step.

**`handlr-drift.yml`** — Wednesdays 06:00 UTC, or manual. Rebuilds `main` in Arch against
whatever `handlr-regex` is currently in `extra` and runs the suite, opening (or commenting on) an
issue labeled `handlr-drift` if it fails. Offset from Monday so a failure is attributable to one
workflow at a time.

There is deliberately **no checksum-refresh workflow**; `SKIP` removed the job it existed to do.

### Known CI limitation

GitHub does not run `pull_request` workflows on PRs opened with the default `GITHUB_TOKEN`, so
the weekly auto-bump PR lands without `build-and-test` having run *on the PR itself*. This is
handled by having `check-upstream-version.yml` build and run the suite before opening the PR
and state the outcome in the body, so the information is never missing — but the PR's own checks
list stays empty.

If you'd rather see real check runs on those PRs, supply a fine-grained PAT
(`contents:write` + `pull-requests:write`) as a repo secret and use it in place of
`secrets.GITHUB_TOKEN`. Pushing an empty commit to the branch also triggers CI.

## Testing

The suite is [bats](https://github.com/bats-core/bats-core) (`pacman -S bats`) and lives in
`tests/`. 52 tests, no runtime dependencies added to the package — `bats` is a developer tool
only, and `tests/` is not shipped to the AUR.

```sh
tests/run.sh                # test the shims in this working tree
tests/run.sh --installed    # test the shims in /usr/bin
tests/run.sh --container    # build and test in an Arch container, start to finish
```

| File | Covers |
| --- | --- |
| `contract_xdg_open.bats` | `xdg-open`'s documented exit codes, URI handling, degraded modes |
| `contract_xdg_mime.bats` | `xdg-mime`'s subcommands, exit codes, and bare-mimetype output |
| `oracle.bats` | differential comparison against the vendored upstream script |
| `packaging.bats` | installed-package properties: file-list parity, `provides`, man pages |
| `helpers.bash` | assertions plus the two degraded-environment helpers below |

Tests that need something unavailable skip themselves rather than fail, so working-tree mode
still runs the contract tests with no package installed.

### Testing degraded environments without breaking your system

Two helpers in `helpers.bash` reproduce the conditions behind the worst bugs this package has
had, non-destructively:

- **`path_without <tool>`** builds a symlink farm of `/usr/bin` (via `cp -as`, ~12 ms) with the
  named tools removed, and returns it for use as `PATH`. That makes `handlr` or `man` "not
  installed" for one command without touching pacman. It's how the suite verifies that
  `xdg-mime install` still works when handlr is missing, and that `--manual` degrades instead
  of dying with man's exit 16.
- **`run_without_dbus`** runs a command with `DBUS_SESSION_BUS_ADDRESS` unset and
  `XDG_RUNTIME_DIR` pointed at a nonexistent path, reproducing the session-bus-less environment
  where raw handlr aborts with `SIGABRT`. The assertions require the documented exit codes and
  explicitly reject `134`.

### What guards what

Three workflows, covering three different sources of breakage:

| Workflow | Guards against | When |
| --- | --- | --- |
| `build-and-test.yml` | changes made in this repo | every push and PR |
| `check-upstream-version.yml` | a new `xdg-utils` release changing vendored behavior | weekly, Mondays |
| `handlr-drift.yml` | a new `handlr-regex` release changing output or exit codes | weekly, Wednesdays |

That last one matters more than it looks: the two most serious bugs found so far were *handlr*
behaviors, not ours — `handlr mime` printing a padded table where a bare mimetype was expected,
and handlr aborting on its own error path without D-Bus. Nothing in a PR-triggered workflow
would ever have caught either. It rebuilds `main` against whatever `handlr-regex` is currently
in `extra` and opens (or comments on) an issue labeled `handlr-drift` when the suite fails.

`check-upstream-version.yml` runs the suite itself, before opening its PR, and reports the
result in the PR body. That's deliberate: GitHub does not run `pull_request` workflows on PRs
created with the default `GITHUB_TOKEN`, so an upstream release that broke the shims would
otherwise land in a PR that merely *looks* untested.

## Local verification in a container

Reproducing CI locally is the fastest way to check a change, and catches things a desktop can't
— the D-Bus panic above was only ever visible in a bare container.

```sh
mkdir -p /tmp/ct && cp PKGBUILD .SRCINFO xdg-open xdg-mime xdg-utils-handlr.install /tmp/ct/
podman run --rm -v /tmp/ct:/pkg -w /pkg archlinux:base-devel bash -c '
  pacman -Sy --noconfirm --needed archlinux-keyring
  pacman -S  --noconfirm --needed base-devel sudo handlr-regex
  useradd -m builder && chown -R builder /pkg
  su builder -c "makepkg -sf --noconfirm"
  pacman -U --noconfirm ./*.pkg.tar.zst
  xdg-mime query filetype /etc/hostname
'
```

Two traps worth knowing:

- **Copy the sources out; never mount the git worktree read-write.** The build `chown`s its
  workspace, which rewrites ownership of your actual repo to a container subuid and leaves git
  refusing to operate (`detected dubious ownership`). Recovery, under rootless podman:
  `podman unshare chown -R 0:0 <repo>`.
- **Official Arch images set `NoExtract = usr/share/man/*`**, so man pages are recorded by
  pacman but never written to disk. `man xdg-open` therefore fails in-container for reasons that
  have nothing to do with this package. Delete that line from `/etc/pacman.conf` and reinstall
  if you need to test `--manual`'s man-page path.

## Toward the AUR

- [x] Checksum maintenance eliminated as a class of problem (`SKIP` on local sources).
- [x] `namcap` clean on both PKGBUILD and built package, modulo the two false positives above.
- [x] `url=` and clone URL point at `LeoCalbi/xdg-utils-handlr`.
- [x] `PACKAGER` set in `~/.config/pacman/makepkg.conf`, so builds carry a real maintainer
      string instead of `Unknown Packager`.
- [ ] Manual testing on real Arch installs beyond the author's:
  - [ ] `xdg-open` opens files and URLs correctly in a real desktop session (GNOME/KDE/Sway/…)
  - [ ] `xdg-settings get/set default-web-browser` still works via the vendored script
  - [ ] a real-world installer that calls `xdg-mime install` completes successfully
  - [ ] replacing `xdg-utils` removes none of its ~90 dependents
- [ ] At least one other person test-builds the package, per AUR guidance to seek review before
      submission.
- [ ] Submit:

  ```sh
  git clone ssh://aur@aur.archlinux.org/xdg-utils-handlr.git aur-xdg-utils-handlr
  cp PKGBUILD .SRCINFO aur-xdg-utils-handlr/
  cd aur-xdg-utils-handlr
  git add PKGBUILD .SRCINFO
  git commit -m "Initial import"
  git push origin master
  ```

  Only `PKGBUILD` and `.SRCINFO` go to the AUR — not the tests, docs or workflows.

## Commit conventions

Conventional Commits with the gitmoji **after** the `type(scope):` prefix, chosen for what the
change does rather than mechanically from the type:

```
feat(pkg): ✨ …      fix(shim): 🐛 …      ci: 👷 …      ci: 💚 …      docs: 📝 …
```

Scopes in use: `pkg` for packaging, `shim` for the `xdg-open`/`xdg-mime` scripts.
