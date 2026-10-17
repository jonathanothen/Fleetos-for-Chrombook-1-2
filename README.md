# FleetOS for Samsung Chromebook XE303C12 (snow) and XE503C12 (peach-pit)

A light, stable Debian 13 (armhf) with XFCE and a macOS-like look, built for old Exynos Chromebooks so they
can be reused instead of discarded.

- **Desktop:** XFCE with the WhiteSur base theme, a flat rounded FleetOS theme layer (5 colour themes,
  switchable at runtime), a Plank dock, and a top panel with menu, window list, Wi-Fi, volume, battery %,
  keyboard layout and clock.
- **Kernel:** our own Linux 6.12 LTS build with the Chromebook drivers built in (no initramfs), small enough
  for the old firmware to load (a big kernel is silently refused).
- **Install:** one USB stick wipes the internal eMMC and installs the system. No dual boot, no ChromeOS left.
- **No built-in account.** The first-boot wizard creates the owner's user, so machines can be handed over or resold.

Status: verified on an XE303C12: USB boot, installer, setup wizard, desktop and audio. Fixes for Wi-Fi, battery %
at login, brightness keys and the keyboard layout are in the code and still being verified (see "Known issues").
The XE503C12 is untested.

## 1. Build (no Linux needed: GitHub Actions)

1. Create a private GitHub repo and push this folder to it (GitHub Desktop is the easiest way on Windows;
   the hidden folders `.github` and `rootfs/overlay/etc/skel/.config` must be included).
2. No secrets or passwords are needed.
3. Actions -> "Build FleetOS USB image" -> Run workflow (`usb_model` = `auto`).
   The kernel is cached between runs; a change to `kernel/` rebuilds it (about 30-40 minutes).
4. Download the artifact `fleetos-usb-auto` (a zip containing a `.img.xz`, about 350 MB; the `.img` is about 2 GB).

The build refuses to produce an image if the root filesystem fails `e2fsck`, if the kernel config lacks critical
options, or if the Wi-Fi driver patch does not apply.

Local build alternative (Debian/Ubuntu or WSL2): `sudo ./build.sh deps && sudo ./build.sh all`

## 2. Write the stick (Windows)

Unpack the zip, then the `.img.xz` (7-Zip), and write the `.img` with balenaEtcher (click Continue at the
"Missing partition table" warning; ChromeOS uses GPT without a regular MBR) or Rufus in DD Image mode.
Use a plain, preferably old, USB 2.0 stick (8 GB or larger). SD cards in USB readers often do not boot.

## 3. Prepare each Chromebook once (developer mode)

See [PREPARE-AND-TROUBLESHOOT.md](PREPARE-AND-TROUBLESHOOT.md): how to enter developer mode and how to enable
USB boot (`sudo enable_dev_usb_boot`). Then insert the stick before powering on and press Ctrl+U at the
"OS verification is OFF" screen.

## 4. Install

The stick boots straight into the installer: 15 s countdown (press any key to abort), then it repartitions the
eMMC, copies the system, writes the kernel (slot A plus a fallback slot B) and powers off. Remove the stick,
power on and press Ctrl+D (or wait 30 s) on the dev-mode screen.

## First boot (setup wizard)

Before the login screen a graphical wizard asks for:

1. **Language** (searchable list of ~40 languages, or any locale code) and **keyboard layout** (every layout and
   variant in the system, up to three, switchable with Alt+Shift).
2. **Name, username, password, computer name.** The username and computer name are suggested from your name and
   corrected automatically (lowercase a-z, digits, `-`; accents are transliterated, e.g. "Asa Oberg" -> `asaoberg`).
3. **Allow booting from USB** (needed to reinstall the machine; kept enabled at every boot if chosen).
4. **Wi-Fi** (network list; skipped with a notice if no adapter is found).

Layouts can be changed later, per user and without root, with **Tangentbord och layouter** in the menu
(`fleet-keyboard`): any layout and variant, up to three, switched with Alt+Shift.

The user it creates is the administrator (member of `sudo`). root has no password and SSH is installed but
disabled (`sudo systemctl enable --now ssh`). If the graphical wizard fails, a text-mode wizard takes over, so a
machine can never be left without a way to log in. To reuse a machine for someone else, reinstall with the stick.

## Themes

Five themes, generated at build time from small palette files in `rootfs/overlay/usr/share/fleet-themes/`
(`light`, `midnatt` dark, `solnedgang`, `mynta`, `sakura`). Switch with **Utseende** in the menu or
`fleet-theme set <id>` / `fleet-theme list`. A theme is a GTK CSS layer on top of WhiteSur, a Plank dock theme
and a flat SVG wallpaper; it also drives the login screen. The compositor is on by default (rounded menus, window shadows). It is software-rendered on these machines, so on a
very slow one you can turn it off with `fleet-effects off` (menus then become plain rectangles; `fleet-effects on`
restores it). A menu is two nested boxes (popup window + menu): the theme styles only the inner one, otherwise you
get "double corners".
To add one, copy a `.conf` file and give it a new `ID`,
`GTKNAME` and colours (the generator stops the build if a placeholder is missing).

## Hardware notes (snow)

- **Backlight:** only 8 steps (0-7). The brightness keys run `fleet-brightness up|down`, which steps one level and
  never goes to 0 (black screen). The `video` group may write the backlight; a passwordless `sudo brightnessctl`
  is the fallback.
- **Audio:** ALSA mixers start muted. `fleet-audio-init` unmutes and sets sane levels on first boot
  (amplifiers 45 %); run `sudo fleet-audio-init force` to redo it.
- **Battery:** `upower` needs user namespaces in the kernel (included). If the panel shows no battery %, run
  `sudo fleet-diag`.
- **Wi-Fi (Marvell 88W8797):** needs `firmware-libertas`. The mainline driver treats an unsupported init command
  (`0x242`) as fatal on this chip, so `kernel/build-kernel.sh` applies a small patch.
- **USB boot flag:** `sudo fleet-usb-boot on|off|status`.

## Updates

- Debian security updates: automatic (unattended-upgrades).
- Kernel: a hook in `/etc/kernel/postinst.d/zz-fleet-kernel` writes each new kernel to the inactive slot (A/B);
  if it fails to boot 3 times the firmware falls back to the old one. A custom apt repo for the kernel and
  meta packages is the next step.

## Diagnostics

`sudo fleet-diag` writes `/tmp/fleet-diag.txt` (failed units, Wi-Fi log, audio controls, backlight, battery,
panel processes). Attach it to bug reports.

## Known issues / to verify

- XE503C12 (peach-pit) is untested: Wi-Fi, sound and the shared USB stick (`auto`) must be checked on one.
- If the firmware picks the wrong device tree on the `auto` stick, build `usb_model=snow` and `pit` sticks.
- Wi-Fi depends on the driver patch above; if `wlan0` is missing, run `fleet-diag` and look for `mwifiex` lines.
- `console-setup.service` may fail on the console (not the desktop); it was caused by an invalid keyboard variant
  that the wizard no longer writes.
- Chinese, Japanese and Korean need extra fonts (`fonts-noto-cjk`), which are not installed.

## Project layout

```
build.sh, config.env              build driver and settings
kernel/                           kernel config fragment and cross-build script (with the Wi-Fi patch)
rootfs/packages.txt               Debian packages
rootfs/host-themes.sh             installs WhiteSur themes/icons on the build host (no qemu); fails the build on error
rootfs/customize.sh               runs in the armhf chroot (FleetOS themes, services, cleanup)
rootfs/overlay/                   files copied into the image (scripts, units, theme sources, skel)
.github/workflows/build.yml       GitHub Actions build
```
