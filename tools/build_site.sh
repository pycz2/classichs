#!/bin/sh
# Builds the GitHub Pages site into build/site (landing + web build of the game in play/)
# and, with --publish, commits it to the gh-pages branch and pushes it.
# Needs Godot 4.7.2 with export templates on PATH as `godot`.
set -e
cd "$(dirname "$0")/.."
OUT=build/site
mkdir -p build
touch build/.gdignore  # Godot must not import (and pack) what lies in build/
tools/build_packs.sh  # res://packs/*.cardpack: the built-in game packs
rm -rf "$OUT"
mkdir -p "$OUT/play" "$OUT/screens"
godot --path . --script res://tools/make_splash.gd  # the splash shows the version (needs a window)
[ "$RULES_PREBUILT" = 1 ] || tools/build_rules.sh web  # the rules engine (rules.wasm)
godot --headless --path . --import >/dev/null
godot --headless --path . --export-release "Web" "$OUT/play/index.html"
cp web/rules.js rules/bin/rules.wasm "$OUT/play/"  # loaded by index.html (html/head_include)
perl -pi -e 's/const CACHEABLE_FILES = \[/const CACHEABLE_FILES = ["rules.js","rules.wasm",/' "$OUT/play/index.service.worker.js"  # offline play (PWA) keeps the engine too
cp -R site/index.html site/style.css site/main.js site/favicon.svg site/og.jpg site/i18n "$OUT/"  # og.jpg: the link preview (media/screens/en/match.png as JPEG)
cp -R media/screens/en media/screens/ru "$OUT/screens/"
python3 tools/site_data.py "$OUT"
godot --path . --script res://tools/site_cards.gd -- "$OUT"  # the cards as the game draws them (needs a window)
touch "$OUT/.nojekyll"
echo "Site built in $OUT"
[ "$1" = "--publish" ] || exit 0
REV=$(git rev-parse --short HEAD)
WT=build/gh-pages
git worktree remove --force "$WT" 2>/dev/null || true
HAS=0
git ls-remote --exit-code --heads origin gh-pages >/dev/null || HAS=$?
if [ "$HAS" = 0 ]; then
	git fetch origin gh-pages
	git worktree add -B gh-pages "$WT" origin/gh-pages
elif [ "$HAS" = 2 ]; then  # no gh-pages on the remote yet: start it fresh
	git branch -D gh-pages 2>/dev/null || true  # left over from a failed first publish
	git worktree add --detach "$WT"
	git -C "$WT" checkout --orphan gh-pages
	git -C "$WT" rm -rf --quiet .
else
	echo "Cannot reach the remote (git ls-remote exit $HAS)" >&2
	exit 1
fi
find "$WT" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$OUT"/. "$WT"/
git -C "$WT" add -A
git -C "$WT" commit -q -m "Site from $REV" || echo "No changes"
git -C "$WT" push origin gh-pages
git worktree remove "$WT"
echo "Published: https://pycz2.github.io/classichs/"
