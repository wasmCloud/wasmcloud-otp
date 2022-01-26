# NOTE: This docker image must be built from the root of this repository in order to copy `host_core`.
# Use the Makefile target `build-image` for best results.

ARG BUILDER_IMAGE
ARG RELEASE_IMAGE

##
# STEP 1: Retrieve dependencies (must happen before NIF compilation)
##
FROM ${BUILDER_IMAGE} AS deps-builder

ARG MIX_ENV=prod
ARG SECRET_KEY_BASE

ENV MIX_ENV=${MIX_ENV} \
  SECRET_KEY_BASE=${SECRET_KEY_BASE}

WORKDIR /opt/app
# This copies our app source code into the build container
COPY ./host_core ./host_core
COPY ./wasmcloud_host ./wasmcloud_host

# Install necessary system dependencies
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  git \
  ca-certificates && \
  update-ca-certificates

# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

WORKDIR /opt/app/host_core
RUN mix deps.get
WORKDIR /opt/app/wasmcloud_host
RUN mix deps.get

##
# STEP 2: Build distillery release
##
FROM ${BUILDER_IMAGE} AS builder
# The name of your application/release (required)
ARG APP_NAME
# The version of the application we are building (required)
ARG APP_VSN
# The environment to build with
ARG MIX_ENV=prod
# Set this to true if this release is not a Phoenix app
ARG SKIP_PHOENIX=false
# Secret key is required
ARG SECRET_KEY_BASE
# Flag to include elixir runtime assets
ARG INCLUDE_ERTS=true

ENV SKIP_PHOENIX=${SKIP_PHOENIX} \
    APP_NAME=${APP_NAME} \
    APP_VSN=${APP_VSN} \
    MIX_ENV=${MIX_ENV} \
    SECRET_KEY_BASE=${SECRET_KEY_BASE} \
    INCLUDE_ERTS=${INCLUDE_ERTS}

# By convention, /opt is typically used for applications
WORKDIR /opt/app

# This copies our app source code into the build container (including compiled NIFs)
COPY --from=deps-builder /opt/app /opt/app

# Install dependencies for build container. This may be packages like `curl`, `bash`,
# or even elixir and erlang depending on the base container
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  curl \
  git \
  ca-certificates \
  libssl-dev \
  pkg-config \
  python2.7 \
  inotify-tools \
  build-essential && \
  # Install node from nodesource (needed for phoenix)
  curl -fsSL https://deb.nodesource.com/setup_14.x | bash - && \
  apt install -y --no-install-recommends nodejs

# Install Rust for NIF compilation
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

WORKDIR ./wasmcloud_host
RUN mix do deps.compile, compile

# This step builds assets for the Phoenix app
RUN if [ ! "$SKIP_PHOENIX" = "true" ]; then \
  cd ./assets && \
  npm install --python=python2.7 && \
  npm run deploy && \
  cd - && \
  mix phx.digest; \
fi

RUN mkdir -p /opt/built && \
  mix distillery.release --verbose && \
  cp _build/${MIX_ENV}/rel/${APP_NAME}/releases/${APP_VSN}/${APP_NAME}.tar.gz /opt/built && \
  cd /opt/built && \
  tar -xzf ${APP_NAME}.tar.gz && \
  mkdir -p /opt/rel && \
  mv ${APP_NAME}.tar.gz /opt/rel

##
# STEP 3: Build optimized final release image
##

# Release image should be the same as the _base container image_ used for the builder.
# E.g. `elixir:1.12.2-alpine`'s base container image is `alpine:3.14'
FROM ${RELEASE_IMAGE}

ARG APP_NAME
ENV REPLACE_OS_VARS=true

WORKDIR /opt/app
COPY --from=builder /opt/built .

# Install release image dependencies (e.g. `bash` is required to run the script and a `libc` installation is required for the NIFs)
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  ca-certificates \
  curl \
  locales \
  libssl-dev && \
  export LANG=en_US.UTF-8 && \
    echo $LANG UTF-8 > /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=$LANG && \
    rm -rf /var/lib/apt/lists/*

# Prevents unnecessary warning messages about language encoding
ENV LC_ALL=en_US.UTF-8

# NATS connection is required and can be overridden
# Default configuration assumes a NATS container is running named `nats` and available over port 4222
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_PROV_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST} \
    WASMCLOUD_PROV_RPC_HOST=${WASMCLOUD_PROV_RPC_HOST}

CMD trap 'exit' INT; /opt/app/bin/wasmcloud_host foreground
