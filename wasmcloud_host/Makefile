.PHONY: help deps

NAME ?= `grep 'app:' ./wasmcloud_host/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
VERSION ?= `grep '@app_vsn ' ./wasmcloud_host/mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`
DOCKERFILE ?= ./wasmcloud_host/Dockerfile
SKIP_PHOENIX ?= false
TAG ?= latest
SECRET_KEY_BASE ?= $(shell mix phx.gen.secret)

RUST_ARCH ?= x86_64
RUST_TARGET ?= unknown-linux-gnu

BASE_ARGS ?= --build-arg APP_NAME=$(NAME) --build-arg APP_VSN=$(VERSION) --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) --build-arg SKIP_PHOENIX=$(SKIP_PHOENIX)
BASE_TAGS ?= -t $(NAME):$(VERSION)-$(BUILD) -t $(NAME):$(TAG)

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build-image: build esbuild ## Build docker image for running, testing, or distribution
	cd ../ && \
	docker build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.13.3-slim \
		--build-arg RELEASE_IMAGE=debian:bullseye-slim  \
		$(BASE_TAGS) \
		-f $(DOCKERFILE) \
		.

build-arm-image: build esbuild ## Build arm64 docker image for running, testing, or distribution
	cd ../ && \
	docker buildx build $(BASE_ARGS) \
		--build-arg BUILDER_IMAGE=elixir:1.13.3-slim \
		--build-arg RELEASE_IMAGE=debian:bullseye-slim \
		-t wasmcloud_host:arm64 \
		--platform linux/arm64 \
		--load \
		-f $(DOCKERFILE) \
		.

deps: ## Fetch mix dependencies
	mix deps.get

release-prod: build
	cd ../host_core && make copy-nif
	MIX_ENV=release_prod SECRET_KEY_BASE=$(SECRET_KEY_BASE) mix distillery.release --executable --verbose

esbuild:
	mix sass default assets/css/app.scss priv/static/assets/app.css
	mix assets.deploy
	cp -r assets/static/* priv/static/
	cp -r assets/css/coreui priv/static/assets/coreui

build: deps ## Build wasmcloud_host for development
	mix compile

run: build ## Run development wasmcloud_host
	mix phx.server

run-image: ## Run the docker compose with specified image tag
	WASMCLOUD_HOST_IMAGE=wasmcloud_host:latest \
	docker-compose -f docker-compose.yml \
	up

run-interactive: build ## Run development wasmcloud_host with iex
	iex -S mix phx.server
