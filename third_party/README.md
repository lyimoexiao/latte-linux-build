# third_party 说明

本目录存放从上游项目 vendor 的二进制与配置，用于刷机包组装。

## device_files/

来自 [xiaomi-latte-dev/xiaomi-latte-flash_tools](https://github.com/xiaomi-latte-dev/xiaomi-latte-flash_tools)
（该仓库未声明 LICENSE，文件原样保留）：

- `fastboot.efi` — DNX 模式下通过 `fastboot boot` 引导的 UEFI fastboot 环境
  （Intel/Android fastboot 项目产物）
- `oemvars.txt` — 相机 / PRAM 等 OEM 变量
- `oemvars-battery-config-fake.txt` / `oemvars-battery-config-fake-disabled.txt`
  — 电池配置（fake battery），刷入顺序以参考脚本为准（最后生效 fake=1）

同步方式：`git -C third_party/flash_tools pull`，再比对拷贝 `device_files/*`。

## flash_tools/

参考仓库浅克隆（`--depth 1`），保留以便同步上游改动（gpt.ini、刷机脚本）。
