#!/usr/bin/env python3
"""Android sparse image 写入器（兼容 img2simg / 旧版 libsparse 约定）。

注意（重要）：旧版 libsparse（Debian/Ubuntu 的 android-sdk-libsparse-utils、
多数 fastboot 客户端）要求 RAW chunk 的 total_sz 包含 12 字节 chunk 头，
即 total_sz = nblocks*blk_sz + 12。若按新约定（纯数据长度）写，libsparse
读取会错位并报 "Invalid sparse file format at data block"，fastboot 会
把镜像当 RAW 处理。生产环境优先使用 img2simg，本脚本作为后备。

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
            # 旧 libsparse 约定：total_sz 包含 12 字节 chunk 头
            fout.write(struct.pack("<III", CHUNK_RAW, nblocks, len(chunk) + 12))
            fout.write(chunk)
            total_blocks += nblocks
            chunks += 1
        # sparse_header（28 字节）: magic(I), major(H), minor(H), file_hdr_sz(H),
        # chunk_hdr_sz(H), blk_sz(I), total_blks(I), total_chunks(I), image_checksum(I)
        fout.seek(header_pos)
        fout.write(struct.pack("<IHHHHIIII", SPARSE_MAGIC, 0x1, 0x0, 28, 12,
                               BLOCK_SIZE, total_blocks, chunks, 0))
    print(f"sparse: {dst} ({total_blocks} blocks, {chunks} chunks)")


if __name__ == "__main__":
    main()
