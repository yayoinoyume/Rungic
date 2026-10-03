#!/bin/bash
set -euo pipefail
R=/w/rootfs
mkdir -p "$R"

# binfmt_misc entries live in the host kernel and outlive the container, and the
# interpreter path is container-local, so a stale entry would break the host.
# Drop any leftover, register ours, and unregister on exit.
cleanup() { echo -1 > /proc/sys/fs/binfmt_misc/rungic-aarch64 2>/dev/null || true; }
trap cleanup EXIT

mount --make-rprivate / 2>/dev/null || true
if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
[ -e /proc/sys/fs/binfmt_misc/rungic-aarch64 ] && cleanup
printf ':rungic-aarch64:M:18:\xb7\x00::/usr/bin/qemu-aarch64:CF\n' > /proc/sys/fs/binfmt_misc/register
echo "--- binfmt ---"
cat /proc/sys/fs/binfmt_misc/rungic-aarch64

echo "--- smoke test: run an arm64 binary under qemu ---"
apt-get update -qq
apt-get install -y -qq gcc-aarch64-linux-gnu arch-test
printf '#include <stdio.h>\nint main(){printf("arm64 under qemu OK\\n");return 0;}\n' > /tmp/t.c
aarch64-linux-gnu-gcc -static -o /tmp/t.aarch64 /tmp/t.c
/tmp/t.aarch64

echo "--- mmdebstrap arm64 minbase ---"
mmdebstrap --architectures=arm64 --variant=minbase --include=apt-utils resolute "$R" http://archive.ubuntu.com/ubuntu/
echo "--- done ---"
du -sh "$R"
