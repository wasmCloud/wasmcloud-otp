#!/bin/bash
TARGET_OS=macos
TARGET_ARCH=aarch64
OTP_VERSION=25

# Checkout OTP
git clone https://github.com/erlang/otp.git
cd otp
git checkout maint-25    # current latest stable version

# Build OTP
./configure
make
make install

# Create release
export RELEASE_ROOT=$(pwd)/release/otp-$OTP_VERSION-$TARGET_OS-$TARGET_ARCH
make release
cd release

tar czf erts-$OTP_VERSION-$TARGET_OS-$TARGET_ARCH.tar.gz otp-$OTP_VERSION-$TARGET_OS-$TARGET_ARCH
