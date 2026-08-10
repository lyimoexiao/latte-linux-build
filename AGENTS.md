# AGENTS.md

本文件记录 latte-linux-build 的项目约定，供开发者与 AI 助手维护时遵循。

## 项目目标

为小米平板 2（latte）构建可刷入（DNX Mode / fastboot）的 Debian / Ubuntu 刷机包。
内核来自 [linux_latte](https://github.com/xiaomi-latte-dev/linux_latte)，
刷机协议参考 [xiaomi-latte-flash_tools](https://github.com/xiaomi-latte-dev/xiaomi-latte-flash_tools)。

## 关键命令

```bash
make check              # 静态检查（bash -n + py_compile）
./scripts/build.sh      # 全矩阵构建（Linux root）
make docker-build-all   # macOS：容器内全矩阵构建
make clean              # 清理 work/ 与 dist/
```

## 构建流水线与约定

- **stage 脚本无副作用假设**：每个 stage 只依赖前序 stage 的输出目录，
  可单独重跑（`./scripts/build.sh --stage N`）。
- **内核只构建一次**：产物在 `work/kernel/`（debs / kernel-release / firmware），
  全部组合复用。CI 中通过 artifact 传递。
- **Server 版本仅构建 en-US**；Desktop 构建 en-US 与 zh-CN（见 `build.sh` 与
  `.github/scripts/gen-matrix.py` 中的矩阵约束，两处逻辑必须一致）。
- **rootfs 组装**：Stage 2 在 chroot 内完成；`policy-rc.d` 阻止服务启动尝试；
  内核 .deb 必须先于 grub 包安装（避免 kernel postinst 触发 update-grub 失败）。
- **grub 配置是静态生成**的（`/boot/grub/grub.cfg`），不运行 grub-mkconfig
  （chroot 中 grub-probe 无法探测无设备的根文件系统）。修改内核版本时需同步更新
  生成逻辑。GRUB 本体在 Stage 3 通过 chroot `grub-install --removable` 安装到 ESP。
- **根分区 UUID 固定**（`config/build.conf` 的 `ROOT_UUID`），同时用于
  `mkfs.ext4 -U`、`/etc/fstab`、`/boot/grub/grub.cfg`，三处必须一致。
- **root.img 刷机版为 Android sparse 格式**；raw 版保留在 stage 目录供本地调试。
- **设备支持配置源**：内核仓库 `fix_file/`（固件、UCM、hwdb）为权威来源，
  升级内核时需同步更新 Stage 2 的部署逻辑。

## 代码风格

- 脚本：`bash`（`set -euo pipefail`），公共函数放 `scripts/helpers.sh`，
  通过 `parse_args` 解析 `--key value` 参数。
- 配置：`config/build.conf` 为 shell 可 source 的键值对，脚本不硬编码默认值。
- Python：`scripts/gpt_ini2bin.py`（分区表）、`scripts/sparse.py`（sparse 镜像）。
- 注释用中文，与项目文档语言一致。

## 真机验证清单（刷入后必测）

1. DNX 进入 + `fastboot boot fastboot.efi` + `getvar product` = latte
2. 分区表刷入后 `gpt.bin` 生效（boot 256MB ESP / system 占满）
3. 首次启动：Secure Boot 关闭后能否进 GRUB 菜单
4. 内核启动：dmesg 无 sdhci/mmc 致命错误；触屏 / WiFi / 蓝牙 / 音频可用
5. root 分区自动扩容生效（`df -h /` 接近磁盘容量）
6. zh-CN 包：fcitx5 输入、CJK 字体渲染正常

## 许可与归属

- `third_party/device_files/`（fastboot.efi、oemvars）来自 xiaomi-latte-flash_tools，
  上游未声明 LICENSE，原样保留。
- `third_party/flash_tools/` 为参考仓库浅克隆，用于同步上游改动。
