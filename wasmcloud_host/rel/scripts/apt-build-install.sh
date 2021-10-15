#!/bin/bash -x

apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  curl \
  git \
  ca-certificates \
  libssl-dev \
  pkg-config \
  build-essential && \
  # Install node from nodesource (needed for phoenix)
  curl -fsSL https://deb.nodesource.com/setup_14.x | bash - && \
  apt install -y --no-install-recommends nodejs
