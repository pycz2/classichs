#!/bin/bash
# Deploys a released game server to a Docker host behind Caddy (set up once by deploy/docker-host/setup.sh).
#   DEPLOY_HOST=user@host DEPLOY_URL=https://hs.example.com tools/deploy_server.sh 0.28.2
# Makes the image from the release (deploy/docker-host/Dockerfile: the stripped Linux binary on
# scratch, no build), uploads it and the release's packs (~/classichs/packs on the host, only the
# changed ones; mounted at /packs), runs classichs-deploy there (it checks the new server, rolls
# back when it does not answer and keeps the 2 newest images), then checks the URL.
# Without a version: copies the scripts of deploy/docker-host to the host (for setup.sh).
set -euo pipefail
: "${DEPLOY_HOST:?set DEPLOY_HOST (the ssh host)}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
V=${1:-}
if [ -z "$V" ]; then
  ssh "$DEPLOY_HOST" mkdir -p classichs
  scp -q "$ROOT/deploy/docker-host/setup.sh" "$ROOT/deploy/docker-host/classichs-deploy" "$DEPLOY_HOST:classichs/"
  echo "copied; on the host: sudo bash ~/classichs/setup.sh <domain>"; exit 0
fi
: "${DEPLOY_URL:?set DEPLOY_URL (https://the server domain)}"
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/deploy_server.sh X.Y.Z" >&2; exit 2; }
API=https://api.github.com/repos/pycz2/classichs/releases/tags/v$V
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir "$W/img" "$W/packs"

curl -fsSL "$API" | python3 -c '
import sys, json
for a in json.load(sys.stdin)["assets"]:
    n = a["name"]
    if n.endswith(".cardpack") or n.startswith("ClassicHS-server-") and n.endswith("-linux-x86_64"):
        print(n, a["browser_download_url"])' > "$W/assets"
grep -q -- "-linux-x86_64 " "$W/assets" || { echo "release v$V has no Linux server binary" >&2; exit 1; }
while read -r name url; do
  case $name in
    *.cardpack) out=$W/packs/${name#ClassicHS-$V-} ;;
    *) out=$W/img/classichs-server ;;
  esac
  curl -fsSL -o "$out" "$url"
done < "$W/assets"
chmod 755 "$W/img/classichs-server"
shopt -s nullglob
packs=("$W"/packs/*.cardpack)
cp "$ROOT/deploy/docker-host/Dockerfile" "$W/img/"
docker build -q --platform linux/amd64 -t "classichs-server:$V" "$W/img" >/dev/null
docker save "classichs-server:$V" | gzip -1 > "$W/image.tar.gz"
docker rmi "classichs-server:$V" >/dev/null 2>&1 || true  # the local copy is not needed
echo "image classichs-server:$V: $(ls -l "$W/image.tar.gz" | awk '{printf "%.1f MB", $5/1e6}') to upload"

# The packs: upload a file only when its SHA-256 differs; remove the ones the release does not have.
# A release without packs (before 0.28.1) leaves the host's packs as they are.
if [ ${#packs[@]} -eq 0 ]; then
  echo "release v$V has no packs: the host keeps its packs"
else
  remote=$(ssh "$DEPLOY_HOST" 'mkdir -p classichs/packs && cd classichs/packs && sha256sum -- *.cardpack 2>/dev/null' || true)
  for f in "${packs[@]}"; do
    n=$(basename "$f")
    grep -qx "$(shasum -a 256 "$f" | cut -d' ' -f1)  $n" <<<"$remote" && continue
    scp -q "$f" "$DEPLOY_HOST:classichs/packs/.$n.part"
    ssh "$DEPLOY_HOST" "mv classichs/packs/.$n.part classichs/packs/$n"
    echo "pack $n uploaded"
  done
  for n in $(sed 's/^[0-9a-f]*  //' <<<"$remote"); do
    [ -f "$W/packs/$n" ] || { ssh "$DEPLOY_HOST" "rm -f classichs/packs/$n"; echo "pack $n removed"; }
  done
fi

# .part, then mv: classichs-deploy never sees a half-uploaded file
ssh "$DEPLOY_HOST" < "$W/image.tar.gz" \
  "mkdir -p classichs/incoming && cat > classichs/incoming/.part && mv classichs/incoming/.part classichs/incoming/classichs-server-$V.tar.gz"
ssh "$DEPLOY_HOST" sudo -n /usr/local/sbin/classichs-deploy "$V"
curl -fsS -o /dev/null "$DEPLOY_URL/admin" && echo "OK: $DEPLOY_URL (game: ${DEPLOY_URL/https:/wss:})"
