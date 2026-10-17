#!/bin/bash
# Runs on the BUILD HOST (native x86, no qemu) as an mmdebstrap customize hook, before customize.sh.
#   host-themes.sh <rootfs>
# Installs the WhiteSur GTK/xfwm4 themes and icon theme straight into the image tree. Themes are only text and
# images, so they do not care which architecture they were built on. Doing it here instead of inside the armhf
# chroot avoids qemu problems with sassc, and a failure now stops the build with the full log (it used to be
# swallowed by "|| true", which produced images without WhiteSur: no window frames, themes without a base).
set -euo pipefail
ROOT=${1:?usage: host-themes.sh <rootfs>}
export TERM=xterm USER=root HOME=${HOME:-/root}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$ROOT/usr/share/themes" "$ROOT/usr/share/icons"

git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme  "$T/gtk"
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme "$T/icons"
git -C "$T/gtk"   rev-parse HEAD > "$ROOT/usr/share/fleet-theme-gtk.rev"
git -C "$T/icons" rev-parse HEAD > "$ROOT/usr/share/fleet-theme-icons.rev"

echo "== WhiteSur GTK theme (log: last lines)"
if ! ( cd "$T/gtk" && ./install.sh -d "$ROOT/usr/share/themes" -n WhiteSur -c light -c dark -o normal ) > "$T/gtk.log" 2>&1; then
  echo "ERROR: WhiteSur GTK install failed. Full log:"; cat "$T/gtk.log"; exit 1
fi
tail -5 "$T/gtk.log"

echo "== WhiteSur icon theme"
if ! ( cd "$T/icons" && ./install.sh -d "$ROOT/usr/share/icons" ) > "$T/icons.log" 2>&1; then
  echo "ERROR: WhiteSur icon install failed. Full log:"; cat "$T/icons.log"; exit 1
fi
tail -3 "$T/icons.log"

# Verify what the rest of the build and the FleetOS themes rely on
for d in WhiteSur-Light WhiteSur-Dark; do
  [ -f "$ROOT/usr/share/themes/$d/gtk-3.0/gtk.css" ] || { echo "ERROR: $d/gtk-3.0/gtk.css missing"; ls "$ROOT/usr/share/themes"; cat "$T/gtk.log"; exit 1; }
  [ -f "$ROOT/usr/share/themes/$d/xfwm4/themerc" ]   || { echo "ERROR: $d/xfwm4/themerc missing (window frames)"; exit 1; }
done
[ -d "$ROOT/usr/share/icons/WhiteSur" ] || { echo "ERROR: icon theme WhiteSur missing"; ls "$ROOT/usr/share/icons"; exit 1; }
echo "WhiteSur themes installed: $(ls "$ROOT/usr/share/themes" | tr '\n' ' ')"
