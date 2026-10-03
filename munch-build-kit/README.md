# munch (Redmi K40S) 构建套件

本目录收录 Redmi K40S（代号 `munch`）上运行 Rungic 的全部构建脚本、内核配置与输入文件。仓库本体（本目录的上级）即 Rungic 源码。

## 大文件获取方式

本目录刻意不收录任何大二进制文件。下面 7 个大文件都能通过官方源下载或本地重建得到。各产物的 SHA-256 见本目录 `SHA256SUMS.txt`（用于核对重建产物是否与已验证版本一致，二进制重编译因时间戳不同哈希会变，属正常现象）。

### 1. 官方源直接下载

**内核源码树**（对应 `kernel-src.tar.gz`，约 200 MB）

```bash
git clone --depth 1 -b lineage-23.2 https://github.com/LineageOS/android_kernel_xiaomi_sm8250
```

该分支 HEAD 即 `71b13e62f057`，与本文档所有构建步骤使用的 commit 一致。

**Android clang 12.0.5 工具链**（对应 `clang-prebuilts.tar.gz`，约 426 MB）

编译本内核必须使用 AOSP 预编译的 `clang-r416183b`（不要用系统 clang 或 NDK 自带 clang）：

```bash
# 方式一：AOSP gitiles 直接下载该目录的 tarball（约 400+ MB）
curl -LO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-d1-release/clang-r416183b.tar.gz

# 方式二：浅克隆该分支后取出目录
git clone --depth 1 -b android12-d1-release https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
# 取出 linux-x86/clang-r416183b/
```

`clang-r416183b` 在 `android12-d1-release` 分支下的存在性已核实；解压后 `bin/clang --version` 应输出 `Android (7284624, based on r416183b) clang version 12.0.5`。

### 2. 从手机提取

**带 Magisk 的当前 boot 基底**（重打 boot 镜像的前置条件）

在已 root 的手机上执行：

```bash
adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot-current.img'
adb pull /data/local/tmp/boot-current.img
```

拿到基底后，用本目录 `boot/pack-boot.sh <新编译的 Image>` 完成内核替换与重打包。注意脚本内 `MB=`（magiskboot 路径）需改为你本机的 magiskboot——它来自 Magisk 官方发行版（https://github.com/topjohnwu/Magisk），也可用 Magisk App 的"安装到 inactive slot"流程获得。

### 3. 本地重建

**编译内核 Image**：`kernel/scripts/build-ion.sh`（最终版）+ `kernel/inputs/`（stock.config、触摸固件、.scmversion）+ `kernel-final/config.final`。构建环境见 `kernel/scripts/Dockerfile.kernel`。要点：触摸固件 `.i` 文件与 `.scmversion` 必须在 `make mrproper` 之后注入；产物 `arch/arm64/boot/Image` 需与三个 vendor `.ko` 一起出（见 `boot/magisk-module/`）。

**Mesa 七包**：`03-mesa/Dockerfile.mesa-cross`（原归档携带的交叉编译定义，主仓库 `packages/mesa/` 配方亦可），构建参数见主仓库 `desktop/mesa-meson-options`。

**37 个本地 deb**（KWin `+rungic9` 五件套 + `rungic-*` 0.504/0.509）：KWin 源码经主仓库 `tools/pq.py source kwin` 生成（上游 `6.6.6` + 16 个 Rungic 补丁），在 ARM64 手机上 `dpkg-buildpackage` 编译；`rungic-*` 用主仓库 `tools/rungic_package.py build <name> --host phone`。

**Rungic APK**：主仓库 `android/build-apk.sh`（Rust + Android NDK），`apk/libxkbcommon/` 提供 Android arm64 `libxkbcommon.so` 的交叉编译脚本（上游源码 https://github.com/xkbcommon/libxkbcommon tag `xkbcommon-1.13.1`，已核实存在）。

**rootfs 镜像**：`rootfs-scripts/`（mkimg-16g.sh 建镜 + populate.sh 填充）。注意：脚本重建出的是干净基础 rootfs；本次适配中做过的 systemd 259→255 降级、pidfd 垫片安装等调试状态需要按主仓库 `docs/91-munch-kernel-rebuild.md` 与文档记录重放。如果手机当前容器运行正常，直接从 `/data/adb/rungic-lxc/images/rootfs.img` 拷出现有镜像是最快的"重建"。

