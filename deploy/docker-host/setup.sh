#!/bin/bash
# One-time setup of a Docker host that already runs Caddy (the caddy:2 image, its Caddyfile
# bind-mounted from /etc/Caddyfile) for the game server on its own domain, behind Caddy's HTTPS (443).
#   sudo bash ~/classichs/setup.sh hs.example.com
# Make the domain's DNS A record point to this host first: Caddy asks Let's Encrypt for its
# certificate right after the reload, and failed tries count against Let's Encrypt's limits.
# What it does (each step is skipped when it is done already):
#  - /srv/classichs: the server's data (database, packs), owned by the image's user 65532;
#  - /usr/local/sbin/classichs-deploy (root) and a sudoers rule: the user who runs this script may
#    run that one script as root without a password (tools/deploy_server.sh does), nothing else;
#  - ~/classichs/incoming and ~/classichs/packs: where the images and the packs are uploaded;
#  - the domain's site in /etc/Caddyfile (a backup first; checked by caddy validate, the backup is put
#    back when it fails), then caddy reload: the other sites keep working, no container is restarted.
set -euo pipefail
DOMAIN=${1:-}
[[ $DOMAIN =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] || { echo "usage: sudo bash setup.sh <domain>" >&2; exit 2; }
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run it with sudo" >&2; exit 2; }
U=$SUDO_USER
HERE=$(cd "$(dirname "$0")" && pwd)
CF=/etc/Caddyfile

ip=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}')
[ -n "$ip" ] && hostname -I | tr ' ' '\n' | grep -qx "$ip" \
  || { echo "$DOMAIN resolves to '${ip:-nothing}', not to this host ($(hostname -I)); add the DNS A record first" >&2; exit 1; }
CADDY=$(docker ps -q --filter ancestor=caddy:2 | head -1)
[ -n "$CADDY" ] || { echo "no running caddy:2 container" >&2; exit 1; }

mkdir -p /srv/classichs && chown 65532:65532 /srv/classichs && chmod 750 /srv/classichs
sed "s/__DEPLOY_USER__/$U/" "$HERE/classichs-deploy" > /usr/local/sbin/classichs-deploy.new
chown root:root /usr/local/sbin/classichs-deploy.new && chmod 755 /usr/local/sbin/classichs-deploy.new
mv /usr/local/sbin/classichs-deploy.new /usr/local/sbin/classichs-deploy
echo "$U ALL=(root) NOPASSWD: /usr/local/sbin/classichs-deploy" > /etc/sudoers.d/classichs-deploy.new
chmod 440 /etc/sudoers.d/classichs-deploy.new
visudo -cf /etc/sudoers.d/classichs-deploy.new >/dev/null && mv /etc/sudoers.d/classichs-deploy.new /etc/sudoers.d/classichs-deploy
install -d -o "$U" -g "$U" "/home/$U/classichs/incoming" "/home/$U/classichs/packs"

if grep -q "^$DOMAIN " "$CF"; then
  echo "$CF already has $DOMAIN"
else
  cp -p "$CF" "$CF.before-classichs"
  # >> keeps the file's inode: the container sees the bind-mounted file, not a stale copy
  printf '\n%s {\n  reverse_proxy classichs:7377\n}\n' "$DOMAIN" >> "$CF"
  if ! docker exec "$CADDY" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    cat "$CF.before-classichs" > "$CF"
    echo "caddy validate failed; $CF is as it was" >&2; exit 1
  fi
fi
docker exec "$CADDY" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
echo "done: https://$DOMAIN answers 502 until the first deploy (tools/deploy_server.sh X.Y.Z)"
