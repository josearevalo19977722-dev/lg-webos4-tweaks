#!/bin/sh
# lg-webos4-tweaks — installer
#
# Run this ON THE TV, as root, with the Homebrew Channel already installed:
#     ssh root@<TV-IP> 'sh -s' < install.sh
#
# Nothing on LG's read-only partitions is ever written to. Patched copies are
# generated here, from your own TV's files, and bind-mounted on top at boot,
# which is also why this repo ships no LG code. uninstall.sh reverts it all.
#
# OPTIONS (environment variables). All are optional; with none, only the RAM
# work is done.
#
#   NETFLIX_BUTTON=<appId>  the remote's Netflix hotkey opens this app instead
#   AMAZON_BUTTON=<appId>   the remote's Amazon hotkey opens this app instead
#   HOME_APP=<appId>        the HOME button opens this app instead of LG's bar
#   TV_INPUT=<appId>        register this app as a TV input, next to HDMI 1/2/3
#   BOOT_APP=<appId>        open this app at every power-on, whatever the last
#                           input was
#   STOP_AIRPLAY=0          keep AirPlay and HomeKit running
#   SKIP_PRELOAD=1          leave app preloading alone
#
# App IDs come from:
#   luna-send -n 1 -f luna://com.webos.applicationManager/listApps '{}' </dev/null
#
# Example — free RAM, point both hotkeys and HOME at your own launcher, make
# it a TV input and open it at boot:
#   ssh root@<TV-IP> 'NETFLIX_BUTTON=youtube.leanback.v4 \
#       HOME_APP=my.launcher TV_INPUT=my.launcher BOOT_APP=my.launcher \
#       sh -s' < install.sh

set -e

DEST=/var/lib/webosbrew
INITD="$DEST/init.d"
PRELOAD_SRC=/etc/configd/layers/base/com.webos.service.preloadmanager.json
APPLAUNCH_SRC=/usr/lib/qt5/qml/KeyFilters/appLaunch.js
SYSTEMUI_SRC=/usr/lib/qt5/qml/KeyFilters/systemUi.js

say() { echo "[lg-webos4-tweaks] $*"; }
die() { echo "[lg-webos4-tweaks] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "must run as root"
[ -d "$DEST" ] || die "$DEST not found — is the Homebrew Channel installed and the TV rooted?"
mkdir -p "$INITD"

# ---------------------------------------------------------------- preloading
if [ "${SKIP_PRELOAD:-0}" != "1" ]; then
    [ -f "$PRELOAD_SRC" ] || die "$PRELOAD_SRC not found; use SKIP_PRELOAD=1 to skip"
    say "generating preload config from your TV's own file"
    sed -e 's/"isEnabled"[[:space:]]*:[[:space:]]*true/"isEnabled" : false/g' \
        "$PRELOAD_SRC" > "$DEST/preloadmanager-disabled.json"
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

# ------------------------------------------------------ remote hotkeys patch
PATCH_KEYS=0
if [ -n "${NETFLIX_BUTTON}${AMAZON_BUTTON}" ]; then
    [ -f "$APPLAUNCH_SRC" ] || die "$APPLAUNCH_SRC not found; is this really webOS 4?"
    say "patching the app hotkeys from your TV's own file"
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
    PATCH_KEYS=1
fi

# ----------------------------------------------------------- HOME key patch
if [ -n "$HOME_APP" ]; then
    [ -f "$SYSTEMUI_SRC" ] || die "$SYSTEMUI_SRC not found; is this really webOS 4?"
    say "patching the HOME key from your TV's own file"
    cp "$SYSTEMUI_SRC" "$DEST/systemUi-patched.js"
    # On release: open the app instead of LG's launcher bar.
    grep -q 'global.goHome();' "$DEST/systemUi-patched.js" \
        || die "could not find 'global.goHome();' — unexpected firmware"
    sed -i "s|global.goHome();|applicationManager.launch(\"$HOME_APP\");|" \
        "$DEST/systemUi-patched.js"
    # On press: do NOT prepare LG's bar, or it flashes underneath. Replaced by
    # a comment so the line count still matches the original.
    grep -q 'global.prepareToGoHome();' "$DEST/systemUi-patched.js" \
        || die "could not find 'global.prepareToGoHome();' — unexpected firmware"
    sed -i 's|global.prepareToGoHome();|/* LG bar disabled */;|' \
        "$DEST/systemUi-patched.js"
    a=$(wc -l < "$SYSTEMUI_SRC"); b=$(wc -l < "$DEST/systemUi-patched.js")
    [ "$a" = "$b" ] || die "line count changed ($a -> $b); refusing to install"
    say "  HOME button -> $HOME_APP"
    PATCH_KEYS=1
fi

# ------------------------------------------------------------- boot scripts
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

if [ "$PATCH_KEYS" = "1" ]; then
cat > "$INITD/20-keys" <<'EOS'
#!/bin/sh
# lg-webos4-tweaks — keyboard patches for the compositor.
#   appLaunch.js  -> the remote's Netflix / Amazon hotkeys
#   systemUi.js   -> the HOME button
#
# WHY THE COMPOSITOR IS RESTARTED:
#   surface-manager starts ~2s into boot and reads these files right then.
#   This script cannot run before ~43s, because webOS does not start
#   devmode.conf (which chains the Homebrew Channel startup) until then.
#   There is no earlier hook, so we mount and restart the compositor.
#
# TO REVERT: delete this file and reboot.

LOG=/var/lib/webosbrew/keys.log
exec >>"$LOG" 2>&1 </dev/null
echo "=== $(date) ==="

PATCHES="/var/lib/webosbrew/appLaunch-patched.js|/usr/lib/qt5/qml/KeyFilters/appLaunch.js
/var/lib/webosbrew/systemUi-patched.js|/usr/lib/qt5/qml/KeyFilters/systemUi.js"

echo "$PATCHES" | while IFS='|' read -r patch target; do
    [ -n "$patch" ] || continue
    [ -f "$patch" ] || continue
    # If an LG update changes the original, never mount a stale patch over it.
    if [ "$(wc -l < "$patch")" -ne "$(wc -l < "$target")" ]; then
        echo "ABORT $target: original $(wc -l < "$target") lines, patch $(wc -l < "$patch")"
        continue
    fi
    mount | grep -q " $target " && { echo "already mounted: $target"; continue; }
    mount -o bind "$patch" "$target" && echo "mounted: $target" && echo x >> /tmp/.keys-new
done

# Restart the compositor only if something new was mounted on this pass.
if [ -f /tmp/.keys-new ]; then
    rm -f /tmp/.keys-new
    (
        sleep 2
        if ! initctl restart surface-manager >/dev/null 2>&1; then
            stop surface-manager >/dev/null 2>&1; sleep 2
            start surface-manager >/dev/null 2>&1
        fi
        sleep 8
        echo "compositor restarted, pid $(pgrep -x surface-manager)"
    ) &
else
    echo "nothing new to mount: compositor left alone"
fi
EOS
chmod +x "$INITD/20-keys"
say "installed $INITD/20-keys"
fi

if [ -n "$TV_INPUT" ]; then
cat > "$INITD/30-tv-input" <<EOS
#!/bin/sh
# lg-webos4-tweaks — registers an app as a TV input, next to HDMI 1/2/3.
#
# The app's appinfo.json MUST declare "supportGIP": true. Without it,
# addDevice answers returnValue:true and the input never appears.
#
# TO REVERT: delete this file, and remove the input from the TV.

APPID=$TV_INPUT
LOG=/var/lib/webosbrew/tv-input.log
exec >>"\$LOG" 2>&1 </dev/null
echo "=== \$(date) ==="

DIR=""
for base in /media/developer/apps/usr/palm/applications \\
            /media/cryptofs/apps/usr/palm/applications \\
            /usr/palm/applications; do
    [ -f "\$base/\$APPID/appinfo.json" ] && DIR="\$base/\$APPID" && break
done
[ -n "\$DIR" ] || { echo "ABORT: \$APPID is not installed"; exit 0; }

# The bus takes a while to answer during boot.
i=0
while [ \$i -lt 30 ]; do
    luna-send -n 1 -f luna://com.webos.service.eim/getAllInputStatus '{}' \\
        </dev/null >/dev/null 2>&1 && break
    i=\$((i+1)); sleep 2
done

luna-send -n 1 -f luna://com.webos.service.eim/addDevice "{
  \\"id\\": \\"MVPD_IP-\$APPID\\",
  \\"appId\\": \\"\$APPID\\",
  \\"label\\": \\"\$APPID\\",
  \\"port\\": 1,
  \\"activate\\": true,
  \\"icon\\": \\"\$DIR/icon.png\\",
  \\"largeIcon\\": \\"\$DIR/largeIcon.png\\",
  \\"mvpdIcon\\": \\"\$DIR/icon.png\\",
  \\"pigImage\\": \\"\$DIR/\\"
}" </dev/null 2>&1 | tr -d '\\n'
echo
EOS
chmod +x "$INITD/30-tv-input"
say "installed $INITD/30-tv-input ($TV_INPUT)"
fi

