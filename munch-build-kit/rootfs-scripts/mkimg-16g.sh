#!/bin/bash
# 16 GiB sparse ext4 image of the ARM64 root tree (CI2 needs ~5 GB for the Plasma
# closure; the original 3 GiB image only had 2.5 GiB free). Same mkfs.ext4 -d
# approach as mkimg.sh, so no loop mount and no privileges are needed.
set -euxo pipefail
IMG=${IMG:-/w/rootfs-plasma.img}
[ -e "$IMG" ] && mv "$IMG" "$IMG.old.$(date +%s)"
truncate -s 16G "$IMG"
mkfs.ext4 -q -F -L rungic -d /w/rootfs "$IMG"
e2fsck -fy "$IMG" >/dev/null 2>&1 || true
echo "=== 结果 ==="
ls -la "$IMG"
echo "实际占用: $(du -h "$IMG" | cut -f1)"
dumpe2fs -h "$IMG" 2>/dev/null | grep -E "Block count|Free blocks|Block size"
