#!/bin/sh
# Deploys the gh-pages branch to GitHub Pages (.github/workflows/pages.yml) and waits for it; a failed
# deploy (Pages stalls now and then while syncing the files, and GitHub stops it at 10 minutes) is
# tried again, up to 5 times a minute apart. Exits 1 when all failed.
# Prints each try, the run's URL and its jobs as they change (tools/log.sh).
# Usage: tools/pages_deploy.sh   (tools/build_site.sh --publish runs it)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/log.sh"
log_init pages_deploy "$ROOT"
for try in 1 2 3 4 5; do
	log_step "Pages deploy, try $try of 5"
	before=$(gh run list --workflow pages.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')
	gh workflow run pages.yml || log_fail "gh workflow run pages.yml failed"
	log_info "started; waiting for the new run to appear"
	run=$before
	while [ "$run" = "$before" ]; do sleep 5; run=$(gh run list --workflow pages.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0'); done
	log_watch_run "$run"
	if [ "$LOG_RUN_CONCLUSION" = success ]; then
		log_info "Pages deployed (try $try): https://pycz2.github.io/classichs/"
		exit 0
	fi
	log_bad "Pages deploy try $try of 5: $LOG_RUN_CONCLUSION"
	[ "$try" = 5 ] || { log_info "the next try in a minute"; sleep 60; }
done
log_fail "the Pages deploy failed 5 times"
