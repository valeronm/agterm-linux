#!/usr/bin/env bash
# Build agterm-linux in Release, stage the payload, and install it as a pacman package through
# packaging/arch-local. Requires the mise toolchain and a vendored libghostty (scripts/setup-linux.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(id -u)" -eq 0 ]]; then
  echo "run as your user; makepkg refuses root and pacman asks for sudo itself" >&2
  exit 1
fi

SWIFT_HOME="$(mise where swift 2>/dev/null || echo "$HOME/.local/share/mise/installs/swift/6.3.2")"
export PATH="$SWIFT_HOME/usr/bin:$PATH"
COMPAT="$(sh scripts/linux-swift-compat.sh)"
export LD_LIBRARY_PATH="$COMPAT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# pkgver allows no hyphen, so linux-v0.41.1-4-gabc1234 becomes 0.41.1.r4.gabc1234.
describe="$(git describe --tags --match 'linux-v*' --long)"
pkgver="$(sed -E 's/^linux-v//; s/\+/./g; s/-([0-9]+)-g/.r\1.g/' <<<"$describe")"

( cd agterm-linux && swift build -c release )

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
AGTERM_PACKAGE_VERSION="$pkgver" scripts/stage-linux.sh "$WORK/stage/agterm-linux"
tar czf "$WORK/agterm-linux-local.tar.gz" -C "$WORK/stage" agterm-linux
cp LICENSE "$WORK/LICENSE"

cd packaging/arch-local
AGTERM_LOCAL_PKGVER="$pkgver" SRCDEST="$WORK" BUILDDIR="$WORK" PKGDEST="$WORK" makepkg -si --cleanbuild
