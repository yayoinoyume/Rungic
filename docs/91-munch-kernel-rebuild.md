# Redmi K40S (munch) LineageOS 内核重编与刷入记录

时间：2026-09-30 晚 至 2026-10-01 凌晨。设备：Redmi K40S（型号 22021211RC，代号 `munch`，序列号 `<DEVICE-SERIAL>`），已刷 LineageOS 23.2 / Android 16（SDK 36），bootloader 已解锁，槽位 `a`，已装 Magisk 31.0。

本篇只记录**实际做过并验证过**的事。看不懂的术语第一次出现时会顺带解释。

## 一、为什么要重编内核

Rungic 要在手机上跑 Linux 容器（LXC）。容器需要内核提供几样东西：

| 名字 | 通俗解释 |
|---|---|
| `SYSVIPC` | 经典的 System V 进程间通信（共享内存、信号量、消息队列） |
| `POSIX_MQUEUE` | 新式消息队列 |
| `IPC_NS` | 进程间通信的「命名空间」，让容器之间互不串味 |
| `PID_NS` | 进程编号的隔离，容器里能重编 PID |
| `USER_NS` | 用户权限的隔离 |
| `DEVTMPFS` | 让 `/dev` 自动生成设备节点 |

LineageOS 自带内核这 6 项**没开**。开内核选项就要重新编译内核，所以有了这次工作。

**只编内核就行，不需要编整个 LineageOS**（那要几百个 G 的存储和十几个小时）。

## 二、最终结果

一次全量干净编译约 **2 分 52 秒**（32 线程，2026-10-01 00:25:08 → 00:28:00）。

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `Image`（内核本体） | 51,441,680 字节 | `5466c860b5fa5c252f43ab8e92c6abfbadce26ec4693bc2f6a890ad5404ecd89` |
| `boot.img`（含 Magisk） | 201,326,592 字节 | `8fed511535e8ab0a1c3f78fcf8ebd841d0ea3e8ab44acc0017b45ae6ce50c34c` |
| `Module.symvers`（符号 CRC 表） | 13,865 行 | `ee0924269d6b1f36fb3df21e2e00545fc9a944f84466bdf91d68bdfe5264aa20` |

产物目录：`.work/artifacts/`。构建脚本：`.work/los-kernel/build-final2.sh`。

关键数字：**版本串 `4.19.325-cip131-st15-perf-g71b13e62f057`，与手机原厂完全一致**。

为什么要一致：Linux 内核里的模块（`.ko`）加载前会核对内核版本串。对不上就直接拒绝加载。

## 三、怎么编的

### 用什么

| 项目 | 值 | 来源 |
|---|---|---|
| 内核源码 | `LineageOS/android_kernel_xiaomi_sm8250` 分支 `lineage-23.2`，commit `71b13e62f057` | GitHub 下载的压缩包 |
| 编译器 | Android clang 12.0.5（r416183b） | LineageOS 当年用的版本 |
| 构建环境 | Docker 镜像 `los-kernel-build:24.04`（Ubuntu 24.04） | `.work/los-kernel/Dockerfile.kernel` |

用 Docker 是为了**不弄脏用户电脑**，编译产生的几 GB 中间文件全在容器和 `.work/` 里。

### 配置从哪来

从手机**原厂 boot 分区里挖出来的**。boot 镜像里嵌了一段压缩的内核配置（叫 IKCFG）。解出来 6,521 行，作为基底，然后只改那 6 项。

这样做的好处：除了那 6 项，其他配置和原厂一模一样，行为最接近原厂。

### 为什么改了配置就必须重编

Linux 内核对每个对外函数算一个校验值（CRC）。改配置会让内核里的数据结构变化，CRC 就会变。手机 `/vendor/lib/modules/` 下有 3 个第三方模块依赖这些 CRC。

实测数据（拿同一份源码、只改配置，编两次对比）：

| 项目 | 数量 |
|---|---|
| 导出符号总数 | 13,853（原厂配置） → 13,865（加 6 项后） |
| **CRC 变化的符号** | **8,659** |
| 新增符号 | 12（`init_user_ns`、`current_in_userns`、`from_kuid` 等） |
| `module_layout` 这个关键符号 | `0x3625ca4d` → `0x034d957c` |

