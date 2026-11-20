#!/bin/bash
# Deploys a released game server to a Docker host behind Caddy (set up once by deploy/docker-host/setup.sh).
#   DEPLOY_HOST=user@host DEPLOY_URL=https://hs.example.com tools/deploy_server.sh 0.28.2
# A release from 0.72.2 on carries the server's image (ClassicHS-X.Y.Z-server-image.tar.gz, made by the Release
# workflow): the host downloads it and the release's changed packs straight from GitHub (~/classichs/packs on the
# host, a pack only when its SHA-256 differs from the asset's digest; mounted at /packs), nothing goes through this
# machine and no Docker is needed here. An older release: this machine downloads its files, makes the image
# (deploy/docker-host/Dockerfile: the stripped Linux binary on scratch, no build; with the admin panel's replay
# player of ClassicHS-X.Y.Z-replay-viewer.zip) and uploads it and the changed packs. Then classichs-deploy runs on
# the host (it checks the new server, rolls back when it does not answer and keeps the 2 newest images), and the
# URL is checked.
# Without a release: tools/deploy_server.sh --from-ci [<commit>] (default: the head of main) waits for the
# Release workflow's run of that commit on main and deploys its build (the artifacts server-linux-x86_64 and
# replay-viewer) as the version X.Y.Z-<short commit> (X.Y.Z: the project's version). No packs: they come only
# with releases, the host keeps its own. Needs gh (logged in) and a classichs-deploy on the host that takes
# X.Y.Z-<commit> (if it is older: this script without a version, then sudo bash ~/classichs/setup.sh <domain>).
# Without a version: copies the scripts of deploy/docker-host to the host (for setup.sh).
# Prints each step with its time (tools/log.sh); the log is kept in build/logs/deploy_server-<time>.log.
# tools/test_deploy_logs.sh runs it against stand-ins of ssh, scp, docker, curl and gh.
set -euo pipefail
: "${DEPLOY_HOST:?set DEPLOY_HOST (the ssh host)}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/log.sh"
V=${1:-} SHA=
[ "$V" != --from-ci ] || SHA=${2:-main}
if [ -z "$V" ]; then
  log_init deploy_server "$ROOT"
  log_step "Copying setup.sh and classichs-deploy to $DEPLOY_HOST:classichs/"
  ssh "$DEPLOY_HOST" mkdir -p classichs
  scp -q "$ROOT/deploy/docker-host/setup.sh" "$ROOT/deploy/docker-host/classichs-deploy" "$DEPLOY_HOST:classichs/"
  log_info "copied; on the host: sudo bash ~/classichs/setup.sh <domain>"; exit 0
