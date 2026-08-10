# latte-linux-build

为小米平板 2（**latte**, Intel Cherry Trail x86_64）构建可刷入系统的构建工具链：
构建 [linux_latte](https://github.com/xiaomi-latte-dev/linux_latte) 内核 → 组装 Debian/Ubuntu
根文件系统 → 生成 **DNX Mode** 可刷入的完整刷机包（tarball）。

构建矩阵（默认全量 6 个组合）：

| 维度 | 取值 |
|---|---|
| 发行版 | Debian 13 (trixie) / Ubuntu 24.04 LTS (noble) |
| 版本 | Server（最小化，**仅 en-US**）/ Desktop（XFCE，en-US / zh-CN） |
| 语言 | Server 仅 en-US；Desktop 含 en-US 与 zh-CN（CJK 字体 + fcitx5 中文输入法） |

## 快速开始

### 本地构建（Linux）

```bash
# 安装依赖（Debian/Ubuntu）
sudo apt install debootstrap build-essential bc bison flex libssl-dev libelf-dev \
  ccache dpkg-dev debhelper rsync dosfstools e2fsprogs python3

# 全矩阵构建（内核编译约 30-60 分钟）
./scripts/build.sh

# 只构建指定组合
./scripts/build.sh --distro debian --edition server --lang en-US

# 只编译内核 / 复用已有内核 / 只执行某阶段
./scripts/build.sh --kernel-only
./scripts/build.sh --skip-kernel --edition desktop
./scripts/build.sh --stage 3 --distro ubuntu
```

产物：`dist/xiaomi-latte-<distro>-<edition>-<lang>-<yyyymmdd>.tar.gz`

### 本地构建（macOS）

Stage 2-4 需要 Linux（root 权限），使用 Docker：

```bash
make docker-build-all     # 容器内全矩阵构建
make docker-run           # 进入交互容器手动执行
```

### GitHub Actions（自动 / 手动）

- **自动**：`push` 到 `main` 全矩阵构建；`push` tag `v*` 构建并发布 GitHub Release
- **手动**：仓库 Actions 页 → **build** workflow → `Run workflow`，
  可指定 distro / edition / lang / 内核 ref

## 刷机

1. 关机后同时按住 **Vol+ / Vol- / Power** 进入 `DNX FASTBOOT`
2. 解压刷机包，运行 `./flash_all.sh`（Windows 用 `flash_all.bat`）
3. 首次启动若进 BIOS 或黑屏：连按 **F2** 关闭 Secure Boot
4. 默认用户 `latte` / `latte`，登录后请立即 `passwd`

详细步骤见刷机包内 `README.md`。

## 目录结构

```
config/                 构建配置（build.conf / gpt.ini / 包清单 / 刷机脚本模板）
scripts/                构建流水线（stage-1 ~ stage-4 + 工具脚本）
docker/                 本地构建容器
third_party/            vendor 的 flash_tools（fastboot.efi / oemvars）与参考仓库
.github/workflows/      GitHub Actions 自动 + 手动构建
```

## 构建流水线

```
stage-1 内核     linux_latte -> xiaomipad2_defconfig -> make deb-pkg -> .deb + 固件
stage-2 rootfs   debootstrap -> 注入内核 .deb -> initramfs -> grub.cfg -> locale/时区/用户
stage-3 镜像     boot.img(FAT32 ESP) + root.img(ext4, sparse) + gpt.bin
stage-4 打包     组装 images + device_files + 刷机脚本 -> tar.gz
```

关键设计（详见各脚本注释）：

- **分区表**：boot 256MB ESP + system 剩余空间（固定 GUID `CC8CF58C-...`），
  与 [xiaomi-latte-flash_tools](https://github.com/xiaomi-latte-dev/xiaomi-latte-flash_tools) 完全兼容
- **引导链**：UEFI → shim → grub（`--removable` 安装到 ESP）→ vmlinuz + initrd
- **根文件系统**：ext4 固定 UUID；首启 `x-systemd.growfs` 自动扩容到整块磁盘
- **内核安装**：`dpkg -i` + `apt-mark hold`，避免发行版升级覆盖自建内核
- **设备支持**：WiFi（brcmfmac4356）/ 蓝牙（BCM4356A2）/ ISP（shisp）/ 音频（rt5659 UCM）/
  触屏（hwdb），全部对齐内核仓库 `fix_file/` 与 postmarketOS 已验证配置

## 自定义

- `config/build.conf`：发行版版本、镜像大小、根分区 UUID、默认用户等
- `config/packages/*.txt`：各发行版/版本/语言包清单
- 内核 ref：`--ref <commit|tag|branch>`（默认 `main`）

## 已知限制与风险

- 构建产物未在真机验证前，请谨慎刷入；真机验证清单见 `AGENTS.md`
- 关闭 Secure Boot 是首启的推荐路径（shim 链仍被安装，若需保持开启可自行 MOK 导入）
- 相机 T4KA3 驱动需应用内核补丁（`fix_file/latte-camera-t4ka3.patch`），默认未启用
