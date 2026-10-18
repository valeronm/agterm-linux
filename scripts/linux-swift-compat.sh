#!/usr/bin/env sh
# Provision libxml2.so.2 / libncurses.so.6 compatibility symlinks for the
# Ubuntu-built Swift toolchain on hosts whose sonames differ: Arch's soname-bumped
# libxml2 + wide ncursesw, and Ubuntu 26.04's libxml2 2.15 (libxml2.so.2 -> .so.16).
#
# Machine-independent: discovers the real libraries across /usr/lib (Arch) and the
# Debian/Ubuntu multiarch dirs (/usr/lib/<arch>/, any architecture), so it needs no
# per-machine configuration. A no-op where the dynamic loader already resolves the
# soname (stock Ubuntu 24.04, the swift:6.3.2 CI container) — nothing is linked there.
#
# Always prints the compat dir on stdout; callers prepend it to LD_LIBRARY_PATH
# (an empty compat dir is harmless on the search path). Idempotent and fast, so it
# is safe to run on every mise env resolution and every run-linux.sh invocation.
set -eu

COMPAT="${XDG_CACHE_HOME:-$HOME/.cache}/agterm/swift-compat"
mkdir -p "$COMPAT"

# The native multiarch triplet (e.g. x86_64-linux-gnu). Used to target the RIGHT
# arch's /usr/lib/<triplet>/ dir — a bare /usr/lib/*/ glob also matches i386-linux-gnu
# and would link a 32-bit lib the 64-bit toolchain can't load. Fall back to a
# uname-derived triplet when gcc/dpkg aren't present.
MULTIARCH="$(gcc -print-multiarch 2>/dev/null \
    || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null \
    || printf '%s-linux-gnu' "$(uname -m)")"

# link <soname> <candidate-path>...
# Candidates are already glob-expanded by the caller; pick the highest-versioned one
# that exists and symlink it to <soname> — unless the loader already resolves the
# soname (host has a native copy) or we linked it on a previous run.
link() {
    soname=$1
    shift
    if ldconfig -p 2>/dev/null | grep -qF "$soname "; then return 0; fi
    if [ -e "$COMPAT/$soname" ]; then return 0; fi
    real=$(for cand in "$@"; do [ -e "$cand" ] && printf '%s\n' "$cand"; done | sort -V | tail -1)
    if [ -n "$real" ]; then ln -sf "$real" "$COMPAT/$soname"; fi
    return 0
}

# Native multiarch dir first (correct arch), then Arch's flat /usr/lib. Unquoted so
# the shell expands the globs here; non-matching patterns pass through and are filtered
# out by the `[ -e ]` test inside link().
link libxml2.so.2    /usr/lib/"$MULTIARCH"/libxml2.so.*     /lib/"$MULTIARCH"/libxml2.so.*     /usr/lib/libxml2.so.*
link libncurses.so.6 /usr/lib/"$MULTIARCH"/libncursesw.so.6 /lib/"$MULTIARCH"/libncursesw.so.6 /usr/lib/libncursesw.so.6

printf '%s\n' "$COMPAT"