fi
: "${DEPLOY_URL:?set DEPLOY_URL (https://the server domain)}"
[ -n "$SHA" ] || [[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/deploy_server.sh X.Y.Z | --from-ci [<commit>]" >&2; exit 2; }
log_init deploy_server "$ROOT"
API=https://api.github.com/repos/pycz2/classichs/releases/tags/v$V
W=$(mktemp -d); LOG_ON_EXIT='rm -rf "$W"'
mkdir "$W/img" "$W/packs"
FROM="release v$V"
DIRECT=
if [ -z "$SHA" ]; then
  # the release's files: name, URL, size, SHA-256 (GitHub's digest; empty for an old asset)
  curl -fsSL "$API" | python3 -c '
import sys, json
for a in json.load(sys.stdin)["assets"]:
    n = a["name"]
    if n.endswith((".cardpack", "-replay-viewer.zip", "-server-image.tar.gz")) or n.startswith("ClassicHS-server-") and n.endswith("-linux-x86_64"):
        print(n, a["browser_download_url"], a["size"], (a.get("digest") or "").removeprefix("sha256:") or "-")' > "$W/assets" \
    || log_fail "cannot read the release v$V: $API"
  grep -q -- "-server-image.tar.gz " "$W/assets" && DIRECT=1
fi
if [ -n "$DIRECT" ]; then log_steps 5; else log_steps 7; fi

# A commit on main: the build of its Release workflow run.
from_ci() {
  export GH_REPO=pycz2/classichs
  full=$(gh api "repos/$GH_REPO/commits/$SHA" --jq .sha) || log_fail "GitHub has no commit $SHA (not pushed?)"
  short=${full:0:7}
  log_step "Waiting for the CI build of $short on main"
  ssh "$DEPLOY_HOST" "grep -qF 'X.Y.Z-<commit>' /usr/local/sbin/classichs-deploy" \
    || log_fail "the host's classichs-deploy takes only X.Y.Z: run tools/deploy_server.sh with no version, then on the host sudo bash ~/classichs/setup.sh <domain>"
  run=
  for i in $(seq 20); do  # a commit pushed a moment ago gets its run within seconds
    run=$(gh run list -w Release -b main -c "$full" -L 1 --json databaseId --jq '.[0].databaseId // empty')
    [ -z "$run" ] || break
    [ "$i" != 1 ] || log_info "no Release run of $short on main yet, waiting up to 5 minutes…"
    sleep 15
  done
  [ -n "$run" ] || log_fail "no Release run of $short on main (is the commit on main?)"
  log_watch_run "$run"
  [ "$LOG_RUN_CONCLUSION" = success ] || log_fail "the CI run $run of $short ended: $LOG_RUN_CONCLUSION"
  FROM="CI run $run"

  log_step "Downloading the server and the replay viewer of $FROM"
  gh run download "$run" -n server-linux-x86_64 -D "$W/ci"
  bin=$(ls "$W"/ci/ClassicHS-server-*-linux-x86_64)
  V=${bin##*/ClassicHS-server-} && V=${V%-linux-x86_64}-$short
  mv "$bin" "$W/img/classichs-server"
  log_info "the server: $(log_fsize "$W/img/classichs-server"), the version label $V"
  # runs before the replay-viewer artifact was added have none: the image goes without it
  if gh run download "$run" -n replay-viewer -D "$W/rv"; then mv "$W"/rv/*-replay-viewer.zip "$W/replay-viewer.zip"; fi
}

# A release: the Linux server, the replay viewer and the packs of its assets.
from_release() {
  log_step "Reading the release v$V"
  log_info "$API"
  grep -q -- "-linux-x86_64 " "$W/assets" || log_fail "release v$V has no Linux server binary"
  log_info "$(wc -l < "$W/assets" | tr -d ' ') files to download: $(log_size "$(awk '{ s += $3 } END { print s }' "$W/assets")")"

  log_step "Downloading the release files"
  while read -r name url size _; do
    case $name in
      *.cardpack) out=$W/packs/${name#ClassicHS-$V-} ;;
      *-replay-viewer.zip) out=$W/replay-viewer.zip ;;
      *-server-image.tar.gz) continue ;;
      *) out=$W/img/classichs-server ;;
    esac
    t=$(log_now)
    curl -fsSL -o "$out" "$url"
    log_info "$name: $(log_fsize "$out") in $(log_dur $(($(log_now) - t)))"
  done < "$W/assets"
}

# A release with its image: the host downloads what it needs from GitHub (its link is fast; this machine's upload
# is slow), then classichs-deploy runs as below.
direct() {
  local name url size sum n remote up=0 same=0 gone=0 t
  log_step "Reading the release v$V"
  log_info "$API"
  log_info "$(wc -l < "$W/assets" | tr -d ' ') files; the host downloads the changed ones from GitHub"
  log_step "The host downloads the changed packs from GitHub"
  remote=$(ssh "$DEPLOY_HOST" 'mkdir -p classichs/packs && cd classichs/packs && sha256sum -- *.cardpack 2>/dev/null' || true)
  log_info "the release has $(grep -c '\.cardpack ' "$W/assets") packs, the host $(grep -c . <<<"$remote" || true)"
  while read -r name url size sum; do
    case $name in *.cardpack) ;; *) continue ;; esac
    n=${name#ClassicHS-$V-}
    if [ "$sum" != - ] && grep -qx "$sum  $n" <<<"$remote"; then
      log_info "$n: same, skipped"; same=$((same + 1)); continue
    fi
    t=$(log_now)
    ssh "$DEPLOY_HOST" "curl -fsSL -o classichs/packs/.$n.part '$url' && mv classichs/packs/.$n.part classichs/packs/$n" </dev/null
    log_info "$n: $(log_size "$size") downloaded on the host in $(log_dur $(($(log_now) - t)))"; up=$((up + 1))
  done < "$W/assets"
  for n in $(sed 's/^[0-9a-f]*  //' <<<"$remote"); do
    grep -q "^ClassicHS-$V-$n " "$W/assets" || { ssh "$DEPLOY_HOST" "rm -f classichs/packs/$n" </dev/null; log_info "$n: removed (not in the release)"; gone=$((gone + 1)); }
  done
  log_info "packs: $up downloaded, $same the same, $gone removed"
  read -r name url size sum < <(grep -- "-server-image.tar.gz " "$W/assets")
  log_step "The host downloads the image ($(log_size "$size"))"
  t=$(log_now)
  ssh "$DEPLOY_HOST" "mkdir -p classichs/incoming && curl -fsSL -o classichs/incoming/.part '$url' && mv classichs/incoming/.part classichs/incoming/classichs-server-$V.tar.gz" </dev/null
  log_info "downloaded on the host in $(log_dur $(($(log_now) - t)))"
}

if [ -n "$DIRECT" ]; then
  direct
else
  if [ -n "$SHA" ]; then from_ci; else from_release; fi

log_step "Making the image classichs-server:$V"
docker info >/dev/null 2>&1 || log_fail "Docker is not running (this build has no ready image): start Docker Desktop and run again"
chmod 755 "$W/img/classichs-server"
# the replay player (/admin/replay/); a release before 0.62 has none: the panel says it is missing
mkdir "$W/img/replay-viewer"
if [ -f "$W/replay-viewer.zip" ]; then
  unzip -q "$W/replay-viewer.zip" -d "$W/img/replay-viewer"
  log_info "the replay viewer: $(find "$W/img/replay-viewer" -type f | wc -l | tr -d ' ') files"
else
  log_warn "$FROM has no replay viewer"
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
if [ -n "$SHA" ]; then
  log_info "a build from main brings no packs (they come only with releases): the host keeps its packs"
elif [ ${#packs[@]} -eq 0 ]; then
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
fi

log_step "Running classichs-deploy $V on the host"
log_info "it starts the new server, checks it and rolls back to the old one if it does not answer"
ssh "$DEPLOY_HOST" sudo -n /usr/local/sbin/classichs-deploy "$V"

log_step "Checking $DEPLOY_URL/admin"
code=$(curl -sS -o /dev/null -w '%{http_code}' "$DEPLOY_URL/admin") || code=000
log_info "$DEPLOY_URL/admin: HTTP $code"
case $code in 2?? | 3??) ;; *) log_fail "$DEPLOY_URL/admin answers HTTP $code" ;; esac
log_info "OK: $DEPLOY_URL (game: ${DEPLOY_URL/https:/wss:})"
