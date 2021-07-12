.PHONY: help

NAME ?= `grep 'app:' ./wasmcloud_host/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
VERSION ?= `grep 'version:' ./wasmcloud_host/mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`
DOCKERFILE ?= ./wasmcloud_host/Dockerfile
SKIP_PHOENIX ?= false
TAG ?= latest

BASE_ARGS ?= --build-arg APP_NAME=$(NAME) --build-arg APP_VSN=$(VERSION) --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) --build-arg SKIP_PHOENIX=$(SKIP_PHOENIX)
BASE_TAGS ?= -t $(NAME):$(VERSION)-$(BUILD) -t $(NAME):$(TAG)

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build-image:# build-x86_64-linux-gnu ## Build docker image for distribution
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILD_IMAGE=$(NAME):$(VERSION)-x86_64-linux-gnu \
		--build-arg RELEASE_IMAGE=debian:buster-slim  \
		--build-arg RELEASE_INSTALL=apt-release-install.sh \
		-t $(NAME):$(VERSION) \
		-f $(DOCKERFILE).release \
		.

build-x86_64-linux-gnu: ## Build package for ARCH x86_64, OS linux with dynamically linked NIFs (gnu libc)
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg NIF_IMAGE=rust:1.53-slim-buster \
		--build-arg NIF_INSTALL=apt-nif-install.sh \
		--build-arg BUILDER_IMAGE=elixir:1.12.2-slim \
		--build-arg BUILD_INSTALL=apt-build-install.sh \
		--build-arg RUSTARCH=x86_64 \
		--build-arg RUSTTARGET=unknown-linux-gnu \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-linux-gnu \
		-f $(DOCKERFILE) \
		.

tarball-x86_64-linux-gnu: build-x86_64-linux-gnu
	cd ../ && \
	docker run -v $(shell pwd)/rel:/host/rel \
		--env TARGET=x86_64-linux-gnu \
		--env NAME=$(NAME) \
		--env VERSION=$(VERSION) \
		--rm -it $(NAME):$(VERSION)-x86_64-linux-gnu /host/rel/scripts/copy-release.sh

build-x86_64-linux-musl: ## Build package for arch x86_64, os linux, with statically linked NIFs (musl libc)
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.12.2-alpine \
		--build-arg RELEASE_IMAGE=alpine:3.14 \
		--build-arg BUILD_INSTALL=apk-build-install.sh \
		--build-arg RELEASE_INSTALL=apk-release-install.sh \
		--build-arg RUST_VERSION=1.53.0 \
		--build-arg RUSTARCH=x86_64 \
		--build-arg RUSTTARGET=unknown-linux-musl \
		--build-arg RUSTFLAGS="-C target-feature=-crt-static" \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-linux-musl \
		-f $(DOCKERFILE) \
		.

tarball-x86_64-linux-musl: build-x86_64-linux-musl
	cd ../ && \
	docker run -v $(shell pwd)/rel:/host/rel \
		--env TARGET=x86_64-linux-musl \
		--env NAME=$(NAME) \
		--env VERSION=$(VERSION) \
		--rm -it $(NAME):$(VERSION)-x86_64-linux-musl /host/rel/scripts/copy-release.sh

build-x86_64-apple-darwin: ## Build package for arch x86_64, os MacOS
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg NIF_IMAGE=wasmcloud/cross:x86_64-apple-darwin \
		--build-arg NIF_INSTALL=apt-nif-install.sh \
		--build-arg BUILDER_IMAGE=elixir:1.12.2 \
		--build-arg BUILD_INSTALL=apt-build-install.sh \
		--build-arg INCLUDE_ERTS=false \
		--build-arg RUSTARCH=x86_64 \
		--build-arg RUSTTARGET=apple-darwin \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-apple-darwin \
		-f $(DOCKERFILE) \
		.

tarball-x86_64-apple-darwin: build-x86_64-apple-darwin
	cd ../ && \
	docker run -v $(shell pwd)/rel:/host/rel \
		--env TARGET=x86_64-apple-darwin \
		--env NAME=$(NAME) \
		--env VERSION=$(VERSION) \
		--rm -it $(NAME):$(VERSION)-x86_64-apple-darwin /host/rel/scripts/copy-release.sh

build-all: build-x86_64-linux-musl build-x86_64-linux-gnu build-x86_64-apple-darwin

run: ## Run the docker compose with specified image tag
	cd ../ && \
	WASMCLOUD_HOST_IMAGE=wasmcloud.azurecr.io/wasmcloud_host:0.20.0-rc0 \
	docker compose -f ./wasmcloud_host/docker-compose.yml \
	up

ARCH ?= x86_64
TARGET ?= unknown-linux-gnu

deps:
	mix deps.get

wasmcloud-nif: ## Build wasmcloud native NIF
	mkdir -p ../host_core/priv/native && \
	cd ../host_core/native/hostcore_wasmcloud_native && \
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

run-interactive: build
	iex -S mix phx.server
