# xdg-utils-handlr

**Make `xdg-open` use [handlr](https://github.com/Anomalocaridid/handlr-regex) — without
uninstalling `xdg-utils` and breaking half your system.**

On Arch, roughly 90 packages in `extra` depend on `xdg-utils`. That makes it awkward to
replace: `handlr` is a far nicer way to decide which application opens what, but removing
`xdg-utils` to get out of its way takes LibreOffice, VS Code, Qt, and plenty more with it.

This package is the compromise that actually works. It **satisfies the `xdg-utils` dependency**,
routes `xdg-open` through handlr, and keeps every other `xdg-*` tool byte-for-byte identical to
upstream — because they're the genuine upstream scripts, vendored unchanged.

```console
$ xdg-open notes.md          # resolved by handlr, with your regex rules
$ pacman -Qi libreoffice-fresh | grep Depends
Depends On      : ... xdg-utils ...        # still satisfied, nothing removed
```

## Install

```sh
git clone https://github.com/LeoCalbi/xdg-utils-handlr.git
cd xdg-utils-handlr
makepkg -si
```

`pacman` will offer to replace `xdg-utils`. Say yes — this package declares
`provides=xdg-utils`, so every package that depends on it stays satisfied and **nothing gets
removed**. [`handlr-regex`](https://archlinux.org/packages/extra/x86_64/handlr-regex/) comes
along automatically from `extra`.

> Not on the AUR yet — see [Status](#status).

## What changes, and what doesn't

Only the two tools handlr can genuinely do a better job of are replaced:

| | Backed by | |
| --- | --- | --- |
| `xdg-open` | **handlr** | the whole point |
| `xdg-mime query filetype` / `query default` / `default` | **handlr** | so queries agree with what `xdg-open` actually does |
| `xdg-mime install` / `uninstall` | upstream, unchanged | handlr has no concept of installing MIME definitions |
| `xdg-settings` · `xdg-desktop-menu` · `xdg-desktop-icon` · `xdg-icon-resource` · `xdg-email` · `xdg-screensaver` | upstream, unchanged | handlr has no equivalent at all |

All eight upstream man pages are installed too, so `man xdg-open` and `xdg-open --manual` work
exactly as before.

**Why not put everything on handlr?** Because that's been tried. An earlier AUR package of this
name shimmed `xdg-open` and stubbed out the rest, which broke real software — installers calling
`xdg-mime install` or `xdg-desktop-menu` suddenly did nothing
([chmln/handlr#15](https://github.com/chmln/handlr/issues/15)). It was eventually delisted. The
six vendored scripts here are that lesson, made permanent.

## What you actually get

Everything in `~/.config/handlr/handlr.toml` now applies to `xdg-open`, which means anything
that opens a file or link on your desktop.

**Route by URL pattern, not just MIME type.** Send YouTube links to a video player while every
other link goes to your browser:

```toml
[[handlers]]
exec = "freetube %u"
terminal = false
regexes = ['(https://)?(www\.)?youtu(be\.com|\.be)/*.']
```

**Pick at open time when more than one app fits.** Register several handlers and get a menu
instead of a hardcoded default:

```toml
enable_selector = true
selector = "wofi --dmenu --prompt 'Open With: '"
```

**Read and change defaults without editing `mimeapps.list` by hand:**

```console
$ handlr list                       # everything currently registered
$ xdg-mime query filetype notes.md
text/markdown
$ xdg-mime default helix.desktop text/markdown
```

## Things that behave a little differently

Mixing handlr with the vendored scripts has a handful of sharp edges — MIME detection that
disagrees with plain `xdg-utils` on some file types, `mimeapps.list` written by two different
code paths, `Terminal=true` entries, and the fact that vendored scripts don't receive upstream
bugfixes until this package is rebuilt.

They're all written up, with workarounds, in
**[`docs/EDGE_CASES.md`](docs/EDGE_CASES.md)** — worth a skim before you file a bug.

## Going back

```sh
sudo pacman -S xdg-utils
```

`pacman` will offer to remove `xdg-utils-handlr`; accept, and you're back to stock. Your handlr
config is left alone, so reinstalling later picks up where you left off.

## Status

**Working and in daily use, not yet on the AUR.** Every change is built in a clean Arch
container and run against a 52-test suite that asserts the `xdg-open`/`xdg-mime` command-line
contract — exit codes *and* output — comparing against the real upstream script as an oracle.
Two scheduled jobs watch for breakage from outside the repo: one for new `xdg-utils` releases,
one for new `handlr-regex` releases.

Still to do before an AUR submission: testing on more real desktops than the author's, and a
second pair of eyes on the build. If you want to help, that's the most useful thing.

## Contributing & development

Build instructions, the CI design, testing, and the AUR checklist live in
**[`docs/DEVELOPING.md`](docs/DEVELOPING.md)**.

Bug reports are welcome — please include your handlr version (`handlr --version`), what you ran,
and what you expected.

## License

MIT, for this repository's own shims and `PKGBUILD` — see [`LICENSE`](LICENSE). The vendored
`xdg-utils` scripts and `handlr-regex` are MIT under their own upstream terms.
