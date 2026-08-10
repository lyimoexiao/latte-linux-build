#!/usr/bin/env bash
# Stage 3: 生成镜像
#   images/xiaomi-latte-boot.img  256MB FAT32 ESP（grub-install + 内核/initrd/grub.cfg）
#   images/xiaomi-latte-root.img  ext4 固定 UUID（raw 副本留在 stage 目录，供本地挂载调试）
#   images/gpt.bin                分区表
#   注意：root.img 刷机版本为 Android sparse 格式（fastboot 分块传输）
#
# 用法: stage-3-images.sh <distro> <edition> <lang>
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

DISTRO="${1:?distro}"; EDITION="${2:?edition}"; LANG="${3:?lang}"
require_root

ROOTFS="$ROOTFS_BASE/$DISTRO-$EDITION-$LANG"
STAGE_DIR="$STAGE/$DISTRO-$EDITION-$LANG"
KVER="$(cat "$KERNEL_OUT/kernel-release")"

info "== Stage 3: 镜像 ($DISTRO/$EDITION/$LANG) =="
[ -d "$ROOTFS" ] || die "rootfs 不存在，请先运行 stage-2"
mkdir -p "$STAGE_DIR/images"

# ---------- boot.img（FAT32 ESP） ----------
BOOT_IMG="$STAGE_DIR/images/xiaomi-latte-boot.img"
ESP_MNT="$STAGE_DIR/esp"
info "生成 boot.img（${BOOT_IMG_SIZE_MB}MB FAT32）"
make_fat_img "$BOOT_IMG" "$BOOT_IMG_SIZE_MB" "BOOT"
mkdir -p "$ESP_MNT"
mount_loop "$BOOT_IMG" "$ESP_MNT"

# 1) 内核 / initrd / 静态 grub.cfg 拷入 ESP（解引用符号链接：FAT32 无符号链接）
cp -Lr "$ROOTFS/boot/." "$ESP_MNT/"
# 2) 绑定 ESP 到 chroot /boot，在目标发行版 chroot 内运行 grub-install
#    （确保使用该发行版签名的 shim/grub，且 grub-probe 能识别 FAT32）
mount --bind "$ESP_MNT" "$ROOTFS/boot"
chroot_enter "$ROOTFS"
trap 'chroot_exit; umount "$ROOTFS/boot" 2>/dev/null || true; umount "$ESP_MNT" 2>/dev/null || true' EXIT
info "grub-install（--removable）"
run_chroot "$ROOTFS" grub-install \
    --target=x86_64-efi --efi-directory=/boot --boot-directory=/boot \
    --removable --no-nvram
chroot_exit
trap - EXIT
umount "$ROOTFS/boot"
# 3) 静态 grub.cfg 多位置放置 + 稳健 stub：
#    Debian/Ubuntu 的 grub-install 嵌入 prefix 可能指向 /boot/grub 或错误分区，
#    仅留 /grub/grub.cfg 会让 GRUB 自动启动时 not found（手动 configfile 却可加载）。
#    在 GRUB 全部候选位置放副本，并用 search --file 按文件内容精确定位 ESP。
mkdir -p "$ESP_MNT/boot/grub"
cp -f "$ESP_MNT/grub/grub.cfg" "$ESP_MNT/boot/grub/grub.cfg"
cp -f "$ESP_MNT/grub/grub.cfg" "$ESP_MNT/grub.cfg"
cat > "$ESP_MNT/EFI/BOOT/grub.cfg" <<'EOF'
search --no-floppy --file --set=root /grub/grub.cfg
set prefix=($root)/grub
configfile $prefix/grub.cfg
EOF
sync
umount "$ESP_MNT"
info "boot.img 完成: $(du -h "$BOOT_IMG" | cut -f1)"

# ---------- root.img（ext4） ----------
RAW_IMG="$STAGE_DIR/xiaomi-latte-root.img"
ROOT_IMG="$STAGE_DIR/images/xiaomi-latte-root.img"   # sparse 刷机版
ROOT_MNT="$STAGE_DIR/root"
info "生成 root.img（${ROOT_IMG_SIZE_MB}MB ext4, UUID=${ROOT_UUID}）"
make_ext4_img "$RAW_IMG" "$ROOT_IMG_SIZE_MB" "$ROOT_LABEL" "$ROOT_UUID"
mkdir -p "$ROOT_MNT"
mount_loop "$RAW_IMG" "$ROOT_MNT"
trap 'umount "$ROOT_MNT" 2>/dev/null || true' EXIT
info "rsync rootfs -> root.img（排除 /boot 内容，其归 ESP 所有）"
rsync -aHAX "$ROOTFS/" "$ROOT_MNT/" --exclude='/boot/*'
sync
umount "$ROOT_MNT"
trap - EXIT

# ---------- gpt.bin ----------
info "生成 gpt.bin"
python3 "$ROOT/scripts/gpt_ini2bin.py" "$ROOT/config/gpt.ini" -o "$STAGE_DIR/images/gpt.bin"

# ---------- root.img 转 sparse ----------
# 优先用 img2simg（AOSP libsparse 官方工具，与 fastboot 客户端/设备端兼容性最好）；
# 无则用内置 python 实现（已对齐旧 libsparse 的 total_sz 约定）
info "root.img -> Android sparse"
if command -v img2simg >/dev/null 2>&1; then
    img2simg "$RAW_IMG" "$ROOT_IMG"
else
    python3 "$ROOT/scripts/sparse.py" "$RAW_IMG" "$ROOT_IMG"
fi

info "Stage 3 完成: $(ls "$STAGE_DIR/images")"
