# NOTE: This docker image must be build from the root of this repository in order to copy `host_core`.

# Release image should be the same as the _base container_ used for the builder.
ARG BUILDER_IMAGE
ARG RELEASE_IMAGE
FROM ${BUILDER_IMAGE} AS builder

# The following are build arguments used to change variable parts of the image.
# The name of your application/release (required)
ARG APP_NAME
# The version of the application we are building (required)
ARG APP_VSN
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

# This copies our app source code into the build container
COPY ./host_core ./host_core
COPY ./wasmcloud_host ./wasmcloud_host
# Install dependencies for build container. This may be packages like `curl`, `bash`, 
# or even elixir and erlang depending on the base container 
ARG BUILD_INSTALL
RUN ./wasmcloud_host/rel/scripts/${BUILD_INSTALL}
# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

# This step installs the Rust toolchain (if not present), needed for NIF compilation
ARG RUST_VERSION
ARG RUST_ARCH
ENV RUST_VERSION=${RUST_VERSION} \
  RUST_ARCH=${RUST_ARCH}
RUN if ! command -v COMMAND &> /dev/null; then \
    ./wasmcloud_host/rel/scripts/rust-install.sh ; \
  fi

WORKDIR ./wasmcloud_host
ARG RUSTFLAGS
ENV RUSTFLAGS="${RUSTFLAGS}"
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

RUN mkdir -p /opt/built && \
  mix distillery.release --verbose && \
  cp _build/${MIX_ENV}/rel/${APP_NAME}/releases/${APP_VSN}/${APP_NAME}.tar.gz /opt/built && \
  cd /opt/built && \
  tar -xzf ${APP_NAME}.tar.gz
  # TODO: uncomment this, just persisting the app tarGEEzy for now to take a look at file sizes
  # && \
  # rm ${APP_NAME}.tar.gz

# From this line onwards, we're in a new image, which will be the image used in production
FROM ${RELEASE_IMAGE}
# The name of your application/release (required)
ARG APP_NAME

# Run release image dependencies (e.g. `bash` is required to run the script and a `libc` installation is required for the NIFs)
ARG RELEASE_INSTALL
COPY ./wasmcloud_host/rel/scripts/${RELEASE_INSTALL} /tmp/install-deps.sh
ENV LANG=en_US.UTF-8
RUN /tmp/install-deps.sh && rm /tmp/install-deps.sh

ENV REPLACE_OS_VARS=true \
  APP_NAME=${APP_NAME}

WORKDIR /opt/app

COPY --from=builder /opt/built .

# NATS connection is required and can be overridden
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST}

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} foreground