#!/bin/bash
# Deploys a released game server to a Docker host behind Caddy (set up once by deploy/docker-host/setup.sh).
#   DEPLOY_HOST=user@host DEPLOY_URL=https://hs.example.com tools/deploy_server.sh 0.28.2
# Makes the image from the release (deploy/docker-host/Dockerfile: the stripped Linux binary on
# scratch, no build; with the admin panel's replay player of ClassicHS-X.Y.Z-replay-viewer.zip),
# uploads it and the release's packs (~/classichs/packs on the host, only the changed ones; mounted
# at /packs), runs classichs-deploy there (it checks the new server, rolls back when it does not
# answer and keeps the 2 newest images), then checks the URL.
# Without a version: copies the scripts of deploy/docker-host to the host (for setup.sh).
# Prints each step with its time (tools/log.sh); the log is kept in build/logs/deploy_server-<time>.log.
# tools/test_deploy_logs.sh runs it against stand-ins of ssh, scp, docker and curl.
set -euo pipefail
: "${DEPLOY_HOST:?set DEPLOY_HOST (the ssh host)}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/log.sh"
V=${1:-}
if [ -z "$V" ]; then
  log_init deploy_server "$ROOT"
  log_step "Copying setup.sh and classichs-deploy to $DEPLOY_HOST:classichs/"
  ssh "$DEPLOY_HOST" mkdir -p classichs
  scp -q "$ROOT/deploy/docker-host/setup.sh" "$ROOT/deploy/docker-host/classichs-deploy" "$DEPLOY_HOST:classichs/"
  log_info "copied; on the host: sudo bash ~/classichs/setup.sh <domain>"; exit 0
fi
: "${DEPLOY_URL:?set DEPLOY_URL (https://the server domain)}"
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/deploy_server.sh X.Y.Z" >&2; exit 2; }
log_init deploy_server "$ROOT"
log_steps 7
API=https://api.github.com/repos/pycz2/classichs/releases/tags/v$V
W=$(mktemp -d); LOG_ON_EXIT='rm -rf "$W"'
mkdir "$W/img" "$W/packs"

log_step "Reading the release v$V"
log_info "$API"
curl -fsSL "$API" | python3 -c '
import sys, json
for a in json.load(sys.stdin)["assets"]:
    n = a["name"]
    if n.endswith((".cardpack", "-replay-viewer.zip")) or n.startswith("ClassicHS-server-") and n.endswith("-linux-x86_64"):
        print(n, a["browser_download_url"], a["size"])' > "$W/assets"
grep -q -- "-linux-x86_64 " "$W/assets" || log_fail "release v$V has no Linux server binary"
log_info "$(wc -l < "$W/assets" | tr -d ' ') files to download: $(log_size "$(awk '{ s += $3 } END { print s }' "$W/assets")")"

log_step "Downloading the release files"
while read -r name url size; do
  case $name in
    *.cardpack) out=$W/packs/${name#ClassicHS-$V-} ;;
    *-replay-viewer.zip) out=$W/replay-viewer.zip ;;
    *) out=$W/img/classichs-server ;;
  esac
  t=$(log_now)
  curl -fsSL -o "$out" "$url"
  log_info "$name: $(log_fsize "$out") in $(log_dur $(($(log_now) - t)))"
done < "$W/assets"

log_step "Making the image classichs-server:$V"
chmod 755 "$W/img/classichs-server"
# the replay player (/admin/replay/); a release before 0.62 has none: the panel says it is missing
mkdir "$W/img/replay-viewer"
if [ -f "$W/replay-viewer.zip" ]; then
  unzip -q "$W/replay-viewer.zip" -d "$W/img/replay-viewer"
  log_info "the replay viewer: $(find "$W/img/replay-viewer" -type f | wc -l | tr -d ' ') files"
else
  log_warn "release v$V has no replay viewer"
fi
shopt -s nullglob
packs=("$W"/packs/*.cardpack)
cp "$ROOT/deploy/docker-host/Dockerfile" "$W/img/"
docker build -q --platform linux/amd64 -t "classichs-server:$V" "$W/img" >/dev/null
docker save "classichs-server:$V" | gzip -1 > "$W/image.tar.gz"
docker rmi "classichs-server:$V" >/dev/null 2>&1 || true  # the local copy is not needed
log_info "image classichs-server:$V: $(log_fsize "$W/image.tar.gz") to upload"

# The packs: upload a file only when its SHA-256 differs; remove the ones the release does not have.
# A release without packs (before 0.28.1) leaves the host's packs as they are.
log_step "Updating the packs on the host"
if [ ${#packs[@]} -eq 0 ]; then
  log_warn "release v$V has no packs: the host keeps its packs"
else
  remote=$(ssh "$DEPLOY_HOST" 'mkdir -p classichs/packs && cd classichs/packs && sha256sum -- *.cardpack 2>/dev/null' || true)
  log_info "the release has ${#packs[@]} packs, the host $(grep -c . <<<"$remote" || true)"
  up=0 same=0 gone=0
  for f in "${packs[@]}"; do
    n=$(basename "$f")
    if grep -qx "$(shasum -a 256 "$f" | cut -d' ' -f1)  $n" <<<"$remote"; then
      log_info "$n: same, skipped"; same=$((same + 1)); continue
    fi
    log_info "$n: uploading $(log_fsize "$f")…"
    t=$(log_now)
    scp -q "$f" "$DEPLOY_HOST:classichs/packs/.$n.part"
    ssh "$DEPLOY_HOST" "mv classichs/packs/.$n.part classichs/packs/$n"
    log_info "$n: uploaded in $(log_dur $(($(log_now) - t)))"; up=$((up + 1))
  done
  for n in $(sed 's/^[0-9a-f]*  //' <<<"$remote"); do
    [ -f "$W/packs/$n" ] || { ssh "$DEPLOY_HOST" "rm -f classichs/packs/$n"; log_info "$n: removed (not in the release)"; gone=$((gone + 1)); }
  done
  log_info "packs: $up uploaded, $same the same, $gone removed"
fi

# .part, then mv: classichs-deploy never sees a half-uploaded file
log_step "Uploading the image ($(log_fsize "$W/image.tar.gz"))"
t=$(log_now)
ssh "$DEPLOY_HOST" < "$W/image.tar.gz" \
  "mkdir -p classichs/incoming && cat > classichs/incoming/.part && mv classichs/incoming/.part classichs/incoming/classichs-server-$V.tar.gz"
log_info "uploaded in $(log_dur $(($(log_now) - t)))"

log_step "Running classichs-deploy $V on the host"
log_info "it starts the new server, checks it and rolls back to the old one if it does not answer"
ssh "$DEPLOY_HOST" sudo -n /usr/local/sbin/classichs-deploy "$V"

log_step "Checking $DEPLOY_URL/admin"
code=$(curl -sS -o /dev/null -w '%{http_code}' "$DEPLOY_URL/admin") || code=000
log_info "$DEPLOY_URL/admin: HTTP $code"
case $code in 2?? | 3??) ;; *) log_fail "$DEPLOY_URL/admin answers HTTP $code" ;; esac
log_info "OK: $DEPLOY_URL (game: ${DEPLOY_URL/https:/wss:})"
