#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends meson ninja-build bison >/dev/null 2>&1
NDK=/opt/android-sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64
W=${RUNGIC_ROOT:-$HOME/projects/Rungic}/.work/deps/libxkbcommon
cd "$W"
SRC=$(ls -d libxkbcommon-1.13.1 2>/dev/null || ls -d libxkbcommon-* | head -1)
echo "源码目录: $SRC"
cd "$SRC"
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
echo "=== meson setup ==="
meson setup build-android --cross-file "$W/android-arm64.ini" \
  -Denable-x11=false -Denable-xkbregistry=false -Denable-tools=false -Denable-bash-completion=false -Denable-wayland=false \
  -Ddefault_library=shared 2>&1 | tail -8
echo "=== ninja ==="
ninja -C build-android 2>&1 | tail -5
echo "=== 产物 ==="
find build-android -name "libxkbcommon.so*" -exec ls -la {} \;
