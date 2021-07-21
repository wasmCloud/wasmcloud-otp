#!/bin/bash -x

apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  ca-certificates \
  curl \
  locales && \
  export LANG=en_US.UTF-8 && \
    echo $LANG UTF-8 > /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=$LANG && \
    rm -rf /var/lib/apt/lists/* # Clean up apt lists to save some space