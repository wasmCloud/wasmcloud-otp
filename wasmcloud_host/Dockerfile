# NOTE: This docker image must be build from the root of this repository in order to copy `host_core`.

# The version of Alpine to use for the final image
# This should match the version of Alpine that the `elixir:1.12.2-alpine` image uses
ARG ALPINE_VERSION=3.14

FROM elixir:1.12.2-alpine AS builder

# The following are build arguments used to change variable parts of the image.
# The name of your application/release (required)
ARG APP_NAME=wasmcloud_host
# The version of the application we are building (required)
ARG APP_VSN=0.20.0
# The environment to build with
ARG MIX_ENV=prod
# Set this to true if this release is not a Phoenix app
ARG SKIP_PHOENIX=false
# If you are using an umbrella project, you can change this
# argument to the directory the Phoenix app is in so that the assets
# can be built
ARG PHOENIX_SUBDIR=.
# Secret key is required
ARG SECRET_KEY_BASE

ENV SKIP_PHOENIX=${SKIP_PHOENIX} \
    APP_NAME=${APP_NAME} \
    APP_VSN=${APP_VSN} \
    MIX_ENV=${MIX_ENV} \
    SECRET_KEY_BASE=${SECRET_KEY_BASE}

# By convention, /opt is typically used for applications
WORKDIR /opt/app

# This step installs all the build tools we'll need
RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
    curl \
    bash \
    nodejs \
    yarn \
    git \
    openssl-dev \
    build-base && \
  mix local.rebar --force && \
  mix local.hex --force

# This step installs the Rust toolchain, needed for NIF compilation
ENV RUST_VERSION="1.53.0"
RUN RUST_ARCHIVE="rust-$RUST_VERSION-x86_64-unknown-linux-musl.tar.gz" && \
  RUST_DOWNLOAD_URL="https://static.rust-lang.org/dist/$RUST_ARCHIVE" && \
  mkdir -p /rust \
  && cd /rust \
  && curl -fsOSL $RUST_DOWNLOAD_URL \
  && curl -s $RUST_DOWNLOAD_URL.sha256 | sha256sum -c - \
  && tar -C /rust -xzf $RUST_ARCHIVE --strip-components=1 \
  && rm $RUST_ARCHIVE \
  && ./install.sh

# This copies our app source code into the build container
COPY ./host_core ./host_core
COPY ./wasmcloud_host ./wasmcloud_host
WORKDIR ./wasmcloud_host

ENV RUSTFLAGS="-C target-feature=-crt-static"
RUN mix do deps.get, deps.compile, compile

# This step builds assets for the Phoenix app (if there is one)
# If you aren't building a Phoenix app, pass `--build-arg SKIP_PHOENIX=true`
# This is mostly here for demonstration purposes
RUN if [ ! "$SKIP_PHOENIX" = "true" ]; then \
  cd ${PHOENIX_SUBDIR}/assets && \
  yarn install && \
  yarn deploy && \
  cd - && \
  mix phx.digest; \
fi

RUN \
  mkdir -p /opt/built && \
  mix distillery.release --verbose && \
  cp _build/${MIX_ENV}/rel/${APP_NAME}/releases/${APP_VSN}/${APP_NAME}.tar.gz /opt/built && \
  cd /opt/built && \
  tar -xzf ${APP_NAME}.tar.gz && \
  rm ${APP_NAME}.tar.gz

# From this line onwards, we're in a new image, which will be the image used in production
FROM alpine:${ALPINE_VERSION}

# The name of your application/release (required)
ARG APP_NAME=wasmcloud_host

RUN apk update && \
    apk add --no-cache \
      bash \
      build-base

ENV REPLACE_OS_VARS=true \
    APP_NAME=${APP_NAME}

WORKDIR /opt/app

COPY --from=builder /opt/built .

# NATS connection is required
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST}

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} foreground