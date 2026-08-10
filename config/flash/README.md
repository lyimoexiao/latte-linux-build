# xiaomi-latte 刷机包

- **发行版**: @DISTRO@ · **版本**: @EDITION@ · **语言**: @LANG@
- **构建日期**: @DATE@
- **内核**: linux_latte (https://github.com/xiaomi-latte-dev/linux_latte)

## 文件说明

```
images/
  gpt.bin                 分区表（boot: 256MB ESP; system: 剩余空间）
  xiaomi-latte-boot.img   boot 分区镜像（FAT32 ESP: shim + grub + vmlinuz + initrd）
  xiaomi-latte-root.img   system 分区镜像（ext4，Android sparse 格式）
device_files/
  fastboot.efi            DNX 模式 fastboot 环境（fastboot boot 引导）
  oemvars*.txt            OEM 变量（相机 / 电池配置）
flash_all.sh / .bat       一键刷机脚本（Linux/macOS / Windows）
```

## 刷机步骤

1. 关闭平板，同时按住 **Vol+ / Vol- / Power**，直到屏幕出现 `DNX FASTBOOT`
2. USB 连接电脑，确认 fastboot 已安装
   - macOS: `brew install android-platform-tools`
   - Debian/Ubuntu: `sudo apt install fastboot`
   - Windows: 安装 Google USB Driver + platform-tools
3. 运行刷机脚本（会先 `fastboot boot fastboot.efi` 进入 fastboot 环境，校验设备为 latte，再刷入）
4. 等待 `system` 分块刷入完成，脚本自动重启
5. **首次启动**：若进入 BIOS 或黑屏，开机时连按 **F2** 关闭 Secure Boot 后保存退出
6. 系统首启自动将 root 分区扩容到整块磁盘，稍等片刻进入系统

## 默认凭据

- 用户: **@USER@** / 密码: **@PASSWORD@**
- 请登录后立即修改：`passwd`

## 故障排查

| 现象 | 处理 |
|---|---|
| `getvar product` 不匹配 | 刷机包与设备不符，禁止继续刷入 |
| 开机黑屏 / 循环 BIOS | 检查 Secure Boot 是否关闭 |
| WiFi 无法启用 | 固件位于 `/lib/firmware/brcm/brcmfmac4356-pcie.*.txt`，必要时重命名为 `brcmfmac4356-pcie.txt` 后重启 |
| 右扬声器无声 | `amixer -c0 cset "name='Amp Input1'" Right` |
| 忘记密码 | 刷机包重刷，或 chroot rootfs 重置 |

> 刷机有风险，操作前请备份数据。参考流程来自
> [xiaomi-latte-flash_tools](https://github.com/xiaomi-latte-dev/xiaomi-latte-flash_tools)。
