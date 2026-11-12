#!/bin/bash
# Releases version X.Y.Z from HEAD (the version bump already committed and pushed to main):
#   DEPLOY_HOST=user@host DEPLOY_URL=https://hs.example.com tools/release.sh X.Y.Z [--from STEP] [--dry-run]
# The steps:
#   check    the version in project.godot, gh, DEPLOY_HOST/DEPLOY_URL (always runs)
#   ci       waits for the Release workflow's run of HEAD on main (the tests); failed jobs are run
#            again up to 2 times (a macOS runner is sometimes never acquired)
#   site     tools/build_site.sh --publish (the web build and the site on GitHub Pages)
#   splash   commits and pushes icons/splash.png if the site build changed it
#   tag      tags vX.Y.Z and pushes the tag
#   release  waits for the tag's Release run (it makes the GitHub release with all the files)
#   deploy   starts Docker Desktop if it is not running (waits for it), then tools/deploy_server.sh X.Y.Z
# then prints a summary: the CI runs, the release (files, size), the site's and the server's versions.
# --from STEP resumes after a failure (tools/release.sh 0.71.0 --from deploy); --dry-run only prints the steps.
# Everything printed is kept in build/logs/release-<UTC time>.log (with the site's and the deploy's output).
# RELEASE_TRAILERS: the lines that end the splash commit's message (the default below; empty: none).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/log.sh"
STEPS="check ci site splash tag release deploy"
usage() { echo "usage: tools/release.sh X.Y.Z [--from STEP] [--dry-run]   (STEP: ${STEPS// /, })" >&2; exit 2; }
V= FROM=check DRY=
while [ $# -gt 0 ]; do
  case $1 in
    --from) [ $# -ge 2 ] || usage; FROM=$2; shift ;;
    --dry-run) DRY=1 ;;
    -*) usage ;;
    *) [ -z "$V" ] || usage; V=$1 ;;
  esac
  shift
done
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ " $STEPS " == *" $FROM "* ]] || { echo "no step '$FROM'" >&2; usage; }
TRAILERS=${RELEASE_TRAILERS-"Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EiXgp8TjHJ4tufzuCLnDgH"}
SITE=https://pycz2.github.io/classichs/
CI_URL= REL_URL=

title() {
  case $1 in
    check) echo "Checking the version, gh and the deploy settings" ;;
    ci) echo "Waiting for CI (the Release workflow on main, HEAD)" ;;
    site) echo "Publishing the site (tools/build_site.sh --publish)" ;;
    splash) echo "Committing the splash (icons/splash.png) if it changed" ;;
    tag) echo "Tagging v$V and pushing the tag" ;;
    release) echo "Waiting for the release build (the Release workflow on v$V)" ;;
    deploy) echo "Deploying the server (tools/deploy_server.sh $V)" ;;
  esac
}

wants() {  # is this step run (not before --from)?
  local s
  for s in $STEPS; do [ "$s" = "$FROM" ] && return 0; [ "$s" = "$1" ] && return 1; done
}

if [ -n "$DRY" ]; then
  echo "tools/release.sh $V: the steps (dry run, nothing runs)"
  i=0
  for s in $STEPS; do
    i=$((i + 1))
    if [ "$s" = check ] || wants "$s"; then mark="run "; else mark="skip"; fi
    printf '  %s  %d/7 %-8s %s\n' "$mark" "$i" "$s" "$(title "$s")"
  done
  echo "then the summary; the log would be in build/logs/release-<UTC time>.log"
  echo "DEPLOY_HOST is ${DEPLOY_HOST:+set}${DEPLOY_HOST:-NOT set}, DEPLOY_URL is ${DEPLOY_URL:-NOT set}"
  exit 0
fi

log_init release "$ROOT"
log_steps 7
log_info "release $V from $(git -C "$ROOT" log --oneline -1)"
[ "$FROM" = check ] || log_info "resuming from the step '$FROM'"

