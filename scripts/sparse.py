#!/usr/bin/env python3
"""Android sparse image 写入器（img2simg 的纯 Python 等价实现）。

fastboot 客户端/固件按 sparse 格式分块传输大镜像（参考 xiaomi-latte-flash_tools
的刷机日志中 "Sending sparse 'system' N/M"）。流式处理，避免大镜像全量读入内存。

用法: sparse.py <input.img> <output.img.sparse>
"""
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
BLOCK_SIZE = 4096
CHUNK_BLOCKS = 1024          # 每个 RAW chunk 4MiB


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input> <output>")
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]

    total_blocks = 0
    chunks = 0
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        header_pos = fout.tell()
        fout.write(b"\0" * 28)          # header 占位，最后回填
        while True:
            chunk = fin.read(CHUNK_BLOCKS * BLOCK_SIZE)
            if not chunk:
                break
            if len(chunk) % BLOCK_SIZE:
                chunk += b"\0" * (BLOCK_SIZE - len(chunk) % BLOCK_SIZE)
            nblocks = len(chunk) // BLOCK_SIZE
            fout.write(struct.pack("<III", CHUNK_RAW, nblocks, len(chunk)))
            fout.write(chunk)
            total_blocks += nblocks
            chunks += 1
        # sparse_header: magic, major, minor, file_hdr_sz, chunk_hdr_sz,
        #                blk_sz, total_blks, total_chunks, image_checksum
        fout.seek(header_pos)
        fout.write(struct.pack("<IIHHIIIII", SPARSE_MAGIC, 0x1, 0x0, 28, 12,
                               BLOCK_SIZE, total_blocks, chunks, 0))
    print(f"sparse: {dst} ({total_blocks} blocks, {chunks} chunks)")


if __name__ == "__main__":
    main()
