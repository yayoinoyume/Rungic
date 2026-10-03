#!/bin/bash
set -e
cd /build

export PATH=/opt/clang/bin:$PATH
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-
export LLVM=1
export LLVM_IAS=1

echo "=== 工具链 ==="
clang --version | head -1

DEFCONFIG=vendor/kona-perf_defconfig
echo "=== 步骤1: $DEFCONFIG ==="
make -j$(nproc) $DEFCONFIG 2>&1 | tail -5

echo "=== 步骤2: 合并 LOS vendor 配置片段 ==="
# AOSP/LineageOS 的 TARGET_KERNEL_CONFIG 顺序
for f in vendor/debugfs.config vendor/xiaomi/sm8250-common.config vendor/xiaomi/munch.config; do
  echo "--- 合并 $f ---"
  ./scripts/kconfig/merge_config.sh -m -O . .config arch/arm64/configs/$f 2>&1 | tail -3
done

echo "=== 步骤3: 注入 LXC 必需的 5+1 项 ==="
./scripts/config --file .config \
  -e SYSVIPC -d POSIX_MQUEUE -e IPC_NS -e PID_NS -e USER_NS -e DEVTMPFS \
  2>/dev/null || true
# 显式写值，确保覆盖 defconfig 里的 "not set"
for opt in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS; do
  ./scripts/config --file .config -e $opt
done

echo "=== 步骤4: olddefconfig 收敛 ==="
make -j$(nproc) olddefconfig 2>&1 | tail -5

echo "=== 步骤5: 验证 LXC 配置生效 ==="
for opt in CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_IPC_NS CONFIG_PID_NS CONFIG_USER_NS CONFIG_DEVTMPFS CONFIG_QCOM_KGSL CONFIG_MODVERSIONS; do
  v=$(grep -E "^${opt}=" .config || grep -E "^# ${opt} is not set" .config || echo "(缺失)")
  echo "  $opt = $v"
done

echo "=== 步骤6: 编译 Image + modules ==="
make -j$(nproc) Image modules 2>&1 | tail -30
echo "=== 编译退出码: $? ==="

echo "=== 产物 ==="
ls -la arch/arm64/boot/Image 2>/dev/null || echo "  ❌ 无 Image"
ls -la .config
echo "--- 产出的 .ko 模块数 ---"
find . -name "*.ko" -not -path "./.git/*" 2>/dev/null | wc -l
