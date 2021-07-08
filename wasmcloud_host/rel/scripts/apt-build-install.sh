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
  npm install --global yarn
