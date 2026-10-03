#!/bin/bash
# 4.19 内核没有 DMABUF_HEAPS（5.6+ 才有），唯一出路是原厂 ION system heap。
# 之前 iononly 构建漏了 ION_SYSTEM_HEAP，导致 /dev/ion 也没有 system heap。
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KERNELVERSION=4.19.325-cip131-st15-perf-g71b13e62f057

echo "############### 0. toolchain ###############"
clang --version | head -1

echo "############### 1. mrproper ###############"
make mrproper > /logs/ion-mrproper.log 2>&1; echo "  mrproper rc=$?"

echo "############### 1b. firmware .i ###############"
FW=/build/drivers/input/touchscreen/focaltech_3658u/include/firmware
mkdir -p "$FW"
cp /inputs/focaltech-fw/fw_ft3658_l11r.i /inputs/focaltech-fw/fw_sample.i "$FW/"
echo "  injected: $(ls -la $FW | grep -c '\.i$') files"

echo "############### 2. stock + 6 LXC + ION_SYSTEM_HEAP ###############"
cp /inputs/stock.config .config
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS ION_SYSTEM_HEAP; do
  ./scripts/config --file .config -e $o
done
./scripts/config --file .config -d DMA_HEAP_SYSTEM
./scripts/config --file .config -d DMABUF_HEAPS
echo "  ION_SYSTEM_HEAP=$(grep -E '^CONFIG_ION_SYSTEM_HEAP=' .config | cut -d= -f2 || echo n)"

echo "############### 3. olddefconfig ###############"
make olddefconfig > /logs/ion-olddefconfig.log 2>&1; echo "  rc=$?"
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS QCOM_KGSL MODVERSIONS ION ION_SYSTEM_HEAP DMA_HEAP_SYSTEM; do
  printf "  CONFIG_%-16s %s\n" "$o" "$(grep -E "^CONFIG_$o=" .config | cut -d= -f2 || echo MISSING)"
done

echo "############### 3b. scmversion ###############"
cp /inputs/scmversion /build/.scmversion
make prepare > /logs/ion-prepare.log 2>&1
echo "  kernel.release = $(cat include/config/kernel.release)"

echo "############### 4. build ###############"
date '+  start %H:%M:%S'
make -j$(nproc) Image modules > /logs/ion-full.log 2>&1
RC=$?
date '+  end   %H:%M:%S'
echo "  MAKE_EXIT=$RC"
[ $RC -ne 0 ] && { echo "--- errors ---"; grep -E "fatal error:|error:" /logs/ion-full.log | sort -u | head -15; }

echo "############### 5. verify ###############"
echo "  release: $(cat include/config/kernel.release)"
if [ -f arch/arm64/boot/Image ]; then
  echo "  Image: $(stat -c %s arch/arm64/boot/Image) bytes"
  echo "  SHA256: $(sha256sum arch/arm64/boot/Image | cut -d' ' -f1)"
else
  echo "  NO IMAGE"
fi
echo "  .ko count: $(find . -name '*.ko' 2>/dev/null | wc -l)"
grep -qE '^CONFIG_ION_SYSTEM_HEAP=y' .config && echo "  ION_SYSTEM_HEAP=y OK" || echo "  ION_SYSTEM_HEAP NOT SET"
echo "  ion_system_heap_create symbols: $(nm vmlinux 2>/dev/null | grep -cE 'ion_system_heap_create')"
echo "DONE"
