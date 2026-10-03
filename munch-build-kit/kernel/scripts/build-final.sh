#!/bin/bash
# ============================================================
# Redmi K40S (munch) LineageOS 23.2 内核重编 —— 干净全量
# 修复：techpack/*/Makefile 用 GNU make `export` 覆盖 Kconfig，
#       强制编译 .conf 里列出的子目录，但其 LINUXINCLUDE 的 -I
#       在递归 make 中不传递 -> 需要 KCFLAGS 全局补 -I
# ============================================================
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64
export LLVM=1 LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-

# ---- 修复项：三个目录各自缺自己的 -I ----
# drivers/clk/qcom/trace.h:  TRACE_INCLUDE_PATH=. + TRACE_INCLUDE_FILE=trace -> ./trace.h
# techpack/display/pll/pll_trace.h: 同理 -> ./pll_trace.h
# techpack/camera-xiaomi/include: uapi/media/cam_defs.h
# 不再用全局 KCFLAGS：会污染其他目录（如 regmap.c 的 #include "trace.h"）
# 改为在各自 Makefile 里做目录级 ccflags/export 修复
export KCFLAGS=

echo "############### 阶段 0: 工具链 ###############"
clang --version | head -2
echo "nproc=$(nproc)"

echo
echo "############### 阶段 1: 干净重建树 ###############"
make mrproper > /logs/stage1-mrproper.log 2>&1
echo "mrproper rc=$?"
echo "残留 .o: $(find . -name '*.o' 2>/dev/null | wc -l)"

echo
echo "############### 阶段 2: 装载原厂配置 ###############"
cp /inputs/stock.config .config
echo "原厂配置行数: $(wc -l < .config)"

echo
echo "############### 阶段 3: 注入 LXC 必需 6 项 ###############"
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS; do
  ./scripts/config --file .config -e $o
  printf "  CONFIG_%-16s -> %s\n" "$o" "$(grep -E "^CONFIG_$o=" .config | cut -d= -f2)"
done

echo
echo "############### 阶段 4: olddefconfig 收敛 ###############"
make olddefconfig > /logs/stage4-olddefconfig.log 2>&1
echo "olddefconfig rc=$?"

echo
echo "--- 关键配置验证 ---"
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS QCOM_KGSL MODVERSIONS \
         MACH_XIAOMI_MUNCH TECHPACK_CAMERA_XIAOMI ARCH_KONA LTO THINLTO_CLANG; do
  printf "  %-26s %s\n" "CONFIG_$o" "$(grep -E "^CONFIG_$o=" .config | cut -d= -f2 || echo '-')"
done
echo "--- 被强制 export 覆盖的符号（.config 说 n 但实际会编）---"
printf "  %-26s .config=%s  konacamera.conf/konadisp.conf 强制=y\n" \
  "CONFIG_SPECTRA_CAMERA" "$(grep -E '^CONFIG_SPECTRA_CAMERA=' .config | cut -d= -f2 || echo 'not set')"
printf "  %-26s .config=%s  konadisp.conf 强制=y\n" \
  "CONFIG_QCOM_MDSS_PLL" "$(grep -E '^CONFIG_QCOM_MDSS_PLL=' .config | cut -d= -f2 || echo 'not set')"

echo
echo "############### 阶段 5: 全量编译 Image + modules ###############"
date '+start %H:%M:%S'
make -j$(nproc) Image modules > /logs/full-final.log 2>&1
RC=$?
date '+end %H:%M:%S'
echo "MAKE_EXIT=$RC"

echo
echo "############### 阶段 6: 产物 ###############"
ls -la arch/arm64/boot/Image 2>/dev/null || echo "  ❌ 无 Image"
if [ -f arch/arm64/boot/Image ]; then
  echo "  Image SHA256: $(sha256sum arch/arm64/boot/Image | cut -d' ' -f1)"
  echo "  Image 大小:   $(stat -c %s arch/arm64/boot/Image) 字节"
fi
echo "  .ko 模块数: $(find . -name '*.ko' 2>/dev/null | wc -l)"
if [ -f Module.symvers ]; then
  echo "  Module.symvers 行数: $(wc -l < Module.symvers)"
  echo "  内核串: $(grep -m1 'UTS_RELEASE' include/config/kernel.release 2>/dev/null || cat include/config/kernel.release 2>/dev/null)"
fi
echo "############### DONE ###############"
