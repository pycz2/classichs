#!/bin/sh
# Builds the GitHub Pages site into build/site (landing + web build of the game in play/)
# and, with --publish, commits it to the gh-pages branch and pushes it.
# Needs Godot 4.7.2 with export templates on PATH as `godot`.
# Prints each phase with its time (tools/log.sh); the log is kept in build/logs/build_site-<time>.log.
set -e
cd "$(dirname "$0")/.."
. tools/log.sh
log_init build_site "$PWD"
if [ "$1" = "--publish" ]; then log_steps 14; else log_steps 10; fi
OUT=build/site
mkdir -p build
touch build/.gdignore  # Godot must not import (and pack) what lies in build/
log_step "Packs"
tools/build_packs.sh  # res://packs/*.cardpack: the built-in game packs
rm -rf "$OUT"
mkdir -p "$OUT/play" "$OUT/screens"
log_step "Splash (the version on it)"
godot --path . --script res://tools/make_splash.gd  # the splash shows the version (needs a window)
log_step "Rules engine (rules.wasm)"
[ "$RULES_PREBUILT" != 1 ] || log_info "RULES_PREBUILT=1: rules/bin/rules.wasm as it is"
[ "$RULES_PREBUILT" = 1 ] || tools/build_rules.sh web  # the rules engine (rules.wasm)
log_step "Godot import"
godot --headless --path . --import >/dev/null
log_step "Web export"
godot --headless --path . --export-release "Web" "$OUT/play/index.html"
log_step "Finishing the web build (tools/web_finish.sh)"
tools/web_finish.sh "$OUT/play"  # the rules engine, version.json, always the newest build
log_info "play/version.json: $(cat "$OUT/play/version.json")"
log_step "Landing page, screens, site data"
cp -R site/index.html site/style.css site/main.js site/name.js site/favicon.svg site/og.jpg site/i18n "$OUT/"  # og.jpg: the link preview (media/screens/en/match.png as JPEG)
cp -R media/screens/en media/screens/ru "$OUT/screens/"
python3 tools/site_data.py "$OUT"
log_step "Docs for game makers (dev/)"
python3 tools/lua_api.py --check  # the API reference must match the engine's g.* functions and hooks
python3 tools/site_docs.py "$OUT"  # dev/: the pages for game makers (site/dev/<lang>/*.md, docs/packs/*.md, the API)
log_step "Cards (as the game draws them)"
godot --path . --script res://tools/site_cards.gd -- "$OUT"  # the cards as the game draws them (needs a window)
touch "$OUT/.nojekyll"
# GitHub Pages takes a site of at most 1 GB; a file over 100 MB git refuses, so the publish splits it into
# parts (below) and the Pages workflow (.github/workflows/pages.yml) joins them again before the deploy.
log_step "Size check"
SIZE=$(du -sk "$OUT" | cut -f1)
log_info "the site: $(log_size $((SIZE * 1024))) in $(find "$OUT" -type f | wc -l | tr -d ' ') files (GitHub Pages takes 950 MB at most here)"
log_info "the files over 5 MB:"
find "$OUT" -type f -size +5M -exec ls -l {} + | sort -k5 -n -r | head -n 5 | awk '{ printf "             %8.1f MB  %s\n", $5 / 1e6, $NF }'
if [ "$SIZE" -gt 950000 ]; then log_fail "too big for GitHub Pages (over 950 MB): ${SIZE} KB"; fi
log_info "Site built in $OUT"
[ "$1" = "--publish" ] || exit 0
log_step "Preparing the gh-pages worktree"
REV=$(git rev-parse --short HEAD)
WT=build/gh-pages
git worktree remove --force "$WT" 2>/dev/null || true
HAS=0
git ls-remote --exit-code --heads origin gh-pages >/dev/null || HAS=$?
if [ "$HAS" = 0 ]; then
	git fetch origin gh-pages
	git worktree add -B gh-pages "$WT" origin/gh-pages
elif [ "$HAS" = 2 ]; then  # no gh-pages on the remote yet: start it fresh
	log_info "no gh-pages on the remote yet: starting it fresh"
	git branch -D gh-pages 2>/dev/null || true  # left over from a failed first publish
	git worktree add --detach "$WT"
	git -C "$WT" checkout --orphan gh-pages
	git -C "$WT" rm -rf --quiet .
else
	log_fail "Cannot reach the remote (git ls-remote exit $HAS)"
fi
log_step "Copying the site, splitting big files, committing"
find "$WT" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$OUT"/. "$WT"/
find "$WT" -path "$WT/.git" -prune -o -type f -size +90M -print | while read -r f; do  # git takes no file over 100 MB
	split -b 90m "$f" "$f.part-" && rm "$f"
	log_info "split ${f#"$WT"/} into: $(for p in "$f".part-*; do printf '%s (%s) ' "${p##*.}" "$(log_fsize "$p")"; done)"
done
git -C "$WT" add -A
if git -C "$WT" commit -q -m "Site from $REV"; then
	log_info "committed $(git -C "$WT" rev-parse --short HEAD) \"Site from $REV\": $(git -C "$WT" show --shortstat --format= HEAD | sed 's/^ *//')"
else
	log_info "No changes"
fi
log_step "Pushing gh-pages"
git -C "$WT" push origin gh-pages
log_step "Pages deploy (tools/pages_deploy.sh)"
tools/pages_deploy.sh  # the deploy to Pages (.github/workflows/pages.yml), tried again when it stalls
git worktree remove "$WT"
log_info "Published: https://pycz2.github.io/classichs/"
