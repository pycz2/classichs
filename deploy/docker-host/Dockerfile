# syntax=docker/dockerfile:1
# The smallest game server image, made from a release without a build (tools/deploy_server.sh puts
# the released Linux binary next to this file): scratch + the 4 libraries the binary links
# (ld-linux, libc, libm, libgcc_s from Debian 13: it needs glibc 2.38+) + the stripped binary,
# about 26 MB (10 MB compressed). The packs are not in it: classichs-deploy mounts them at /packs.
# No CA certificates: the server here keeps packs in /data/store; S3 over https would need them.
FROM debian:trixie-slim AS tools
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends binutils >/dev/null \
 && mkdir -p /root-fs/lib64 /root-fs/usr/lib/x86_64-linux-gnu \
 && mkdir -m 1777 /root-fs/tmp \
 && cp -Lp /lib64/ld-linux-x86-64.so.2 /root-fs/lib64/ \
 && cd /usr/lib/x86_64-linux-gnu && cp -Lp libc.so.6 libm.so.6 libgcc_s.so.1 /root-fs/usr/lib/x86_64-linux-gnu/
COPY classichs-server /classichs-server
RUN strip /classichs-server

FROM scratch
COPY --from=tools /root-fs/ /
COPY --from=tools /classichs-server /usr/local/bin/classichs-server
USER 65532:65532
WORKDIR /data
EXPOSE 7377
ENTRYPOINT ["/usr/local/bin/classichs-server"]
