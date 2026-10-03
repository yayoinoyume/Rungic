#!/bin/bash
set -euxo pipefail
R=/w/rootfs
OUT=/w/ubuntu-mesa-rootfs.tar.gz
# Trim the package-manager residue; these are apt-generated caches, not payload.
for d in var/lib/apt/lists var/cache/apt var/log tmp; do
  find "$R/$d" -mindepth 1 -delete 2>/dev/null || true
done
mkdir -p "$R/dev" "$R/proc" "$R/sys" "$R/run"
echo "--- size before packing ---"
du -sh "$R"
# Exclude the runtime mount points; LXC/our enter helper bind them in.
tar --numeric-owner --xattrs --xattrs-include='*' -C "$R" \
    --exclude=./dev --exclude=./proc --exclude=./sys --exclude=./run \
    --exclude=./etc/alternatives --exclude=./usr/share/man \
    -czf "$OUT" .
ls -la "$OUT"