## 目录结构

| 本仓库路径 | 内容 |
|---|---|
| `kernel/scripts/` | 内核构建脚本（`build-ion.sh` 为最终版）与 `Dockerfile.kernel` |
| `kernel/inputs/` | 原厂配置基底 `stock.config`（6521 行）、版本串 `.scmversion`、触摸固件、ABI 对照符号表 |
| `kernel-final/` | 最终 `.config`（`config.final`）与最终 `Module.symvers` |
| `boot/` | `pack-boot.sh`（magiskboot 打包）与 vendor 模块替换的 Magisk 模板 |
| `rootfs-scripts/` | rootfs 制作脚本（mmdebstrap / 16G 镜像 / 填充） |
| `apk/libxkbcommon/` | Android arm64 libxkbcommon 交叉编译脚本 |

## 与原归档的路径对应

原 `rungic-munch-build-kit/` 归档中的 `02-kernel/kernel-src/`、`02-kernel/clang/`、`03-mesa/`、`04-packages/`、`05-apk/*.apk`、`06-boot/*.img`、`07-rootfs/rootfs-plasma.img` 均为二进制大文件，按上方"大文件获取方式"获取；仓库中只保留脚本、配置与校验值。

---

以下为原始归档说明（路径按旧归档结构，对照上表使用）：

# Rungic munch 构建归档（方案 B）

- 生成时间：2026-10-01
- 目标设备：Redmi K40S，代号 munch，型号 22021211RC，SM8250，Adreno 650
- 目标系统：LineageOS 23.2 / Android 16 / SDK 36
- 最终内核：4.19.325-cip131-st15-perf-g71b13e62f057
- 归档方式：仅存储（不压缩）打包

本归档用于让其他人复现这套构建，或供自己以后重建。
只包含"下载输入、配置、构建脚本和必要成品"，不包含原厂 vendor 模块等二进制固件。

---

## 一、目录说明

| 目录 | 内容 |
|---|---|
| `01-repo/` | 项目仓库本体（不含 `.work`），含所有 `packages/*/recipe.json`、`release/packages.json`、`system/*.txt`、`provenance/`、Dockerfile、构建脚本 |
| `02-kernel/inputs/` | 内核配置来源、触摸固件、符号表、版本串 |
| `02-kernel/configs/` | 最终编译配置、最终符号表、Image、kernel-configs 仓库 |
| `02-kernel/scripts/` | 内核构建脚本和 Dockerfile |
| `02-kernel/kernel-src/` | 完整内核源码树（含 `.config` 和 `arch/arm64/boot/Image`） |
| `02-kernel/clang/` | Android clang 12.0.5 (r416183b) 工具链 |
| `03-mesa/` | Mesa 7 个 deb、meson 选项、交叉编译配置 |
| `04-packages/` | 本地 deb 仓库（kwin、rungic-* 等，共 37 个 deb） |
| `05-apk/` | `Rungic-2.24.apk` 和签名文件 |
| `06-boot/` | 当前可用的 boot 镜像 |
| `07-rootfs/` | `rootfs-plasma.img`（16 GiB 稀疏文件，实际占用约 306 MB） |
| `SHA256SUMS.txt` | 关键文件校验值 |

---

## 二、内核最终编译配置（最重要，请重点保存）

最终编译用的完整配置在四个地方都有副本，任意一个都能用：

| 文件 | 说明 |
|---|---|
| `02-kernel/configs/config.final` | 最终编译配置的独立副本（从编译完成的 `.config` 直接复制） |
| `02-kernel/kernel-src/.config` | 最终编译配置的原始位置 |
| `02-kernel/inputs/stock.config` | 从原厂 boot 分区 IKCFG 解出的基础配置，6521 行 |
| `02-kernel/configs/Module.symvers.final` | 最终符号表独立副本 |
| `02-kernel/kernel-src/Module.symvers` | 最终符号表原始位置 |
| `02-kernel/inputs/Module.symvers.lxc6` | 开 LXC 后的符号表 |
| `02-kernel/inputs/Module.symvers.stock` | 原厂符号表，对照用 |
| `02-kernel/configs/` | 还包含 Android kernel-configs 仓库（含 `.git`） |

### 关键配置项（已核对）

