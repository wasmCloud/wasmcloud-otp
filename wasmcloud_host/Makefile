.PHONY: help

NAME ?= `grep 'app:' ./wasmcloud_host/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
VERSION ?= `grep 'version:' ./wasmcloud_host/mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`
DOCKERFILE ?= ./wasmcloud_host/Dockerfile
SKIP_PHOENIX ?= false
TAG ?= latest

RUST_ARCH ?= x86_64
RUST_TARGET ?= unknown-linux-gnu

BASE_ARGS ?= --build-arg APP_NAME=$(NAME) --build-arg APP_VSN=$(VERSION) --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) --build-arg SKIP_PHOENIX=$(SKIP_PHOENIX)
BASE_TAGS ?= -t $(NAME):$(VERSION)-$(BUILD) -t $(NAME):$(TAG)

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build-image: ## Build docker image for distribution
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
		--build-arg RUST_ARCH=x86_64 \
		--build-arg RUST_TARGET=unknown-linux-gnu \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-linux-gnu \
		-f $(DOCKERFILE) \
		.

tarball-x86_64-linux-gnu: ## Retrieve tarball artifact
	cd ../ && \
	docker run -v $(shell pwd)/rel:/host/rel \
		--env TARGET=x86_64-linux-gnu \
		--env NAME=$(NAME) \
		--env VERSION=$(VERSION) \
		--rm -it $(NAME):$(VERSION)-x86_64-linux-gnu /host/rel/scripts/copy-release.sh

run: ## Run the docker compose with specified image tag
	cd ../ && \
	WASMCLOUD_HOST_IMAGE=wasmcloud.azurecr.io/wasmcloud_host:0.20.0-rc0 \
	docker compose -f ./wasmcloud_host/docker-compose.yml \
	up

deps: ## Fetch mix dependencies
	mix deps.get

wasmcloud-nif: ## Build wasmcloud native NIF
	mkdir -p ../host_core/priv/native && \
	cd ../host_core/native/hostcore_wasmcloud_native && \
	cargo build --release --target $(RUST_ARCH)-$(RUST_TARGET) && \
	cd target/$(RUST_ARCH)-$(RUST_TARGET)/release/ && \
	ls | egrep ".*(dylib|so|dll)$$" | xargs -I % cp % ../../../../../priv/native/libhostcore_wasmcloud_native.so

wasmex-nif: ## Build wasmex native NIF
	mkdir -p deps/wasmex/priv/native && \
	cd deps/wasmex/native/wasmex && \
	cargo build --release --target $(RUST_ARCH)-$(RUST_TARGET) && \
	cd target/$(RUST_ARCH)-$(RUST_TARGET)/release/ && \
	ls | egrep ".*(dylib|so|dll)$$" | xargs -I % cp % ../../../../../priv/native/libwasmex.so

build: deps ## Build wasmcloud_host for development
	mix compile

build-prod: deps wasmcloud-nif wasmex-nif ## Build wasmcloud_host for production
	MIX_ENV=prod mix compile

run-interactive: build ## Run development wasmcloud_host with iex
	iex -S mix phx.server
