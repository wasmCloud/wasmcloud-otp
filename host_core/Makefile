.PHONY: build run 

CARGO ?= cargo

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

deps:
	mix deps.get

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

build: deps
	mix compile

build-prod: deps wasmcloud-nif wasmex-nif
	MIX_ENV=prod mix compile

run: build
	mix

run-interactive: build
	iex -S mix