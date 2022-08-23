.PHONY: build run help deps
.DEFAULT: help

CARGO ?= cargo --color always

EXTRA_TEST_ARGS ?=

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build: deps ## Compile host_core
	mix compile

build-image: ## Compile host_core docker image
	MIX_ENV=prod docker build -t host_core:alpine .

deps: ## Fetch mix dependencies
	mix deps.get

run: build ## Run host_core
	mix

run-interactive: build ## Run host_core with an iex session
	iex -S mix

test: build ## Run test suite, launch NATS with docker-compose
	docker compose -f ./test/docker-compose.yml up --detach
	MIX_ENV=test mix test $(EXTRA_TEST_ARGS)
	docker compose -f ./test/docker-compose.yml down

##
# Release Targets
##

# HOST_CORE_NATIVE_NIF_DIR ?= priv/native
# HOST_CORE_NATIVE_NIF_NAME ?= libhostcore_wasmcloud_native.so
# RELEASE_NIF_PATH ?= priv/built
# RELEASE_FILE ?= host_core

release: deps ## Creates a mix release for host_core
	MIX_ENV=prod mix release
