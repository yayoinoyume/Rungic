#!/bin/bash
set -euxo pipefail
R=/w/rootfs
dpkg --add-architecture arm64
apt-get update -qq
mkdir -p /tmp/debs && cd /tmp/debs
apt-get download libgles2:arm64
for f in *.deb; do dpkg-deb -x "$f" "$R"; done
ls -la "$R/usr/lib/aarch64-linux-gnu/libGLESv2.so"* 2>&1 | head -3
