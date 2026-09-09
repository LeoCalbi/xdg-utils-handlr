# Maintainer: Leonardo Calbi <leocalbi@gmail.com>
#
# xdg-utils-handlr
#
# Drop-in replacement for the official `xdg-utils` package that redirects
# `xdg-open` (and, where feasible, `xdg-mime`) to `handlr-regex`, while
# vendoring the unmodified upstream scripts for every xdg-utils tool that
# handlr has no equivalent for (xdg-settings, xdg-desktop-menu,
# xdg-desktop-icon, xdg-icon-resource, xdg-email, xdg-screensaver).
#
# Rationale / sources consulted:
#  - Upstream xdg-utils package contents (8 binaries + man pages):
#    https://archlinux.org/packages/extra/any/xdg-utils/files/
#  - xdg-open(1) synopsis/exit codes:
#    https://man.archlinux.org/man/xdg-open.1.en
#  - handlr-regex README (documented xdg-open shim, `handlr get/set/mime`):
#    https://github.com/Anomalocaridid/handlr-regex
#  - Prior art / known limitation ("doesn't cover all xdg-tools commands"):
#    https://github.com/chmln/handlr/issues/15
#    (AUR xdg-utils-handlr, now delisted, only ever shimmed xdg-open)
#
# This package intentionally does NOT try to reimplement xdg-settings,
# xdg-desktop-menu, xdg-desktop-icon, xdg-icon-resource, xdg-email or
# xdg-screensaver on top of handlr: handlr has no data model or commands
# for any of them (no menu installation, no icon installation, no email
# composition, no screensaver control). Stubbing them out silently is
# exactly the failure mode reported against the old AUR package (e.g.
# breaking `reaper-bin`'s installer). Instead, the genuine upstream
# scripts are vendored unmodified so dependents keep working exactly as
# before.

pkgname=xdg-utils-handlr
pkgver=1.2.1
pkgrel=1
pkgdesc="xdg-utils replacement: xdg-open/xdg-mime redirected to handlr-regex, other tools vendored from upstream xdg-utils"
arch=('any')
url="https://github.com/LeoCalbi/xdg-utils-handlr"
license=('MIT')
depends=('handlr-regex')
makedepends=('xmlto' 'docbook-xsl' 'w3m')
optdepends=(
    'exo: for Xfce support in vendored xdg-screensaver/xdg-email fallbacks'
    'kde-cli-tools: for KDE Plasma support in vendored fallbacks'
    'perl-file-mimeinfo: for generic mimetype support in vendored xdg-mime fallback path'
    'xorg-xprop: for X11 support in xdg-screensaver'
    'xorg-xset: for X11 support in xdg-screensaver'
)
provides=("xdg-utils=${pkgver}")
conflicts=('xdg-utils')
install="${pkgname}.install"
source=(
    "xdg-utils-${pkgver}.tar.gz::https://gitlab.freedesktop.org/xdg/xdg-utils/-/archive/v${pkgver}/xdg-utils-v${pkgver}.tar.gz"
    "xdg-open"
    "xdg-mime"
    "xdg-utils-handlr.install"
)
# Only the remote tarball carries a real checksum. xdg-open, xdg-mime and
# the install hook live in this repo next to the PKGBUILD, so a sum over
# them guarantees nothing -- anyone able to change a shim can change its
# recorded sum in the same commit -- while forcing an `updpkgsums` run
# after every shim edit or makepkg fails with a bogus corruption error.
sha256sums=('f6b648c064464c2636884c05746e80428110a576f8daacf46ef2e554dcfdae75'
            'SKIP'
            'SKIP'
            'SKIP')

build() {
    cd "${srcdir}/xdg-utils-v${pkgver}"
    ./configure --prefix=/usr --mandir=/usr/share/man
    make -C scripts scripts man
}

package() {
    local upstream="${srcdir}/xdg-utils-v${pkgver}"

    # --- Install our handlr-backed replacements -----------------------
    install -Dm755 "${srcdir}/xdg-open" "${pkgdir}/usr/bin/xdg-open"
    install -Dm755 "${srcdir}/xdg-mime" "${pkgdir}/usr/bin/xdg-mime"

    # --- Vendor unmodified upstream scripts for everything handlr does
    #     not (and cannot) implement ------------------------------------
    for tool in xdg-settings xdg-desktop-menu xdg-desktop-icon \
                xdg-icon-resource xdg-email xdg-screensaver; do
        install -Dm755 "${upstream}/scripts/${tool}" "${pkgdir}/usr/bin/${tool}"
    done

    # xdg-mime's fallback path (see xdg-mime shim) shells out to the real
    # upstream script for subcommands handlr can't do (install/uninstall
    # of new mimetype definitions). Ship it alongside, out of $PATH, and
    # have our shim call it explicitly.
    install -Dm755 "${upstream}/scripts/xdg-mime" \
        "${pkgdir}/usr/lib/xdg-utils-handlr/xdg-mime.upstream"

    # --- Man pages (all 8, unmodified, so `man xdg-open` etc. still work)
    for tool in xdg-desktop-icon xdg-desktop-menu xdg-email \
                xdg-icon-resource xdg-mime xdg-open xdg-screensaver \
                xdg-settings; do
        install -Dm644 "${upstream}/scripts/man/${tool}.1" \
            "${pkgdir}/usr/share/man/man1/${tool}.1"
    done

    install -Dm644 "${upstream}/LICENSE" \
        "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
