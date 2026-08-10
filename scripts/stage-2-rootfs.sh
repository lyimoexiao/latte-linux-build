#!/usr/bin/env bash
# Stage 2: 构建 rootfs
#   debootstrap -> 安装包组 -> 注入内核 .deb -> initramfs -> 系统配置（locale/时区/用户/固件）
#   -> 静态 grub.cfg（GRUB 安装与 ESP 组装在 Stage 3 完成）
#
# 用法: stage-2-rootfs.sh <distro> <edition> <lang>
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

DISTRO="${1:?distro}"; EDITION="${2:?edition}"; LANG="${3:?lang}"
require_root

SUITE="$(suite_of "$DISTRO")"; MIRROR="$(mirror_of "$DISTRO")"; SECMIRROR="$(secmirror_of "$DISTRO")"
COMPONENTS="$(components_of "$DISTRO")"
TZ="$(timezone_of "$LANG")"; LOCALE="$(locale_of "$LANG")"
ROOTFS="$ROOTFS_BASE/$DISTRO-$EDITION-$LANG"
STAGE_DIR="$STAGE/$DISTRO-$EDITION-$LANG"
KVER="$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || true)"
PKGS="$(resolve_packages "$DISTRO" "$EDITION" "$LANG")"

info "== Stage 2: rootfs ($DISTRO/$EDITION/$LANG, suite=$SUITE) =="
[ -n "$KVER" ] && [ -n "$(ls "$KERNEL_OUT"/debs/linux-image-*.deb 2>/dev/null)" ] \
    || die "内核产物缺失，请先运行 stage-1-kernel.sh"

rm -rf "$ROOTFS" "$STAGE_DIR"; mkdir -p "$ROOTFS" "$STAGE_DIR"

# ---------- debootstrap ----------
# 注意：debootstrap 的 --components 需要逗号分隔；apt sources.list 需要空格分隔
info "debootstrap $SUITE (amd64, minbase) -> $ROOTFS"
debootstrap --variant=minbase --arch=amd64 --components="${COMPONENTS// /,}" \
    "$SUITE" "$ROOTFS" "$MIRROR"

# 阻止 chroot 内服务启动尝试（镜像构建标准做法）
printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
chmod +x "$ROOTFS/usr/sbin/policy-rc.d"

# ---------- apt 源 ----------
if [ "$DISTRO" = debian ]; then
    cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE $DEBIAN_COMPONENTS
deb $MIRROR $SUITE-updates $DEBIAN_COMPONENTS
deb $SECMIRROR $SUITE-security $DEBIAN_COMPONENTS
EOF
else
    cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE $UBUNTU_COMPONENTS
deb $MIRROR $SUITE-updates $UBUNTU_COMPONENTS
deb $SECMIRROR $SUITE-security $UBUNTU_COMPONENTS
EOF
fi

chroot_enter "$ROOTFS"
trap 'chroot_exit' EXIT
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

# ---------- 基础包 ----------
info "apt update + 安装包组"
run_chroot "$ROOTFS" apt-get update -y
# shellcheck disable=SC2086
run_chroot "$ROOTFS" apt-get install -y --no-install-recommends $PKGS

# ---------- 注入内核 ----------
# 注意：必须排除 -dbg 调试包（仅含 vmlinux 调试符号，不含 /boot/vmlinuz）。
# 字母序上 linux-image-*-dbg 排在 linux-image-* 之前，直接 head -n1 会抓错。
KERNEL_DEB="$(ls "$KERNEL_OUT"/debs/linux-image-*.deb | grep -v -- '-dbg' | head -n1)"
[ -n "$KERNEL_DEB" ] || die "未找到内核镜像包（linux-image-*）"
info "注入内核: $(basename "$KERNEL_DEB")"
cp "$KERNEL_DEB" "$ROOTFS/tmp/"
run_chroot "$ROOTFS" dpkg -i "/tmp/$(basename "$KERNEL_DEB")"
run_chroot "$ROOTFS" apt-get install -f -y
rm -f "$ROOTFS/tmp/$(basename "$KERNEL_DEB")"

# ---------- 系统配置 ----------
info "写入系统配置（fstab/hostname/时区/locale/固件/initramfs/grub.cfg）"

