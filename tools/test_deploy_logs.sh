#!/bin/bash
# Checks what tools/deploy_server.sh prints (tools/log.sh) without a host, a release or Docker: ssh, scp,
# docker and curl are stand-ins in a temporary directory put first on PATH (nothing leaves this machine).
# Three runs: a good deploy, classichs-deploy failing on the host, the URL answering 502.
# Usage: tools/test_deploy_logs.sh [-v]   (-v: show each run's output)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin" "$T/logs"

cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
# the release's JSON, its files, or an HTTP status (FAKE_HTTP)
out= w= url=
while [ $# -gt 0 ]; do
  case $1 in -o) out=$2; shift ;; -w) w=$2; shift ;; -*) ;; *) url=$1 ;; esac; shift
done
case $url in
  https://api.github.com/*/releases/tags/v*)
    v=${url##*/v} d=https://github.com/pycz2/classichs/releases/download/v$v
    printf '{"assets": [%s]}\n' "$(for n in ClassicHS-server-$v-linux-x86_64 ClassicHS-$v-replay-viewer.zip \
      ClassicHS-$v-classic.cardpack ClassicHS-$v-neon.cardpack ClassicHS-$v-web.zip; do
      printf '{"name": "%s", "browser_download_url": "%s/%s", "size": 1234567},' "$n" "$d" "$n"; done | sed 's/,$//')" ;;
  *.zip) python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], "w"); z.writestr("index.html", "x"); z.writestr("index.wasm", "y")' "$out" ;;
  *.cardpack) n=${url##*-}; printf 'pack-%s' "${n%.cardpack}" > "$out" ;;
  *-linux-x86_64) head -c 2000000 /dev/zero > "$out" ;;
  */admin) [ "$w" = '%{http_code}' ] && printf '%s' "${FAKE_HTTP:-200}" ;;
  *) echo "fake curl: unexpected $url" >&2; exit 99 ;;
esac
EOF

cat > "$T/bin/ssh" <<'EOF'
#!/bin/bash
# the host: classic.cardpack is the same as the release's, old.cardpack is not in it
shift; cmd=$*
case $cmd in
  *sha256sum*) printf '%s  classic.cardpack\n%s  old.cardpack\n' "$(printf pack-classic | shasum -a 256 | cut -d' ' -f1)" "$(printf old | shasum -a 256 | cut -d' ' -f1)" ;;
  *"cat > classichs/incoming/.part"*) cat > /dev/null ;;
  *classichs-deploy*)
    if [ "${FAKE_DEPLOY_FAIL:-}" = 1 ]; then
      echo "classichs ${cmd##* } does not answer; its last log lines:" >&2
      echo "Error: the database is locked" >&2
      echo "rolled back to classichs-server:0.70.0" >&2; exit 1
    fi
    echo "classichs ${cmd##* } is running (images: ${cmd##* } 0.70.0 )" ;;
  mkdir* | mv* | rm*) ;;
  *) echo "fake ssh: unexpected $cmd" >&2; exit 99 ;;
esac
EOF

cat > "$T/bin/scp" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$T/bin/docker" <<'EOF'
#!/bin/bash
case $1 in
  build) echo sha256:0123456789abcdef ;;
  save) head -c 3000000 /dev/urandom ;;
  rmi) ;;
  *) echo "fake docker: unexpected $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$T"/bin/*

fails=0
run() {  # name, expected exit, then the texts the output must have
  local name=$1 want=$2 got=0; shift 2
  PATH="$T/bin:$PATH" CHS_LOG_DIR="$T/logs/$name" DEPLOY_HOST=test@deploy.invalid DEPLOY_URL=https://deploy.invalid \
    "$ROOT/tools/deploy_server.sh" 0.71.0 > "$T/$name.out" 2>&1 || got=$?
  [ "${VERBOSE:-}" != 1 ] || { echo "----- $name"; cat "$T/$name.out"; }
  local bad=""
  [ "$got" = "$want" ] || bad="exit $got, not $want; "
  for s in "$@"; do grep -qF -- "$s" "$T/$name.out" || bad="$bad missing \"$s\";"; done
  local log; log=$(ls "$T/logs/$name"/deploy_server-*.log 2>/dev/null | head -1)
  if [ -z "$log" ]; then bad="$bad no log file;"
  else
    grep -q $'\033' "$log" && bad="$bad colours in the log file;"
    grep -qF "✔ 1/7 done in" "$log" || bad="$bad the log file lacks the steps;"
  fi
  if [ -n "$bad" ]; then echo "FAIL $name: $bad"; sed 's/^/  /' "$T/$name.out"; fails=$((fails + 1)); else echo "ok   $name"; fi
}
[ "${1:-}" != -v ] || VERBOSE=1

run good 0 "▶ 1/7 Reading the release v0.71.0" "4 files to download: 4.9 MB" \
  "ClassicHS-server-0.71.0-linux-x86_64: 2.0 MB in" "the replay viewer: 2 files" "image classichs-server:0.71.0: 3.0 MB to upload" \
  "the release has 2 packs, the host 2" "classic.cardpack: same, skipped" "neon.cardpack: uploading 9 B…" \
  "neon.cardpack: uploaded in" "old.cardpack: removed (not in the release)" "packs: 1 uploaded, 1 the same, 1 removed" \
  "▶ 5/7 Uploading the image (3.0 MB)" "classichs 0.71.0 is running" "https://deploy.invalid/admin: HTTP 200" \
  "OK: https://deploy.invalid (game: wss://deploy.invalid)" "✔ 7/7 done in" "✔ deploy_server finished in" "deploy_server: log in"
FAKE_DEPLOY_FAIL=1 run deploy_fails 1 "Error: the database is locked" "the last lines of the output:" "    | rolled back to classichs-server:0.70.0" \
  "✘ deploy_server failed at 6/7 Running classichs-deploy 0.71.0" "exit 1, the command: ssh"
FAKE_HTTP=502 run url_502 1 "https://deploy.invalid/admin: HTTP 502" "✘ deploy_server failed at 7/7 Checking https://deploy.invalid/admin after" \
  ": https://deploy.invalid/admin answers HTTP 502"
[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
