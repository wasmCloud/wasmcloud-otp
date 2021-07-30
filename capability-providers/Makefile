.PHONY: httpserver keyvalue build help
.DEFAULT_GOAL := help
CARGO ?= cargo --color always

create-build-dir:
	mkdir -p ./_build

httpserver-linux: create-build-dir ## Build the httpserver capability provider for linux
	cd httpserver/go && \
	GOOS=linux go build -o httpserver-linux && \
	mv httpserver-linux ../../_build/httpserver-linux

keyvalue-linux: create-build-dir ## Build the httpserver capability provider for linux
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-unknown-linux-gnu && \
	cp target/x86_64-unknown-linux-gnu/release/wasmcloud-redis ../../_build/wasmcloud-redis-linux

httpserver-mac: create-build-dir ## Build the httpserver capability provider for mac
	cd httpserver/go && \
	GOOS=darwin go build -o httpserver-mac && \
	mv httpserver-mac ../../_build/httpserver-mac

keyvalue-mac: create-build-dir ## Build the keyvalue capability provider for mac
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-apple-darwin && \
	cp target/x86_64-apple-darwin/release/wasmcloud-redis ../../_build/wasmcloud-redis-mac

httpserver-windows: create-build-dir ## Build the httpserver capability provider for windows
	cd httpserver/go && \
	GOOS=windows go build -o httpserver-windows && \
	mv httpserver-windows ../../_build/httpserver-windows.exe

keyvalue-windows: create-build-dir ## Build the keyvalue capability provider for windows 
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-pc-windows-gnu && \
	cp target/x86_64-pc-windows-gnu/release/wasmcloud-redis.exe ../../_build/wasmcloud-redis-windows.exe

build-all: httpserver-linux keyvalue-linux httpserver-mac keyvalue-mac httpserver-windows keyvalue-windows ## Build httpserver and keyvalue for linux, mac, and windows

pars: par-httpserver par-redis ## Build the httpserver and redis provider with linux, mac, and windows binaries
par-httpserver: build-all ## Build the httpserver provider archive with linux, mac, and windows binaries
	wash par create --arch x86_64-macos \
		--binary _build/httpserver-mac \
		--capid wasmcloud:httpserver \
		--name "HTTPServer (Go)" \
		--vendor "wasmCloud" \
		--version 0.13.0 \
		--revision 3 \
		--destination _build/httpserver.par.gz \
		--compress

	wash par insert _build/httpserver.par.gz \
		--arch x86_64-linux \
		--binary _build/httpserver-linux

	wash par insert _build/httpserver.par.gz \
		--arch x86_64-windows \
		--binary _build/httpserver-windows.exe

par-redis: build-all ## Build the redis provider archive with linux, mac, and windows binaries
	wash par create --arch x86_64-macos \
		--binary _build/wasmcloud-redis-mac \
		--capid wasmcloud:keyvalue \
		--name "Redis (Rust)" \
		--vendor "wasmCloud" \
		--version 0.13.0 \
		--revision 3 \
		--destination _build/redis.par.gz \
		--compress

	wash par insert _build/redis.par.gz \
		--arch x86_64-linux \
		--binary _build/wasmcloud-redis-linux

	wash par insert _build/redis.par.gz \
		--arch x86_64-windows \
		--binary _build/wasmcloud-redis-windows.exe

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