`module_layout` 是每个模块都必须引用的符号，它一变，**所有**模块都加载不了。

受影响的 3 个模块（`/vendor/lib/modules/` 下）：

| 模块 | 作用 | 依赖符号 | 会失配 |
|---|---|---|---|
| `gspca_main.ko` | USB 摄像头 | 73 | 47 |
| `rmnet_perf.ko` | 蜂窝数据性能 | 62 | 26 |
| `rmnet_shs.ko` | 蜂窝数据通道 | 108 | 31 |

后两个是**手机上当时正加载着的**，不处理会导致移动数据失效。所以必须把这 3 个模块一起换成自己编的（自己编的和自己编的内核当然匹配）。

## 四、编译时踩到的 6 个坑

### 坑 1：`-I` 包含路径传不下去

**现象**：报 `fatal error: './pll_trace.h' file not found`。

**原因**：这套高通（CAF）内核的 `techpack/*/Makefile` 里用了这种写法：

```
include $(srctree)/techpack/camera-xiaomi/config/konacamera.conf
```

那个 `.conf` 文件里是 `export CONFIG_SPECTRA_CAMERA=y`。GNU make 的 `export` 会**覆盖**配置文件的值，所以哪怕 `.config` 里写的是「不编译」，这些目录照样编。

更麻烦的是，这些 Makefile 里靠 `LINUXINCLUDE += -I某个目录` 来告诉编译器去哪找头文件。但 make 递归进入子目录时开的是**新进程**，普通变量不传递，**只有 `export` 出来的才传**。所以子目录全部找不到头文件。

**修法**：把这几处改成 `export LINUXINCLUDE +=`。

一共改了 4 个 Makefile 文件（改动很小，只加了 include 路径，没动任何逻辑）：

| 文件 | 改动 |
|---|---|
| `techpack/camera-xiaomi/Makefile` | `USERINCLUDE` / `LINUXINCLUDE` 前加 `export` |
| `techpack/display/pll/Makefile` | `ccflags-y` 加 `-I$(src)` |
| `drivers/clk/qcom/Makefile` | 新增 `ccflags-y += -I$(src)` |
| `techpack/camera-xiaomi/.../cam_cci/Makefile` | 新增 `ccflags-y += -I$(src)` |

备份在 `.work/los-kernel/.backups/20260930-fix-includes/`。

### 坑 2：`drivers/clk/qcom` 完全没有 include 配置

这个目录的 `Makefile` 里一条 `ccflags` 都没有，但 `clk-debug.c` 需要。原因是它的 `trace.h` 里有这么两行：

```
#define TRACE_INCLUDE_PATH .
#define TRACE_INCLUDE_FILE trace
```

内核生成代码时会展开成 `#include "./trace.h"`，需要能按**当前目录**找到。加 `-I$(src)` 解决。

### 坑 3：我用全局 `KCFLAGS` 加 `-I`，污染了别的目录

**这是我自己的错误。** 我一开始图省事，用 `KCFLAGS="-I..."` 全局加包含路径，结果 `drivers/base/regmap/regmap.c` 里那句 `#include "trace.h"` 抢先命中了 `clk/qcom` 的 `trace.h`，报 `check_trace_callback_type_clk_measure` 未定义。

**教训**：包含路径必须用目录级的 `ccflags-y`，不能全局加。

### 坑 4：固件文件被 Git 忽略，压缩包里没有

**现象**：报 `fatal error: 'include/firmware/fw_ft3658_l11r.i' file not found`。

**原因**：触摸屏驱动（focaltech 3658u）要把固件二进制转成 C 数组文件（`.i`），但源码树根目录的 `.gitignore` 第 24 行有 `*.i`，把这些文件排除了。GitHub 打的源码压缩包里就没有。

**修法**：单独从 LineageOS 仓库下载这两个文件（`fw_ft3658_l11r.i` 594,560 字节，`fw_sample.i` 是 0 字节的空占位符），放在 `.work/los-kernel/inputs/focaltech-fw/`，构建时注入。

### 坑 5：`make mrproper` 会把上面这些文件删掉

清理指令 `mrproper` 会连固件 `.i` 文件一起删。第一次我就是先清理、后发现文件没了，又得重下一遍。

