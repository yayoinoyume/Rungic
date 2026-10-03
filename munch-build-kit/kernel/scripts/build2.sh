#!/bin/bash
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1

echo "=== 工具链 ==="; clang --version | head -1

echo "=== 用线刷包原厂配置作为基底 ==="
cp /logs/stock.config .config
echo "  基底行数: $(wc -l < .config)"

echo "=== 注入 LXC 必需的 6 项 ==="
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS; do
  ./scripts/config --file .config -e $o
done

echo "=== olddefconfig 收敛 ==="
make -j$(nproc) olddefconfig > /logs/olddefconfig.log 2>&1
echo "  退出码=$?"

echo "=== 配置验证 ==="
for o in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS QCOM_KGSL MODVERSIONS MACH_XIAOMI_MUNCH TECHPACK_CAMERA_XIAOMI; do
  printf "  %-32s %s\n" "CONFIG_$o" "$(grep -E "^CONFIG_$o=" .config || echo '(未设置)')"
done

echo "=== 与原厂配置差异（应只有 6 项 + 派生 + 版本记录）==="
grep -E "^(CONFIG_SYSVIPC|CONFIG_POSIX_MQUEUE|CONFIG_IPC_NS|CONFIG_PID_NS|CONFIG_USER_NS|CONFIG_DEVTMPFS)=" .config | sed 's/^/  /'

echo "=== 开始编译（完整日志到 /logs/full-build2.log）==="
make -j$(nproc) Image modules > /logs/full-build2.log 2>&1
RC=$?
echo "=== MAKE_EXIT=$RC ==="
echo "=== 产物 ==="
ls -la arch/arm64/boot/Image 2>/dev/null || echo "  无 Image"
echo "--- .ko 模块数 ---"
find . -name "*.ko" -not -path "./.git/*" | wc -l
echo "--- 前 10 个 .ko ---"
find . -name "*.ko" -not -path "./.git/*" | head -10
