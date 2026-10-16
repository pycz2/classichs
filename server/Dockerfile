# syntax=docker/dockerfile:1
# The game server. The rules engine (../rust/engine, ../rust/script) and what it embeds
# (../data/cards.json, ../docs/packs/schema/keywords.json, the Classic pack source ../packs/classic) are outside server/, so
# build from the repository root, after building the packs (tools/build_packs.sh: the
# image bundles packs/*.cardpack, Neonfall the default game, Classic too):
#   tools/build_packs.sh && docker build -f server/Dockerfile -t classichs-server .
# (docker-compose.yml in this directory does that.)

FROM rust:1.99-slim-trixie AS build
WORKDIR /src
COPY data/cards.json data/cards.json
COPY docs/packs/schema/keywords.json docs/packs/schema/keywords.json
COPY packs/classic packs/classic
COPY rust/script rust/script
COPY rust/engine rust/engine
COPY server server
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/server/target \
    cd server && cargo build --release --locked \
    && cp target/release/classichs-server /classichs-server \
    && mkdir -p /out/data

# Debian 13 with glibc, libgcc and CA certificates; no shell; user 65532 (nonroot).
FROM gcr.io/distroless/cc-debian13:nonroot
COPY --from=build /classichs-server /usr/local/bin/classichs-server
COPY --from=build --chown=65532:65532 /out/ /
# Bundled packs, installed once as server packs at start (--default-pack neon: Neonfall is the
# default game). More: mount files into /packs (docker-compose.yml).
COPY packs/*.cardpack /packs/
VOLUME /data
WORKDIR /data
EXPOSE 7377
ENTRYPOINT ["/usr/local/bin/classichs-server"]
CMD ["--listen", "0.0.0.0:7377", "--db", "/data/classichs.db", "--store-dir", "/data/store", "--packs-dir", "/packs"]
