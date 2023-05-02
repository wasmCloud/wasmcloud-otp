FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt update && \
  apt install -y --no-install-recommends ca-certificates && \
  rm -rf /var/lib/apt/lists/*

ARG BIN
COPY ${BIN} /usr/local/bin/host_core

RUN host_core maintenance install

# NATS connection is required and can be overridden
# Default configuration assumes a NATS container is running named `nats` and available over port 4222
ARG WASMCLOUD_RPC_HOST=nats
ARG WASMCLOUD_PROV_RPC_HOST=nats
ARG WASMCLOUD_CTL_HOST=nats
ENV LANG="C.UTF-8" \
    LC_TYPE="C.UTF-8" \
    WASMCLOUD_RPC_HOST=${WASMCLOUD_RPC_HOST} \
    WASMCLOUD_CTL_HOST=${WASMCLOUD_CTL_HOST} \
    WASMCLOUD_PROV_RPC_HOST=${WASMCLOUD_PROV_RPC_HOST}

CMD ["/usr/local/bin/host_core"]