**修法**：构建脚本里把注入固件的动作放在 `mrproper` **之后**。

### 坑 6：版本串对不上，模块会被拒

tarball 里没有 `.git` 目录，内核脚本 `setlocalversion` 算不出 `-g71b13e62f057` 这个后缀，编出来的版本串是 `4.19.325-cip131-st15-perf`，比原厂少一截，**模块 vermagic 会不匹配**。

试过用环境变量 `KERNELVERSION=` 覆盖，**无效** —— 内核 `Makefile:306` 用的是 `KERNELVERSION = ...`（等号赋值），会覆盖环境变量。

**修法**：用内核自带的 `.scmversion` 文件机制。在源码树根放一个 `.scmversion`，内容写 `-g71b13e62f057`，脚本就会输出 `-cip131-st15-perf-g71b13e62f057`。实测验证通过。

同样要注意：这个文件也会被 `mrproper` 删，所以也在清理之后注入。

## 五、我犯的三个操作错误

坦白记下来：

1. **`fastboot flash` 的镜像路径写错了。** 我把镜像推到手机 `/data/local/tmp/`，然后 `fastboot flash boot_a /data/local/tmp/xxx.img`。**fastboot 模式下手机读不到自己内部的文件**，必须传电脑端的路径。正确的是 `fastboot flash boot_a <电脑上的文件>`。
2. **用了 `mv` 而不是 `cp`。** 准备 Magisk 模块时想把文件挪到新目录，结果把源目录搬空了。
3. **两次构建互相覆盖了产物。** 为了做对照实验（编一份「不改配置」的），结果那次的产物把正式产物覆盖了。事后靠 SHA256 对不上才发现。**教训**：每次构建完要立刻把产物拷到独立目录。

## 六、刷入

第一次我自己执行 `fastboot flash` 失败了：

```
Sending 'boot_a' (196608 KB)   FAILED (AdbWriteEndpointSync failed: ... (31))
```

这是这台机器的老毛病，[79 篇](79-g100-ci-execution.md) 记过类似的 121 超时。**手机没变砖**，重启回 Android 正常。

用户手动在 Windows PowerShell 里刷，一次成功：

```
fastboot flash boot C:\Users\<user>\Downloads\boot-munch-lxc6-magisk.img
Sending 'boot_a' (196608 KB)   OKAY [4.472s]
Writing 'boot_a'               OKAY [0.476s]
```

boot.img 是用 Magisk 自带的 `magiskboot` 打的：解开手机上当前的 Magisk 版 boot → 换掉里面的 kernel → 重新打包。**这样 root 不会丢**。头部信息（header v3、页大小 4096、OS 版本 16.0.0）都沿用原来的。

## 七、刷完发现模块没生效，又修了 3 个问题

刷完第一次开机，`dmesg` 里出现：

```
rmnet_shs: disagrees about version of symbol module_layout
rmnet_perf: disagrees about version of symbol module_layout
```

原因是那 3 个 vendor 模块还是原厂的。计划用 Magisk 模块替换它们，又踩了 3 个坑：

### 坑 7：模块目录里有 `disable` 文件

`magisk --install-module` 装完之后，模块目录里出现了 `disable` 文件。**有这个文件，Magisk 会完全跳过这个模块**，静默失效。删掉就好了。

另外这个命令**只提取了 `module.prop`，没提取 `vendor/` 下的 `.ko` 文件**，只好改用 root 直接把解包后的文件放到位。

### 坑 8：magic mount 根本没运行

正常 Magisk 模块会用「魔法挂载」把文件覆盖到 `/vendor`。但这台机器上 `/mnt/magisk` 目录不存在，`/vendor` 还是裸的 erofs（Android 16 的只读文件系统），说明 magic mount 压根没跑。

**最后靠模块里的 `post-fs-data.sh` 脚本做 bind mount 生效。**

### 坑 9：bind mount 之后 SELinux 拦住了

**这个坑最隐蔽。** 文件确实被换掉了（哈希对得上），但模块还是加载不了。`dmesg` 里是：

```
avc: denied { getattr } comm="modprobe" path="/vendor/lib/modules/rmnet_shs.ko"
  scontext=u:r:vendor_modprobe:s0  tcontext=u:object_r:system_file:s0
```

