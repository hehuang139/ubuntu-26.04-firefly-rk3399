#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run in the project builder with /src read-only and /out on a scratch volume.
set -euo pipefail
cd /out
root=/out/rootfs
base=ubuntu-base-26.04.1-base-arm64.tar.gz
suite=resolute
if [[ ! -s $root/usr/lib/os-release ]]; then
    gpgv --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg inputs/SHA256SUMS.gpg inputs/SHA256SUMS
    printf '%s  %s\n' 5a1906794ced63a71a8119c3f211ef5f0bbe0a243001b4bbd41fdf80c5b219fd "inputs/$base" | sha256sum -c -
    mkdir -p "$root"
    tar -xpf "inputs/$base" --numeric-owner -C "$root"
fi
grep -Fxq "VERSION_CODENAME=$suite" "$root/usr/lib/os-release"
if [[ ! -e /proc/sys/fs/binfmt_misc/register ]]; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
registered=0
cleanup() {
    umount "$root/proc" "$root/sys" 2>/dev/null || true
    umount -R "$root/dev" 2>/dev/null || true
    if (( registered )); then update-binfmts --disable qemu-aarch64; fi
}
trap cleanup EXIT
if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    update-binfmts --enable qemu-aarch64
    registered=1
fi
mount -t proc proc "$root/proc"
mount -t sysfs -o ro sysfs "$root/sys"
mount --rbind /dev "$root/dev"
mount --make-rslave "$root/dev"
install -m 0755 /usr/bin/qemu-aarch64-static "$root/usr/bin/"
[[ ! -L $root/etc/resolv.conf ]] || unlink "$root/etc/resolv.conf"
cp -L /etc/resolv.conf "$root/etc/resolv.conf"
install -Dm 0644 "${FIREFLY_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}" "$root/run/firefly-build/ca-certificates.crt"
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 0755 "$root/usr/sbin/policy-rc.d"
[[ ! -f $root/etc/apt/sources.list ]] || truncate -s0 "$root/etc/apt/sources.list"
cat > "$root/etc/apt/sources.list.d/ubuntu.sources" <<SOURCES
Types: deb
URIs: https://ports.ubuntu.com/ubuntu-ports/
Suites: $suite $suite-updates $suite-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SOURCES
cat > "$root/etc/apt/apt.conf.d/90firefly-build" <<'APT'
Acquire::Retries "4";
Acquire::https::CaInfo "/run/firefly-build/ca-certificates.crt";
Acquire::Languages "none";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT
# Prevent stale service state from the chroot from reaching the image.
install -d "$root/etc/initramfs-tools/conf.d"
printf 'MODULES=most\nCOMPRESS=gzip\nFSTYPE=ext4\n' > "$root/etc/initramfs-tools/conf.d/20-firefly"
chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C /bin/bash -eux <<'ROOTFS'
[[ $(dpkg --print-architecture) == arm64 ]]
apt-get -o APT::Update::Error-Mode=any update
apt-cache policy linux-image-generic gnome-shell
apt-get install -y --no-install-recommends \
    linux-image-generic linux-firmware initramfs-tools e2fsprogs zstd \
    ubuntu-minimal systemd-sysv systemd-resolved systemd-timesyncd udev dbus-user-session \
    network-manager netplan.io wpasupplicant wireless-regdb \
    gdm3 gnome-initial-setup gnome-shell gnome-session gnome-control-center \
    nautilus gnome-keyring gnome-terminal gnome-calculator dconf-cli \
    gvfs-backends adwaita-icon-theme mesa-vulkan-drivers libgl1-mesa-dri \
    xwayland pipewire-audio alsa-utils bluez \
    locales language-pack-zh-hans language-pack-gnome-zh-hans tzdata fonts-noto-cjk fonts-noto-core \
    openssh-server sudo curl ethtool zram-tools cloud-guest-utils
apt-get check
test -z "$(dpkg --audit)"
locale-gen en_US.UTF-8 zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8
gnome-shell --version
passwd -l root
ROOTFS
mkdir -p records
chroot "$root" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' > records/packages.tsv
chroot "$root" apt-get clean
