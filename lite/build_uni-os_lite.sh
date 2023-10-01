#!/bin/bash

#
# Build script for uni-os lite ISO
#
# This script based and inspired by:
#   - https://help.ubuntu.com/community/LiveCDCustomization
#   - https://bazaar.launchpad.net/~timo-jyrinki/ubuntu-fi-remix/main/files
#   - https://github.com/estobuntu/ubuntu-estonian-remix 
#   - https://code.launchpad.net/~ubuntu-cdimage/debian-cd/ubuntu
#   - https://github.com/jkbys/ubuntu-ja-remix
#
# Author: Yamato Tanikawa <tanick_developer@outlook.jp>
#
# License CC-BY-SA 3.0: http://creativecommons.org/licenses/by-sa/3.0/
#

INPUT_ISO="debian-live-11.7.0-amd64-standard+nonfree.iso"
OUTPUT_ISO="uni-os_lite_1.0_amd64.iso"
VOLUME_ID="uni-os lite 1.0 amd64"
NAMESERVER="1.1.1.1"
#TIMEZONE="Asia/Tokyo"
#ZONEINFO_FILE="/usr/share/zoneinfo/Asia/Tokyo"

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

cp /root/build-config/apt/trusted.gpg.d/* /etc/apt/trusted.gpg.d/
cp /root/build-config/apt/sources.list.d/* /etc/apt/sources.list.d/
cp /root/build-config/apt/sources.list /etc/apt/sources.list

apt-get update
apt-get install -y uni-desktop /root/build-config/packages/*.deb
apt-get autopurge -y
apt-get purge -y uni-os-build-conflicts

cp /root/build-config/lightdm/slick-greeter.conf /etc/lightdm/

plymouth-set-default-theme -R link

sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=`cat \/etc\/os-release | grep PRETTY_NAME= | cut -d \\" -f 2`/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
echo 'GRUB_THEME="/usr/share/grub/themes/zorin/theme.txt"' >> /etc/default/grub

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
mksquashfs edit/ extract-cd/live/filesystem.squashfs -xattrs -comp xz
log "Done."

# make iso
log "Making $OUTPUT_ISO ..." 
xorriso \
  -as mkisofs  \
  -volid "$VOLUME_ID" \
  -o "$OUTPUT_ISO" \
  -J -joliet-long -l  \
  -b isolinux/isolinux.bin  \
  -no-emul-boot  \
  -boot-load-size 4  \
  -boot-info-table  \
  --grub2-boot-info  \
  -append_partition 2 0xef boot/grub/efi.img  \
  -appended_part_as_gpt  \
  --mbr-force-bootable  \
  -eltorito-alt-boot  \
  -e --interval:appended_partition_2:all::  \
  -no-emul-boot \
  -partition_offset 16 \
  -r \
  extract-cd/
log "Done."

# umount
umount squashfs/
umount mnt/
