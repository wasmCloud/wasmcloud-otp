RUST_ARCHIVE="rust-$RUST_VERSION-$RUST_ARCH.tar.gz" && \
  RUST_DOWNLOAD_URL="https://static.rust-lang.org/dist/$RUST_ARCHIVE" && \
  mkdir -p /rust \
  && cd /rust \
  && curl -fsOSL $RUST_DOWNLOAD_URL \
  && curl -s $RUST_DOWNLOAD_URL.sha256 | sha256sum -c - \
  && tar -C /rust -xzf $RUST_ARCHIVE --strip-components=1 \
  && rm $RUST_ARCHIVE \
  && ./install.sh