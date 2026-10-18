#!/usr/bin/env bash
# Build agterm-linux in Release, stage the relocatable payload, and install it system-wide with
# the payload's install.sh (PREFIX defaults to /usr/local). Requires the mise toolchain and a
# vendored libghostty (run scripts/setup-linux.sh once). Only the install step asks for sudo.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(id -u)" -eq 0 ]]; then
  echo "run as your user; only the install step needs root" >&2
  exit 1
fi

SWIFT_HOME="$(mise where swift 2>/dev/null || echo "$HOME/.local/share/mise/installs/swift/6.3.2")"
export PATH="$SWIFT_HOME/usr/bin:$PATH"
COMPAT="$(sh scripts/linux-swift-compat.sh)"
export LD_LIBRARY_PATH="$COMPAT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

( cd agterm-linux && swift build -c release )

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
scripts/stage-linux.sh "$STAGE/agterm-linux"

installer=("$STAGE/agterm-linux/install.sh")
prefix="${PREFIX:-/usr/local}"
[[ -n "${PREFIX:-}" ]] && installer=(env "PREFIX=$PREFIX" "${installer[@]}")
probe="$prefix"
while [[ ! -e "$probe" ]]; do probe="$(dirname "$probe")"; done
if [[ -w "$probe" ]]; then
  "${installer[@]}"
else
  echo "installing to $prefix with sudo"
  sudo "${installer[@]}"
fi
