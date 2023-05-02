.PHONY: help deps build esbuild run run-interactive

SKIP_PHOENIX ?= false
SECRET_KEY_BASE ?= $(shell mix phx.gen.secret)
WASMCLOUD_HOST_IMAGE ?= wasmcloud_host:latest

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

deps: ## Fetch mix dependencies
	mix deps.get
	$(MAKE) esbuild

esbuild: ## Build frontend code that relies on esbuild
	mix sass default assets/css/app.scss priv/static/assets/app.css
	mix assets.deploy
	cp -r assets/static/* priv/static/
	cp -r assets/css/coreui priv/static/assets/coreui

build: deps ## Build wasmcloud_host for development
	mix compile

run: build ## Run development wasmcloud_host
	mix phx.server

run-image: ## Run the docker compose with specified image tag
	WASMCLOUD_HOST_IMAGE=$(WASMCLOUD_HOST_IMAGE) \
	docker compose up

run-interactive: build ## Run development wasmcloud_host with iex
	iex -S mix phx.server
