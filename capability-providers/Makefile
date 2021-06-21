.PHONY: httpserver keyvalue build help
.DEFAULT_GOAL := build
CARGO ?= cargo --color always

httpserver:
	cd httpserver/go && \
	GOOS=linux go build . && \
	mv httpserver ../../../host_core/priv/providers

keyvalue:
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-unknown-linux-gnu && \
	mv target/x86_64-unknown-linux-gnu/release/wasmcloud-redis ../../../host_core/priv/providers

httpserver-mac:
	cd httpserver/go && \
	GOOS=darwin go build . && \
	mv httpserver ../../../host_core/priv/providers

keyvalue-mac:
	cd keyvalue/rust && \
	$(CARGO) build --release --target x86_64-apple-darwin && \
	mv target/x86_64-apple-darwin/release/wasmcloud-redis ../../../host_core/priv/providers

build: httpserver keyvalue
build-mac: httpserver-mac keyvalue-mac

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