```
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_USER_NS=y
CONFIG_DEVTMPFS=y
CONFIG_ION=y
CONFIG_ION_SYSTEM_HEAP=y
CONFIG_QCOM_KGSL=y
CONFIG_MODVERSIONS=y

# CONFIG_DMA_HEAP_SYSTEM is not set
# CONFIG_DMABUF_HEAPS is not set
```

### 版本串

```
.scmversion  内容：-g71b13e62f057
CONFIG_LOCALVERSION="-perf"
最终 uname：4.19.325-cip131-st15-perf-g71b13e62f057
```

### 内核源码

```
仓库：https://github.com/LineageOS/android_kernel_xiaomi_sm8250
分支：lineage-23.2
commit：71b13e62f057
```

### 编译器

```
Android clang 12.0.5
based on r416183b
路径：02-kernel/clang/
```

### 构建环境

```
Docker 镜像：los-kernel-build:24.04
Dockerfile：02-kernel/scripts/Dockerfile.kernel
基础镜像：ubuntu:24.04
```

### 内核构建脚本

```
02-kernel/scripts/build-ion.sh        ← 最终使用的脚本
02-kernel/scripts/build-final2.sh
02-kernel/scripts/build-iononly.sh
02-kernel/scripts/build-dmaheap.sh
```

### 编译环境变量

```bash
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KERNELVERSION=4.19.325-cip131-st15-perf-g71b13e62f057
```

### 固件文件

```
02-kernel/inputs/focaltech-fw/fw_ft3658_l11r.i   580.6 KB
02-kernel/inputs/focaltech-fw/fw_sample.i        0 B 占位符
```

这两个文件被源码树 `.gitignore` 里的 `*.i` 排除，GitHub 源码包中没有，需要单独放回
`drivers/input/touchscreen/focaltech_3658u/include/firmware/`。

### boot 打包

```
工具：magiskboot（来自 Magisk 31.0）
方式：解包当前带 Magisk 的 boot，替换 kernel，再重新打包，保留 ramdisk
当前可用镜像：06-boot/boot-munch-ionheap-magisk.img
```

### 需要替换的 vendor 模块（仅名称，本归档不含模块文件）

```
gspca_main.ko
rmnet_perf.ko
rmnet_shs.ko
```

---

## 三、Mesa 构建输入

```
仓库：https://github.com/lfdevs/mesa-for-android-container
commit：98f3d6229d61452cef80f8563af7c56ae599dc14
tag：mesa-26.3.0-devel-20260824
tree：5d0abacd0ef77a988c930198957975b037289494
包版本：26.3.0~devel20260824+rungic3
```

目录里包含：

- `03-mesa/*.deb`：7 个成品包；
- `03-mesa/mesa-meson-options`：正式 meson 选项；
- `03-mesa/aarch64-linux-gnu.ini`：交叉编译配置。

Dockerfile 在 `01-repo` 里没有直接对应，原始文件在 `.work/mesa-build/container/Dockerfile`，
本归档未包含；如果重建，需要按下面内容准备：

```
FROM ubuntu:26.04
dpkg --add-architecture arm64
主机工具：gcc-aarch64-linux-gnu、g++-aarch64-linux-gnu、
          binutils-aarch64-linux-gnu、meson、ninja-build、
          python3-mako、python3-yaml、flex、bison、
          glslang-tools、spirv-tools、libwayland-bin、wayland-protocols
目标库：libdrm-dev:arm64、libgbm-dev:arm64、libwayland-dev:arm64、
        libx11-dev:arm64、libx11-xcb-dev:arm64、libxcb-dri3-dev:arm64、
        libvulkan-dev:arm64、libglvnd-dev:arm64、libdisplay-info-dev:arm64 等
```

Mesa 补丁（在 `01-repo/packages/mesa/debian/patches/rungic/`）：

```
egl-x11-dri3-fallback-software.patch
kgsl-dmabuf-import-ubwc.patch
kgsl-import-is-shared.patch
x11-kgsl-needs-dri3.patch
```

---

## 四、rootfs 构建输入

```
运行时包清单：01-repo/system/ubuntu-packages.txt
构建依赖清单：01-repo/system/ubuntu-build-packages.txt
精确包锁：    01-repo/provenance/plasma-mobile-20260923/release/packages.tsv（1964 行）
基础镜像：    ubuntu:26.04（resolute）
工具：        mmdebstrap、proot、qemu-user、e2fsprogs
镜像成品：    07-rootfs/rootfs-plasma.img（16 GiB 稀疏）
```

