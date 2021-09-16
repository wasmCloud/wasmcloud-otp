.PHONY: build run help deps
.DEFAULT: help

CARGO ?= cargo --color always

UNAME := $(shell uname)
UNAME_ARCH := $(shell uname -p)
ARCH ?= x86_64
TARGET ?= unknown-linux-gnu
ifeq ($(UNAME_ARCH), aarch64)
ARCH = aarch64
endif
ifeq ($(UNAME), Darwin)
TARGET = apple-darwin
endif
ifeq ($(UNAME), Windows_NT)
TARGET = pc-windows-gnu
endif

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


build: deps ## Compile host_core
	mix compile

build-prod: deps wasmcloud-nif wasmex-nif ## Build assets for production
	MIX_ENV=prod mix compile

deps: ## Fetch mix dependencies
	mix deps.get

run: build ## Run host_core
	mix

run-interactive: build ## Run host_core with an iex session
	iex -S mix

test: build ## Run test suite, launch NATS with docker-compose
	docker-compose -f ./test/docker-compose.yml up --detach
	MIX_ENV=test mix test
	docker-compose -f ./test/docker-compose.yml down

wasmcloud-nif: ## Build wasmcloud native NIF
	cd native/hostcore_wasmcloud_native && \
	cargo build --release --target $(ARCH)-$(TARGET) && \
	cd target/$(ARCH)-$(TARGET)/release/ && \
	ls | egrep ".*(dylib|so|dll)$$" | xargs -I % cp % ../../../../../priv/native/libhostcore_wasmcloud_native.so

wasmex-nif: ## Build wasmex native NIF
	mkdir -p deps/wasmex/priv/native && \
	cd deps/wasmex/native/wasmex && \
	cargo build --release --target $(ARCH)-$(TARGET) && \
	cd target/$(ARCH)-$(TARGET)/release/ && \
	ls | egrep ".*(dylib|so|dll)$$" | xargs -I % cp % ../../../../../priv/native/libwasmex.so
