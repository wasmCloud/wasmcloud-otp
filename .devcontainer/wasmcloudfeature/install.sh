#!/bin/bash
set -e

NATS_VERSION=2.9.14
ARCH=$(uname -m)
echo $ARCH
# Rename arch to match NATS scheme
if [[ "$ARCH" == "aarch64" ]]; then
  NATS_ARCH="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
  NATS_ARCH="amd64"
else
  NATS_ARCH=$ARCH
fi
URL=https://github.com/nats-io/nats-server/releases/download/v$NATS_VERSION/nats-server-v$NATS_VERSION-$NATS_ARCH.deb

echo "Performing NATS server install"
echo "Downloading from $URL"

curl -fLO $URL
dpkg -i ./nats-server-v$NATS_VERSION-$NATS_ARCH.deb

# Set up PATH to properly pick up elixir/erlang binaries
echo 'export PATH="/home/vscode/.asdf/installs/elixir/1.14.2/bin:/home/vscode/.asdf/installs/erlang/25.0/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install mix tools for Elixir compilation
mix local.hex --force
mix local.rebar --force