---

## 五、定制包清单

17 个 rebuilt 包：

```
kwin                    4:6.6.6-0ubuntu0.1       16 个 rungic 补丁
mesa                    26.3.0~devel20260824     4 个补丁
kscreen                 4:6.6.5-0ubuntu0.1       1 个补丁
libcamera               0.7.0-1ubuntu2           2 个补丁
qt6-multimedia          6.10.2-2                 1 个补丁
plasma-camera           2.1.1-2build1            1 个补丁
plasma-mobile           6.6.5-0ubuntu0.1         13 个补丁
plasma-settings         25.12.0-1                1 个补丁
kf6-bluez-qt            6.24.0-0ubuntu1          1 个补丁
powerdevil              4:6.6.6-0ubuntu0.1       1 个补丁
kwayland                4:6.6.4-0ubuntu1         1 个补丁
plasma-keyboard         6.6.6-0ubuntu0.1         2 个补丁
xdg-desktop-portal-kde  6.6.6-0ubuntu0.1         1 个补丁
wl-clipboard            2.3.0                    无
flatpak                 1.16.6-1                 1 个补丁
xwayland                2:24.1.10-1              1 个补丁
gst-plugins-base1.0     1.28.2-1ubuntu0.1        1 个补丁
```

每个包的固定来源在 `01-repo/packages/<名称>/recipe.json`。

19 个项目自有包（`01-repo/packaging/`）：

```
rungic-plasma-config     rungic-plasma-services   rungic-plasma-session
rungic-plasma-bridges    rungic-plasma-input      rungic-plasma-recording
rungic-plasma-diagnostics rungic-design           rungic-voice-agent
rungic-cua               rungic-agent-screen      rungic-cast
rungic-codex             rungic-codec             rungic-docker
rungic-firefox           rungic-snapshot          rungic-flatpak-gl
rungic-suggestions
```

---

## 六、APK 构建输入

```
构建镜像：rungic-apk:26.04（基于 ubuntu:26.04）
Rust：    rustup stable，target aarch64-linux-android
SDK：     cmdline-tools 11076708，build-tools 36.0.0，platform android-36
NDK：     27.3.13750724
签名：    01-repo/signing/development/launcher-signing.p12
产物：    05-apk/Rungic-2.24.apk
```

SDK 下载地址：

```
https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
```

Rust 依赖清单：

```
01-repo/android/host/Cargo.toml
（完整锁定版本以 .work/build/android-host/source/Cargo.lock 为准，本归档未包含）
```

libxkbcommon：

```
版本：1.13.1
来源：Ubuntu 26.04 源包
交叉编译：NDK 27.3.13750724 aarch64 clang
```

OCR 资源（可选）：

```
01-repo/provenance/ocr-20260925/sources.json
```

---

## 七、补充的构建环境文件

这些是 v2 增补的构建环境定义和脚本，之前的版本遗漏了：

### Mesa

| 文件 | 说明 |
|---|---|
| `03-mesa/Dockerfile.mesa-cross` | Mesa 交叉编译镜像 `rungic-mesa-cross:26.04` 的 Dockerfile |
| `03-mesa/Dockerfile.cross` | 另一份 Mesa 交叉构建 Dockerfile |
| `03-mesa/scripts/build.sh` | 正式 Mesa 构建脚本 |
| `03-mesa/scripts/build-debug.sh` | debug 版构建脚本 |
| `03-mesa/meson-options-debug` | debug 版 meson 选项 |
| `03-mesa/probes/probe*.sh` | Mesa / KGSL 探针脚本 |
| `03-mesa/aarch64-pkg-config` | 交叉编译用的 pkg-config 包装 |
| `03-mesa/aarch64-linux-gnu.artifacts.ini` | 另一份交叉编译配置 |

### APK / Rust 宿主

| 文件 | 说明 |
|---|---|
| `05-apk/Dockerfile.apk` | APK 构建镜像 `rungic-apk:26.04` 的 Dockerfile |
| `05-apk/libxkbcommon/*.sh` | libxkbcommon Android 交叉编译脚本 |
| `05-apk/libxkbcommon/android-arm64.ini` | libxkbcommon 的 meson 交叉编译配置 |
| `05-apk/native-libs/` | APK 组装用的预编译库（Rust 合成器、libc++_shared、libxkbcommon） |