# hostname
echo "$DEVICE_PRODUCT" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $DEVICE_PRODUCT
EOF

# 时区
echo "$TZ" > "$ROOTFS/etc/timezone"
ln -sf "/usr/share/zoneinfo/$TZ" "$ROOTFS/etc/localtime"

# locale
{
    echo "en_US.UTF-8 UTF-8"
    [ "$LANG" = zh-CN ] && echo "zh_CN.UTF-8 UTF-8"
} > "$ROOTFS/etc/locale.gen"
run_chroot "$ROOTFS" locale-gen
printf 'LANG=%s\n' "$LOCALE" > "$ROOTFS/etc/default/locale"

# fstab（root 固定 UUID + 首启 x-systemd.growfs 自动扩容；/boot 为 ESP，PARTLABEL 定位）
cat > "$ROOTFS/etc/fstab" <<EOF
UUID=$ROOT_UUID / ext4 defaults,x-systemd.growfs 0 1
PARTLABEL=$BOOT_PART_LABEL /boot vfat defaults,nofail 0 2
EOF

# initramfs 模块（eMMC/USB/触屏/gadget）
cp "$ROOT/config/initramfs-modules" "$ROOTFS/etc/initramfs-tools/modules"

# 音频模块开机加载（fix_file/audio.md + 实测修正）
# 注意：加载顺序很关键。仅 preload snd_soc_rt5659 时声卡注册会卡 EPROBE_DEFER
# （snd_soc_register_card failed -517，aplay 无声卡）；按 平台->codec->machine
# 顺序加载即可正常注册（已在真机验证）。
mkdir -p "$ROOTFS/etc/modules-load.d"
cat > "$ROOTFS/etc/modules-load.d/latte.conf" <<'EOF'
snd_intel_sst_acpi
snd_soc_sst_atom_hifi2_platform
snd_soc_rt5659
snd_soc_sst_cht_bsw_rt5659
EOF

# 启动早期 modules-load.d 加载时机早于 I2C/ACPI 设备就绪，声卡仍可能卡 -517；
# 此 oneshot 服务在 multi-user.target 后按正确顺序重载音频模块（真机验证有效）。
cat > "$ROOTFS/etc/systemd/system/latte-audio-fix.service" <<'EOF'
[Unit]
Description=Reload audio modules in correct order (fix EPROBE_DEFER)
After=systemd-modules-load.service multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "modprobe -r snd_soc_sst_cht_bsw_rt5659 snd_soc_rt5659 snd_soc_sst_atom_hifi2_platform snd_intel_sst_acpi 2>/dev/null; modprobe snd_intel_sst_acpi 2>/dev/null; modprobe snd_soc_sst_atom_hifi2_platform 2>/dev/null; modprobe snd_soc_rt5659 2>/dev/null; modprobe snd_soc_sst_cht_bsw_rt5659 2>/dev/null"

[Install]
WantedBy=multi-user.target
EOF
run_chroot "$ROOTFS" systemctl enable latte-audio-fix.service 2>/dev/null || true

# 触摸屏底部按键 hwdb（来源：linux_latte/fix_file/README.md）
mkdir -p "$ROOTFS/etc/udev/hwdb.d"
cat > "$ROOTFS/etc/udev/hwdb.d/60-keyboard.hwdb" <<'EOF'
# Fix mapping of menu / home / back capacitive buttons on bottom bezel
# Menu: LeftMeta + S   -> menu      (ignore LeftMeta, map S to menu)
# Home: LeftCtrl + Esc -> LeftMeta  (ignore LeftCtrl, map Esc to LeftMeta)
# Back: Backspace      -> back      (map backspace to back)
evdev:name:FTSC1000:00 2808:509C Keyboard:dmi:*:svnXiaomiInc:pnMipad2:*
 KEYBOARD_KEY_700e0=reserved	# LeftCtrl -> ignore
 KEYBOARD_KEY_700e3=reserved	# LeftMeta -> ignore
 KEYBOARD_KEY_70016=menu	# S -> menu
 KEYBOARD_KEY_70029=leftmeta	# Esc -> LeftMeta (Windows key / Win8 tablets home)
 KEYBOARD_KEY_7002a=back	# Backspace -> back
