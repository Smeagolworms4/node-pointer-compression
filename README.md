# node-pointer-compression

[![Build](https://github.com/Smeagolworms4/node-pointer-compression/actions/workflows/build.yml/badge.svg)](https://github.com/Smeagolworms4/node-pointer-compression/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/smeagolworms4/node-pointer-compression?label=Docker%20Hub&logo=docker&color=0b7285)](https://hub.docker.com/r/smeagolworms4/node-pointer-compression)
[![Licence](https://img.shields.io/badge/licence-MIT-3d7a3d)](https://github.com/Smeagolworms4/node-pointer-compression/blob/main/LICENSE)

Node.js built with **V8 pointer compression**, on Alpine, for `linux/amd64` and `linux/arm64`.
A drop-in replacement for `node:alpine` that uses less memory.

```
docker run --rm smeagolworms4/node-pointer-compression:24-alpine -p process.config.variables.v8_enable_pointer_compression
1
```

## Why

On a 64-bit machine every reference between JavaScript objects takes 8 bytes. With pointer
compression, V8 keeps the whole heap inside one 4 GB region and stores each reference as a
4-byte offset, so the JavaScript heap shrinks. Chrome ships V8 this way; the official Node.js
binaries do not.

The Node.js project publishes an unofficial pointer-compression binary for glibc on x64 only.
Nothing exists for arm64, nor for Alpine. This repository builds both architectures from the
official sources and publishes them every time Node.js releases.

Measured on [KomgaJS](https://github.com/Smeagolworms4/komga-js), a media server, with the same
workload on the stock binary and on a pointer-compression build:

| | Stock Node.js | Pointer compression |
|---|---|---|
| Resident memory after a library scan, x64 desktop | 247 MB | 220 MB |
| Resident memory in use, arm64 Raspberry Pi, 6,500 books | 222 MB | 185 MB |
| Scan time, API latency, throughput | — | no measurable difference |

Only the JavaScript heap shrinks: native memory (buffers, SQLite, image libraries) is untouched,
so the gain depends on how much of your process is JavaScript objects.

## Images

`smeagolworms4/node-pointer-compression` on Docker Hub, tagged like the official image:

| Tag | Content |
|---|---|
| `24.21.0-alpine`, `24-alpine`, `lts-alpine`, `current-alpine`, `alpine`, `latest` | Node.js, npm, and the headers needed to build native addons |
| `24.21.0-alpine-slim`, `24-alpine-slim`, `lts-alpine-slim`, `current-alpine-slim`, `alpine-slim`, `slim` | the `node` binary only, for final images that install nothing |

- `lts` is the newest LTS line, `current` the newest line; `alpine`, `latest` and `slim` follow `lts`.
- Every tag is a multi-architecture image: `linux/amd64` and `linux/arm64`.
- Lines built: every maintained Node.js line from 24 up, the lines for which Node.js itself publishes a pointer-compression binary.
- Same layout as `node:alpine`: `node` user (uid 1000), `/usr/local` prefix, same entrypoint.
- Full ICU data, as in the official binaries.
- Yarn is not included: `corepack enable` on the lines that still ship Corepack, or `npm install -g yarn`.

Typical use, building with the full image and running on the slim one:

```dockerfile
FROM smeagolworms4/node-pointer-compression:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

FROM smeagolworms4/node-pointer-compression:24-alpine-slim
WORKDIR /app
COPY --from=build /app .
USER node
CMD ["server.js"]
```

## What changes for your code

- **The JavaScript heap is capped at 4 GB** per isolate (main thread, and each worker).
  `--max-old-space-size` above that has no effect. Buffers and other native memory do not count.
- **Native addons.** Addons written against Node-API load as is, prebuilt binaries included
  (`better-sqlite3` is loaded in the tests of every build). An addon that uses the V8 API directly
  must be compiled against this build: the headers are in the full image, under `/usr/local/include/node`.
- **Alpine means musl**, as with `node:alpine`: prebuilt glibc binaries do not load.
- **No 32-bit build**: pointer compression only exists on 64-bit targets.
- Node.js marks the build option experimental (`--experimental-enable-pointer-compression`),
  and these binaries do not go through the Node.js release test suite. Each image is only
  smoke-tested here (see below): run your own tests on it before relying on it.

## How it is built

- [`Dockerfile`](https://github.com/Smeagolworms4/node-pointer-compression/blob/main/Dockerfile):
  the source-build path of the official `node:alpine` Dockerfile, with one more `./configure` flag.
  The source tarball is checked against the signed `SHASUMS256.txt` of the release, with the
  [Node.js release keyring](https://github.com/nodejs/release-keys).
- [`tools/versions.mjs`](https://github.com/Smeagolworms4/node-pointer-compression/blob/main/tools/versions.mjs):
  reads the [Node.js release schedule](https://github.com/nodejs/Release) and the list of releases,
  keeps the latest version of every maintained line, drops the ones already on Docker Hub.
- [`.github/workflows/build.yml`](https://github.com/Smeagolworms4/node-pointer-compression/blob/main/.github/workflows/build.yml):
  runs every day. Each missing version is compiled on a native runner per architecture (no
  emulation), then tested before anything is pushed:
  [`test/smoke.mjs`](https://github.com/Smeagolworms4/node-pointer-compression/blob/main/test/smoke.mjs)
  checks that pointer compression is on, that objects really take 4-byte references, and that
  crypto, zlib, ICU and WebAssembly work; a Node-API addon is installed and loaded. A version gets
  its tags only when both architectures passed.

Build one yourself:

```
docker build --build-arg NODE_VERSION=24.21.0 --target full -t node-pc:24.21.0-alpine .
docker build --build-arg NODE_VERSION=24.21.0 --target slim -t node-pc:24.21.0-alpine-slim .
docker run --rm -v "$PWD/test:/test:ro" node-pc:24.21.0-alpine node /test/smoke.mjs 24.21.0
```

Compiling Node.js takes a while: count in hours on a 4-core machine.
`--build-arg JOBS=4` limits the parallelism, `--build-arg ALPINE_VERSION=3.23` picks another base,
`--build-arg NODE_CONFIGURE_FLAGS="--with-intl=small-icu"` passes more flags to `./configure`.

## Licence

MIT for the files of this repository. Node.js and its dependencies keep their own
[licences](https://github.com/nodejs/node/blob/main/LICENSE). The entrypoint script comes from
[docker-node](https://github.com/nodejs/docker-node) (MIT).
