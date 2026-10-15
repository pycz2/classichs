# syntax=docker/dockerfile:1
# The game server. The rules engine (../rust/engine) and its card data (../data/cards.json)
# are outside server/, so build from the repository root:
#   docker build -f server/Dockerfile -t classichs-server .
# (docker-compose.yml in this directory does that.)

FROM rust:1.99-slim-trixie AS build
WORKDIR /src
COPY data/cards.json data/cards.json
COPY rust/engine rust/engine
COPY server server
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/server/target \
    cd server && cargo build --release --locked \
    && cp target/release/classichs-server /classichs-server \
    && mkdir -p /out/data /out/packs

# Debian 13 with glibc, libgcc and CA certificates; no shell; user 65532 (nonroot).
FROM gcr.io/distroless/cc-debian13:nonroot
COPY --from=build /classichs-server /usr/local/bin/classichs-server
COPY --from=build --chown=65532:65532 /out/ /
# Bundled packs (installed once as server packs at start): mount or COPY *.cardpack into /packs.
VOLUME /data
WORKDIR /data
EXPOSE 7377
ENTRYPOINT ["/usr/local/bin/classichs-server"]
CMD ["--listen", "0.0.0.0:7377", "--db", "/data/classichs.db", "--store-dir", "/data/store", "--packs-dir", "/packs"]
