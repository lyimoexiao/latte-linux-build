#!/usr/bin/env bash
# latte-linux-build 总编排入口
#   stage-1（内核，一次）-> stage-2（rootfs）-> stage-3（镜像）-> stage-4（打包）
#
# 用法示例:
#   ./scripts/build.sh                                   # 全矩阵 2x2x2
#   ./scripts/build.sh --distro debian --edition server --lang en-US
#   ./scripts/build.sh --kernel-only
#   ./scripts/build.sh --skip-kernel --edition desktop   # 复用已有内核
#   ./scripts/build.sh --stage 3 --distro ubuntu         # 只生成镜像
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

usage() {
    cat <<'EOF'
用法: ./scripts/build.sh [选项]

选项:
  --distro <all|debian|ubuntu>    发行版（默认 all）
  --edition <all|server|desktop>  版本（默认 all）
  --lang <all|en-US|zh-CN>        语言（默认 all）
  --ref <commit|tag|branch>       内核 ref（默认 build.conf KERNEL_REF）
  --kernel-only                   只构建内核并退出
  --skip-kernel                   复用已有内核产物（${KERNEL_OUT}）
  --stage <2|3|4>                 只执行指定阶段（对每个组合）
EOF
}

parse_args "$@"
if [ "${help:-0}" = 1 ]; then usage; exit 0; fi

# ---------- 矩阵解析 ----------
case "${distro:-all}" in
    all|"")    dlist="debian ubuntu" ;;
    debian|ubuntu) dlist="$distro" ;;
    *) die "未知 distro: $distro" ;;
esac
case "${edition:-all}" in
    all|"")    elist="server desktop" ;;
    server|desktop) elist="$edition" ;;
    *) die "未知 edition: $edition" ;;
esac
case "${lang:-all}" in
    all|"")    llist="en-US zh-CN" ;;
    en-US|zh-CN) llist="$lang" ;;
    *) die "未知 lang: $lang" ;;
esac
# Server 版本仅构建 en-US（需求约束）
[ -n "${lang:-}" ] && [ "$lang" != all ] && [ "$lang" != en-US ] && \
    [ "$edition" = server ] && warn "Server 版本仅支持 en-US，忽略 --lang $lang"

# ---------- 内核 ----------
if [ "${kernel_only:-0}" = 1 ]; then
    "$ROOT/scripts/stage-1-kernel.sh" --ref "${ref:-$KERNEL_REF}"
    exit 0
fi
if [ "${skip_kernel:-0}" != 1 ] && [ -z "${stage:-}" ]; then
    "$ROOT/scripts/stage-1-kernel.sh" --ref "${ref:-$KERNEL_REF}"
else
    info "跳过内核构建"
    [ -f "$KERNEL_OUT/kernel-release" ] || die "缺少内核产物（${KERNEL_OUT}），无法跳过 stage-1"
fi

# ---------- 矩阵构建 ----------
for d in $dlist; do
    for e in $elist; do
        lang_list="$llist"
        [ "$e" = server ] && lang_list="en-US"
        for l in $lang_list; do
            info "===== 组合: $d / $e / $l ====="
            case "${stage:-}" in
                ""|2) "$ROOT/scripts/stage-2-rootfs.sh" "$d" "$e" "$l" ;;
            esac
            case "${stage:-}" in
                ""|3) "$ROOT/scripts/stage-3-images.sh" "$d" "$e" "$l" ;;
            esac
            case "${stage:-}" in
                ""|4) "$ROOT/scripts/stage-4-package.sh" "$d" "$e" "$l" ;;
            esac
        done
    done
done

info "全部完成。产物目录: $OUTDIR/"
ls -lh "$OUTDIR/" 2>/dev/null || true
