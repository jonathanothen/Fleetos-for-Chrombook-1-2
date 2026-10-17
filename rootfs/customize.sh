#!/bin/bash
# Runs INSIDE the armhf chroot after the packages are installed.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Locale, time, keyboard (Swedish default; Nordic layouts switchable) ---
sed -i 's/^# *sv_SE.UTF-8/sv_SE.UTF-8/; s/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=sv_SE.UTF-8
ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
echo Europe/Stockholm > /etc/timezone
# /etc/default/keyboard comes from the overlay; apply to the console
setupcon --save-only 2>/dev/null || true

# --- Users ---
# No built-in account and no shared password. The first user is created by the
# first-boot wizard (fleet-setup.service). root has no password (locked).
echo "fleet" > /etc/hostname
echo "127.0.1.1 fleet" >> /etc/hosts

# --- Kernel (our own build, drivers built in) ---
apt-get -y install initramfs-tools
mkdir -p /etc/initramfs-tools
echo "update_initramfs=no" > /etc/initramfs-tools/update-initramfs.conf   # no initramfs needed
apt-get -y install /tmp/linux-image-*.deb
rm -f /tmp/linux-image-*.deb

# --- Mac-like look: WhiteSur theme + icons (fetched at build time) ---
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme /tmp/ws-gtk
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme /tmp/ws-icons
( cd /tmp/ws-gtk && git rev-parse HEAD > /usr/share/fleet-theme-gtk.rev && ./install.sh -d /usr/share/themes -n WhiteSur -c Light 2>&1 | tail -3 ) || true
( cd /tmp/ws-icons && git rev-parse HEAD > /usr/share/fleet-theme-icons.rev && ./install.sh -d /usr/share/icons 2>&1 | tail -3 ) || true
rm -rf /tmp/ws-gtk /tmp/ws-icons

# --- Services ---
# First-boot wizard: runs on the installed machine, not on the install stick (see fleet-setup.service)
touch /etc/fleet-needs-setup
# ssh is installed but NOT enabled: no remote access until the owner turns it on
# (sudo systemctl enable --now ssh).
for s in lightdm NetworkManager fleet-firstboot.service fleet-mark-good.service fleet-installer.service fleet-setup.service fleet-installer-shell.service fleet-usb-boot.service fleet-audio-init.service zramswap; do
  systemctl enable "$s" || echo "WARN: could not enable $s"
done
systemctl set-default graphical.target
# SSH host keys and machine-id must be unique per machine -> created at first boot
rm -f /etc/ssh/ssh_host_*
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id

# --- Cleanup ---
apt-get -y autoremove --purge || true
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/* /tmp/* /root/.cache
find /usr/share/doc -type f ! -name copyright -delete 2>/dev/null || true
find /usr/share/man /usr/share/info -type f -delete 2>/dev/null || true
