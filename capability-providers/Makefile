.PHONY: httpserver keyvalue build help
.DEFAULT_GOAL := build
CARGO ?= cargo --color always

httpserver:
	cd httpserver/go && \
	GOOS=linux go build -o httpserver-linux && \
	cp httpserver-linux ../../../host_core/priv/providers/httpserver

keyvalue:
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-unknown-linux-gnu && \
	cp target/x86_64-unknown-linux-gnu/release/wasmcloud-redis ../../../host_core/priv/providers/wasmcloud-redis

httpserver-mac:
	cd httpserver/go && \
	GOOS=darwin go build -o httpserver-mac && \
	cp httpserver-mac ../../../host_core/priv/providers/httpserver

keyvalue-mac:
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-apple-darwin && \
	cp target/x86_64-apple-darwin/release/wasmcloud-redis ../../../host_core/priv/providers/wasmcloud-redis

httpserver-windows:
	cd httpserver/go && \
	GOOS=windows go build -o httpserver-windows && \
	cp httpserver-windows ../../../host_core/priv/providers/httpserver

keyvalue-windows:
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-pc-windows-gnu && \
	cp target/x86_64-pc-windows-gnu/release/wasmcloud-redis.exe ../../../host_core/priv/providers/wasmcloud-redis.exe

build-linux: httpserver keyvalue
build-mac: httpserver-mac keyvalue-mac
build-windows: httpserver-windows keyvalue-windows
build-all: build-linux build-mac build-windows

pars: par-http par-redis
par-http: build-all
	wash par create --arch x86_64-macos \
		--binary httpserver/go/httpserver-mac \
		--capid wasmcloud:httpserver \
		--name "HTTPServer (Go)" \
		--vendor "wasmCloud" \
		--version 0.13.0 \
		--revision 3 \
		--destination httpserver.par.gz \
		--compress

	wash par insert httpserver.par.gz \
		--arch x86_64-linux \
		--binary httpserver/go/httpserver-linux

	wash par insert httpserver.par.gz \
		--arch x86_64-windows \
		--binary httpserver/go/httpserver-windows

par-redis: build-all
	wash par create --arch x86_64-macos \
		--binary keyvalue/rust/target/x86_64-apple-darwin/release/wasmcloud-redis \
		--capid wasmcloud:keyvalue \
		--name "Redis (Rust)" \
		--vendor "wasmCloud" \
		--version 0.13.0 \
		--revision 3 \
		--destination redis.par.gz \
		--compress

	wash par insert redis.par.gz \
		--arch x86_64-linux \
		--binary keyvalue/rust/target/x86_64-unknown-linux-gnu/release/wasmcloud-redis

	wash par insert redis.par.gz \
		--arch x86_64-windows \
		--binary keyvalue/rust/target/x86_64-pc-windows-gnu/release/wasmcloud-redis.exe

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
