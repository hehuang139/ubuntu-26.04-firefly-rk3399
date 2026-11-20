# Firefly-RK3399 · Ubuntu 26.04.1 LTS GNOME

本项目面向**原版 Firefly-RK3399 DDR3 Rev 1.0（2 GiB）**，从 [Ubuntu Base 26.04.1 LTS](https://cdimage.ubuntu.com/ubuntu-base/releases/26.04.1/release/)（Resolute、ARM64）和 Ubuntu 官方软件仓库构建 GNOME 镜像。TF 与 eMMC 镜像、校验值和验证记录发布在本项目的 [Releases](https://github.com/hehuang139/ubuntu-26.04-firefly-rk3399/releases)。[Ubuntu 22.04.5](https://github.com/hehuang139/ubuntu-firefly-rk3399) 由独立项目维护。

复用本板的 U-Boot 2025.10 和 TF-A 2.13，并按介质选用不同的引导件。保留经板上定位的 VSEL 规则：大核电源 `0x40` 的休眠 selector 必须是 `1`，GPU `0x41` 保持 `1`，两路保留 `regulator-off-in-suspend`。脚本从实际内核包的 DTB 沿 CPU 和 GPU 的供电引用核对这两路，再生成 extlinux 启动文件。Ubuntu 26.04 的内核包可能提供 EFI UKI，脚本从其 `.linux` 节和 zboot 负载生成供 U-Boot `booti` 使用的 ARM64 `Image`，不使用 UKI 内嵌的设备树。有关原故障及影响范围，见 [22.04 原板故障复盘](https://github.com/hehuang139/ubuntu-firefly-rk3399/blob/5f2035ee30d6efbeb47ad05390c51e6144dfde87/docs/vsel.md)。本版本使用的内核包和回归测试见 [26.04 内核输入记录](records/resolute-kernel-check.md)。

## 构建

在 Linux 主机上准备 Docker，至少预留 16 GiB 的构建空间和另外 4 GiB 的输出空间：

```sh
docker build -t firefly-ubuntu26-builder:local .
./rebuild.sh all
```

可分步执行 `fetch`、`rootfs`、`finalize`、`sd`、`emmc`；`image` 顺序制作两种介质。`FIREFLY_STAGE` 与 `FIREFLY_OUTPUT` 可指向容量足够的目录。Ubuntu Base 启用 GPG 签名检查和固定 SHA-256；APT 继续检查 Ubuntu 官方 ARM64 签名索引与包哈希。构建记录位于 `work/ubuntu26/records`，其中 `packages.tsv` 包含安装的包和版本。APT 更新会改变选用的包版本。

组装时同时检查引导件哈希、分区表、完整分区回读、ext4、启动菜单、内核和 initrd、实际选中的 DTB、发行版和 GNOME 会话。内核和 initramfs 更新钩子重新核对 DTB；新 DTB 不合格时保留已验证的启动菜单。`scripts/test-vsel-update.sh` 使用实际安装的本板 DTB、ARM64 内核和 initrd 测试旧 `0/1` 配置，覆盖 TF、eMMC、内核更新、回退和拒绝不匹配设备树的路径。

## 启动与安装

`*-sd-test1.img.gz` 写 TF，`*-emmc-test1.img.gz` 写 eMMC 用户区。镜像解压为 7 GiB，含 MBR、引导区和 ext4 根分区。先用 16 GB 或更大的 TF 卡检查板上启动、HDMI、输入和网络，再写 eMMC。eMMC 用户区至少需要 7 GiB；不要写到分区或 `mmcblkNboot0/1`。

1. 先用 `sha256sum --ignore-missing -c SHA256SUMS`（同目录须有下载的镜像） 核验下载。用支持 `.img.gz` 的写盘工具把 TF 版写到卡上，等待读回校验。断电，接 HDMI 和 USB 键鼠，再插卡开机。
2. 按 GNOME 首次设置创建账号。镜像没有默认用户，root 被锁定，SSH 默认关闭。需要远程访问时，登录后运行 `sudo systemctl enable --now ssh` 及 `hostname -I`。
3. 若要安装到 eMMC，从已能启动的 TF 版进入系统，用 `findmnt -no SOURCE /` 与 `lsblk -o PATH,SIZE,TYPE,MOUNTPOINTS` 排除正在使用的 TF。确认目标设备在 `/sys/block/mmcblkN/device/type` 显示 `MMC`，`readlink -f /sys/block/mmcblkN` 路径经过 `fe330000`。备份原系统，卸载目标盘的分区并关闭其 swap。以整盘恢复方式写入解压后的 eMMC 版；若旧盘采用 GPT 且工具不会清理，应先清掉已确认目标盘上的旧 GPT 主、备表。写后按 `SHA256SUMS` 中同名 `.img` 的校验值核对前 7 GiB 的回读，关机拔 TF 再尝试 eMMC。

两种介质的 PARTUUID 分别为 `26339001-01` 与 `26339002-01`；首次启动会尝试扩展根分区。需要串口时，本板 UART2 为 `1500000 8N1`，使用 3.3 V TTL，接 RX/TX/GND，不接 VCC。
