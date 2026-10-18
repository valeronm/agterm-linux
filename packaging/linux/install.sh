#!/usr/bin/env bash
# Install (default) or remove (--uninstall) the agterm-linux payload staged beside this script,
# under PREFIX (default /usr/local). Re-running from a newer payload updates the install.
set -euo pipefail

src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
app_id="io.github.melonamin.agterm"

# The installed copy sits at $prefix/lib/agterm-linux/install.sh, and its location is the only
# record of the prefix an uninstall has to undo.
default_prefix=/usr/local
if [[ "$src" == */lib/agterm-linux ]]; then
  default_prefix="${src%/lib/agterm-linux}"
fi
prefix="${PREFIX:-$default_prefix}"
target="$prefix/lib/agterm-linux"

mode=install
case "${1:-}" in
  "") ;;
  --uninstall) mode=uninstall ;;
  *)
    echo "usage: [PREFIX=/usr/local] ${0##*/} [--uninstall]" >&2
    exit 2
    ;;
esac

# A prefix that does not exist yet is writable when its nearest existing ancestor is.
probe="$prefix"
while [[ ! -e "$probe" ]]; do probe="$(dirname "$probe")"; done
if [[ ! -w "$probe" ]]; then
  echo "$prefix is not writable; run with sudo" >&2
  exit 1
fi

# Files the payload places outside its own tree, as paths relative to share/.
shared_files() {
  (cd "$src/share" && find applications icons pixmaps -type f 2>/dev/null)
}

refresh_caches() {
  gtk-update-icon-cache -f -t "$prefix/share/icons/hicolor" 2>/dev/null || true
  update-desktop-database "$prefix/share/applications" 2>/dev/null || true
}

if [[ "$mode" == uninstall ]]; then
  for link in "$prefix/bin/agterm-linux" "$prefix/bin/agtermctl"; do
    case "$(readlink "$link" 2>/dev/null || true)" in
      "$target"/*) rm -f "$link" ;;
    esac
  done
  while IFS= read -r rel; do
    rm -f "$prefix/share/$rel"
  done < <(shared_files)
  # Removing the running script is safe: bash reads it through an open descriptor.
  rm -rf "$target"
  refresh_caches
  echo "uninstalled from $prefix. Settings and session state stay in ~/.config/agterm and ~/.local/share/agterm."
  exit 0
fi

if [[ "$src" == "$target" ]]; then
  echo "this is the installed copy; run install.sh from a new payload to update, or pass --uninstall" >&2
  exit 1
fi

for required in bin/agterm-linux bin/agterm-linux.bin bin/agtermctl bin/agtermctl.bin bin/zmx \
  lib/libghostty.so share/ghostty share/agterm/VERSION "share/applications/$app_id.desktop"; do
  [[ -e "$src/$required" ]] || { echo "incomplete payload: $src/$required is missing" >&2; exit 1; }
done

# The payload bundles the Swift runtime and libghostty; GTK, libadwaita, WebKitGTK and glibc come
# from the host, and a missing or too-old one is reported here rather than at launch.
linked="$(LD_LIBRARY_PATH="$src/lib" ldd -r "$src/bin/agterm-linux.bin" "$src/bin/agtermctl.bin" 2>&1 || true)"
missing="$(awk '/=> not found/ {print "  " $1}' <<<"$linked" | sort -u)"
if [[ -n "$missing" ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release 2>/dev/null || true
  {
    echo "these shared libraries are missing:"
    echo "$missing"
    echo "install the runtime libraries first:"
    case " ${ID:-} ${ID_LIKE:-} " in
      *" debian "*|*" ubuntu "*) echo "  sudo apt install libgtk-4-1 libadwaita-1-0 libwebkitgtk-6.0-4 libepoxy0" ;;
      *" fedora "*) echo "  sudo dnf install gtk4 libadwaita webkitgtk6.0 libepoxy" ;;
      *" arch "*) echo "  sudo pacman -S gtk4 libadwaita webkitgtk-6.0 libepoxy" ;;
      *) echo "  GTK 4, libadwaita, WebKitGTK 6.0 and libepoxy; your package manager can name the package for a soname above" ;;
    esac
  } >&2
  exit 1
fi
outdated="$(awk '/undefined symbol|version .* not found/ {$1 = $1; print "  " $0}' <<<"$linked" | sort -u)"
if [[ -n "$outdated" ]]; then
  {
    echo "the installed libraries are older than these binaries need:"
    echo "$outdated"
    echo "agterm-linux needs glibc 2.39, GTK 4.14, libadwaita 1.5 and WebKitGTK 6.0 or newer"
  } >&2
  exit 1
fi

# Overwriting a mapped library in place crashes every open window, so the new tree is swapped in
# with rename and running terminals keep the old one.
rm -rf "$target.new"
mkdir -p "$prefix/lib" "$prefix/bin"
cp -R "$src" "$target.new"
if [[ -e "$target" ]]; then
  rm -rf "$target.old"
  mv "$target" "$target.old"
fi
mv "$target.new" "$target"
rm -rf "$target.old"

ln -sfn "$target/bin/agterm-linux" "$prefix/bin/agterm-linux"
ln -sfn "$target/bin/agtermctl" "$prefix/bin/agtermctl"
while IFS= read -r rel; do
  install -Dm644 "$src/share/$rel" "$prefix/share/$rel"
done < <(shared_files)
refresh_caches

echo "installed $(<"$target/share/agterm/VERSION") to $prefix. Launch with: agterm-linux (or from the app grid)"
if pgrep -x agterm-linux.bin >/dev/null 2>&1; then
  echo "open agterm windows keep running the previous build until they are restarted"
fi
