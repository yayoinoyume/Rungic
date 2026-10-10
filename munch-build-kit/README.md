# munch (Redmi K40S) 构建套件

本目录收录在 Redmi K40S（代号 `munch`，骁龙 870 / SM8250）上运行
[Rungic](../README.md) 所需的构建脚本、内核配置与输入文件。Rungic 在这台设备上
以 LXC 容器方式运行 Ubuntu + Plasma 桌面（整体方案见主仓库
`docs/91-munch-kernel-rebuild.md`）。

## 这个套件能做什么

按顺序完成四件事，就能在一台已解锁并刷入 LineageOS 23.2（Android 16）的
K40S 上得到可运行 Rungic 的手机：

1. **编译内核**：LineageOS 自带内核缺少 LXC 必需的 6 项配置
   （SYSVIPC / POSIX_MQUEUE / IPC_NS / PID_NS / USER_NS / DEVTMPFS），
   也没有 Rungic 渲染通路依赖的 ION system heap。本套件的脚本从原厂 boot
   中提取的配置基底出发，只打开这 7 项，产出与原厂版本串完全一致
   （`4.19.325-cip131-st15-perf-g71b13e62f057`）的内核 Image。
2. **替换 3 个 vendor 模块**：内核配置一变，符号 CRC 全变，原厂
   `gspca_main` / `rmnet_perf` / `rmnet_shs` 三个模块会拒绝加载（移动数据会失效）。
   `boot/` 里的 Magisk 模块模板用新内核重新编译这三个模块并在开机时替换。
3. **重打包 boot**：`boot/pack-boot.sh` 把新内核塞进手机当前的 Magisk boot
   镜像，保留 root。
4. **制作 rootfs**：`rootfs-scripts/` 在 x86 主机上用 qemu-user 模式构建
   ARM64 的 Ubuntu rootfs，装好本地编译的 Mesa，打出的 16 GiB 稀疏镜像
   就是 Rungic 的系统盘。

## 目录结构

| 路径 | 内容 |
|---|---|
| `kernel/scripts/` | 内核构建脚本与 `Dockerfile.kernel` 编译环境（主脚本 `build-ion.sh`） |
| `kernel/inputs/` | 原厂配置基底 `stock.config`（6521 行）、版本串 `scmversion`、focaltech 触摸固件、ABI 对照符号表 |
| `kernel-final/` | 最终 `.config`（`config.final`）与最终 `Module.symvers`（vendor 模块重编的 CRC 基准） |
| `boot/` | `pack-boot.sh`（magiskboot 重打包）与 vendor 模块替换的 Magisk 模块模板 |
| `rootfs-scripts/` | rootfs 制作：建 16 GiB 稀疏镜像、qemu-user 填充 Ubuntu + 本地 Mesa |
| `apk/libxkbcommon/` | Rungic APK 依赖的 Android arm64 `libxkbcommon.so` 交叉编译脚本 |

`SHA256SUMS.txt` 记录关键输入与产物的 SHA-256，用于核对重建产物；二进制重编译
因时间戳不同哈希会变，属正常现象。

## 需要自备的大文件

本目录刻意不收录二进制。构建前需要准备 4 样东西：