**SELinux 是 Android 的安全机制**，它按「标签」决定谁能读哪个文件。源文件在 `/data` 下，bind 到 `/vendor` 后标签还是 `system_file`，而加载模块的 `modprobe` 进程只被允许读 `vendor_file`，所以被拒。

**修法**：bind 之后立刻执行 `restorecon`，把标签改回 `vendor_file`。加上这一步后模块正常加载。

## 八、验收结果（全部实机读出）

| 检查项 | 方法 | 结果 |
|---|---|---|
| 新内核确实生效 | 看 `/proc/version` 的编译时间 | `Thu Oct 1 00:25:09 CST 2026`，正是本次构建时刻 |
| 6 项配置生效 | 读 `/proc/config.gz` | 6 项全是 `y` |
| IPC 命名空间 | `unshare --ipc` | 成功 |
| PID 命名空间 | `unshare --pid --fork` | 成功 |
| 用户命名空间 | `unshare --user` | 成功 |
| System V IPC | 看 `/proc/sys/kernel/` 下的 sysctl | 8 项全在（`shmmax`、`sem`、`msgmax` 等） |
| POSIX 消息队列 | `mount -t mqueue` | 挂载成功 |
| KGSL 图形（Rungic 渲染硬依赖） | `ls /dev/kgsl-3d0` | 存在 |
| 模块 CRC 拒绝 | `dmesg \| grep "disagrees about version"` | **0 次** |
| 未知符号 | `dmesg \| grep "Unknown symbol"` | **0 次** |
| vendor 模块加载 | `lsmod` | `rmnet_perf`、`rmnet_shs` 均在 |
| Magisk root | `magisk -v`、`su -c id` | `31.0:MAGISK:R`、`uid=0` |
| 蜂窝数据通路 | `ip addr show rmnet_data0` | 网卡 UP |

`dmesg` 里剩下的 `modprobe ... exited with status 1` 是正常的：那是在找 `/vendor/lib/modules/5.4-gki/` 目录（这是给 GKI 内核用的，本机不是），以及 `rmnet_ctl`/`rmnet_core`（这两个已经编进内核里了，本来就没有 `.ko` 文件）。

## 九、还剩什么

内核已经不是瓶颈了。往下走是装 RungicOS rootfs 并在手机上跑通 LXC 容器，这部分**本篇没有做，也还没有验证**。

## 十、想复现的话

```bash
# 1. 准备（一次性）
#    - 源码：LineageOS/android_kernel_xiaomi_sm8250 的 lineage-23.2 分支
#    - 编译器：Android clang 12.0.5 (r416183b)
#    - Docker 镜像 los-kernel-build:24.04（见 .work/los-kernel/Dockerfile.kernel）
#    - 原厂内核配置：从原厂 boot.img 的 IKCFG 解出，存为 inputs/stock.config
#    - focaltech 固件：从 LineageOS 仓库下载两个 .i 文件到 inputs/focaltech-fw/
#    - 存一个 .scmversion，内容 -g71b13e62f057

# 2. 编译（会先清理，再注入固件和版本串，然后全量编译）
docker run --rm \
  -v kernel-src:/build -v clang-:/opt/clang \
  -v build-logs:/logs -v inputs:/inputs:ro \
  -v build-final2.sh:/bf2.sh:ro \
  los-kernel-build:24.04 bash /bf2.sh

# 3. 打包 boot.img（保留 Magisk）
./boot-pack/pack-boot.sh <绝对路径>/kernel-src/arch/arm64/boot/Image

# 4. 刷入（镜像路径必须是电脑端路径）
fastboot flash boot <电脑上的>/boot.img

# 5. 装 Magisk 模块（替换 3 个 vendor 模块）
#    模块目录结构：
#      module.prop
#      post-fs-data.sh      ← bind mount + restorecon
#      vendor/lib/modules/*.ko
```

## 相关文档

- [75 篇](75-image-build-separation.md)：三段式镜像分工
- [79 篇](79-g100-ci-execution.md)：fastboot 刷写超时（121）的记录
- [85 篇](85-lxc-rootless-docker.md)：LXC 相关
