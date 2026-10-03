#!/bin/bash
# ============================================================
# 把新编译的 Image 塞进手机当前的 Magisk boot.img（保住 root）
# 用法: pack-boot.sh <新 Image 路径>
# ============================================================
set -e
cd "$(dirname "$0")"
NEWIMG="$1"
[ -z "$NEWIMG" ] && { echo "用法: $0 <Image 路径>"; exit 1; }
[ -f "$NEWIMG" ] || { echo "❌ 找不到 $NEWIMG"; exit 1; }
MB=${RUNGIC_ROOT:-$HOME/projects/Rungic}/.work/magisk-official/magiskboot

echo "=== 1. 干净工作目录 ==="
mkdir -p work && cd work
cp ../phone-magisk.img ./orig-boot.img
$MB unpack orig-boot.img 2>&1 | sed 's/^/    /'
echo "--- 原组件 ---"
ls -la --time-style=+ | grep -vE "^total|orig-boot|ramdisk|kernel"

echo
echo "=== 2. 记录原 kernel（供回退校验）==="
sha256sum kernel | tee ../orig-kernel.sha256

echo
echo "=== 3. 替换为新 Image ==="
cp "$NEWIMG" ./kernel
echo "  新 kernel: $(stat -c %s kernel) 字节"
echo "  SHA256   : $(sha256sum kernel | cut -d' ' -f1)"
echo "  magic    : $(python3 -c "print(open('kernel','rb').read(4).hex())")"

echo
echo "=== 4. 确认 ramdisk 仍是 Magisk 版 ==="
if grep -qa "magiskinit" ramdisk.cpio 2>/dev/null || strings ramdisk.cpio | grep -q magiskinit; then
  echo "  ✅ ramdisk 含 magiskinit（root 保留）"
else
  echo "  ⚠ ramdisk 未检出 magiskinit，继续但请留意"
fi
echo "  ramdisk: $(stat -c %s ramdisk.cpio) 字节"

echo
echo "=== 5. 打包（复用原 header + 压缩格式）==="
$MB repack orig-boot.img new-boot.img 2>&1 | sed 's/^/    /'
echo "  产物: $(stat -c %s new-boot.img) 字节"
echo "  SHA256: $(sha256sum new-boot.img | cut -d' ' -f1)"

echo
echo "=== 6. 回读校验（重新解包确认结构一致）==="
mkdir -p verify && cp new-boot.img verify/ && cd verify
$MB unpack new-boot.img 2>&1 | sed 's/^/    /'
echo "  回读 kernel: $(stat -c %s kernel) 字节  SHA=$(sha256sum kernel | cut -c1-16)"
echo "  回读 ramdisk: $(stat -c %s ramdisk.cpio) 字节"
cd ..
echo
echo "=== 完成 ==="
echo "  boot.img: $(pwd)/new-boot.img"