| 需要什么 | 获取方式 |
|---|---|
| **内核源码树**（约 200 MB） | `git clone --depth 1 -b lineage-23.2 https://github.com/LineageOS/android_kernel_xiaomi_sm8250`（该分支 HEAD 即 `71b13e62f057`，与所有脚本一致） |
| **Android clang 12.0.5**（约 426 MB） | AOSP 预编译 `clang-r416183b`：`curl -LO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-d1-release/clang-r416183b.tar.gz`（解压后 `bin/clang --version` 应含 `based on r416183b`；不要用系统 clang 或 NDK clang） |
| **手机当前的 Magisk boot 镜像** | 已 root 的手机上 `adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot-current.img'` 后 `adb pull`，得到 `pack-boot.sh` 需要的 `phone-magisk.img` |
| **magiskboot** | 来自 [Magisk 官方发行版](https://github.com/topjohnwu/Magisk)；`pack-boot.sh` 通过 `RUNGIC_ROOT` 或 `$HOME/projects/Rungic/.work/magisk-official/magiskboot` 查找它 |

所有 URL 已逐一验证可用。源码包与工具链的原始归档（`kernel-src.tar.gz`、
`clang-prebuilts.tar.gz`）如需留存，可自行下载后按 `SHA256SUMS.txt` 核对。

## 快速开始

```bash
# 1. 建编译容器（见 kernel/scripts/Dockerfile.kernel）
docker build -t munch-kernel:24.04 - < munch-build-kit/kernel/scripts/Dockerfile.kernel

# 2. 放入源码与输入（容器内路径约定：/build 源码、/opt/clang 工具链、/inputs 输入）
#    mount 源码到 /build，clang 解压到 /opt/clang，munch-build-kit/kernel/inputs 挂到 /inputs

# 3. 编译内核（容器内执行；约 3 分钟全量编译，32 线程）
bash /bf2.sh   # 或逐条执行 build-ion.sh 里的步骤

# 4. 打包 boot（主机上执行）
munch-build-kit/boot/pack-boot.sh <新编译的 Image>

# 5. 刷入并安装模块
fastboot flash boot new-boot.img
# vendor 模块替换见 boot/magisk-module/（需将重编的 3 个 .ko 放入 vendor/lib/modules/）

# 6. 制作 rootfs（见 rootfs-scripts/ 内各脚本头注释）
```

> `pack-boot.sh` 假定 `phone-magisk.img` 与脚本同目录；`build-ion.sh` 假定容器内
> `/inputs` 下有 `stock.config`、`focaltech-fw/`、`scmversion`。这两个约定都在
> 脚本头注释里写明了。

## 复现时需要知道的坑

这些坑都在实机验证中踩过，细节记录在主仓库 `docs/91-munch-kernel-rebuild.md`：

- **内核版本串必须与原厂完全一致**：vendor 模块按版本串拒绝加载。tarball 没有
  `.git`，setlocalversion 产不出 `-g<hash>` 后缀，所以脚本用 `KERNELVERSION=`
  精确覆盖（`kernel/inputs/scmversion` 记录的 `-g71b13e62f057` 是它的来龙去脉）。
- **触摸固件 `.i` 文件必须在 `make mrproper` 之后注入**：`build-ion.sh` 已处理。
- **Magisk 模块目录出现 `disable` 文件会静默失效**：安装后要删掉它。
- **这台设备 magic mount 不生效**：模块替换靠 `post-fs-data.sh` 的 bind mount
  + `restorecon` 修正 SELinux 标签，模板里已包含。
- **WSL2 默认禁用无特权 user namespace**：rootfs 构建用 Docker +
  `docker run --privileged --rm tonistiigi/binfmt --install arm64`，不要用
  `podman unshare`。

## 容器里的 Docker：为什么一开始用不了，后来怎么修好

Rungic 的桌面跑在一个 LXC 容器里（可以理解成"手机里的另一台小电脑"）。我们想在这个
容器里直接用 Docker 跑别的服务，结果 Docker 怎么都起不来。查下来是两个原因，都跟这台
K40S 的脾气有关。

### 原因一：一个"补丁程序"顺手关掉了 Docker 需要的能力

这台手机的内核有个小毛病：它有个叫 `pidfd` 的功能只做了一半，会让容器里的系统组件
（systemd）没法正常回收进程。为了绕过这个毛病，Rungic 往容器里塞了一个自制的补丁程序
（`system/pidfd-shim.c`，装好后是 `/usr/local/lib/rungic-pidfd.so`），开机时先加载它，
把这个半成品功能"藏起来"，系统组件就会改走另一条能用的老路。

问题出在：这个补丁程序启动时，顺手打开了一个叫 `NoNewPrivs` 的开关。这个开关的意思是
"禁止这个进程和它的所有子孙进程提权"。它会被**所有**子进程继承。

而 Docker 的非 root 模式（rootless Docker）恰好需要一个小工具 `newuidmap`，这个工具靠
"临时提权"才能干活。开关一开，`newuidmap` 就废了，Docker 建自己的隔离空间时直接报错：

```
newuidmap: write to uid_map failed: Operation not permitted
```

**修法**：让补丁程序在打开这个开关之前，先试试"不提权能不能装好过滤器"。因为容器里的
root 本来就有足够权限，所以这条路走得通。只有实在没权限时才回退到老做法。这样补丁程序
该干的事（藏起 pidfd）照干，但不再连累 Docker。

### 原因二：镜像源写了两遍，Docker 拒绝启动

Docker 拉镜像在国内要配"镜像加速源"。我们一开始在两处都写了这份配置：

- 用户自己建的 `~/.config/docker/daemon.json`
- Docker 启动命令里的 `--registry-mirror` 参数

Docker 发现同一项配置被指定了两次，直接报 `specified both` 并拒绝启动。

**修法**：镜像源只留一个地方。现在由安装包统一提供 `/etc/docker/daemon.json`，
启动命令不再重复传参数；用户自己那份 `~/.config/docker/daemon.json` 仍然优先，
Docker 会按自己的规矩取用。

### 修好之后

改完这两处，重新打包装进容器、重启一次，实测全部通过：

- 容器里的 1 号进程 `NoNewPrivs` 从 1 变回 0
- Docker 开机自动启动
- `docker pull` 能拉镜像、`docker run` 能跑容器
- 端口发布（`-p 18080:80`）从手机这边能访问
- 容器里能正常上网

两个安装包（`rungic-plasma-session`、`rungic-docker`）都用项目自带的方式
**在这台手机自己的容器里原生编译**（`tools/rungic_package.py build <包> --host phone`），
不需要另外的编译机。

细节记录在主仓库 `docs/85-lxc-rootless-docker.md`。

## 脚本一览

`kernel/scripts/` 里按用途分组：

| 脚本 | 用途 |
|---|---|
| `build-ion.sh` | **最终版**：stock 配置 + 6 项 LXC 配置 + ION system heap，产出验证过的 Image |
| `build-final.sh` / `build-final2.sh` | 只开 6 项 LXC 配置的中间版本（不含 ION），保留供对照 |
| `build-kernel.sh` / `build2.sh` | 早期版本，保留供参考 |
| `build-iononly.sh` / `build-dmaheap.sh` / `build-ref.sh` | ION/dma-heap 方案探索过程 |
| `build-resume.sh` | 增量续编 |
| `diag.sh` / `rerun.sh` | 配置与编译问题排查 |

只想拿结果的话，用 `build-ion.sh` 就够了；其余脚本记录了方案的演进过程，
想理解为什么最终选择 ION 而不是 backport dma-heap，可以按顺序读。
