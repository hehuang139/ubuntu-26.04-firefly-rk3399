#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Generate and validate a disk image from a prepared staging directory.
set -euo pipefail
mode=${1:?usage: assemble.sh sd|emmc}
case $mode in
  sd) signature=26339001; label=FF3399-TF; expected=074afaeec584916a1d7d939b4d46a328c804c5e0754e81207ed656874f48c23c ;;
  emmc) signature=26339002; label=FF3399-EMMC; expected=cb2c57287af28b1abc4cb93be985a9c0afff1d6b9553429c2b9392f4b1577e8f ;;
  *) exit 2 ;;
esac
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=${FIREFLY_OUTPUT:-/out/outputs}
cd -- "${FIREFLY_STAGE:-/out}"
root=$PWD/rootfs
loader="$project/bootloader/$mode/u-boot-rockchip.bin"
read -r release < records/kernel-release.txt
printf '%s  %s\n' "$expected" "$loader" | sha256sum -c -
mkdir -p -- "$output"
out="$output/firefly-rk3399-ubuntu-26.04.1-gnome-arm64-${mode}-test1.img"
asset="$out.gz"
[[ ! -e $out && ! -L $out && ! -e $asset && ! -L $asset ]]
tmp=$(mktemp -d "assemble-$mode.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
size_mib=7168
root_mib=16
partuuid="$signature-01"
printf '%s\n' "$partuuid" > "$root/etc/firefly-root-partuuid"
printf 'PARTUUID=%s / ext4 defaults,noatime 0 1\n' "$partuuid" > "$root/etc/fstab"
FIREFLY_ROOTFS="$root" bash "$root/usr/local/sbin/firefly-update-boot" "$release"
grep -q "APPEND root=PARTUUID=$partuuid " "$root/boot/extlinux/extlinux.conf"
[[ -s $root/boot/firefly/$release/Image ]]
[[ -s $root/boot/firefly/$release/rk3399-firefly.dtb ]]
[[ -s $root/boot/initrd.img-$release ]]
# MBR fits systems containing a stock Rockchip loader at sector 64.
truncate -s "${size_mib}M" "$tmp/disk.img"
sectors=$(( (size_mib - root_mib) * 2048 ))
start=$(( root_mib * 2048 ))
printf 'label: dos\nlabel-id: 0x%s\nunit: sectors\n\nstart=%s, size=%s, type=83, bootable\n' "$signature" "$start" "$sectors" |
    sfdisk --no-reread "$tmp/disk.img"
[[ $(stat -c %s "$loader") -le $(( root_mib * 1048576 - 32768 )) ]]
dd if="$loader" of="$tmp/disk.img" bs=512 seek=64 conv=notrunc status=none
truncate -s "$(( size_mib - root_mib ))M" "$tmp/root.ext4"
mkfs.ext4 -q -F -L "$label" -O '^64bit,^metadata_csum' \
    -E lazy_itable_init=0,lazy_journal_init=0 -m 1 -d "$root" "$tmp/root.ext4"
e2fsck -f -n "$tmp/root.ext4"
dd if="$tmp/root.ext4" of="$tmp/disk.img" bs=1M seek="$root_mib" conv=notrunc,sparse status=none
python3 "$project/scripts/verify.py" "$tmp/disk.img" "$mode" "$loader" "$tmp/root.ext4"
unlink "$tmp/root.ext4"
if [[ ${FIREFLY_RAW_ONLY:-0} == 1 ]]; then
  mv -- "$tmp/disk.img" "$out"
  printf 'Raw image ready: %s\n' "$out"
else
  staging=$(mktemp "$asset.partial.XXXXXX")
  trap 'rm -rf -- "$tmp"; rm -f -- "$staging"' EXIT
  raw_hash=$(sha256sum "$tmp/disk.img" | cut -d ' ' -f1)
  if command -v pigz >/dev/null; then
    pigz -p 6 -n -3 -c "$tmp/disk.img" > "$staging"
  else
    gzip -n -1 -c "$tmp/disk.img" > "$staging"
  fi
  [[ $(gzip -dc -- "$staging" | sha256sum | cut -d ' ' -f1) == "$raw_hash" ]]
  chmod 0644 "$staging"
  mv -T -- "$staging" "$asset"
  printf '%s  %s\n' "$raw_hash" "${out##*/}" > "$output/${out##*/}.sha256"
  (cd -- "$output" && sha256sum "${asset##*/}" > "${asset##*/}.sha256")
  printf 'Compressed image ready: %s\n' "$asset"
fi
