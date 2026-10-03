#!/bin/bash
# libxkbcommon（Android aarch64）交叉编译：Rust 合成器的 build.rs 强制要求
# 一个非空的 libxkbcommon.so（smithay_android feature）。
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends meson ninja-build bison xz-utils wget >/dev/null 2>&1
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] || continue
  sed -i "s|http://archive.ubuntu.com/ubuntu/|http://mirrors.ustc.edu.cn/ubuntu/|g" "$f"
  sed -i "s/^Types: deb$/Types: deb deb-src/" "$f"
done
apt-get update -qq >/dev/null 2>&1

NDK=/opt/android-sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64
W=${RUNGIC_ROOT:-$HOME/projects/Rungic}/.work/deps/libxkbcommon
mkdir -p "$W"; cd "$W"
if [ ! -d src ]; then
  echo "=== 取 Ubuntu 26.04 的 libxkbcommon 1.13.1 源码 ==="
  apt-get source -qq libxkbcommon >/dev/null 2>&1
  mv libxkbcommon-* src 2>/dev/null || true
fi
cd "$W/src"
cat > "$W/android-arm64.ini" <<EOF
[binaries]
c = '$NDK/bin/aarch64-linux-android24-clang'
cpp = '$NDK/bin/aarch64-linux-android24-clang++'
ar = '$NDK/bin/llvm-ar'
strip = '$NDK/bin/llvm-strip'
ld = '$NDK/bin/aarch64-linux-android24-clang'
pkg-config = '/bin/false'

[properties]
sys_root = '$NDK/sysroot'
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
rm -rf build-android
echo "=== meson setup（Android aarch64 交叉）==="
meson setup build-android --cross-file "$W/android-arm64.ini" \
  -Dxkbcommon-x11=disabled -Denable-wayland=false \
  -Ddefault_library=shared -Denable-xkcb=disabled 2>&1 | tail -6
echo "=== ninja ==="
ninja -C build-android 2>&1 | tail -5
echo "=== 产物 ==="
find build-android -name "libxkbcommon.so*" -exec ls -la {} \;
