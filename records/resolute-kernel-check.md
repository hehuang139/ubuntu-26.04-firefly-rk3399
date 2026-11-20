# Resolute ARM64 内核输入 · 2026-11-20

Ubuntu Base：`ubuntu-base-26.04.1-base-arm64.tar.gz`，SHA-256 `5a1906794ced63a71a8119c3f211ef5f0bbe0a243001b4bbd41fdf80c5b219fd`，Ubuntu CD Image 签名密钥 `843938DF228D22F7B3742BC0D94AA3F0EFE21092`。

| Ubuntu ARM64 软件包（resolute-updates） | SHA-256 |
| --- | --- |
| `linux-image-7.0.0-44-generic_7.0.0-44.44_arm64.deb` | `550f7d8ec3067d807f56ac5c92c445ca22d1518adecbf13f718fcaa1a6e68f09` |
| `linux-modules-7.0.0-44-generic_7.0.0-44.44_arm64.deb` | `cfb98e1ff2d53e0b39963bee04cb3ec0c40f34361f27b08b644cf330cee867ea` |

从模块包读取 `usr/lib/firmware/7.0.0-44-generic/device-tree/rockchip/rk3399-firefly.dtb`。原件 SHA-256 `7e973c4e426c8da3307a5cd2ccf94340b4ba3d9fe4e9a0aed70d1afe881bc954`，大核 `0x40` 为 `0`，GPU `0x41` 为 `1`，两路均有 `regulator-off-in-suspend`。核对板级供电引用后，只修改大核的 selector。

从 Ubuntu 内核的 EFI UKI `.linux` 中提取 zboot zstd 负载，解成 ARM64 `Image`，SHA-256 `75e2988c9a5070a95940b34d0be181884886199b69cc43337ecb3ee4a63c07e5`。用该 `vmlinuz`、上述 DTB 和回归用的 initrd 执行两个更新钩子：TF/eMMC 均能生成修正树和内核入口，能在未生成 initrd 时保留旧启动菜单，能拒绝陌生的 GPU 稳压器与截断的内核。

QEMU 10.2.0 Firefly 模型，2 GiB，使用合成 DTB 直接加载解出的 `Image`。串口打印 `Linux version 7.0.0-44-generic`（Ubuntu 版本 `7.0.0-44.44-generic 7.0.14`）和 `SMP: Total of 6 processors activated.`。此轮只启动内核，未传入 initrd 或根磁盘，在 VFS 查找根分区时结束。