EOF

# 设备固件（来自 stage-1 的 $KERNEL_OUT/firmware）
mkdir -p "$ROOTFS/lib/firmware/brcm"
cp "$KERNEL_OUT/firmware/$FW_WIFI" "$ROOTFS/lib/firmware/brcm/"
cp "$KERNEL_OUT/firmware/$FW_BT" "$ROOTFS/lib/firmware/brcm/"
cp "$KERNEL_OUT/firmware/$FW_ISP" "$ROOTFS/lib/firmware/"
# atomisp 驱动实际按 intel/ipu/shisp_2401a0_v21.bin 查找（fix_file README 写的
# /lib/firmware 根目录位置驱动不识别，实测 dmesg 报 Direct firmware load failed）
mkdir -p "$ROOTFS/lib/firmware/intel/ipu"
cp "$KERNEL_OUT/firmware/$FW_ISP" "$ROOTFS/lib/firmware/intel/ipu/"
# ALSA UCM 音频拓扑：使用修复版（config/ucm），不再拷贝 fix_file/audio 的旧 UCM
# （旧版对 alsa-lib 1.2.x 不兼容：conf.d 按声卡 id 匹配不上、HiFi.conf 的
# If.Controls/${CardId}/cset 分别报 ControlExists/cdev 错误）。已在真机验证：
# 入口按声卡 id chtbswrt5659 建目录，wireplumber 成功创建 HiFi Speaker sink。
mkdir -p "$ROOTFS/usr/share/alsa/ucm2/chtbswrt5659"
cp "$ROOT/config/ucm/chtbswrt5659.conf" "$ROOTFS/usr/share/alsa/ucm2/chtbswrt5659/"
cp "$ROOT/config/ucm/HiFi.conf" "$ROOTFS/usr/share/alsa/ucm2/chtbswrt5659/"
cp "$ROOT/config/ucm/Speaker.conf" "$ROOTFS/usr/share/alsa/ucm2/chtbswrt5659/"
# 若 WiFi 固件未加载，提供常见备选文件名（fix_file/README.md 说明）
[ -f "$ROOTFS/lib/firmware/brcm/$FW_WIFI" ] && \
    cp -n "$ROOTFS/lib/firmware/brcm/$FW_WIFI" "$ROOTFS/lib/firmware/brcm/brcmfmac4356-pcie.txt" || true

# ---------- 缺失固件（linux-firmware 仓库） ----------
# BCM4356(Cypress CYW4356) PCIe 固件在 linux-firmware 的 cypress/ 目录（Cypress
# 命名），而驱动按 brcmfmac4356-pcie*.bin 查找，需复制改名；Intel SST 音频 DSP
# 固件 fw_sst_22a8.bin 同理（intel/）。缺失会导致 dmesg 报 Direct firmware load
# failed（WiFi 无网卡、音频无声）。
FW_GIT="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
mkdir -p "$ROOTFS/lib/firmware/brcm" "$ROOTFS/lib/firmware/intel"
dl_fw() { curl -sfL --max-time 60 "$FW_GIT/$1" -o "$2" || warn "固件下载失败: $1"; }
dl_fw cypress/cyfmac4356-pcie.bin "$ROOTFS/lib/firmware/brcm/brcmfmac4356-pcie.bin"
dl_fw cypress/cyfmac4356-pcie.clm_blob "$ROOTFS/lib/firmware/brcm/brcmfmac4356-pcie.clm_blob"
# 驱动优先按板名查找（DMI 匹配 Xiaomi Inc-Mipad2）
cp -f "$ROOTFS/lib/firmware/brcm/brcmfmac4356-pcie.bin" \
    "$ROOTFS/lib/firmware/brcm/brcmfmac4356-pcie.Xiaomi Inc-Mipad2.bin"
dl_fw intel/fw_sst_22a8.bin "$ROOTFS/lib/firmware/intel/fw_sst_22a8.bin"

# GRUB 内核参数（静态 grub.cfg 的参考配置；update-grub 运行时也会读取）
mkdir -p "$ROOTFS/etc/default"
cat > "$ROOTFS/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR=latte
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="root=UUID=$ROOT_UUID"
GRUB_DISABLE_OS_PROBER=true
EOF

