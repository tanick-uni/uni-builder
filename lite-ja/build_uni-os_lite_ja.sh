#!/bin/bash

#
# Build script for uni-os lite ja ISO
#
# This script based and inspired by:
#   - https://help.ubuntu.com/community/LiveCDCustomization
#   - https://bazaar.launchpad.net/~timo-jyrinki/ubuntu-fi-remix/main/files
#   - https://github.com/estobuntu/ubuntu-estonian-remix 
#   - https://code.launchpad.net/~ubuntu-cdimage/debian-cd/ubuntu
#   - https://github.com/jkbys/ubuntu-ja-remix
#   - https://wiki.debian.org/RepackBootableISO
#
# Author: Yamato Tanikawa <tanick_developer@outlook.jp>
#
# License CC-BY-SA 3.0: http://creativecommons.org/licenses/by-sa/3.0/
#

INPUT_ISO="debian-live-11.7.0-amd64-standard+nonfree.iso"
OUTPUT_ISO="uni-os_lite_ja_1.0_amd64.iso"
VOLUME_ID="uni-os_lite_ja_1.0_amd64"
NAMESERVER="1.1.1.1"
TIMEZONE="Asia/Tokyo"
ZONEINFO_FILE="/usr/share/zoneinfo/Asia/Tokyo"

log() {
  echo "$(date -Iseconds) [info ] $*"
}

log_error() {
  echo "$(date -Iseconds) [error] $*" >&2
}

# only root can run
if [[ "$(id -u)" != "0" ]]; then
  log_error "This script must be run as root"
  exit 1
fi

# check existence of input iso
if [[ ! -f $INPUT_ISO ]]; then
  log_error "No Input ISO file: $INPUT_ISO"
  exit 1
fi

# install packages
apt-get install -y squashfs-tools xorriso rsync

# remove directories
log "Removing previously created directories ..."
umount squashfs/
umount mnt/
rm -rf edit/ extract-cd/ mnt/ squashfs/
log "Done."

# mount and copy
log "Mount ISO and copy files ..."
mkdir mnt
mount -o loop ${INPUT_ISO} mnt/
mkdir extract-cd
rsync -a --exclude=/live/filesystem.squashfs mnt/ extract-cd/
chmod +rw -R extract-cd/
log "Done."

# extract squashfs
log "Extracting squashfs ..."
mkdir squashfs
mount -t squashfs -o loop mnt/live/filesystem.squashfs squashfs
mkdir edit
cp -a squashfs/* edit/
log "Done."

# boot/grub/
cp build-config/grub/grub.cfg extract-cd/boot/grub/

# isolinux/
cp build-config/isolinux/menu.cfg extract-cd/isolinux/
cp build-config/isolinux/splash.png extract-cd/isolinux/

# copy build-config to chroot directory.
cp -r build-config edit/root/

mount --bind /dev/ edit/dev

# chroot start
log "Execute commands inside chroot"
chroot edit/ <<EOT
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

echo "nameserver $NAMESERVER" > /etc/resolv.conf

rm -f /etc/localtime
ln -s "$ZONEINFO_FILE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

cp /root/build-config/apt/trusted.gpg.d/* /etc/apt/trusted.gpg.d/
cp /root/build-config/apt/sources.list.d/* /etc/apt/sources.list.d/
cp /root/build-config/apt/sources.list /etc/apt/

apt-get update
apt-get install -y uni-desktop uni-desktop-l10n-ja /root/build-config/packages/*.deb
apt-get autopurge -y
apt-get purge -y uni-os-build-conflicts

cp /root/build-config/lightdm/slick-greeter.conf /etc/lightdm/

plymouth-set-default-theme -R link

update-locale LANG=ja_JP.UTF-8
sed -i 's/# ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
locale-gen --keep-existing

apt-get clean
umount /proc
umount /sys
umount /dev/pts

rm /etc/resolv.conf
EOT
# chroot end

# cleanup
rm -rf edit/root/build-config
rm -rf edit/root/.bash_history
rm -rf edit/tmp/*
rm -rf edit/var/lib/apt/lists/*
rm -rf edit/var/lib/dpkg/*-old
rm -rf edit/var/cache/debconf/*-old
umount edit/dev/

# make squashfs
log "Making filesystem.squashfs ..."
mksquashfs edit/ extract-cd/live/filesystem.squashfs -comp xz
log "Done."

# extract mbr template
dd if="$INPUT_ISO" bs=1 count=432 of=isohdpfx.bin

# make iso
log "Making $OUTPUT_ISO ..."
xorriso \
  -as mkisofs \
  -r -J --joliet-long \
  -V "$VOLUME_ID" \
  -o "$OUTPUT_ISO" \
  -isohybrid-mbr isohdpfx.bin \
  --mbr-force-bootable \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  extract-cd/
rm isohdpfx.bin
log "Done."

# calculate md5sum
md5sum $OUTPUT_ISO > $OUTPUT_ISO.md5

# umount
umount squashfs/
umount mnt/
