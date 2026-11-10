#!/bin/sh
# Deploys the gh-pages branch to GitHub Pages (.github/workflows/pages.yml) and waits for it; a failed
# deploy (Pages stalls now and then while syncing the files, and GitHub stops it at 10 minutes) is
# tried again, up to 5 times a minute apart. Exits 1 when all failed.
# Usage: tools/pages_deploy.sh   (tools/build_site.sh --publish runs it)
for try in 1 2 3 4 5; do
	before=$(gh run list --workflow pages.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')
	gh workflow run pages.yml || exit 1
	run=$before
	while [ "$run" = "$before" ]; do sleep 5; run=$(gh run list --workflow pages.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0'); done
	until [ "$(gh run view "$run" --json status --jq .status)" = "completed" ]; do sleep 15; done
	if [ "$(gh run view "$run" --json conclusion --jq .conclusion)" = "success" ]; then
		echo "Pages deployed (try $try)"
		exit 0
	fi
	echo "Pages deploy failed (try $try of 5)" >&2
	[ "$try" = 5 ] || sleep 60
done
exit 1
