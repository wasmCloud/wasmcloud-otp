##
# STEP 1: Retrieve dependencies (must happen before NIF compilation)
##
ARG BUILDER_IMAGE
ARG RELEASE_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV} \
    WASMEX_BUILD=true

WORKDIR /opt/app
COPY ./ ./

# Install necessary system dependencies
RUN apk add bash git curl build-base

# Grab platform-specific NIF if building with release_prod, otherwise build NIF manually
RUN if [ "$MIX_ENV" = "release_prod" ] ; then cp ./priv/built/`uname -m`/libhostcore_wasmcloud_native.so ./priv/built/libhostcore_wasmcloud_native.so ; else echo "not grabbing" ; fi
# Ensure intermediate artifacts don't get bundled into the final release
RUN rm -rf priv/built/aarch64 priv/built/x86_64 priv/native

# Get Rust for building NIFs (wasmex)
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
# Set PATH to include Rust toolchain, enable static compilation
ENV PATH="/root/.cargo/bin:${PATH}" \
    RUSTFLAGS="-C target-feature=-crt-static" \
    CARGO_HTTP_DEBUG="true" \
    CARGO_LOG="cargo::ops::registry=debug"

# Remove any cargo registry things
RUN rm -rf ~/.cargo/registry/*

# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force && \
  mix deps.get && \
  mix release

RUN mkdir -p /opt/built && \
    mv _build/${MIX_ENV}/rel/host_core/* /opt/built

##
# STEP 2: Build optimized final release image
##

# Release image should be the same as the _base container image_ used for the builder.
# E.g. `elixir:1.13.3-alpine`'s base container image is `alpine:3.15.4'
FROM ${RELEASE_IMAGE}

WORKDIR /opt/app
# Required for the erlang VM
RUN apk add bash ncurses libgcc libstdc++

COPY --from=builder /opt/built .

# NATS connection is required and can be overridden
# Default configuration assumes a NATS container is running named `nats` and available over port 4222
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_PROV_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST} \
    WASMCLOUD_PROV_RPC_HOST=${WASMCLOUD_PROV_RPC_HOST}

CMD ["/opt/app/bin/host_core", "start"]