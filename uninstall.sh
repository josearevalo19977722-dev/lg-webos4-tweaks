#!/bin/sh
# lg-webos4-tweaks — uninstaller
#
#     ssh root@<TV-IP> 'sh -s' < uninstall.sh
#
# Removes everything this project installed. Nothing on LG's partitions was
# ever modified, so a reboot is all it takes to be back to stock.

set -e
DEST=/var/lib/webosbrew
say() { echo "[lg-webos4-tweaks] $*"; }

[ "$(id -u)" = "0" ] || { echo "must run as root" >&2; exit 1; }

for f in "$DEST/init.d/10-free-ram" \
         "$DEST/init.d/20-keys" \
         "$DEST/init.d/20-remote-buttons" \
         "$DEST/init.d/30-tv-input" \
         "$DEST/init.d/45-boot-app" \
         "$DEST/preloadmanager-disabled.json" \
         "$DEST/appLaunch-patched.js" \
         "$DEST/systemUi-patched.js"; do
    [ -e "$f" ] && rm -f "$f" && say "removed $f"
done

say "removed. Reboot to drop the bind-mounts and return to stock:  reboot"
say "if you registered a TV input, remove it from the TV's input list too."
