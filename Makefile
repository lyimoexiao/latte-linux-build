# latte-linux-build 便捷入口
# 注意：Stage 2-4 需要 Linux（root 权限），macOS 请使用 docker-build 目标。

.PHONY: build kernel docker-build docker-run docker-build-all clean check

build:
	./scripts/build.sh

kernel:
	./scripts/build.sh --kernel-only

docker-build:
	docker build -t latte-linux-build docker/

docker-run: docker-build
	docker run --rm -it -v $(CURDIR):/build -w /build latte-linux-build bash

docker-build-all: docker-build
	docker run --rm -v $(CURDIR):/build -w /build latte-linux-build ./scripts/build.sh

clean:
	rm -rf work dist

check:
	bash -n scripts/*.sh
	python3 -m py_compile scripts/*.py
