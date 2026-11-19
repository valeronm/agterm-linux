#!/usr/bin/env bash
# Build agterm-linux in Release, stage the payload, and install it through the host's package manager:
# a pacman package through packaging/arch-local on Arch, a DEB built from packaging/linux/nfpm.yml on
# Debian and Ubuntu. Requires the mise toolchain and a vendored libghostty (scripts/setup-linux.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(id -u)" -eq 0 ]]; then
  echo "run as your user; the package manager asks for sudo itself" >&2
  exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*)
    format=pacman
    command -v makepkg >/dev/null || { echo "makepkg not found" >&2; exit 1; }
    ;;
  *" debian "*)
    format=deb
    NFPM="$(mise which nfpm 2>/dev/null)" || { echo "nfpm not found; run mise install" >&2; exit 1; }
    ;;
  *)
    echo "no package format for ${PRETTY_NAME:-this distribution}; use scripts/install-linux.sh" >&2
    exit 1
    ;;
esac

SWIFT_HOME="$(mise where swift 2>/dev/null || echo "$HOME/.local/share/mise/installs/swift/6.3.2")"
export PATH="$SWIFT_HOME/usr/bin:$PATH"
COMPAT="$(sh scripts/linux-swift-compat.sh)"
export LD_LIBRARY_PATH="$COMPAT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Commits past the tag go into build metadata so a DEB sorts them after the tagged release; a pacman
# pkgver allows neither a hyphen nor a plus.
describe="$(git describe --tags --match 'linux-v*' --long)"
release="$(sed -E 's/^linux-v//; s/-[0-9]+-g[0-9a-f]+$//' <<<"$describe")"
build="$(sed -E 's/.*-([0-9]+)-g([0-9a-f]+)$/r\1.g\2/' <<<"$describe")"
if [[ "$release" == *+* ]]; then version="$release.$build"; else version="$release+$build"; fi
export AGTERM_PACKAGE_VERSION="$version"

( cd agterm-linux && swift build -c release )

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
scripts/stage-linux.sh "$WORK/stage/agterm-linux"

case "$format" in
  pacman)
    tar czf "$WORK/agterm-linux-local.tar.gz" -C "$WORK/stage" agterm-linux
    cp LICENSE "$WORK/LICENSE"
    cd packaging/arch-local
    AGTERM_LOCAL_PKGVER="${version//[+-]/.}" SRCDEST="$WORK" BUILDDIR="$WORK" PKGDEST="$WORK" makepkg -si --cleanbuild
    ;;
  deb)
    # shellcheck source=../linux/arch.sh
    source linux/arch.sh
    AGTERM_PACKAGE_ROOT="$WORK/stage/agterm-linux" AGTERM_PACKAGE_ARCH="$PACKAGE_ARCH" \
      "$NFPM" package --config packaging/linux/nfpm.yml --packager deb --target "$WORK/agterm-linux.deb"
    # apt reads a local package as its unprivileged _apt user, which cannot enter mktemp's 0700 directory.
    chmod 755 "$WORK"
    # A rebuild of an unchanged commit carries the installed version, which apt would otherwise skip.
    sudo apt install --reinstall "$WORK/agterm-linux.deb"
    ;;
esac
