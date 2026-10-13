#!/bin/sh
# OMR v0.63 rpi4 image: /etc/config/fstab has a mount entry for '/' with
# enabled_fsck=1. At boot, block remounts root read-only for fsck and never
# remounts it rw -> apk, uci commit, passwd all fail.
# Root is already mounted by the kernel (root=/dev/mmcblk0p2), so drop the entry.
mount -o remount,rw /
i=0
while uci -q get fstab.@mount[$i] >/dev/null; do
	if [ "$(uci -q get fstab.@mount[$i].target)" = "/" ]; then
		uci delete fstab.@mount[$i]
		uci commit fstab
		echo "removed fstab entry for /"
		break
	fi
	i=$((i+1))
done
# boot FAT partition was not cleanly unmounted (power pulled)
umount /boot 2>/dev/null && fsck.fat -a /dev/mmcblk0p1; mount /boot 2>/dev/null
echo "reboot, then check: touch /root/test && echo RW OK"
echo "Always 'poweroff' before pulling power."