# 重新生成 initramfs（应用 initramfs-tools/modules）
run_chroot "$ROOTFS" update-initramfs -u -k all

# ---------- 引导器（仅安装，ESP 组装在 Stage 3） ----------
# 注意：内核 .deb 必须先于 grub 安装，避免 kernel postinst 触发 update-grub（chroot 中会失败）
info "安装 shim + grub（EFI）"
run_chroot "$ROOTFS" apt-get install -y --no-install-recommends shim-signed grub-efi-amd64-signed

# 静态 grub.cfg 必须在 grub 包安装之后写入：
# Ubuntu 的 grub-efi-amd64-signed / shim-signed postinst 会运行 update-grub，
# 用 grub-mkconfig 覆盖 /boot/grub/grub.cfg；其生成的 linux 条目路径为
# /boot/vmlinuz-*，而 ESP 根没有 /boot 子目录，GRUB 会报 not found。
# 最后写入保证静态配置不被覆盖。Stage3 会把此文件连同内核拷入 ESP。
mkdir -p "$ROOTFS/boot/grub"
cat > "$ROOTFS/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3

menuentry 'Mi Pad 2 - $DISTRO $EDITION $LANG (kernel $KVER)' {
    linux /vmlinuz-$KVER root=UUID=$ROOT_UUID rw quiet
    initrd /initrd.img-$KVER
}
EOF

# ---------- 默认用户 ----------
info "创建默认用户 $DEFAULT_USER"
run_chroot "$ROOTFS" useradd -m -s /bin/bash "$DEFAULT_USER" 2>/dev/null || true
echo "$DEFAULT_USER:$DEFAULT_PASSWORD" | chroot "$ROOTFS" chpasswd
run_chroot "$ROOTFS" usermod -aG sudo "$DEFAULT_USER"

# 启用服务（失败不中断：server 无 NetworkManager/lightdm）
# desktop-gnome 用 gdm3，desktop(XFCE) 用 lightdm；两个都 enable 无妨
run_chroot "$ROOTFS" systemctl enable ssh NetworkManager lightdm gdm3 gdm 2>/dev/null || true

# ---------- GNOME 专属配置 ----------
if [ "$EDITION" = "desktop-gnome" ]; then
    # 触屏输入：GNOME 内置屏幕键盘默认启用（onboard 也已安装）
    mkdir -p "$ROOTFS/etc/dconf/profile" "$ROOTFS/etc/dconf/db/local.d"
    printf 'user-db:user\nsystem-db:local\n' > "$ROOTFS/etc/dconf/profile/user"
    cat > "$ROOTFS/etc/dconf/db/local.d/10-latte-input" <<'EOF'
[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=true
EOF
    run_chroot "$ROOTFS" dconf update 2>/dev/null || true
fi

# ---------- 关键组件冒烟检查 ----------
# 防止 --no-install-recommends 漏掉 Recommends 依赖（wpa_supplicant/wireplumber
# 等均因此缺失过）；组件缺失直接构建失败，而不是刷机后才暴露。
info "关键组件检查"
missing=""
for cmd in ip ping wpa_supplicant nmcli; do
    run_chroot "$ROOTFS" bash -c "command -v $cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
case "$EDITION" in
    desktop|desktop-gnome)
        for cmd in wireplumber pactl amixer bluetoothctl; do
            run_chroot "$ROOTFS" bash -c "command -v $cmd" >/dev/null 2>&1 || missing="$missing $cmd"
        done
        [ "$LANG" = "zh-CN" ] && { \
            run_chroot "$ROOTFS" bash -c "command -v fcitx5" >/dev/null 2>&1 || missing="$missing fcitx5"; }
        ;;
esac
if [ -n "$missing" ]; then
    die "关键组件缺失:${missing}"
fi
info "关键组件齐全"

# ---------- 清理 ----------
info "清理"
run_chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists"/*
rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"
rm -rf "$ROOTFS/var/log/journal"/* 2>/dev/null || true
rm -f "$ROOTFS/usr/sbin/policy-rc.d"

chroot_exit; trap - EXIT
info "Stage 2 完成: $ROOTFS (内核 $KVER)"
