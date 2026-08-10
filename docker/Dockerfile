# latte-linux-build 构建容器
# 用途：macOS / 非 Linux 主机上通过 Docker 构建刷机包（Stage 2-4 需要 Linux + root）
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        debootstrap \
        build-essential \
        bc bison flex libssl-dev libelf-dev \
        ccache dpkg-dev rsync \
        dosfstools mtools e2fsprogs \
        python3 curl ca-certificates \
        kmod sudo file xz-utils git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
