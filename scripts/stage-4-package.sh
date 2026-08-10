#!/usr/bin/env bash
# Stage 4: 组装刷机包 tarball
#   输出: $OUTDIR/xiaomi-latte-<distro>-<edition>-<lang>-<yyyymmdd>.tar.gz
#
# 用法: stage-4-package.sh <distro> <edition> <lang>
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

DISTRO="${1:?distro}"; EDITION="${2:?edition}"; LANG="${3:?lang}"

STAGE_DIR="$STAGE/$DISTRO-$EDITION-$LANG"
DATE="$(date +%Y%m%d)"
PKG_NAME="xiaomi-latte-$DISTRO-$EDITION-$LANG-$DATE"
PKG_DIR="$OUTDIR/$PKG_NAME"

info "== Stage 4: 打包 $PKG_NAME =="
for f in gpt.bin xiaomi-latte-boot.img xiaomi-latte-root.img; do
    [ -f "$STAGE_DIR/images/$f" ] || die "缺少镜像 ${f}，请先运行 stage-3"
done

rm -rf "$PKG_DIR"; mkdir -p "$PKG_DIR/images" "$PKG_DIR/device_files"
cp "$STAGE_DIR/images/"gpt.bin "$STAGE_DIR/images/"xiaomi-latte-boot.img "$STAGE_DIR/images/"xiaomi-latte-root.img "$PKG_DIR/images/"
cp "$ROOT/third_party/device_files/"* "$PKG_DIR/device_files/"
# 模板替换（flash 脚本 + README 均含 @USER@/@PASSWORD@ 等占位符）
for t in flash_all.sh flash_all.bat README.md; do
    sed -e "s/@DISTRO@/$DISTRO/g" -e "s/@EDITION@/$EDITION/g" -e "s/@LANG@/$LANG/g" \
        -e "s/@DATE@/$DATE/g" -e "s/@USER@/$DEFAULT_USER/g" -e "s/@PASSWORD@/$DEFAULT_PASSWORD/g" \
        "$ROOT/config/flash/$t" > "$PKG_DIR/$t"
done
chmod +x "$PKG_DIR/flash_all.sh"

tar -C "$OUTDIR" -czf "$PKG_DIR.tar.gz" "$PKG_NAME"
info "刷机包: $OUTDIR/$PKG_NAME.tar.gz ($(du -h "$PKG_DIR.tar.gz" | cut -f1))"