if [ -n "$BOOT_APP" ]; then
cat > "$INITD/45-boot-app" <<EOS
#!/bin/sh
# lg-webos4-tweaks — opens an app at every power-on.
#
# Registering an app as a TV input only makes it BE an input; webOS still
# restores the last input used. Turn the TV off on HDMI 2 and you come back
# to HDMI 2. This forces the app instead.
#
# It waits for the compositor RESTARTED by 20-keys: anything launched before
# that restart is taken down with it. The restarted one is recognised by its
# start time being past second 40 (the original starts around second 2).
#
# DISABLE without deleting: create /media/internal/no-boot-app
# TO REVERT: delete this file and reboot.

APPID=$BOOT_APP
LOG=/var/lib/webosbrew/boot-app.log
BRAKE=/media/internal/no-boot-app
exec >>"\$LOG" 2>&1 </dev/null
echo "=== \$(date) ==="
[ -e "\$BRAKE" ] && { echo "disabled by \$BRAKE"; exit 0; }

(
    hz=\$(getconf CLK_TCK 2>/dev/null || echo 100)
    i=0
    while [ \$i -lt 90 ]; do
        sm=\$(pgrep -x surface-manager)
        if [ -n "\$sm" ]; then
            born=\$(( \$(awk '{print \$22}' /proc/\$sm/stat 2>/dev/null || echo 0) / hz ))
            [ "\$born" -gt 40 ] && break
        fi
        sleep 1; i=\$((i+1))
    done
    sleep 5
    now=\$(luna-send -n 1 -f luna://com.webos.applicationManager/getForegroundAppInfo \\
          '{}' </dev/null 2>/dev/null | tr -d ' \\n"' | sed 's/.*appId://; s/,.*//')
    [ "\$now" = "\$APPID" ] && { echo "already showing \$APPID"; exit 0; }
    luna-send -n 1 -f luna://com.webos.applicationManager/launch \\
        "{\\"id\\":\\"\$APPID\\"}" </dev/null >/dev/null 2>&1
    echo "launched \$APPID at \$(cut -d. -f1 /proc/uptime)s (was \${now:-empty})"
) &
EOS
chmod +x "$INITD/45-boot-app"
say "installed $INITD/45-boot-app ($BOOT_APP)"
fi

say "done. Reboot the TV to apply:  reboot"
say "logs live in $DEST/*.log"
