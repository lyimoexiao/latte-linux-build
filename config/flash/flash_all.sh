#!/usr/bin/env bash
# 一键刷机（Linux / macOS）
# 用法: 解压刷机包后执行 ./flash_all.sh（或 ./flash_all.sh 指定 fastboot 路径）
set -euo pipefail

FASTBOOT="${FASTBOOT:-fastboot}"
DIR="$(cd "$(dirname "$0")" && pwd)"

command -v "$FASTBOOT" >/dev/null 2>&1 || {
    echo "缺少 fastboot 命令。" >&2
    echo "  macOS : brew install android-platform-tools" >&2
    echo "  Debian/Ubuntu : sudo apt install fastboot" >&2
    exit 1
}

echo "==> 进入 DNX Fastboot 模式后："
echo "    关机 -> 同时按住 Vol+ / Vol- / Power 直至屏幕显示 DNX FASTBOOT"
echo "    然后连接 USB 数据线，按回车继续"
read -r -p "" </dev/tty || true

echo "==> 引导 fastboot 环境 (fastboot.efi)"
"$FASTBOOT" boot "$DIR/device_files/fastboot.efi"

echo "==> 校验设备型号（应为 latte）"
product="$("$FASTBOOT" getvar product 2>&1 | sed -n 's/^product: *//p' | tail -n1)"
[ "$product" = "latte" ] || {
    echo "设备型号不匹配: '${product:-未知}'，已中止（避免误刷变砖）" >&2
    exit 1
}

"$FASTBOOT" oem unlock

echo "==> 刷入 OEM 变量"
"$FASTBOOT" flash oemvars "$DIR/device_files/oemvars.txt"
"$FASTBOOT" flash oemvars "$DIR/device_files/oemvars-battery-config-fake-disabled.txt"
"$FASTBOOT" flash oemvars "$DIR/device_files/oemvars-battery-config-fake.txt"

echo "==> 刷入分区表 + 系统镜像"
"$FASTBOOT" flash gpt "$DIR/images/gpt.bin"
"$FASTBOOT" flash boot "$DIR/images/xiaomi-latte-boot.img"
"$FASTBOOT" flash system "$DIR/images/xiaomi-latte-root.img"

"$FASTBOOT" reboot

echo
echo "刷入完成！首次启动注意事项："
echo "  1. 若开机进入 BIOS 或黑屏：开机过程中连按 F2，关闭 Secure Boot 后保存重启"
echo "  2. 默认用户: @USER@ / @PASSWORD@（请尽快修改密码）"
echo "  3. root 分区会在首次启动自动扩容到整块磁盘"
