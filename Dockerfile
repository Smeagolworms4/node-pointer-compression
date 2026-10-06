# Node.js built from source with V8 pointer compression, on Alpine (musl).
# Same layout as the official node:alpine image (https://github.com/nodejs/docker-node): node user, /usr/local prefix,
# docker-entrypoint.sh. The only build difference is `--experimental-enable-pointer-compression`.
#
# Targets:
#   full  (default)  node, npm, npx, corepack when Node ships it, and the headers to build native addons
#   slim             the node binary only
ARG ALPINE_VERSION=3.24

FROM alpine:${ALPINE_VERSION} AS build
ARG NODE_VERSION
# Extra ./configure flags, and the make parallelism (default: every core).
ARG NODE_CONFIGURE_FLAGS=""
ARG JOBS=""
RUN apk add --no-cache binutils-gold curl g++ gcc gnupg libgcc linux-headers make python3 py-setuptools xz
WORKDIR /build
# Sources verified against the release signature, with the Node.js release keyring
# (https://github.com/nodejs/release-keys) rather than a key server.
RUN set -eu \
  && test -n "$NODE_VERSION" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.sig" \
  && curl -fsSLo nodejs-keyring.kbx "https://github.com/nodejs/release-keys/raw/HEAD/gpg/pubring.kbx" \
  && gpgv --keyring ./nodejs-keyring.kbx SHASUMS256.txt.sig SHASUMS256.txt \
  && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xf "node-v$NODE_VERSION.tar.xz" --strip-components=1 \
  && rm "node-v$NODE_VERSION.tar.xz"
RUN set -eu \
  && ./configure --experimental-enable-pointer-compression $NODE_CONFIGURE_FLAGS \
  && make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN)}" V= \
  && make install DESTDIR=/out \
  && strip /out/usr/local/bin/node \
  # Unused OpenSSL headers, ~34 MB: https://github.com/nodejs/node/issues/46451
  && case "$(apk --print-arch)" in x86_64) OPENSSL_ARCH=linux-x86_64 ;; aarch64) OPENSSL_ARCH=linux-aarch64 ;; *) OPENSSL_ARCH='linux*' ;; esac \
  && find /out/usr/local/include/node/openssl/archs -mindepth 1 -maxdepth 1 ! -name "$OPENSSL_ARCH" -exec rm -rf {} \; \
  && rm -rf /out/usr/local/share/doc /out/usr/local/share/man \
  && test "$(/out/usr/local/bin/node -p process.config.variables.v8_enable_pointer_compression)" = 1

FROM alpine:${ALPINE_VERSION} AS base
ARG NODE_VERSION
ENV NODE_VERSION=${NODE_VERSION}
RUN addgroup -g 1000 node \
  && adduser -u 1000 -G node -s /bin/sh -D node \
  && apk add --no-cache libstdc++
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node"]

FROM base AS slim
COPY --from=build /out/usr/local/bin/node /usr/local/bin/node
RUN ln -s /usr/local/bin/node /usr/local/bin/nodejs && node --version

FROM base AS full
COPY --from=build /out/usr/local/ /usr/local/
RUN ln -s /usr/local/bin/node /usr/local/bin/nodejs && node --version && npm --version
