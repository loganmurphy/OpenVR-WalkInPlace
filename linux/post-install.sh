#!/bin/sh
# Post-install fixups for the Linux/SteamOS overlay package.
#
# Run on the HOST (not inside the container) after `./build.sh install`:
#   sh linux/post-install.sh [container-name]     (default container: wip)
#
# What it does:
#   1. Removes the container's glibc/libstdc++ copies that linuxdeployqt bundled
#   2. Copies libraries the packaging missed from the container into the overlay's lib/
#   3. Installs run-overlay.sh next to the overlay binary
#   4. Creates the folder the app reads its data models from

BOX="${1:-wip}"
APP="$HOME/.steam/steam/vrwalkinplace"
LIB="$APP/lib"
HERE="$(dirname "$(readlink -f "$0")")"

[ -e "$APP/OpenVR-WalkInPlaceOverlay" ] || { echo "Overlay not found in $APP. Run ./build.sh install first."; exit 1; }
command -v distrobox >/dev/null 2>&1 || { echo "distrobox not found. Run this on the host, not in the container."; exit 1; }

# 1. Remove bundled glibc: it is older than SteamOS's and breaks every other library
echo "Removing bundled glibc/libstdc++ copies..."
ls "$LIB" | grep -E '^(libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libnsl)\.so|^ld-linux|^libstdc\+\+\.so|^libgcc_s\.so' | while read -r f; do
  rm -v "$LIB/$f"
done

# Libraries the overlay and its Qt plugins need but can't find
list_missing() {
  for f in "$APP/OpenVR-WalkInPlaceOverlay" "$APP"/plugins/*/*.so; do
    [ -e "$f" ] && LD_LIBRARY_PATH="$LIB" ldd "$f" 2>/dev/null
  done | awk '/=> not found/ {print $1}' | sort -u
}

# 2. Copy missing libraries from the container (repeat: copied libraries bring dependencies of their own)
prev=""
for round in 1 2 3 4 5; do
  missing="$(list_missing)"
  [ -z "$missing" ] && break
  [ "$missing" = "$prev" ] && break
  prev="$missing"
  echo "Round $round: copying from container '$BOX': $(echo $missing)"
  distrobox enter "$BOX" -- sh -c 'lib=$1; shift; for n in "$@"; do
    f=$(find /usr/lib -name "$n" 2>/dev/null | head -1)
    if [ -n "$f" ]; then cp -vL "$f" "$lib/"; else echo "not in container: $n"; fi
  done' _ "$LIB" $missing
done

missing="$(list_missing)"
if [ -n "$missing" ]; then
  echo "WARNING: still missing:"
  echo "$missing"
else
  echo "All libraries resolved."
fi

# 3. Launcher
cp "$HERE/run-overlay.sh" "$APP/run-overlay.sh" && chmod +x "$APP/run-overlay.sh"

# 4. Data model folder (build.sh creates a different one)
mkdir -p "$HOME/.local/share/pottedmeat7/OpenVRWalkInPlace"

echo "Done. Start SteamVR, connect the headset, then run: $APP/run-overlay.sh"
