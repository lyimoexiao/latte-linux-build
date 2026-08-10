#!/usr/bin/env bash
# 公共函数库：所有 stage 脚本 source 本文件
set -euo pipefail

# 仓库根目录（脚本位于 <root>/scripts）
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------- 配置加载 ----------
CONF="$ROOT/config/build.conf"
[ -f "$CONF" ] || { echo "缺少配置文件: $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

# 解析 args（--key value / --flag），写入全局 KEY=value / FLAG=1
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --*=*) declare -g "${1#--}" 2>/dev/null || true ;;
            --*)   local k="${1#--}"; shift; declare -g "$k=${1:-1}" ;;
            *)     echo "未知参数: $1" >&2; return 1 ;;
        esac
        shift 2>/dev/null || true
    done
    return 0
}

# ---------- 日志 ----------
info() { printf '\033[1;36m[INFO ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN ]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { error "$*"; exit 1; }

require_root() {
    [ "$(id -u)" = "0" ] || die "该阶段需要 root 权限（debootstrap / 镜像挂载）。建议在 Docker 容器或 GitHub Actions 中运行。"
}

# ---------- 发行版参数 ----------
suite_of()    { case "$1" in debian) echo "$DEBIAN_SUITE";; ubuntu) echo "$UBUNTU_SUITE";; esac; }
mirror_of()   { case "$1" in debian) echo "$DEBIAN_MIRROR";; ubuntu) echo "$UBUNTU_MIRROR";; esac; }
secmirror_of(){ case "$1" in debian) echo "$DEBIAN_SECURITY_MIRROR";; ubuntu) echo "$UBUNTU_SECURITY_MIRROR";; esac; }
components_of(){ case "$1" in debian) echo "$DEBIAN_COMPONENTS";; ubuntu) echo "$UBUNTU_COMPONENTS";; esac; }

timezone_of() { case "${1:-}" in zh-CN) echo "$TIMEZONE_ZH";; *) echo "$TIMEZONE_EN";; esac; }
locale_of()   { case "${1:-}" in zh-CN) echo "zh_CN.UTF-8";; *) echo "en_US.UTF-8";; esac; }

# ---------- 包清单读取 ----------
pkg_list() { # pkg_list <文件>
    local f="$ROOT/config/packages/$1"
    [ -f "$f" ] || { warn "包清单不存在: $f"; return 0; }
    grep -Ev '^\s*(#|$)' "$f" | tr '\n' ' '
}

# 计算某组合需要安装的包集合（去重）
resolve_packages() { # resolve_packages <distro> <edition> <lang>
    local distro="$1" edition="$2" lang="$3"
    ( pkg_list base-common.txt; pkg_list "base-${edition}.txt"
      pkg_list "${distro}-extras.txt"
      [ "$edition" = "desktop" ] && pkg_list "lang-${lang}.txt"
    ) | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

# ---------- chroot ----------
_chroot_mounted=()
chroot_enter() { # chroot_enter <rootfs> — 挂载 /proc /sys /dev 并复制 resolv.conf
    local rootfs="$1"
    mount --bind /dev "$rootfs/dev"
    mount --bind /proc "$rootfs/proc"
    mount --bind /sys "$rootfs/sys"
    cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf"
    _chroot_mounted+=("$rootfs")
}

chroot_exit() { # chroot_exit — 卸载
    local rootfs
    for rootfs in "${_chroot_mounted[@]:-}"; do
        umount "$rootfs/dev" "$rootfs/proc" "$rootfs/sys" 2>/dev/null || true
    done
    _chroot_mounted=()
}

run_chroot() { # run_chroot <rootfs> <cmd...>
    local rootfs="$1"; shift
    chroot "$rootfs" "$@"
}

# ---------- 镜像 ----------
make_fat_img() { # make_fat_img <img> <size_mb> <label>
    local img="$1" size_mb="$2" label="$3"
    truncate -s "${size_mb}M" "$img"
    mkfs.vfat -F 32 -n "$label" "$img" >/dev/null
}

make_ext4_img() { # make_ext4_img <img> <size_mb> <label> <uuid>
    local img="$1" size_mb="$2" label="$3" uuid="$4"
    truncate -s "${size_mb}M" "$img"
    mkfs.ext4 -F -q -m 1 -L "$label" -U "$uuid" "$img"
}

mount_loop() { # mount_loop <img> <mountpoint>
    mount -o loop "$1" "$2"
}

unmount() { # unmount <mountpoint>
    umount "$1"
}

# ---------- 内核版本 ----------
# 从内核源码树 Makefile 解析 KERNELRELEASE（含 LOCALVERSION 后缀由 stage-1 写入 kernel-release 文件）
kernel_version() { # kernel_version <kernelsrc>
    local v p s e
    v=$(awk -F'= *' '/^VERSION/{print $2}' "$1/Makefile" | tr -d ' ')
    p=$(awk -F'= *' '/^PATCHLEVEL/{print $2}' "$1/Makefile" | tr -d ' ')
    s=$(awk -F'= *' '/^SUBLEVEL/{print $2}' "$1/Makefile" | tr -d ' ')
    e=$(awk -F'= *' '/^EXTRAVERSION/{print $2}' "$1/Makefile" | tr -d ' ')
    echo "${v}.${p}.${s}${e}"
}
