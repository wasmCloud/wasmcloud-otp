apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  build-essential \
  # Set proper locale encoding for Elixir (required)
  locale && \
  export LANG=en_US.UTF-8 && \
    echo $LANG UTF-8 > /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=$LANG