### 内核

| 文件 | 说明 |
|---|---|
| `02-kernel/clang-prebuilts.tar.gz` | Android clang 12.0.5 原始下载包（425 MB） |
| `02-kernel/kernel-src.tar.gz` | LineageOS 内核源码原始下载包（199 MB） |
| `02-kernel/scripts/diag.sh`、`rerun.sh` | 内核辅助脚本 |

### 内核设备树与参考代码

| 文件 | 说明 |
|---|---|
| `02-kernel/device/device-munch/` | LineageOS 的 munch 设备树 |
| `02-kernel/device/device-sm8250-common/` | SM8250 公共设备树 |
| `02-kernel/device/kernel-sm8250/` | SM8250 内核配置辅助目录 |
| `02-kernel/dmaheap-ref/` | 从上游 5.6 / 6.6 摘出的 dma-heap 参考代码（用于判断 backport 方案） |
| `02-kernel/backups/` | 内核构建脚本修改前的备份 |

### boot 与 Magisk 替换脚本

| 文件 | 说明 |
|---|---|
| `06-boot/pack-boot.sh` | 用 `magiskboot` 打包 boot 的脚本 |
| `06-boot/magisk-module/module.prop` | Magisk 模块描述 |
| `06-boot/magisk-module/post-fs-data.sh` | 开机 bind mount + restorecon 脚本（只含脚本，不含 `.ko` 模块本身） |

### rootfs

| 文件 | 说明 |
|---|---|
| `07-rootfs/scripts/Dockerfile` | rootfs 构建用 Dockerfile |
| `07-rootfs/scripts/mkimg-16g.sh`、`mkimg.sh` | 生成 16 GiB 镜像的脚本 |
| `07-rootfs/scripts/pack.sh` | 打包脚本 |
| `07-rootfs/scripts/add-gles.sh`、`add_gles2.sh` | 补充 GLES 库的脚本 |
| `07-rootfs/scripts/bootstrap.sh`、`populate.sh` | 早期占位脚本 |

## 八、本归档不包含的东西

| 不包含 | 原因 |
|---|---|
| Docker 镜像本身 | 在 `docker_data.vhdx` 里，太大；Dockerfile 都在 `01-repo` 或 `02-kernel/scripts` |
| 澎湃 OS / MIUI 刷机包 | 约 25 GB，恢复原厂时才需要 |
| LineageOS 刷机包 | 回退保险，单独保留在 Windows Downloads |
| 原厂 vendor 模块二进制 | 需要时从原厂固件重新解包 |
| 内核源码树里的 `.thinlto-cache` | root 权限的编译缓存，可重建 |
| `.work/build/android-host/source/Cargo.lock` | 如果复现 APK 构建，需要从仓库重新生成 |

---

## 九、使用这个归档时的注意事项

1. `07-rootfs/rootfs-plasma.img` 是 16 GiB 稀疏文件，实际只占约 306 MB。
   复制或解压时尽量保持稀疏（Linux 用 `cp --sparse=always`，Windows 用支持稀疏的工具），
   否则会展开成 16 GB。

2. 内核源码树里的 `.thinlto-cache` 没有复制，因为它是 root 权限的编译缓存。
   重新编译时它会被自动重建，不影响结果。

3. Dockefile 与脚本里可能有原作者的硬编码路径，例如
   `/home/<user>/android-kernel/prebuilts/clang/...` 和 `192.0.2.10:6152`。
   复现时需要把 `RUNGIC_ANDROID_CLANG*` 和 `RUNGIC_PROXY` 置空。

4. WSL2 默认禁用无特权 user namespace。构建 rootfs 时不能直接用 `podman unshare`，
   需要用 Docker：

   ```
   docker run --privileged --rm tonistiigi/binfmt --install arm64
   ```

5. 签名密钥 `01-repo/signing/development/launcher-signing.p12` 是开发用密钥，
   不要公开分发；如果这个归档要给别人，先把 `signing/` 目录排除。

---

## 十、关键文件校验

见 `SHA256SUMS.txt`。
