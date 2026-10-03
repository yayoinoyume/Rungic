#!/bin/bash
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
echo "=== 续编（配置已就绪，不 mrproper）==="
date '+start %H:%M:%S'
make -j$(nproc) Image modules > /logs/full-final.log 2>&1
RC=$?
date '+end %H:%M:%S'
echo "MAKE_EXIT=$RC"
echo "=== 错误汇总 ==="
grep -E "fatal error:|error:" /logs/full-final.log | sort -u | head -20
echo "=== 产物 ==="
ls -la arch/arm64/boot/Image 2>/dev/null && echo "  Image SHA256: $(sha256sum arch/arm64/boot/Image | cut -d' ' -f1)" || echo "  ❌ 无 Image"
echo "  .ko 数: $(find . -name '*.ko' 2>/dev/null | wc -l)"
[ -f Module.symvers ] && echo "  Module.symvers: $(wc -l < Module.symvers) 行"
echo "  内核版本串: $(cat include/config/kernel.release 2>/dev/null)"
echo "DONE"
