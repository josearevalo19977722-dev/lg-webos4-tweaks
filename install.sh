#!/bin/sh
# lg-webos4-tweaks — installer
#
# Run this ON THE TV, as root, with the Homebrew Channel already installed:
#     ssh root@<TV-IP> 'sh -s' < install.sh
#
# Everything it installs lives under /var/lib/webosbrew and is reverted by
# uninstall.sh. No file on LG's read-only partitions is ever written to:
# patched copies are generated here, from your own TV's files, and bind-mounted
# on top at boot. That is also why this repo ships no LG code.
#
# Options (environment variables):
#   NETFLIX_BUTTON=<appId>   remap the remote's Netflix hotkey
#   AMAZON_BUTTON=<appId>    remap the remote's Amazon hotkey
#   STOP_AIRPLAY=0           keep AirPlay/HomeKit running
#   SKIP_PRELOAD=1           do not touch app preloading
#   SKIP_BUTTONS=1           do not touch the remote buttons
#
# Example:
#   ssh root@<TV-IP> 'NETFLIX_BUTTON=youtube.leanback.v4 \
#       AMAZON_BUTTON=com.disney.disneyplus-prod sh -s' < install.sh

set -e

DEST=/var/lib/webosbrew
INITD="$DEST/init.d"
PRELOAD_SRC=/etc/configd/layers/base/com.webos.service.preloadmanager.json
APPLAUNCH_SRC=/usr/lib/qt5/qml/KeyFilters/appLaunch.js

