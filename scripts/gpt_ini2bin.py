#!/usr/bin/env python3
"""gpt.ini -> gpt.bin 转换器。

移植自 xiaomi-latte-dev/xiaomi-latte-flash_tools/gpt_ini2bin.py。
输出 Intel DNX fastboot 可识别的分区表二进制（magic 0x6A8B0DA1）。

用法: gpt_ini2bin.py <gpt.ini> [-o <gpt.bin>]
"""
import argparse
import struct
import uuid
from configparser import ConfigParser

# GPT 分区类型 GUID
TYPE_2_GUID = {
    "fat": "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7",
    "esp": "c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
    "linux": "0fc63daf-8483-4772-8e79-3d69d8477de4",
    "linux-swap": "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f",
    "boot": "49a4d17f-93a3-45c1-a0de-f50b2ebe2599",
    "recovery": "4177c722-9e92-4aab-8644-43502bfd5506",
    "misc": "ef32a33b-a409-486c-9141-9ffb711f6266",
    "metadata": "20ac26be-20b7-11e3-84c5-6cfdb94711e9",
    "tertiary": "767941d0-2085-11e3-ad3b-6cfdb94711e9",
    "factory": "9fdaa6ef-4b3f-40d2-ba8d-bff16bfb887b",
}

MAGIC = 0x6A8B0DA1


def zero_pad(s: bytes, size: int) -> bytes:
    if len(s) > size:
        raise ValueError(f"字段过长: {len(s)} > {size}")
    return s + bytes(size - len(s))


def parse_partitions(gpt_ini: str, cfg: ConfigParser):
    parts = cfg.get("base", "partitions").split()
    with open(gpt_ini) as f:
        for line in f:
            words = line.split()
            if len(words) > 2 and words[0] == "partitions" and words[1] == "+=":
                parts += words[2:]
    return parts


def main():
    ap = argparse.ArgumentParser(description="Convert gpt.ini to gpt.bin (DNX format)")
    ap.add_argument("gpt_ini", nargs="?", default="gpt.ini")
    ap.add_argument("-o", "--output", default="gpt.bin")
    args = ap.parse_args()

    cfg = ConfigParser()
    cfg.read(args.gpt_ini)
    parts = parse_partitions(args.gpt_ini, cfg)

    start_lba = cfg.getint("base", "start_lba", fallback=0)
    out = bytearray()
    out += struct.pack("<III", MAGIC, start_lba, len(parts))

    for p in parts:
        length = cfg.getint("partition." + p, "len")
        label = cfg.get("partition." + p, "label").encode("utf-16le")
        guid_type = uuid.UUID(TYPE_2_GUID[cfg.get("partition." + p, "type")])
        if cfg.has_option("partition." + p, "guid"):
            guid = uuid.UUID(cfg.get("partition." + p, "guid"))
        else:
            guid = uuid.uuid4()
        out += struct.pack("<i", length)
        out += zero_pad(label, 36 * 2)
        out += guid_type.bytes_le
        out += guid.bytes_le

    with open(args.output, "wb") as f:
        f.write(bytes(out))
    print(f"wrote {args.output} ({len(out)} bytes, {len(parts)} partitions)")


if __name__ == "__main__":
    main()
