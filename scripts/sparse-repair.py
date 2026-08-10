#!/usr/bin/env python3
"""修复历史版本 sparse.py 生成的错误 Android sparse 镜像。

背景：旧版 sparse.py 用 32 字节格式写头部（标准 sparse_header 为 28 字节），
且写入流程是先写 28 字节占位、再 seek(0) 覆盖写 32 字节头——后 4 字节把
第 1 个 chunk 头的 type 字段（0xCAC1）覆盖成了 0。因此真实文件布局为：

  [0..31]  旧版 32B 头部（真实字段在 16/20/24 偏移）
  [32..39] chunk1 的 nblocks/total_sz（type 被覆盖，记为 RAW）
  [40..]   chunk1 数据，随后是第 2..N 个标准 chunk（type 完整）

本工具：
  - 已是标准格式（28B 头）→ 原样透传
  - 旧版错误格式 → 从旧头恢复真实字段，重建标准头，重建 chunk1 type 为 RAW，
    其余 chunk 数据原样搬移，并整体校验（chunk 数、数据块数、文件大小）。

用法: sparse-repair.py <input.sparse> <output.sparse>
"""
import os
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4
BLK_SZ = 4096
COPY_BUF = 1 << 20


def copy_exact(src, dst, n):
    """从 src 精确复制 n 字节到 dst（流式）。"""
    left = n
    while left > 0:
        b = src.read(min(COPY_BUF, left))
        if not b:
            raise EOFError(f"输入提前结束: 还差 {left} 字节")
        dst.write(b)
        left -= len(b)


def parse_std_header(f):
    f.seek(0)
    h = f.read(28)
    if len(h) < 28:
        return None
    magic, major, minor, fhs, chs, blk, tblk, tch, csum = struct.unpack("<IHHHHIIII", h)
    return dict(magic=magic, major=major, minor=minor, fhs=fhs, chs=chs,
                blk=blk, total_blks=tblk, total_chunks=tch, csum=csum)


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.sparse> <output.sparse>")
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    size = os.path.getsize(src)

    with open(src, "rb") as fin:
        fin.seek(0)
        magic = struct.unpack("<I", fin.read(4))[0]
        if magic != SPARSE_MAGIC:
            print(f"{src}: 不是 Android sparse 镜像 (magic=0x{magic:08X})")
            sys.exit(1)

        hdr = parse_std_header(fin)
        if hdr and hdr["fhs"] == 28 and hdr["chs"] == 12 and hdr["blk"] == BLK_SZ:
            fin.seek(0)
            with open(dst, "wb") as fout:
                copy_exact(fin, fout, size)
            print(f"{src}: 已是标准 sparse，直接复制到 {dst}")
            return

        # ---------- 旧版错误布局 ----------
        fin.seek(16)
        blk_sz, total_blks, total_chunks = struct.unpack("<III", fin.read(12))
        print(f"旧版头部: blk_sz={blk_sz} total_blks={total_blks} total_chunks={total_chunks}")
        if blk_sz != BLK_SZ:
            print(f"错误: blk_sz={blk_sz}，预期 {BLK_SZ}，无法可靠修复")
            sys.exit(1)

        # chunk1 的 nblocks/total_sz 在 32-39，type 被覆盖（记为 RAW）
        fin.seek(32)
        n1, sz1 = struct.unpack("<II", fin.read(8))
        if n1 * blk_sz != sz1:
            print(f"错误: chunk1 大小不一致 n1={n1} sz1={sz1}")
            sys.exit(1)

        # 预期文件大小预测（用于校验）——见末尾 written_chunks/total_data 校验
        # 逐 chunk 搬移并统计
        written_chunks = 0
        total_data = 0
        fin.seek(40)  # chunk1 数据起点
        with open(dst, "wb") as fout:
            fout.write(struct.pack("<IHHHHIIII", SPARSE_MAGIC, 1, 0, 28, 12,
                                   BLK_SZ, total_blks, total_chunks, 0))

            # chunk1（type=RAW，从 32-39 的 nblocks/total_sz）
            fout.write(struct.pack("<III", CHUNK_RAW, n1, sz1))
            copy_exact(fin, fout, sz1)
            written_chunks += 1
            total_data += sz1

            # 第 2..N 个标准 chunk
            for i in range(1, total_chunks):
                hdr_raw = fin.read(12)
                if len(hdr_raw) < 12:
                    print(f"错误: 读取第 {i+1} 个 chunk 头失败")
                    sys.exit(1)
                ctype, nb, tsz = struct.unpack("<III", hdr_raw)
                fout.write(hdr_raw)
                if ctype == CHUNK_RAW:
                    if tsz != nb * blk_sz:
                        print(f"错误: chunk{i+1} RAW 大小不一致")
                        sys.exit(1)
                    copy_exact(fin, fout, tsz)
                    total_data += tsz
                elif ctype in (CHUNK_DONT_CARE, CHUNK_FILL, CHUNK_CRC32):
                    pass
                else:
                    print(f"错误: chunk{i+1} 未知类型 0x{ctype:04X}")
                    sys.exit(1)
                written_chunks += 1

    # 校验
    if written_chunks != total_chunks:
        print(f"错误: chunk 数不一致 期望{total_chunks} 实际{written_chunks}")
        sys.exit(1)
    if total_data != total_blks * blk_sz:
        print(f"错误: 数据块数不一致 期望{total_blks*blk_sz} 实际{total_data}")
        sys.exit(1)
    print(f"修复完成: {dst} ({total_blks} blocks, {written_chunks} chunks, {total_data} bytes)")


if __name__ == "__main__":
    main()
