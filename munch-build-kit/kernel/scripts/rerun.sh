#!/bin/bash
cd /build
export PATH=/opt/clang/bin:$PATH
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1
make -j$(nproc) Image modules > /logs/full-build.log 2>&1
echo "MAKE_EXIT=$?" >> /logs/full-build.log
