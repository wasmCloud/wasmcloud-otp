# NOTE: This docker image must be built from the root of this repository in order to copy `host_core`.
# Use the Makefile for best results.

ARG NIF_IMAGE
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
# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

WORKDIR /opt/app/host_core
RUN mix deps.get
WORKDIR /opt/app/wasmcloud_host
RUN mix deps.get

##
# STEP 2: Build NIFs for target architecture
##

# NIFs are built using an image with a proper Rust installation
FROM ${NIF_IMAGE} AS nif-builder
# Install dependencies needed for NIF install
ARG NIF_INSTALL
ARG RUSTFLAGS
ARG RUST_ARCH
ARG RUST_TARGET
ENV RUSTFLAGS="${RUSTFLAGS}" \
  RUST_ARCH="${RUST_ARCH}" \
  RUST_TARGET="${RUST_TARGET}"
COPY ./wasmcloud_host/rel/scripts/${NIF_INSTALL} ./${NIF_INSTALL}
RUN chmod +x ${NIF_INSTALL} && \
  ./${NIF_INSTALL} && \
  rm ${NIF_INSTALL}

# Copy resources from deps-builder image
COPY --from=deps-builder /opt/app /opt/app

# Build wasmcloud native NIF and wasmex native NIF
WORKDIR /opt/app/wasmcloud_host
# Copy cargo config in case of cross-compilation
COPY ./wasmcloud_host/rel/cargo-config.toml ../host_core/native/hostcore_wasmcloud_native/.cargo/config
COPY ./wasmcloud_host/rel/cargo-config.toml deps/wasmex/native/wasmex/.cargo/config
# If RUSTFLAGS are not provided, don't leave as blank environment variable. This can break cross-compilation
RUN if [ -z "$RUSTFLAGS" ]; then unset RUSTFLAGS; fi && \
  make wasmcloud-nif && \
  make wasmex-nif && \
  rm -rf ../host_core/native/hostcore_wasmcloud_native/target \
  ./deps/wasmex/native/wasmex/target

##
# STEP 3: Build distillery release
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
COPY --from=nif-builder /opt/app /opt/app

# Install dependencies for build container. This may be packages like `curl`, `bash`, 
# or even elixir and erlang depending on the base container 
ARG BUILD_INSTALL
RUN ./wasmcloud_host/rel/scripts/${BUILD_INSTALL}
# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

WORKDIR ./wasmcloud_host
RUN mix do deps.compile, compile

# This step builds assets for the Phoenix app
RUN if [ ! "$SKIP_PHOENIX" = "true" ]; then \
  cd ./assets && \
  yarn install && \
  yarn deploy && \
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

# This Docker image is primarily concerned with building the release tarball and is not designed for running the app
# While this will run the application, the container size is not optimized and the `Dockerfile.release` should be used instead
CMD trap 'exit' INT; /opt/built/bin/wasmcloud_host foreground