#!/bin/bash -x

apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  curl \
  git \
  ca-certificates \
  libssl-dev \
  pkg-config \
  locales \
  build-essential && \
  # Install node from nodesource (needed for phoenix)
  curl -fsSL https://deb.nodesource.com/setup_14.x | bash - && \
  apt install -y --no-install-recommends nodejs && \
  # Install yarn package manager via npm
  npm install --global yarn && \
  # Set locales for elixir
  export LANG=en_US.UTF-8 && \
    echo $LANG UTF-8 > /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=$LANG
