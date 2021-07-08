.PHONY: help

NAME ?= `grep 'app:' ./wasmcloud_host/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
VERSION ?= `grep 'version:' ./wasmcloud_host/mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`
DOCKERFILE ?= ./wasmcloud_host/Dockerfile
SKIP_PHOENIX ?= true
TAG ?= latest

BASE_ARGS ?= --build-arg APP_NAME=$(NAME) --build-arg APP_VSN=$(VERSION) --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) --build-arg SKIP_PHOENIX=$(SKIP_PHOENIX)
BASE_TAGS ?= -t $(NAME):$(VERSION)-$(BUILD) -t $(NAME):latest

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build-x86_64-linux-musl: ## Build package for arch x86_64, os linux, with statically linked NIFs (musl libc)
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.12.2-alpine \
		--build-arg RELEASE_IMAGE=alpine:3.14 \
		--build-arg BUILD_INSTALL=apk-build-install.sh \
		--build-arg RELEASE_INSTALL=apk-release-install.sh \
		--build-arg RUST_VERSION=1.53.0 \
		--build-arg RUST_ARCH=x86_64-unknown-linux-musl \
		--build-arg RUSTFLAGS="-C target-feature=-crt-static" \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-linux-musl \
		-f $(DOCKERFILE) \
		.

build-x86_64-linux-gnu: ## Build package for ARCH x86_64, OS linux with dynamically linked NIFs (gnu libc)
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.12.2-slim \
		--build-arg RELEASE_IMAGE=debian:buster-slim \
		--build-arg BUILD_INSTALL=apt-build-install.sh \
		--build-arg RELEASE_INSTALL=apt-release-install.sh \
		--build-arg RUST_VERSION=1.53.0 \
		--build-arg RUST_ARCH=x86_64-unknown-linux-gnu \
		$(BASE_TAGS) \
		-t $(NAME):$(VERSION)-x86_64-linux-gnu \
		-f $(DOCKERFILE) \
		.

build-all: build-x86_64-linux-musl build-x86_64-linux-gnu

run: ## Run the docker compose with specified image tag
	cd ../ && \
	WASMCLOUD_HOST_IMAGE=$(NAME):$(TAG) \
	docker compose -f ./wasmcloud_host/docker-compose.yml \
	up