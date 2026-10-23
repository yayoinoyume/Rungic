# K40S：systemd 255 的 apt 账目对齐与 /tmp 上限

> 适用设备：Redmi K40S（`munch`，SM8250，LineageOS 23.2 / Android 16，内核 4.19.325）。
> 本文记录 2026-10-23 的实机修复。其他机型不要直接套用：它们的内核和 systemd 版本不同。

## 一、现象

在 K40S 的 Rungic 容器里，`apt-get install` 任何**新包**都会在依赖求解阶段失败：

```
libsystemd-dev : Depends: libsystemd0 (= 259.5-0ubuntu3.4) but 255.4-1ubuntu8.17 is to be installed
libudev-dev    : Depends: libudev1 (= 259.5-0ubuntu3.4) but 255.4-1ubuntu8.17 is to be installed
netplan-generator : Depends: systemd (>= 258~) but 255.4-1ubuntu8.17 is to be installed
netplan.io        : Depends: systemd (>= 258~) but 255.4-1ubuntu8.17 is to be installed
E: Unmet dependencies.
```

`dpkg --audit` 却是空的，因为 dpkg 不检查版本依赖，只有 apt 会检查。已经装过的包可以重复安装，新包一律被拒。

## 二、根因

- systemd 258 起把最低内核基线提高到 **5.4**，并移除 cgroup v1 支持；K40S 的内核是 **4.19**。
- 2026-10-01 为了让桌面能启动，容器运行时被降到 Ubuntu 24.04 的 `255.4-1ubuntu8.17`（`/var/log/dpkg.log` 08:24 有记录）。仓库的 `system/init` 另有 pidfd 垫片，让 systemd 走 `waitpid` 路径。
- 降级只处理了运行时，留下了三处账目不平：
  - `libsystemd-dev` / `libudev-dev` 仍是 resolute 的 `259.5`；
  - `netplan.io` / `netplan-generator` 是 resolute 的 `1.2`，硬性要求 `systemd (>= 258~)`；
  - apt 的候选版本仍是 259，任何 `apt upgrade` 都可能把 systemd 拉回去。
- 因此 apt 的整个已安装集合是不一致的，它在考虑新包之前就退出。

## 三、为什么不升 systemd

- 4.19 低于 systemd 258 的 5.4 基线；历史上 259 在这个容器里表现为所有 unit `Result=resources`，桌面起不来。
- `apt --fix-broken install` 会提出把 systemd 升到 259，等于用“修复”再次弄坏桌面。
- 结论：运行时保持 255.4，改的是**包元数据**，不是 systemd 本身。

## 四、修复脚本

脚本：`munch-build-kit/rootfs-scripts/reconcile-systemd-255.sh`

在 K40S 的 Rungic 容器内以 root 运行：

```bash
# 只检查，不改任何东西
munch-build-kit/rootfs-scripts/reconcile-systemd-255.sh --check

# 下载、重打包并校验，但不安装（可先预览）
munch-build-kit/rootfs-scripts/reconcile-systemd-255.sh --dry-run

# 应用（必须显式 --apply）
munch-build-kit/rootfs-scripts/reconcile-systemd-255.sh --apply
```

脚本做四件事：

1. 从 Launchpad 取**正好 255.4-1ubuntu8.17** 的 `libsystemd-dev`、`libudev-dev`，校验 SHA-256 后安装。它们只是开发头文件，不影响运行中的桌面。
2. 下载 resolute 的 `netplan.io` / `netplan-generator` `1.2-1ubuntu5.1`，重打包为 `1.2-1ubuntu5.1+rungic255.1`，只把依赖 `systemd (>= 258~)` 改成 `>= 255~`。脚本会逐项比较重打包前后的所有普通文件和符号链接，发现任何差异就拒绝安装。
3. 写入 `/etc/apt/preferences.d/rungic-systemd-255`：systemd 255 全家、两个开发包、netplan 全家的版本 pin（优先级 1001）。
4. `apt-mark hold` 同一组包，防止日常 `apt upgrade` 或 `unattended-upgrades` 把 systemd 拉回 259。

脚本不会重启容器，也不会替换运行中的 systemd。`--rollback` 会从 `$WORK/backup/<时间>/` 恢复修复前的包并撤掉 pin/hold。

选项：

- `--deb-dir DIR`：离线时从目录取预下载的四个 deb；
- `--work DIR`：工作与备份目录，默认 `/var/tmp/rungic-apt-reconcile`。

## 五、验证

2026-10-23 在 K40S 实机执行后的结果：

- `apt-get check`：通过；
- `apt-get install -y --no-install-recommends tree`：正常下载、解包、配置；
- `apt-cache policy systemd libsystemd-dev netplan.io`：Candidate 等于已安装版本；
- `apt-get upgrade -s` / `full-upgrade -s`：不再出现 systemd 259；
- `systemctl show -p Version`：仍是 `255.4-1ubuntu8.17`；
- `dpkg --audit`：空。

## 六、限制

- 明确要求 `systemd >= 258` 或 `libsystemd0 >= 256` 的新包仍然装不了；apt 会直接说明原因。这是内核限制，不是脚本缺陷。
- 255 系列后续的安全更新（例如 `8.18`）不会自动安装；需要时手动评估并更新 pin。
- 26.04 + 4.19 内核 + systemd 259 是不被上游支持的组合。长期应改用 Ubuntu 24.04 rootfs，或换内核 ≥ 5.4 的设备。

## 七、/tmp 上限（同批修复）

K40S 修复时发现 `/tmp` 是 tmpfs，默认按内存一半分配（5.7 GiB），被 Agent 工作目录写满后连带把 swap 用到 7.2 GiB、可用内存只剩 451 MiB。

同批改动：

- `system/plasma.config` 的 `/tmp` 挂载加 `size=2G`，保留 `nosuid,nodev,mode=1777`；
- `system/config/etc/profile.d/50-rungic-tmpdir.sh`：登录 shell 默认 `TMPDIR=/var/tmp`；
- `system/config/etc/systemd/system.conf.d/50-rungic-tmpdir.conf` 与 `user.conf.d/50-rungic-tmpdir.conf`：系统与用户服务默认 `TMPDIR=/var/tmp`。

**生效条件**：这些文件随 `rungic-plasma-config` 部署；新的 tmpfs 上限要等 LXC 容器下次启动，已经在运行的进程仍使用旧环境。
2026-10-23 的实机修复只把现有 `/tmp` 从 5.6 GiB 清到 196 MiB，并**没有重启容器**。

## 八、证据与相关文档

- 修复前状态、apt 报错、`dpkg.log` 的降级记录：本文 §1–2（2026-10-23 实机读取）。
- 修复后验证：本文 §5（2026-10-23 实机执行）。
- K40S 内核重编与 LXC 前提：[91](91-munch-kernel-rebuild.md)。
- 上游 systemd 258 的内核基线说明：systemd `NEWS` 的 `CHANGES WITH 258`。
- 构建套件入口：[munch-build-kit/README.md](../munch-build-kit/README.md)。
