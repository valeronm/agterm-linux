#!/usr/bin/env bash
# Build and launch agterm-linux (the GTK4/libadwaita port).
# Requires the mise toolchain (zig 0.16.0 + swift 6.3.2) and a built libghostty
# in agterm-linux/vendor/ (run scripts/setup-linux.sh once).
set -euo pipefail
cd "$(dirname "$0")/.."

# Locate the mise-managed Swift toolchain without hardcoding the install layout.
SWIFT_HOME="$(mise where swift 2>/dev/null || echo "$HOME/.local/share/mise/installs/swift/6.3.2")"
export PATH="$SWIFT_HOME/usr/bin:$PATH"
# Bridge libxml2.so.2 / libncurses.so.6 for the Ubuntu Swift toolchain (no sudo).
# scripts/linux-swift-compat.sh discovers the real sonames and provisions the shim
# (a no-op where the loader already has them); it's the same helper mise.toml sources.
COMPAT="$(sh "$(dirname "$0")/linux-swift-compat.sh")"
export LD_LIBRARY_PATH="$COMPAT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Point the dev build at the vendored ghostty resources (shell-integration + sibling terminfo) so
# GHOSTTY_RESOURCES_DIR resolves to them (else the resolver falls back to a system/installed dir).
export AGTERM_GHOSTTY_RESOURCES="$(pwd)/agterm-linux/vendor/ghostty/share/ghostty"

cd agterm-linux
swift build "$@"
exec ./.build/debug/AgtermLinux
