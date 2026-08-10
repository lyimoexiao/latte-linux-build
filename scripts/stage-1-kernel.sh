#!/usr/bin/env bash
# Stage 1: 构建 linux_latte 内核
#   产出: $KERNEL_OUT/debs/  (linux-image-*.deb 等)
#         $KERNEL_OUT/kernel-release
#         $KERNEL_OUT/firmware/  (WiFi/蓝牙/ISP 固件 + UCM 音频配置)
#
# 用法: stage-1-kernel.sh [--ref <commit|tag|branch>]
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

parse_args "$@"
KERNEL_REF="${ref:-$KERNEL_REF}"

info "== Stage 1: 内核构建 (ref=$KERNEL_REF) =="

# ---------- 依赖检查 ----------
for c in git make gcc dpkg-buildpackage rsync; do
    command -v "$c" >/dev/null || die "缺少依赖: $c"
done

# ccache 加速（若可用）
if command -v ccache >/dev/null 2>&1; then
    export PATH="/usr/lib/ccache:/usr/lib64/ccache:$PATH"
    info "ccache 已启用"
fi

# ---------- 获取源码 ----------
mkdir -p "$KERNEL_SRC" "$KERNEL_OUT/debs" "$KERNEL_OUT/firmware"
if [ -d "$KERNEL_SRC/.git" ]; then
    info "更新内核源码: $KERNEL_SRC"
    git -C "$KERNEL_SRC" fetch --depth 1 origin 2>/dev/null || git -C "$KERNEL_SRC" fetch --unshallow origin || true
else
    info "克隆内核源码: $KERNEL_REPO"
    git clone --depth 1 "$KERNEL_REPO" "$KERNEL_SRC"
fi
if ! git -C "$KERNEL_SRC" checkout -f "$KERNEL_REF" 2>/dev/null; then
    warn "无法直接 checkout $KERNEL_REF，尝试 FETCH_HEAD"
    git -C "$KERNEL_SRC" checkout -f FETCH_HEAD
fi
info "内核 commit: $(git -C "$KERNEL_SRC" rev-parse --short HEAD)"

# ---------- 构建 ----------
info "配置: make $KERNEL_DEFCONFIG"
make -C "$KERNEL_SRC" "$KERNEL_DEFCONFIG"
info "编译: make -j$(nproc) LOCALVERSION=$KERNEL_LOCALVERSION bindeb-pkg"
make -C "$KERNEL_SRC" -j"$(nproc)" LOCALVERSION="$KERNEL_LOCALVERSION" bindeb-pkg

# ---------- 收集产物 ----------
KVER="$(make -s -C "$KERNEL_SRC" LOCALVERSION="$KERNEL_LOCALVERSION" kernelrelease | tail -n1)"
echo "$KVER" > "$KERNEL_OUT/kernel-release"
info "KERNELRELEASE=$KVER"

# .deb 输出到源码树父目录
SRC_PARENT="$(cd "$KERNEL_SRC/.." && pwd)"
cp -f "$SRC_PARENT"/*.deb "$KERNEL_OUT/debs/" 2>/dev/null || true
rm -f "$SRC_PARENT"/*.deb "$SRC_PARENT"/*.buildinfo "$SRC_PARENT"/*.changes "$SRC_PARENT"/*.dsc "$SRC_PARENT"/*.tar.* 2>/dev/null || true
[ -n "$(ls -A "$KERNEL_OUT/debs")" ] || die "未找到内核 .deb 产物"

# ---------- 设备固件 ----------
FW_SRC="$KERNEL_SRC/fix_file"
[ -d "$FW_SRC" ] || die "内核仓库缺少 fix_file/ 目录"
cp -f "$FW_SRC/$FW_WIFI" "$FW_SRC/$FW_BT" "$FW_SRC/$FW_ISP" "$KERNEL_OUT/firmware/"
[ -d "$FW_SRC/audio" ] && cp -r "$FW_SRC/audio" "$KERNEL_OUT/firmware/"
# 触摸屏底部按键 hwdb（内核仓库文档提供）
FW_SRC_README="$FW_SRC/README.md"
info "固件目录: $(ls "$KERNEL_OUT/firmware")"

info "Stage 1 完成: 内核 $KVER"
