#!/bin/bash
set -euxo pipefail
R=/w/rootfs
A=/artifacts/mesa

cleanup() { echo -1 > /proc/sys/fs/binfmt_misc/rungic-aarch64 2>/dev/null || true; }
trap cleanup EXIT
mount --make-rprivate / 2>/dev/null || true
if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
[ -e /proc/sys/fs/binfmt_misc/rungic-aarch64 ] && cleanup
printf ':rungic-aarch64:M:18:\xb7\x00::/usr/bin/qemu-aarch64:CF\n' > /proc/sys/fs/binfmt_misc/register

for d in proc sys dev dev/pts; do
  mkdir -p "$R/$d"
  mountpoint -q "$R/$d" || mount --bind /$d "$R/$d"
done
cp /etc/resolv.conf "$R/etc/resolv.conf"

# The project's own sources use the full component set (system/config/etc/apt);
# minbase only wires up 'main', and vulkan-tools / libxcb-keysyms1 live outside it.
cat > "$R/etc/apt/sources.list" <<'SRC'
deb http://archive.ubuntu.com/ubuntu/ resolute main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ resolute-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ resolute-security main restricted universe multiverse
SRC

# Mesa's own external dependencies (desktop/package-mesa.py) + the GLVND
# dispatchers it deliberately leaves to the distribution + vulkaninfo.
RUNTIME="libc6 libdrm2 libexpat1 libelf1t64 libgcc-s1 libstdc++6 libzstd1 zlib1g libvulkan1
libwayland-client0 libwayland-server0 libx11-6 libx11-xcb1 libxcb1 libxcb-dri3-0
libxcb-present0 libxcb-randr0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-glx0
libxext6 libxfixes3 libxshmfence1 libxxf86vm1 libxcb-keysyms1 libdisplay-info3 libudev1
libglvnd0 libgl1 libegl1 vulkan-tools"
# shellcheck disable=SC2086
chroot "$R" env DEBIAN_FRONTEND=noninteractive apt-get update -qq
# shellcheck disable=SC2086
chroot "$R" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $RUNTIME

echo "--- install our Mesa build ---"
mkdir -p "$R/tmp/debs"
cp "$A"/*.deb "$R/tmp/debs/"
chroot "$R" bash -c 'dpkg -i /tmp/debs/*.deb'

echo "--- verify ---"
chroot "$R" dpkg -l | grep -E 'mesa|gbm|vulkan' | head -20
chroot "$R" bash -c 'ls -la /usr/lib/aarch64-linux-gnu/libgallium*.so /usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so /usr/share/vulkan/icd.d/'
chroot "$R" bash -c 'command -v vulkaninfo && vulkaninfo --summary 2>&1 | head -40' || echo "vulkaninfo needs a real GPU (expected under qemu)"
