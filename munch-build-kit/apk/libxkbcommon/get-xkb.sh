#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] || continue
  sed -i "s|http://archive.ubuntu.com/ubuntu/|http://mirrors.ustc.edu.cn/ubuntu/|g; s|http://security.ubuntu.com/ubuntu/|http://mirrors.ustc.edu.cn/ubuntu/|g" "$f"
  sed -i "s/^Types: deb$/Types: deb deb-src/" "$f"
done
apt-get update -qq >/dev/null 2>&1
echo "=== libxkbcommon 版本 ==="
apt-cache policy libxkbcommon-dev 2>/dev/null | head -4
echo "=== 源码包信息 ==="
apt-cache showsrc libxkbcommon 2>/dev/null | grep -E "^(Package|Version)" | head -4
