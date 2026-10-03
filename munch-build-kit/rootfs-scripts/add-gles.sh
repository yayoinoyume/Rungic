#!/bin/bash
# Add GLES/GLES2 inspection tooling to the arm64 root tree without running any
# arm64 binary: download the arm64 debs on the x86 host, then unpack them.
set -euxo pipefail
R=/w/rootfs
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq --download-only --no-install-recommends \
    mesa-utils:arm64 mesa-utils-bin:arm64 libgles2-mesa:arm64 2>/dev/null \
  || apt-get install -y -qq --download-only --no-install-recommends mesa-utils:arm64
mkdir -p /tmp/debs
cp /var/cache/apt/archives/*.deb /tmp/debs/ 2>/dev/null || true
ls /tmp/debs/*.deb | wc -l
for f in /tmp/debs/*.deb; do
  dpkg-deb -x "$f" "$R"
done
echo "--- installed binaries ---"
ls -la "$R/usr/bin/eglinfo" "$R/usr/bin/glxinfo" "$R/usr/bin/es2_info" "$R/usr/bin/es2gears_wayland" 2>&1 | head
echo "--- libGLESv2 / EGL vendor json ---"
ls -la "$R/usr/lib/aarch64-linux-gnu/libGLESv2.so"* "$R/usr/share/glvnd/egl_vendor.d/" 2>&1 | head
