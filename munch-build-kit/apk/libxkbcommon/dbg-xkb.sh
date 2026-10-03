#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends xz-utils wget >/dev/null 2>&1
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
  [ -f "$f" ] || continue
  sed -i "s|http://archive.ubuntu.com/ubuntu/|http://mirrors.ustc.edu.cn/ubuntu/|g" "$f"
  sed -i "s/^Types: deb$/Types: deb deb-src/" "$f"
done
apt-get update 2>&1 | tail -3
echo "=== apt-get source 真实输出 ==="
cd ${RUNGIC_ROOT:-$HOME/projects/Rungic}/.work/deps/libxkbcommon
apt-get source libxkbcommon 2>&1 | tail -12
echo "=== 目录 ==="
ls -la
