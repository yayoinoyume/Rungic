#!/bin/bash
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 LLVM=1 LLVM_IAS=1 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-

echo "===== 1. auto.conf 里的关键符号（y/m 才会写进 auto.conf）====="
grep -E "SPECTRA_CAMERA|QCOM_MDSS_PLL|ARCH_KONA|DEBUG_QCOM_CLOCK|DMSS_PLL" include/config/auto.conf || echo "  (auto.conf 里一个都没有)"
echo "  auto.conf 行数: $(wc -l < include/config/auto.conf)"

echo
echo "===== 2. 强制重编 clk-debug.o，看真实命令行里的 -I 和 TRACE ====="
rm -f drivers/clk/qcom/clk-debug.o
make drivers/clk/qcom/clk-debug.o V=1 2>&1 | tr ' ' '\n' | grep -E "TRACE_INCLUDE|^-I|fatal error|^clang|clang-" | head -25

echo
echo "===== 3. 用 KCFLAGS 加 -I 后重试（验证假设）====="
rm -f drivers/clk/qcom/clk-debug.o
make drivers/clk/qcom/clk-debug.o KCFLAGS="-I/build/drivers/clk/qcom" 2>&1 | tail -4

echo
echo "===== 4. 同样手法测 cam_cci_dev.o ====="
rm -f techpack/camera-xiaomi/drivers/cam_sensor_module/cam_cci/cam_cci_dev.o
make techpack/camera-xiaomi/drivers/cam_sensor_module/cam_cci/cam_cci_dev.o KCFLAGS="-I/build/techpack/camera-xiaomi/drivers/cam_sensor_module/cam_cci" 2>&1 | tail -4

echo
echo "===== 5. 同样手法测 dsi_pll_10nm.o ====="
rm -f techpack/display/pll/dsi_pll_10nm.o
make techpack/display/pll/dsi_pll_10nm.o KCFLAGS="-I/build/techpack/display/pll" 2>&1 | tail -4
