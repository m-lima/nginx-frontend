git clone https://github.com/m-lima/crypter /tmp/crypter && \
docker run -it --rm -v /tmp/crypter:/src -w /src -e RUSTFLAGS="-C target-feature=-crt-static" rust:alpine ash -c 'apk add musl-dev && cargo build --release --features ffi' && \
mv /tmp/crypter/target/release/libcrypter.so lib/. && \
rm -rf /tmp/crypter
