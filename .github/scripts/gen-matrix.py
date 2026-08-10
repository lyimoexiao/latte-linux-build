#!/usr/bin/env python3
"""GitHub Actions 矩阵生成器：根据环境变量展开构建矩阵。

读取 DISTRO / EDITION / LANG（all 或具体值），输出:
    matrix=<json>
供 build.yml 的 resolve job 使用。
"""
import json
import os

DISTROS = ["debian", "ubuntu"]
EDITIONS = ["server", "desktop"]
LANGS = ["en-US", "zh-CN"]


def expand(value: str, all_values: list) -> list:
    if not value or value == "all":
        return all_values
    if value not in all_values:
        raise SystemExit(f"未知取值: {value}")
    return [value]


# Server 版本仅支持 en-US；Desktop 支持 en-US / zh-CN
matrix = []
for d in expand(os.environ.get("DISTRO"), DISTROS):
    for e in expand(os.environ.get("EDITION"), EDITIONS):
        langs = ["en-US"] if e == "server" else expand(os.environ.get("LANG"), LANGS)
        for l in langs:
            matrix.append({"distro": d, "edition": e, "lang": l})
print(json.dumps(matrix))
