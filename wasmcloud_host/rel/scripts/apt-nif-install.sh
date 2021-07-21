#!/bin/sh -x

apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  curl \
  git \
  ca-certificates \
  libssl-dev \
  pkg-config \
  build-essential