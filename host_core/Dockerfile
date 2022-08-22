##
# STEP 1: Retrieve dependencies (must happen before NIF compilation)
##
FROM elixir:1.13.3-alpine AS builder

ARG MIX_ENV=release_prod
ENV MIX_ENV=${MIX_ENV} \
    WASMEX_BUILD=true

WORKDIR /opt/app
COPY ./ ./

# Install necessary system dependencies
RUN apk add bash git curl build-base

# COPY ./priv/built/x86_64/libhostcore_wasmcloud_native.so ./priv/built/x86_64/libhostcore_wasmcloud_native.so
COPY ./priv/built/aarch64/libhostcore_wasmcloud_native.so ./priv/built/aarch64/libhostcore_wasmcloud_native.so
# Grab platform-specific NIF
RUN cp ./priv/built/`uname -m`/libhostcore_wasmcloud_native.so ./priv/built/libhostcore_wasmcloud_native.so 
RUN rm -rf priv/built priv/native

# Get Rust for building NIFs (wasmex)
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
# Set PATH to include Rust toolchain, enable static compilation
ENV PATH="/root/.cargo/bin:${PATH}" \
    RUSTFLAGS="-C target-feature=-crt-static"

# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force && \
  mix deps.get && \
  mix distillery.release --verbose && \
  mkdir -p /opt/built && \
  tar -xzf _build/release_prod/rel/host_core/releases/0.56.0/host_core.tar.gz -C /opt/built

# 
# RUN ls -R ./host_core/priv/built
# COPY ./host_core/priv/built/x86_64/libhostcore_wasmcloud_native.so ./host_core/priv/built/x86_64/libhostcore_wasmcloud_native.so
# COPY ./host_core/priv/built/aarch64/libhostcore_wasmcloud_native.so ./host_core/priv/built/aarch64/libhostcore_wasmcloud_native.so
# # Grab platform-specific NIF
# RUN cp ./host_core/priv/built/`uname -m`/libhostcore_wasmcloud_native.so ./host_core/priv/built/libhostcore_wasmcloud_native.so 
# WORKDIR ./wasmcloud_host
# RUN mix do deps.compile, compile

##
# STEP 3: Build optimized final release image
##

# Release image should be the same as the _base container image_ used for the builder.
# E.g. `elixir:1.13.3-alpine`'s base container image is `alpine:3.15.4'
FROM alpine:3.16

WORKDIR /opt/app
# Required for the erlang VM
RUN apk add bash ncurses libgcc libstdc++

COPY --from=builder /opt/built/ .

# NATS connection is required and can be overridden
# Default configuration assumes a NATS container is running named `nats` and available over port 4222
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_PROV_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST} \
    WASMCLOUD_PROV_RPC_HOST=${WASMCLOUD_PROV_RPC_HOST}

CMD ["/opt/app/bin/host_core", "foreground"]