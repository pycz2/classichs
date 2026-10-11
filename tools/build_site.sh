#!/bin/sh
# Builds the GitHub Pages site into build/site (landing + web build of the game in play/)
# and, with --publish, commits it to the gh-pages branch and pushes it.
# Needs Godot 4.7.2 with export templates on PATH as `godot`.
set -e
cd "$(dirname "$0")/.."
OUT=build/site
rm -rf "$OUT"
mkdir -p "$OUT/play" "$OUT/screens"
godot --headless --path . --export-release "Web" "$OUT/play/index.html"
rm -f "$OUT"/play/*.import
cp site/index.html site/style.css site/main.js site/favicon.svg "$OUT/"
cp -R media/screens/en media/screens/ru "$OUT/screens/"
touch "$OUT/.nojekyll"
echo "Site built in $OUT"
[ "$1" = "--publish" ] || exit 0
REV=$(git rev-parse --short HEAD)
WT=build/gh-pages
git worktree remove --force "$WT" 2>/dev/null || true
if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
	git fetch origin gh-pages
	git worktree add -B gh-pages "$WT" origin/gh-pages
else
	git worktree add --detach "$WT"
	git -C "$WT" checkout --orphan gh-pages
	git -C "$WT" rm -rf --quiet .
fi
find "$WT" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$OUT"/. "$WT"/
git -C "$WT" add -A
git -C "$WT" commit -q -m "Site from $REV" || echo "No changes"
git -C "$WT" push origin gh-pages
git worktree remove "$WT"
echo "Published: https://pycz2.github.io/classichs/"
