# lg-webos4-tweaks

Ad-free home screen, more free RAM and remappable remote buttons for **rooted 2018 LG TVs (webOS 4.x)**.

🇪🇸 [Léeme en español](README.es.md)

---

2018 LG TVs ship with ~840 MB of RAM and spend a good chunk of it keeping Netflix, the
browser and other apps preloaded in the background whether you use them or not. The result
is a TV that swaps, stutters and takes forever to open anything.

Measured on a **43UK6300PSB** (webOS 4.4.3, firmware 05.50.70):

| | Before | After |
|---|---|---|
| Available RAM | 183 MB | **373 MB** |
| Swap in use | 197 MB | 0 MB |
| Preloaded apps | 9 | 0 |
| Remote buttons | Netflix / Prime Video, fixed | any app you like |

Most projects of this kind target 2019 and newer. [LGlow](https://github.com/IrvingGuerra/lglow),
the obvious choice, explicitly excludes 2018 because it replaces the full-screen home
(`com.webos.app.fullhome`) that webOS 4.5 introduced — 2018 TVs don't have it. This repo is
what's left once you accept that, and it turned out to be the part that actually matters.

## What it does

**Stops app preloading.** LG keeps up to 2 apps resident from a list of 9. Disabling that is
where almost all of the memory comes back.

**Stops AirPlay and HomeKit** (optional, `STOP_AIRPLAY=0` to keep them). Together they hold
~35 MB permanently.

**Remaps the Netflix and Amazon hotkeys** on the remote to any installed app.

It does **not** replace your home screen. For that, install
[Hearth](https://github.com/rudra-avatar/webos-custom-launcher) from the Homebrew Channel —
see [Home screen](#home-screen) below for the webOS 4 caveat.

## Requirements

- A 2018 LG TV (webOS 4.x), **rooted**, with the Homebrew Channel installed.
- SSH access to the TV.

Not rooted yet? Check [cani.rootmy.tv](https://cani.rootmy.tv/) with your model and firmware
first. If it's still rootable, [dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot)
works from a USB stick with no developer mode and no LG account.

> **Turn off automatic updates before anything else.** Once LG ships a patched firmware to
> your TV, rooting it is over for good. In Homebrew Channel, also enable **Block system updates**.

## Install

```sh
git clone https://github.com/josearevalo19977722-dev/lg-webos4-tweaks
cd lg-webos4-tweaks

# RAM only
ssh root@<TV-IP> 'sh -s' < install.sh

# RAM + remap both remote buttons
ssh root@<TV-IP> 'NETFLIX_BUTTON=youtube.leanback.v4 \
                  AMAZON_BUTTON=com.disney.disneyplus-prod sh -s' < install.sh
```

Then reboot the TV. List your app IDs with:

```sh
ssh root@<TV-IP> 'luna-send -n 1 -f luna://com.webos.applicationManager/listApps "{}" </dev/null'
```

### Options

| Variable | Effect |
|---|---|
| `NETFLIX_BUTTON=<appId>` | remap the Netflix hotkey |
| `AMAZON_BUTTON=<appId>` | remap the Amazon hotkey |
| `STOP_AIRPLAY=0` | keep AirPlay and HomeKit running |
| `SKIP_PRELOAD=1` | leave preloading alone |
| `SKIP_BUTTONS=1` | leave the remote alone |

## Uninstall

```sh
ssh root@<TV-IP> 'sh -s' < uninstall.sh
```

Reboot and you're back to stock. **No file on LG's partitions is ever modified** — patched
copies live in `/var/lib/webosbrew` and are bind-mounted on top at boot, so removing the
scripts and rebooting is a complete revert.

## How it works

Everything below was worked out on a live TV; it's written down because none of it is
documented anywhere for webOS 4.

### Preloading lives in a read-only config

`/etc/configd/layers/base/com.webos.service.preloadmanager.json` and its per-resolution
variants under `distro/` list which apps get preloaded. `/etc` is read-only (and the overlay
is 100% full), so the installer generates a copy with every `isEnabled` set to `false` and
`maxPreloadApp: 0`, and the boot script bind-mounts it over all five paths.

The copy is generated **from your TV's own file**, so it works on models whose app list
differs from the one this was built on.

### HomeKit comes back if you just stop it

`airplay-adaptor` is a normal upstart job. `homekit` is not — it's spawned on demand by
`ls-hubd`, the Luna service bus, so its parent respawns it. `kill -9` makes it stay down.

### The remote's hotkeys are in a JavaScript file

Not in `com.webos.keyaction.json` — that only covers system keys (volume, guide, subtitles).
The app hotkeys are in `handleCPHotkeys()` inside
`/usr/lib/qt5/qml/KeyFilters/appLaunch.js`, loaded by the compositor:

```js
case WebOS.Key_webOS_Netflix:  appId = "netflix";  break;
case WebOS.Key_webOS_Amazon:   appId = "amazon";   break;
case WebOS.Key_webOS_IVI:      appId = "ivi";      break;
```

Two string literals. That's the whole binding.

### …and mounting the patch is not enough

This one cost an extra reboot to find:

```
 2s  surface-manager starts and reads appLaunch.js
42s  webOS runs start-devmode.sh, which chains the Homebrew Channel startup
44s  our script bind-mounts the patched file  ← too late
```

The compositor never re-reads the file, and there is no earlier hook available, so
`20-remote-buttons` restarts `surface-manager` after mounting. You'll see one UI blink
during boot. A welcome side effect: restarting the compositor after boot settles frees
another ~80 MB.

To confirm it worked, check that `surface-manager`'s start offset is **later** than 44s:

```sh
sm=$(pgrep -x surface-manager)
echo $(( $(awk '{print $22}' /proc/$sm/stat) / $(getconf CLK_TCK) ))s
```

### `luna-send` fails silently without stdin

If stdin isn't redirected, `luna-send` exits 0 and does nothing — no output, no error. Every
call needs `</dev/null`. Expect to lose an hour to this one.

## Home screen

[Hearth](https://github.com/rudra-avatar/webos-custom-launcher) runs fine on webOS 4 even
though it's only tested from webOS 7 upward, because it builds for Chrome 53.

Its **"make this launcher the default instead of LG Home"** option does **not** work on
webOS 4 — the Home button keeps opening LG's launcher bar. What does work: enable
**"Add the launcher as a TV input"**. It then appears next to HDMI 1/2/3, and the TV returns
to that input on power-on, so it boots straight into Hearth. There is no "boot into app X"
setting — `powerOnScreen` only accepts `todays` or `liveTv`.

## Ad-free YouTube

The stock YouTube app is `"type": "native"` with `"main": "cobalt"` — Google's lightweight TV
engine. The official [youtube-webos](https://github.com/webosbrew/youtube-webos) is a `web`
app, so on a 2018 TV it runs in Chrome 53 and declares no webOS 4 support.

[NicholasBly's fork](https://github.com/NicholasBly/youtube-webos) explicitly supports webOS 3
and 4 and keeps the translation layers older TVs need. Use its **standard** build, not the
`webOS22+` one. Confirmed working on a 43UK6300PSB.

Either way you must uninstall the stock YouTube first — they share the `youtube.leanback.v4`
app ID. It's reinstallable from the LG Content Store, which keeps working: blocking updates
only redirects `su.lge.com` and `snu.lge.com`.

## Credits

Built on [webOS Homebrew Project](https://www.webosbrew.org/),
[dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) and
[LGlow](https://github.com/IrvingGuerra/lglow), whose approach of never writing to LG's
partitions this project follows.

Not affiliated with LG. Rooting and modifying your TV is your own responsibility.

## License

MIT — see [LICENSE](LICENSE). No LG code is included: every patched file is generated on
your own device from the files already on it.