say() { echo "[lg-webos4-tweaks] $*"; }
die() { echo "[lg-webos4-tweaks] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "must run as root"
[ -d "$DEST" ] || die "$DEST not found — is the Homebrew Channel installed and the TV rooted?"
mkdir -p "$INITD"

say "webOS: $(cat /var/run/nyx/os_info.json 2>/dev/null | head -c 120 || echo unknown)"

# ---------------------------------------------------------------- preloading
if [ "${SKIP_PRELOAD:-0}" != "1" ]; then
    [ -f "$PRELOAD_SRC" ] || die "$PRELOAD_SRC not found; use SKIP_PRELOAD=1 to skip"
    say "generating preload config from your TV's own file"
    sed -e 's/"isEnabled"[[:space:]]*:[[:space:]]*true/"isEnabled" : false/g' \
        "$PRELOAD_SRC" > "$DEST/preloadmanager-disabled.json"
    # Cap the preload slots too.
    if grep -q '"maxPreloadApp"' "$DEST/preloadmanager-disabled.json"; then
        sed -i 's/"maxPreloadApp"[[:space:]]*:[[:space:]]*[0-9]*/"maxPreloadApp": 0/' \
            "$DEST/preloadmanager-disabled.json"
    else
        sed -i '1s/^{/{\n    "maxPreloadApp": 0,/' "$DEST/preloadmanager-disabled.json"
    fi
    grep -q '"isEnabled" : true' "$DEST/preloadmanager-disabled.json" \
        && die "some entries are still enabled; aborting"
    say "  $(grep -c '"isEnabled" : false' "$DEST/preloadmanager-disabled.json") apps disabled"
    INSTALL_RAM=1
else
    INSTALL_RAM=0
fi

# ----------------------------------------------------------- remote buttons
INSTALL_BUTTONS=0
if [ "${SKIP_BUTTONS:-0}" != "1" ] && [ -n "${NETFLIX_BUTTON}${AMAZON_BUTTON}" ]; then
    [ -f "$APPLAUNCH_SRC" ] || die "$APPLAUNCH_SRC not found; this TV may not be webOS 4"
    say "patching the hotkey map from your TV's own file"
    cp "$APPLAUNCH_SRC" "$DEST/appLaunch-patched.js"
    for pair in "netflix:$NETFLIX_BUTTON" "amazon:$AMAZON_BUTTON"; do
        orig=${pair%%:*}; new=${pair#*:}
        [ -n "$new" ] || continue
        grep -q "appId = \"$orig\";" "$DEST/appLaunch-patched.js" \
            || die "could not find 'appId = \"$orig\";' — unexpected firmware"
        sed -i "s|appId = \"$orig\";|appId = \"$new\";|" "$DEST/appLaunch-patched.js"
        say "  $orig button -> $new"
    done
    a=$(wc -l < "$APPLAUNCH_SRC"); b=$(wc -l < "$DEST/appLaunch-patched.js")
    [ "$a" = "$b" ] || die "line count changed ($a -> $b); refusing to install"
    INSTALL_BUTTONS=1
fi

# ------------------------------------------------------------ boot scripts
if [ "$INSTALL_RAM" = "1" ]; then
cat > "$INITD/10-free-ram" <<'EOS'
#!/bin/sh
# lg-webos4-tweaks — frees RAM on boot.
# Disables LG's app preloading and (optionally) AirPlay/HomeKit.
# TO REVERT: delete this file and reboot.

PATCH=/var/lib/webosbrew/preloadmanager-disabled.json
LOG=/var/lib/webosbrew/free-ram.log
STOP_AIRPLAY=__STOP_AIRPLAY__
exec >>"$LOG" 2>&1 </dev/null
echo "=== $(date) ==="

# /etc is read-only, so we bind-mount our copy on top of LG's config.
if [ -f "$PATCH" ]; then
    for f in /etc/configd/layers/base/com.webos.service.preloadmanager.json \
             /etc/configd/layers/distro/*/com.webos.service.preloadmanager.json; do
        [ -f "$f" ] && mount -o bind "$PATCH" "$f" && echo "mounted: $f"
    done
fi

stop_extras() {
    [ "$STOP_AIRPLAY" = "1" ] || return 0
    stop airplay-adaptor >/dev/null 2>&1 && echo "airplay-adaptor stopped"
    # homekit is spawned on demand by ls-hubd, so 'stop' alone will not do.
    hk=$(pgrep -x homekit)
    [ -n "$hk" ] && kill -9 $hk 2>/dev/null && echo "homekit stopped (pid $hk)"
}
stop_extras

# The boot keeps launching things after this point, so sweep again later.
(
    sleep 90
    stop_extras
    for app in netflix com.webos.app.browser youtube.leanback.v4 \
               com.webos.app.tips amazon vudu pooq; do
        luna-send -n 1 -f luna://com.webos.applicationManager/closeByAppId \
            "{\"id\":\"$app\"}" </dev/null >/dev/null 2>&1
    done
    echo "deferred sweep: $(free -m | awk '/Mem:/{print $7}') MB available"
) &
EOS
sed -i "s/__STOP_AIRPLAY__/${STOP_AIRPLAY:-1}/" "$INITD/10-free-ram"
chmod +x "$INITD/10-free-ram"
say "installed $INITD/10-free-ram"
fi

if [ "$INSTALL_BUTTONS" = "1" ]; then
cat > "$INITD/20-remote-buttons" <<'EOS'
#!/bin/sh
# lg-webos4-tweaks — remaps the remote's Netflix / Amazon hotkeys.
#
# WHY THE COMPOSITOR IS RESTARTED:
#   surface-manager starts ~2s into boot and reads appLaunch.js right then.
#   This script cannot run before ~44s, because webOS does not execute
#   start-devmode.sh (which chains the Homebrew Channel startup) until ~42s.
#   There is no earlier hook, so we mount the patch and restart the compositor.
#
# TO REVERT: delete this file and reboot.

PATCH=/var/lib/webosbrew/appLaunch-patched.js
TARGET=/usr/lib/qt5/qml/KeyFilters/appLaunch.js
LOG=/var/lib/webosbrew/remote-buttons.log
exec >>"$LOG" 2>&1 </dev/null
echo "=== $(date) ==="

[ -f "$PATCH" ] || { echo "ABORT: patch missing"; exit 0; }

# If an LG update changed the original, never mount a stale patch over it.
if [ "$(wc -l < "$PATCH")" -ne "$(wc -l < "$TARGET")" ]; then
    echo "ABORT: original $(wc -l < "$TARGET") lines, patch $(wc -l < "$PATCH")"
    exit 0
fi

# Loop guard: if it is already mounted, do not restart the compositor again.
if mount | grep -q "KeyFilters/appLaunch.js"; then
    echo "already mounted; compositor left alone"
    exit 0
fi

mount -o bind "$PATCH" "$TARGET" || { echo "ABORT: mount failed"; exit 0; }
echo "mounted: $TARGET"

( # backgrounded so the rest of the boot is not held up
    sleep 5
    if ! initctl restart surface-manager >/dev/null 2>&1; then
        stop surface-manager >/dev/null 2>&1; sleep 2
        start surface-manager >/dev/null 2>&1
    fi
    sleep 8
    echo "compositor restarted, pid $(pgrep -x surface-manager)"
) &
EOS
chmod +x "$INITD/20-remote-buttons"
say "installed $INITD/20-remote-buttons"
fi

say "done. Reboot the TV to apply:  reboot"
say "logs: $DEST/free-ram.log  $DEST/remote-buttons.log"
