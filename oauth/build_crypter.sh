#!/usr/bin/env bash

base=`dirname "${0}"`

pod=podman
if [ "${1}" ]; then
  pod="${1}"
fi

if ! $(command -v "${pod}" > /dev/null); then
  echo "[31mExecutable [m${pod}[31m not found[m" >&2
  echo "Run ${0} <executable> to override" >&2
  exit 1
fi

git clone --depth 1 --branch v0.1.3 https://github.com/m-lima/crypter /tmp/crypter && \
${pod} run -it --rm -v /tmp/crypter:/src -w /src -e RUSTFLAGS="-C target-feature=-crt-static" docker.io/rust:1.73.0-alpine3.18 ash -c 'apk add musl-dev && cargo build --release --features ffi' && \
mv /tmp/crypter/target/release/libcrypter.so "${base}/lib/." && \
rm -rf /tmp/crypter
