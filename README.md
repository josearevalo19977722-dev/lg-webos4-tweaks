# lg-webos4-tweaks

More free RAM, a remappable remote and a HOME button that opens whatever you
want, on **rooted 2018 LG TVs (webOS 4.x)**.

🇪🇸 [Léeme en español](README.es.md)

![A custom launcher running on a 2018 LG TV](docs/hearth-home.png)

<sub>A 43UK6300PSB running a custom home screen instead of LG's launcher bar.
Captured natively through the TV's own DevTools endpoint, not photographed.</sub>

---

2018 LG TVs ship with ~840 MB of RAM and spend a good chunk of it keeping
Netflix, the browser and other apps preloaded in the background whether you use
them or not. The result is a TV that swaps, stutters and takes forever to open
anything.

Measured on a **43UK6300PSB** (webOS 4.4.3-22, firmware 05.50.70):

| | Before | After |
|---|---|---|
| Available RAM | 183 MB | **373 MB** |
| Swap in use | 197 MB | 0 MB |
| Preloaded apps | 9 | 0 |
| Remote hotkeys | Netflix / Prime Video, fixed | any app you like |
| HOME button | LG's launcher bar | any app you like |

Most projects of this kind target 2019 and newer.
[LGlow](https://github.com/IrvingGuerra/lglow), the obvious choice, explicitly
excludes 2018 because it replaces the full-screen home
(`com.webos.app.fullhome`) that webOS 4.5 introduced — 2018 TVs don't have it.
This repo is what's left once you accept that, and it turned out to be the part
that actually matters.

## Compatibility

**Tested on:** LG 43UK6300PSB, webOS 4.4.3-22 (`goldilocks-gorongosa`),
firmware 05.50.70, platform `lm18a` / `HE_DTV_W18A`.

**Should work on** the 2018 webOS 4.x line, which is what has
`/usr/lib/qt5/qml/KeyFilters/appLaunch.js` and a launcher bar instead of a
full-screen home. Every patch checks the file it is about to replace and
refuses if it doesn't match, so a mismatch is a no-op, not a brick.

**Not supported:** 2019 and newer (webOS 4.5+). The RAM part may still work,
but the key patches assume this exact compositor layout.

> **Firmware numbering is not comparable across years.** LGlow asks for
> "05.40.09 or newer", which is a 2019 branch. This TV runs 05.50.70, a higher
> number from the 2018 branch. Don't read one as newer than the other.

## Versions

| Component | Version used | Notes |
|---|---|---|
| Homebrew Channel | 0.7.3 | required |
| dejavuln-autoroot | 0.0.10 | used to root; USB, no developer mode |
| This repo | see git log | no releases yet |

## Requirements

- A 2018 LG TV (webOS 4.x), **rooted**, with the Homebrew Channel installed.
- SSH access to the TV, enabled in the Homebrew Channel's settings.

Not rooted yet? Check [cani.rootmy.tv](https://cani.rootmy.tv/) with your model
and firmware first. If it's still rootable,
[dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) works from
a USB stick with no developer mode and no LG account.

> **Turn off automatic updates before anything else.** Once LG ships a patched
> firmware to your TV, rooting it is over for good. In the Homebrew Channel,
> also enable **Block system updates**. That only redirects `su.lge.com` and
> `snu.lge.com`; the LG Content Store keeps working.

> **Never install LG's Developer Mode app** on a rooted TV. It removes root on
> the next reboot.

## Download

```sh
git clone https://github.com/josearevalo19977722-dev/lg-webos4-tweaks
cd lg-webos4-tweaks
```

Or grab the ZIP from the green **Code** button on GitHub and unzip it. There is
nothing to build: the installer is a shell script.

## Install

The installer runs **on the TV**, fed over SSH. Nothing is copied or left
behind on your computer.

```sh
# RAM only — the safest first step
ssh root@<TV-IP> 'sh -s' < install.sh
```

```sh
# Everything: free RAM, remap both hotkeys and HOME, register a TV input
# and open your launcher at every power-on
ssh root@<TV-IP> 'NETFLIX_BUTTON=youtube.leanback.v4 \
                  AMAZON_BUTTON=com.disney.disneyplus-prod \
                  HOME_APP=my.launcher \
                  TV_INPUT=my.launcher \
                  BOOT_APP=my.launcher sh -s' < install.sh
```

Then **reboot the TV**. The patches only take effect from a boot.

### Options

| Variable | Effect |
|---|---|
| `NETFLIX_BUTTON=<appId>` | the Netflix hotkey opens this app instead |
| `AMAZON_BUTTON=<appId>` | the Amazon hotkey opens this app instead |
| `HOME_APP=<appId>` | the HOME button opens this app instead of LG's bar |
| `TV_INPUT=<appId>` | register this app as a TV input, next to HDMI 1/2/3 |
| `BOOT_APP=<appId>` | open this app at every power-on |
| `STOP_AIRPLAY=0` | keep AirPlay and HomeKit running |
| `SKIP_PRELOAD=1` | leave app preloading alone |

Find your app IDs with:

```sh
ssh root@<TV-IP> 'luna-send -n 1 -f luna://com.webos.applicationManager/listApps "{}" </dev/null'
```

> `TV_INPUT` needs the target app's `appinfo.json` to declare
> `"supportGIP": true`. Without it `addDevice` answers `returnValue: true` and
> the input silently never appears.

## Verify it worked

After rebooting:

```sh
# mounts in place: 5 preload configs, 1–2 key patches
ssh root@<TV-IP> 'mount | grep -c preloadmanager; mount | grep -c KeyFilters'

# the compositor restarted AFTER the patches were mounted (so it read them):
# this must print a number greater than ~45
ssh root@<TV-IP> 'sm=$(pgrep -x surface-manager); \
  echo $(( $(awk "{print \$22}" /proc/$sm/stat) / $(getconf CLK_TCK) ))s'

# free memory
ssh root@<TV-IP> 'free -m'
```

Every script writes its own log:

```
/var/lib/webosbrew/free-ram.log
/var/lib/webosbrew/keys.log
/var/lib/webosbrew/tv-input.log
/var/lib/webosbrew/boot-app.log
```

## Uninstall

```sh
ssh root@<TV-IP> 'sh -s' < uninstall.sh
```

Reboot and you're back to stock. **No file on LG's partitions is ever
modified** — patched copies live in `/var/lib/webosbrew` and are bind-mounted
on top at boot, so removing the scripts and rebooting is a complete revert.

If you used `TV_INPUT`, remove the input from the TV's own input list too.

## What gets installed

```
/var/lib/webosbrew/
├── init.d/10-free-ram              preloading off, AirPlay/HomeKit stopped
├── init.d/20-keys                  mounts the key patches, restarts compositor
├── init.d/30-tv-input              registers the app as a TV input
├── init.d/45-boot-app              opens the app at power-on
├── preloadmanager-disabled.json    generated from your TV's own config
├── appLaunch-patched.js            generated from your TV's own file
└── systemUi-patched.js             generated from your TV's own file
```

## How it works

Everything below was worked out on a live TV; it's written down because none of
it is documented anywhere for webOS 4.

### Preloading lives in a read-only config

`/etc/configd/layers/base/com.webos.service.preloadmanager.json` and its
per-resolution variants under `distro/` list which apps get preloaded. `/etc` is
read-only (and the overlay is 100% full), so the installer generates a copy with
every `isEnabled` set to `false` and `maxPreloadApp: 0`, and the boot script
bind-mounts it over all five paths.

The copy is generated **from your TV's own file**, so it works on models whose
app list differs from the one this was built on.

### HomeKit comes back if you just stop it

`airplay-adaptor` is a normal upstart job. `homekit` is not — it's spawned on
demand by `ls-hubd`, the Luna service bus, so its parent respawns it. `kill -9`
makes it stay down.

### The remote's hotkeys are in a JavaScript file

Not in `com.webos.keyaction.json` — that only covers system keys (volume, guide,
subtitles). The app hotkeys are in `handleCPHotkeys()` inside
`/usr/lib/qt5/qml/KeyFilters/appLaunch.js`, loaded by the compositor:

```js
case WebOS.Key_webOS_Netflix:  appId = "netflix";  break;
case WebOS.Key_webOS_Amazon:   appId = "amazon";   break;
case WebOS.Key_webOS_IVI:      appId = "ivi";      break;
```

Two string literals. That's the whole binding.

### The HOME button cannot be caught from an app

A watcher that polls "which app is in front" and reacts when LG's home appears
**never fires on webOS 4**: the launcher bar is a compositor overlay, not an app.
`com.webos.app.home` shows up in neither `running` nor `getForegroundAppInfo`.
That approach is designed for 2019+, where the home is a full-screen card.

The key itself is handled in `handleSystemKeys()` in `systemUi.js`, as
`Qt.Key_Super_L`:

```js
if (pressed)  { global.prepareToGoHome(); ... }   // shows LG's bar
else          { if (longPressTimer.isRunning(key)) global.goHome(); }
```

Both lines matter. Patch only the second one and LG's bar still flashes
underneath on every press, because the first already put it there. Long-press
is left alone, so it still opens Recents.

### …and mounting the patches is not enough

This one cost an extra reboot to find:

```
 2s  surface-manager starts and reads the KeyFilters files
43s  webOS starts devmode.conf, which chains the Homebrew Channel startup
44s  our script bind-mounts the patched files  ← too late
```

The compositor never re-reads them, and there is no earlier hook available, so
`20-keys` restarts `surface-manager` after mounting. You'll see one UI blink
during boot. A welcome side effect: restarting the compositor after boot settles
frees another ~80 MB.

### Registering a TV input needs a flag nobody mentions

`luna://com.webos.service.eim/addDevice` registers an app next to HDMI 1/2/3.
It answers `returnValue: true`… and does nothing, unless the app's
`appinfo.json` declares `"supportGIP": true`.

The device record needs `pigImage` too, or it fails with `EIM.101`.

### "Boot into my launcher" is really "resume the last input"

Registering the input only makes the app *be* an input. webOS restores whatever
input was active when you switched the TV off: turn it off on HDMI 2 and you
come back to HDMI 2. There is no "start on app X" setting — `powerOnScreen`
only accepts `todays` or `liveTv`.

`45-boot-app` forces it, and has to wait for the compositor restarted by
`20-keys`: anything launched before that restart is taken down with it. It spots
the restarted one by its start time being past second 40, since the original
starts around second 2. On the test TV the app appears at **~62 s** after
power-on. Roughly 60 s is the floor; it could be ~45 s without the key patches.

### `luna-send` fails silently without stdin

If stdin isn't redirected, `luna-send` exits 0 and does nothing — no output, no
error. Every call needs `</dev/null`. Expect to lose an hour to this one.

It also prints **multi-line** JSON, so flatten with `tr -d '\n'` before pulling
fields out with `sed`, or your logs become unreadable.

### Taking clean screenshots

`/dev/fb0` is all zeros — the UI is composited in hardware and never passes
through it — and there is no `com.webos.service.capture` on webOS 4. But web
apps expose a Chrome DevTools endpoint on port **9998**, so you can grab a
pixel-perfect PNG of any of them:

```sh
ssh -f -N -L 19998:127.0.0.1:9998 root@<TV-IP>
curl -s http://127.0.0.1:19998/json/list        # find the page id
# then send Page.captureScreenshot over the WebSocket for that page
```

The screenshot at the top of this README was taken that way.

### Injecting remote keys for testing

You can write raw evdev events to the remote's device and the compositor reacts
exactly as it would to a real press. 16 bytes per event on 32-bit ARM:

```python
struct.pack("<llHHi", 0, 0, type, code, value)   # timeval, type, code, value
```

```sh
ssh root@<TV-IP> 'cat > /dev/input/event1' < event.bin
```

| Button | evdev code | Name |
|---|---|---|
| HOME | 125 | `KEY_LEFTMETA` |
| BACK | **412** | `KEY_PREVIOUS` — **not** `KEY_BACK` (158) |
| EXIT | 174 | `KEY_EXIT` |
| OK | 28 | `KEY_ENTER` |
| Arrows | 103 / 108 / 105 / 106 | up / down / left / right |
| — | 773 | the remote interleaves this between presses; ignore it |

The Back one is worth repeating: it is **not** `KEY_BACK`. Testing with 158
makes a working handler look broken.

## Troubleshooting

**Nothing changed after installing.** The patches only apply from a boot.
Reboot, then check `keys.log`.

**`ABORT: original N lines, patch M`** in `keys.log` — an LG update changed the
original file. Run `install.sh` again to regenerate the patch from the new file.

**The TV boots to HDMI instead of your app.** That's the "resume last input"
behaviour. Use `BOOT_APP=<appId>`.

**The TV disappears from the network.** Its IP is handed out by DHCP and can
change. Find it again by its MAC: ping-sweep the subnet, then
`arp -a | grep -i <your TV's MAC prefix>`. An ARP entry showing `incomplete`
means nothing is answering at that address.

**Everything looks broken after a patch.** SSH keeps working even if the
compositor doesn't — it's an independent service. Delete the offending script
from `/var/lib/webosbrew/init.d/` and reboot.

## Home screen

This repo doesn't ship a launcher; it makes room for one and lets you bind the
buttons to it. Two that run on webOS 4:

- [Hearth](https://github.com/rudra-avatar/webos-custom-launcher) builds for
  Chrome 53, so it runs here even though it's only tested from webOS 7 upward.
  Its own "make this the default instead of LG Home" option does **not** work on
  webOS 4 — use `HOME_APP` from this repo instead.
- Anything you write yourself. A web app plus `HOME_APP`, `TV_INPUT` and
  `BOOT_APP` is enough to replace LG's home completely.

## Ad-free YouTube

The stock YouTube app is `"type": "native"` with `"main": "cobalt"` — Google's
lightweight TV engine. The official
[youtube-webos](https://github.com/webosbrew/youtube-webos) is a `web` app, so
on a 2018 TV it runs in Chrome 53 and declares no webOS 4 support.

[NicholasBly's fork](https://github.com/NicholasBly/youtube-webos) explicitly
supports webOS 3 and 4 and keeps the translation layers older TVs need. Use its
**standard** build, not the `webOS22+` one. Confirmed working on a 43UK6300PSB.

Either way you must uninstall the stock YouTube first — they share the
`youtube.leanback.v4` app ID. It's reinstallable from the LG Content Store.

## Credits

Built on [webOS Homebrew Project](https://www.webosbrew.org/),
[dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) and
[LGlow](https://github.com/IrvingGuerra/lglow), whose approach of never writing
to LG's partitions this project follows.

Not affiliated with LG. Rooting and modifying your TV is your own
responsibility.

## License

MIT — see [LICENSE](LICENSE). No LG code is included: every patched file is
generated on your own device from the files already on it.
