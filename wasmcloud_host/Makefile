.PHONY: help deps build esbuild release build-image buildx-cross-image run run-interactive

NAME ?= `grep 'app:' ./wasmcloud_host/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
VERSION ?= `grep '@app_vsn ' ./wasmcloud_host/mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`
DOCKERFILE ?= ./wasmcloud_host/Dockerfile
SKIP_PHOENIX ?= false
TAG ?= latest
SECRET_KEY_BASE ?= $(shell mix phx.gen.secret)

BASE_ARGS ?= --build-arg APP_NAME=$(NAME) --build-arg APP_VSN=$(VERSION) --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) --build-arg SKIP_PHOENIX=$(SKIP_PHOENIX)
BASE_TAGS ?= -t $(NAME):$(VERSION)-$(BUILD) -t $(NAME):$(TAG)

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

deps: ## Fetch mix dependencies
	mix deps.get

build: deps ## Build wasmcloud_host for development
	mix compile

esbuild: deps
	mix sass default assets/css/app.scss priv/static/assets/app.css
	mix assets.deploy
	cp -r assets/static/* priv/static/
	cp -r assets/css/coreui priv/static/assets/coreui

build-image: build esbuild ## Compile wasmcloud_host docker image, requires local elixir toolchain since dart-sass doesn't work in arm64 environments
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.13.3-slim \
		--build-arg RELEASE_IMAGE=debian:bullseye-slim  \
		--build-arg MIX_ENV=prod \
		$(BASE_TAGS) \
		-f $(DOCKERFILE) \
		.

buildx-cross-image: build esbuild ## Compile wasmcloud_host docker image using buildx for amd64 and arm64
	cd ../ && \
	docker buildx build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.13.3-slim \
		--build-arg RELEASE_IMAGE=debian:bullseye-slim \
		--build-arg MIX_ENV=prod \
		-t wasmcloud_host:slim \
		--platform linux/amd64,linux/arm64 \
		--load \
		-f $(DOCKERFILE) \
		.

run: build ## Run development wasmcloud_host
	mix phx.server

run-image: ## Run the docker compose with specified image tag
	WASMCLOUD_HOST_IMAGE=wasmcloud_host:latest \
	docker-compose -f docker-compose.yml \
	up

run-interactive: build ## Run development wasmcloud_host with iex
	iex -S mix phx.server

      # wasmcloud.azurecr.io/${{ matrix.app-name }}:${{ env.app-version }}
      # wasmcloud.azurecr.io/${{ matrix.app-name }}:latest
      # wasmcloud/${{ matrix.app-name }}:${{ env.app-version }}
      # wasmcloud/${{ matrix.app-name }}:latest