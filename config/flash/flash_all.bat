@echo off
Title * MI PAD 2 LATTE ONE KEY FLASH
mode con:cols=80 lines=35
setlocal
pushd "%~dp0"

echo 进入 DNX Fastboot 模式：
echo   关机 - 同时按住 Vol+ / Vol- / Power 直至显示 DNX FASTBOOT
echo 然后连接 USB 数据线，按任意键继续...
pause >nul

fastboot boot device_files\fastboot.efi
fastboot getvar product
fastboot getvar product 2>&1 | findstr /r /c:"^product: *latte" || (echo Missmatching image and device & timeout 10 & exit /B 1)

fastboot oem unlock

fastboot flash oemvars device_files\oemvars.txt
fastboot flash oemvars device_files\oemvars-battery-config-fake-disabled.txt
fastboot flash oemvars device_files\oemvars-battery-config-fake.txt

fastboot flash gpt images\gpt.bin
fastboot flash boot images\xiaomi-latte-boot.img
fastboot flash system images\xiaomi-latte-root.img

fastboot reboot

echo.
echo 刷入完成！首次启动注意事项：
echo   1. 若开机进入 BIOS 或黑屏：开机过程中连按 F2，关闭 Secure Boot 后保存重启
echo   2. 默认用户: @USER@ / @PASSWORD@（请尽快修改密码）
echo   3. root 分区会在首次启动自动扩容到整块磁盘
pause
popd
