#!/bin/bash
# ============================================================
# 版本串与原厂完全一致 + 6 项 LXC 配置 + DMABUF system_heap（/dev/dma_heap/system）
# 原厂 uname -r = 4.19.325-cip131-st15-perf-g71b13e62f057
# tarball 无 .git，setlocalversion 产不出 -g<hash> 后缀，
# 用 KERNELVERSION= 精确覆盖，使 vermagic 与原厂一致。
# ============================================================
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-

export KERNELVERSION=4.19.325-cip131-st15-perf-g71b13e62f057

echo "############### 0. 工具链 ###############"
clang --version | head -1

echo "############### 1. 干净重建 ###############"
make mrproper > /logs/f2-mrproper.log 2>&1; echo "  mrproper rc=$?  残留.o=$(find . -name '*.o' 2>/dev/null | wc -l)"

echo "############### 1b. 注入固件 .i 文件（mrproper 会删，必须在其后）###############"
FW=/build/drivers/input/touchscreen/focaltech_3658u/include/firmware
mkdir -p "$FW"
cp /inputs/focaltech-fw/fw_ft3658_l11r.i /inputs/focaltech-fw/fw_sample.i "$FW/"
echo "  已注入: $(ls -la $FW | grep -c '\.i$') 个 .i 文件"
for f in "$FW"/*.i; do printf "  %-22s %s 字节\n" "$(basename $f)" "$(stat -c %s "$f")"; done

echo "############### 2. 原厂配置 + 6 项 LXC ###############"
cp /inputs/stock.config .config
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS DMABUF_HEAPS DMA_HEAP_SYSTEM; do
  ./scripts/config --file .config -e $o
done
echo "  已注入: $(grep -cE '^CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|USER_NS|DEVTMPFS)=y' .config)/6 LXC + $(grep -cE '^CONFIG_(DMABUF_HEAPS|DMA_HEAP_SYSTEM)=y' .config)/2 dma-heap"

echo "############### 3. olddefconfig ###############"
make olddefconfig > /logs/f2-olddefconfig.log 2>&1; echo "  rc=$?"
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS QCOM_KGSL MODVERSIONS DMABUF_HEAPS DMA_HEAP_SYSTEM; do
  printf "  CONFIG_%-14s %s\n" "$o" "$(grep -E "^CONFIG_$o=" .config | cut -d= -f2 || echo MISSING)"
done

echo "############### 3b. 注入 .scmversion（需在 olddefconfig 之后，mrproper 也会删）###############"
# tarball 无 .git -> setlocalversion 产不出 -g<hash> 后缀。
# 用 .scmversion 补齐，使 kernel.release 与原厂 uname -r 完全一致（vermagic 必须匹配）
cp /inputs/scmversion /build/.scmversion
echo "  .scmversion  = $(cat /build/.scmversion)"
echo "  预期版本串   = 4.19.325$(/build/scripts/setlocalversion /build)"
make prepare > /logs/f2-prepare.log 2>&1
echo "  kernel.release = $(cat include/config/kernel.release)"

echo "############### 4. 全量编译 ###############"
date '+  start %H:%M:%S'
make -j$(nproc) Image modules > /logs/full-final2.log 2>&1
RC=$?
date '+  end   %H:%M:%S'
echo "  MAKE_EXIT=$RC"
[ $RC -ne 0 ] && { echo "--- 错误 ---"; grep -E "fatal error:|error:" /logs/full-final2.log | sort -u | head -15; }

echo "############### 5. 产物验收 ###############"
echo "  版本串: $(cat include/config/kernel.release)"
if [ -f arch/arm64/boot/Image ]; then
  echo "  Image: $(stat -c %s arch/arm64/boot/Image) 字节"
  echo "  SHA256: $(sha256sum arch/arm64/boot/Image | cut -d' ' -f1)"
else
  echo "  ❌ 无 Image"
fi
echo "  .ko 数: $(find . -name '*.ko' 2>/dev/null | wc -l)"
echo "--- system_heap 验收 ---"
if [ -f drivers/dma-buf/heaps/system_heap.o ]; then
  echo "  system_heap.o = $(stat -c %s drivers/dma-buf/heaps/system_heap.o) 字节"
  nm drivers/dma-buf/heaps/system_heap.o | grep -E ' T (system_heap_ioctl|system_heap_allocate|system_heap_mmap)$'
else
  echo "  ❌ system_heap.o 未生成"
fi
echo "  Module.symvers: $([ -f Module.symvers ] && wc -l < Module.symvers || echo 0) 行"
echo "--- 模块与 vermagic ---"
for k in $(find . -name '*.ko' 2>/dev/null); do
  echo "  $(basename $k): $(modinfo $k 2>/dev/null | grep ^vermagic | sed 's/vermagic:[[:space:]]*//')"
done
echo "--- 关键符号验收 ---"
for s in create_ipc_ns create_pid_namespace init_user_ns sem_init shm_init msg_init devtmpfs_init; do
  printf "  %-22s %s\n" "$s" "$(nm vmlinux 2>/dev/null | grep -cE " [TtDd] $s\$")"
done
echo "DONE"
