# xdg-utils-handlr

A drop-in replacement for Arch Linux's `xdg-utils` package that redirects
`xdg-open` and the query/set-default parts of `xdg-mime` to
[`handlr-regex`](https://github.com/Anomalocaridid/handlr-regex), while
vendoring the **unmodified upstream `xdg-utils` scripts** for every tool
handlr has no equivalent for.

This lets you replace `xdg-open`'s default-app resolution with handlr's
faster, more configurable engine (including regex-based handlers) without
uninstalling `xdg-utils` and breaking the ~90 packages in the Arch `extra`
repo that depend on it.

## Status

**Testing / pre-AUR.** This repository exists to validate the package on
real machines and via CI before it is submitted to the AUR. See
[Roadmap](#roadmap-toward-aur) below.

## What's replaced vs. vendored

| Tool                                                    | Backend                                                        |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| `xdg-open`                                              | **handlr** (`handlr open`)                                     |
| `xdg-mime query filetype` / `query default` / `default` | **handlr** (`handlr mime` / `handlr get` / `handlr set`)       |
| `xdg-mime install` / `uninstall`                        | **vendored upstream** `xdg-mime` script (no handlr equivalent) |
| `xdg-settings`                                          | **vendored upstream**, unmodified                              |
| `xdg-desktop-menu`                                      | **vendored upstream**, unmodified                              |
| `xdg-desktop-icon`                                      | **vendored upstream**, unmodified                              |
| `xdg-icon-resource`                                     | **vendored upstream**, unmodified                              |
| `xdg-email`                                             | **vendored upstream**, unmodified                              |
| `xdg-screensaver`                                       | **vendored upstream**, unmodified                              |

All 8 upstream man pages are installed unmodified so `man xdg-open`, `xdg-open --manual`, etc. keep working.

### Why not replace everything with handlr?

`handlr` only implements default-application resolution (open/get/set/mime).
It has no data model or commands for MIME-type installation, desktop menu
entries, desktop icons, icon resources, email composition, or screensaver
control. A prior AUR package (`xdg-utils-handlr`, since delisted) tried a
handlr-only replacement and broke installers that called the other
`xdg-utils` tools (see
[chmln/handlr#15](https://github.com/chmln/handlr/issues/15)). This package
avoids that failure mode by vendoring the real scripts for anything handlr
doesn't cover.

## Requirements

- Arch Linux (or an Arch-based distro using `pacman`)
- [`handlr-regex`](https://aur.archlinux.org/packages/handlr-regex) (pulled in automatically as a `depends`)

## Installing (from this repo, pre-AUR)

```sh
git clone https://github.com/LeoCalbi/xdg-utils-handlr.git
cd xdg-utils-handlr
makepkg -si
```

`makepkg` will:

1. Download the pinned upstream `xdg-utils` source tarball from
   `gitlab.freedesktop.org` (version matches Arch's `extra/xdg-utils`).
2. Install the handlr-backed `xdg-open` and `xdg-mime` shims.
3. Vendor the unmodified upstream scripts for the remaining 6 tools.
4. Offer to remove the conflicting `xdg-utils` package (since this
   package declares `provides=('xdg-utils')` + `conflicts=('xdg-utils')`,
   pacman treats the requirement as satisfied for all dependents).

## Uninstalling / reverting to plain xdg-utils

```sh
sudo pacman -S xdg-utils --overwrite '*'
```

or simply:

```sh
sudo pacman -R xdg-utils-handlr
sudo pacman -S xdg-utils
```

## Automated maintenance (CI)

Two extra workflows, on top of `build-and-test.yml`, keep this package from
going stale:

- **`check-upstream-version.yml`** — runs weekly (Mondays 06:00 UTC, or
  on-demand via "Run workflow"). It queries the
  [`xdg/xdg-utils` GitLab API](https://gitlab.freedesktop.org/xdg/xdg-utils/-/tags)
  for the latest tag, and if it's newer than the `pkgver` in `PKGBUILD`:
  bumps `pkgver`, resets `pkgrel=1`, recomputes `sha256sums` with
  `updpkgsums`, regenerates `.SRCINFO`, and opens a pull request for
  review. If the PR step fails for any reason, it falls back to opening
  (or reusing) a tracking issue labeled `upstream-update` so the release
  is never silently missed.
- **`update-sha256sums.yml`** — runs on every pull request that touches
  `PKGBUILD`, `xdg-open`, or `xdg-mime`. It re-runs `updpkgsums` and
  regenerates `.SRCINFO`, then pushes a fixup commit onto the PR branch if
  anything drifted. This means contributors never have to remember to run
  `updpkgsums` by hand before merging (skipped on PRs from forks, since
  the default token can't push to a fork's branch — the `build-and-test`
  `.SRCINFO`-sync check will still fail loudly in that case instead).

Both workflows require the repo's default `GITHUB_TOKEN` to have write
access to contents/PRs/issues (Settings → Actions → General → Workflow
permissions → "Read and write permissions").

## Known edge cases

See [`docs/EDGE_CASES.md`](docs/EDGE_CASES.md) for a full analysis of
behavioral discrepancies versus plain `xdg-utils` or plain `handlr-regex`
(mimeapps.list write races, multi-handler selector interaction with
vendored tools, terminal-entry handling differences, and version-drift
risk from vendoring).

## Roadmap toward AUR

- [x] `updpkgsums` is now run automatically by CI (see
      [Automated maintenance](#automated-maintenance-ci) above) and the
      initial `sha256sums` have been generated locally against the pinned
      upstream tarball.
- [x] `namcap PKGBUILD` and `namcap *.pkg.tar.zst` both pass cleanly
      (only two known false positives on the built package: `sh` shebangs
      against `bash` in `base`, and `handlr-regex` flagged as
      possibly-unused because namcap only inspects library links, not
      shell-level `command -v` / `handlr open` calls).
- [x] `url=` in `PKGBUILD` and the clone URL in
      [Installing (from this repo, pre-AUR)](#installing-from-this-repo-pre-aur)
      now point at `https://github.com/LeoCalbi/xdg-utils-handlr`.
- [x] `PACKAGER` is set in `~/.config/pacman/makepkg.conf` so built
      packages carry a real maintainer string instead of
      `Unknown Packager` in `pacman -Qi`.
- [ ] (Optional) Provide a fine-grained PAT as `secrets.CI_PAT` (or
      similar) and swap it into
      [`check-upstream-version.yml`](.github/workflows/check-upstream-version.yml)
      in place of `secrets.GITHUB_TOKEN`. GitHub intentionally does not
      re-trigger `pull_request` workflows on PRs opened by the default
      `GITHUB_TOKEN`, so the weekly auto-bump PR currently lands without
      `build-and-test` running against it. A PAT with `contents:write` +
      `pull-requests:write` scopes on this repo restores CI on those PRs.
- [ ] Manual testing on a real Arch install (not just the CI container):
      - [ ] Confirm `xdg-open` correctly opens files/URLs via handlr on a
            real desktop session (GNOME/KDE/Sway/etc.)
      - [ ] Confirm `xdg-settings get/set default-web-browser` still works
            via the vendored script
      - [ ] Confirm at least one real-world installer that calls
            `xdg-mime install` (e.g. an AUR package bundling a custom
            MIME type) completes successfully
      - [ ] Confirm removing `xdg-utils` and installing this package
            does not trigger removal of any of the ~90 dependent packages
- [ ] Open an issue upstream in `handlr-regex` referencing this package
      as prior art / feature request for native `install`/`uninstall`
      and `xdg-settings` support, per the discussion in
      [chmln/handlr#15](https://github.com/chmln/handlr/issues/15).
- [ ] Have at least one other person test-build via the CI artifact or
      locally, per AUR guidance to seek review before submission.
- [ ] Submit to AUR:
      ```sh
      git clone ssh://aur@aur.archlinux.org/xdg-utils-handlr.git aur-xdg-utils-handlr
      cp PKGBUILD .SRCINFO aur-xdg-utils-handlr/
      cd aur-xdg-utils-handlr
      git add PKGBUILD .SRCINFO
      git commit -m "Initial import"
      git push origin master
      ```

## License

- This repository's own shim scripts (`xdg-open`, `xdg-mime`) and
  `PKGBUILD`: MIT (see [`LICENSE`](LICENSE)).
- Vendored `xdg-utils` scripts: MIT, per upstream
  (see `/usr/share/licenses/xdg-utils-handlr/LICENSE` after install).
- `handlr-regex` itself: MIT, per its own repository.
