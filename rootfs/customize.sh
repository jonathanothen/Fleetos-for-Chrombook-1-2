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

# --- Mac-like look: WhiteSur GTK/xfwm4 themes and icons ---
# They are installed on the build host by rootfs/host-themes.sh (a mmdebstrap hook that runs before this script).
# Stop here if they are missing: a WhiteSur-less image has no window frames and no base for the FleetOS themes.
for t in WhiteSur-Light WhiteSur-Dark; do
  [ -f "/usr/share/fleet-base/themes/$t/gtk-3.0/gtk.css" ] || { echo "ERROR: $t is missing (host-themes.sh failed?)"; exit 1; }
done
[ -d /usr/share/icons/WhiteSur ] || { echo "ERROR: icon theme WhiteSur is missing"; exit 1; }
# FleetOS themes (light, midnatt, solnedgang, mynta, sakura) are generated from small palette files
chmod +x /usr/local/sbin/fleet-theme-gen /usr/local/bin/fleet-theme
/usr/local/sbin/fleet-theme-gen
# The appearance settings should list FleetOS themes only: drop every other GTK/window-frame theme package files
# (Default, Emacs, Raleigh, HighContrast ...). The WhiteSur base lives in /usr/share/fleet-base, not here.
find /usr/share/themes -mindepth 1 -maxdepth 1 ! -name 'FleetOS*' -exec rm -rf {} +
ls /usr/share/themes | tr '\n' ' '; echo
[ "$(ls -d /usr/share/themes/FleetOS* | wc -l)" -eq 5 ] || { echo "ERROR: expected 5 FleetOS themes"; exit 1; }

# --- Services ---
# First-boot wizard: runs on the installed machine, not on the install stick (see fleet-setup.service)
touch /etc/fleet-needs-setup
# ssh is installed but NOT enabled: no remote access until the owner turns it on
# (sudo systemctl enable --now ssh).
for s in lightdm NetworkManager fleet-firstboot.service fleet-mark-good.service fleet-installer.service fleet-setup.service fleet-installer-shell.service fleet-usb-boot.service fleet-audio-init.service zramswap; do
  systemctl enable "$s" || echo "WARN: could not enable $s"
done
# sudoers drop-ins must be mode 0440 and valid, or sudo ignores them
chmod 0440 /etc/sudoers.d/fleet-brightness
visudo -cf /etc/sudoers.d/fleet-brightness
# Debian enables ssh automatically when openssh-server is installed; turn it off explicitly.
systemctl disable ssh.service ssh.socket 2>/dev/null || true
# Speed: units that only cost boot time or idle CPU/RAM on these machines. All still start on demand where
# something needs them (blueman-mechanism is D-Bus activated; e2scrub is for LVM, we use plain ext4).
systemctl disable blueman-mechanism.service e2scrub_reap.service e2scrub_all.timer man-db.timer \
  NetworkManager-wait-online.service 2>/dev/null || true
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
