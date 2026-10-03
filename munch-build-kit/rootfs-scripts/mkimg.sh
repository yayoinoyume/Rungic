#!/bin/bash
# Pack the ARM64 root tree into a single sparse ext4 image. A single file avoids
# the absolute-symlink limitation of Android's tar extractor entirely.
set -euxo pipefail
IMG=/w/rootfs.img
[ -e "$IMG" ] && mv "$IMG" "$IMG.old.$(date +%s)"
truncate -s 3G "$IMG"
mkfs.ext4 -q -F -L rungic -d /w/rootfs "$IMG"
e2fsck -fy "$IMG" >/dev/null 2>&1 || true
ls -la "$IMG"
du -sh "$IMG"
