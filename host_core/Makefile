.PHONY: build run help deps
.DEFAULT: help

CARGO ?= cargo --color always

UNAME := $(shell uname)
UNAME_ARCH := $(shell uname -p)
ARCH ?= x86_64
TARGET ?= unknown-linux-gnu
ifeq ($(UNAME_ARCH), aarch64)
ARCH = aarch64
else ifeq ($(UNAME_ARCH), arm)
ARCH = aarch64
endif
ifeq ($(UNAME), Darwin)
TARGET = apple-darwin
endif
ifeq ($(UNAME), Windows_NT)
TARGET = pc-windows-gnu
endif

EXTRA_TEST_ARGS ?=

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_\-.*]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


build: deps ## Compile host_core
	mix compile

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

HOST_CORE_NATIVE_NIF_DIR ?= priv/native
HOST_CORE_NATIVE_NIF_NAME ?= libhostcore_wasmcloud_native.so
RELEASE_NIF_PATH ?= priv/built
MIX_ENV = release_prod
RELEASE_FILE ?= host_core

# Copies native NIF from directory into the path the release expects
copy-nif:
	@mkdir -p $(RELEASE_NIF_PATH)
	@cp $(HOST_CORE_NATIVE_NIF_DIR)/$(HOST_CORE_NATIVE_NIF_NAME) $(RELEASE_NIF_PATH)/$(HOST_CORE_NATIVE_NIF_NAME)

distillery-release-prod: 
	@export MIX_ENV=$(MIX_ENV) && \
		mix deps.get && \
		mix compile && \
		mix distillery.release --executable --verbose

## The following targets assemble a distillery release following a strict order
# 1. Copy the Wasmcloud Native NIF from a supplied location so it can be built separately
# 2. Assemble the distillery release without building a NIF
# 3. Assemble the application tarball with all of the above components
#
# This is intended to be used to easily assemble a distillery release with a provided
# NIF, reducing release times.
release-prod: copy-nif distillery-release-prod ## Assemble distillery release with copied native NIF

cleanup-release: ## Remove distillery release specific artifacts
	mix clean
	rm -r priv/built _build/release_prod
