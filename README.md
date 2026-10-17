# FleetOS for Samsung Chromebook XE303C12 (snow) + XE503C12 (peach-pit)

Debian 13 (armhf) + XFCE with a macOS-like look (WhiteSur theme + Plank dock), custom
kernel with all drivers built in, Swedish default keyboard (se, no, dk, fi switchable with Alt+Shift).
One USB stick wipes the internal eMMC and installs the system. No dual boot.

## 1. Build (no Linux needed: GitHub Actions)

1. Create a private GitHub repo and push this folder to it.
2. No secrets or passwords are needed: the image contains **no user account**. The first-boot wizard
   lets the owner create their own user (see "First boot" below).
3. Actions -> "Build FleetOS USB image" -> Run workflow (usb_model = `auto`).
4. Download the artifact `fleetos-usb-auto` (a `.img.xz`, about 1.5 GB).

Local build alternative (Debian/Ubuntu or WSL2): `sudo ./build.sh deps && sudo ./build.sh all`

## First boot

On the first start of an installed machine a graphical wizard (before the login screen) asks for language,
keyboard (se/no/dk/fi), name, username, password, computer name and Wi-Fi. The user it creates is the
administrator (member of `sudo`). There is no built-in or shared account, root has no password, and SSH is
installed but disabled. If the graphical wizard cannot run, a text-mode wizard takes over, so a machine can
never be left without a way to log in. This makes the machines safe to hand over or resell.

To reuse a machine for someone else: reinstall with the stick (it wipes the disk) and the wizard runs again.

## 2. Write the stick (Windows)

Use balenaEtcher (reads `.img.xz` directly) -> select the file -> select a USB stick (8 GB+) -> Flash.

## 3. Prepare each Chromebook once (developer mode)

1. Power off. Hold Esc + Refresh, press Power. At the recovery screen press Ctrl+D, confirm. (ChromeOS is wiped, takes ~5 min.)
2. In ChromeOS (or on the dev-mode screen) USB boot must be allowed. On first ChromeOS setup screen press Ctrl+Alt+F2, log in as `chronos`, run:
   `sudo crossystem dev_boot_usb=1 dev_boot_signed_only=0`
3. Insert the stick, reboot, at the "OS verification is OFF" screen press Ctrl+U.

## 4. Install

The stick boots straight into the installer: 15 s countdown (press any key to abort),
then it repartitions eMMC, copies the system, writes the kernel and powers off.
Remove the stick, power on, press Ctrl+D (or wait 30 s) on the dev-mode screen.
Hostname becomes `fleet-<last 6 of MAC>`; SSH host keys are generated at first boot.

## Updates

- Debian security updates: automatic (unattended-upgrades).
- Kernel: a hook in `/etc/kernel/postinst.d/zz-fleet-kernel` writes each new kernel to the
  inactive slot (A/B); if it fails to boot 3 times the firmware falls back to the old one.
  A custom apt repo for the kernel/meta packages is the next step.

## Status: UNTESTED ON HARDWARE

Points that must be verified on one XE303C12 and one XE503C12 first:
- FIT with several dtbs on the stick (`auto`): if depthcharge picks the wrong dtb, build `usb_model=snow` and `pit` sticks separately.
- Kernel config symbol names (a missing driver shows up as a warning in the kernel build log).
- Wifi firmware (`mrvl/sd8797_uapsta.bin`) and sound on both models.