# Finds the Release workflow's run for a commit (--commit SHA) or a tag (--tag vX.Y.Z), waiting for it
# to appear (15 minutes at most); prints its id.
find_run() {
  local i id
  for i in $(seq 60); do
    if [ "$1" = --commit ]; then
      id=$(gh run list -w Release -c "$2" --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
    else
      id=$(gh run list -w Release --json databaseId,headBranch -q ".[] | select(.headBranch==\"$2\") | .databaseId" 2>/dev/null | head -1 || true)
    fi
    [ -n "$id" ] && { echo "$id"; return 0; }
    [ $((i % 4)) = 1 ] && log_info "no Release run for $2 yet, waiting ($(((i - 1) * 15))s)…" >&2
    sleep 15
  done
  return 1
}

# Waits for a run; when it fails, shows its failed jobs' last log lines and runs the failed jobs again (2 times).
run_ok() {
  local id=$1 try
  for try in 1 2 3; do
    log_watch_run "$id"
    [ "$LOG_RUN_CONCLUSION" = success ] && { log_info "run $id: success"; return 0; }
    log_warn "run $id: $LOG_RUN_CONCLUSION; the failed jobs' last log lines:"
    gh run view "$id" --log-failed 2>/dev/null | tail -n 30 | sed 's/^/      | /' || true
    [ "$try" = 3 ] && break
    log_warn "running the failed jobs again (try $((try + 1)) of 3)"
    gh run rerun "$id" --failed
    sleep 20
  done
  log_fail "run $id is still '$LOG_RUN_CONCLUSION' after 2 reruns: $(gh run view "$id" --json url -q .url)"
}

step_check() {
  local pv
  pv=$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")
  [ "$pv" = "$V" ] || log_fail "project.godot has the version '$pv', not $V"
  log_info "project.godot: version $pv"
  gh auth status >/dev/null 2>&1 || log_fail "gh is not logged in (gh auth login)"
  log_info "gh: logged in"
  git -C "$ROOT" fetch -q origin main
  if [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ]; then
    log_info "HEAD is origin/main: $(git -C "$ROOT" log --oneline -1)"
  else
    log_warn "HEAD $(git -C "$ROOT" rev-parse --short HEAD) is not origin/main $(git -C "$ROOT" rev-parse --short origin/main): the CI step waits for a run of HEAD"
  fi
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$V" >/dev/null; then log_warn "the tag v$V exists already"; fi
  [ -n "${DEPLOY_HOST:-}" ] || log_fail "set DEPLOY_HOST (the ssh host of the game server)"
  [ -n "${DEPLOY_URL:-}" ] || log_fail "set DEPLOY_URL (https://the game server domain)"
  log_info "deploy to $DEPLOY_URL"
}

step_ci() {
  local sha id
  sha=$(git -C "$ROOT" rev-parse HEAD)
  id=$(find_run --commit "$sha") || log_fail "no Release run for $sha after 15 minutes (is HEAD pushed?)"
  CI_URL=$(gh run view "$id" --json url -q .url)
  run_ok "$id"
}

step_site() {
  "$ROOT/tools/build_site.sh" --publish
}

step_splash() {
  if [ -z "$(git -C "$ROOT" status --porcelain -- icons/splash.png)" ]; then
    log_info "no splash change"
    return 0
  fi
  git -C "$ROOT" add icons/splash.png
  git -C "$ROOT" commit -q -m "Splash for $V${TRAILERS:+

$TRAILERS}"
  log_info "committed: $(git -C "$ROOT" log --oneline -1)"
  git -C "$ROOT" push -q origin main
  log_info "pushed to main (it starts another CI run on main; the release does not wait for it)"
}

step_tag() {
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$V" >/dev/null; then
    log_warn "the tag v$V exists already ($(git -C "$ROOT" log --oneline -1 "v$V")): pushing it as it is"
  else
    git -C "$ROOT" tag -a "v$V" -m "Version $V"
    log_info "tagged $(git -C "$ROOT" log --oneline -1)"
  fi
  git -C "$ROOT" push -q origin "v$V"
  log_info "pushed the tag v$V"
}

release_info() {  # the GitHub release: its URL, files and their total size
  gh release view "v$V" --json url,assets -q '"\(.url) \(.assets | length) \([.assets[].size] | add // 0)"' 2>/dev/null
}

step_release() {
  local id url n size info
  id=$(find_run --tag "v$V") || log_fail "no Release run for v$V after 15 minutes"
  REL_URL=$(gh run view "$id" --json url -q .url)
  run_ok "$id"
  info=$(release_info) && [ -n "$info" ] || log_fail "no GitHub release v$V"
  read -r url n size <<<"$info"
  log_info "$url: $n files, $(log_size "$size")"
  gh release view "v$V" --json assets -q '.assets[] | "\(.size) \(.name)"' |
    while read -r s name; do log_info "  $(log_size "$s")  $name"; done
}

ensure_docker() {
  local i
  if docker info >/dev/null 2>&1; then log_info "Docker is running"; return 0; fi
  log_info "Docker is not running: starting Docker Desktop (open -a Docker)"
  open -a Docker || log_fail "could not start Docker Desktop: start Docker and resume with --from deploy"
  for i in $(seq 60); do
    docker info >/dev/null 2>&1 && { log_info "Docker is running ($((i * 5))s)"; return 0; }
    [ $((i % 3)) = 0 ] && log_info "waiting for Docker… $((i * 5))s"
    sleep 5
  done
  log_fail "Docker did not start in 5 minutes"
}

step_deploy() {
  ensure_docker
  "$ROOT/tools/deploy_server.sh" "$V"
}

i=0
for s in $STEPS; do
  i=$((i + 1))
  if [ "$s" = check ] || wants "$s"; then
    log_step "$(title "$s")" "$i"
    "step_$s"
  else
    log_info "$i/7 $s: skipped (--from $FROM)"
  fi
done

log_done
_log '1;36' "$(_log_at) ▶ Summary"
summary() { _log '1' "$(_log_at)   $*"; }
summary "version:          $V"
[ -n "$CI_URL" ] || CI_URL="(not waited for in this run)"
summary "CI on main:       $CI_URL"
if [ -z "$REL_URL" ]; then
  REL_URL=$(gh run list -w Release --json url,headBranch -q ".[] | select(.headBranch==\"v$V\") | .url" 2>/dev/null | head -1 || true)
fi
summary "release build:    ${REL_URL:-?}"
info=$(release_info || true)
if [ -n "$info" ]; then
  read -r url n size <<<"$info"
  summary "GitHub release:   $url ($n files, $(log_size "$size"))"
else
  summary "GitHub release:   v$V not found"
fi
sv=$(curl -fsS "${SITE}play/version.json" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
summary "site:             $SITE (play/version.json: $sv$([ "$sv" = "$V" ] && echo ", OK" || echo ", NOT $V: the Pages cache may lag a few minutes"))"
code=$(curl -sS -o /dev/null -w '%{http_code}' "$DEPLOY_URL/admin" 2>/dev/null) || code=000
running=$(grep -o "classichs $V is running" "${CHS_LOG_FILE:-/dev/null}" | head -1 || true)
summary "server:           $DEPLOY_URL/admin HTTP $code; ${running:-the deploy did not run in this log}"
summary "                  (the server has no public version endpoint: /admin/api/me shows it after logging in)"
