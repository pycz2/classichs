#!/bin/sh
# Builds every pack source packs/<name>/ (docs/packs/format.md; the .cardpack files are not in git):
# - the game's built-in packs into packs/<name>.cardpack (res://packs, read by game/packs.gd; the exports take them);
# - the packs whose recipe says "bundle_in_client": false (the expansions after Naxxramas) into
#   build/packs/<name>.cardpack: not in the game's builds, but release files and the server's
#   (tools/export_all.sh, server/Dockerfile, tools/deploy_server.sh take both folders).
set -e
cd "$(dirname "$0")/.."
mkdir -p build/packs
touch build/.gdignore
for src in packs/*/; do
	name=$(basename "$src")
	[ -f "packs/$name/manifest.json" ] || continue
	out=packs
	[ "$(python3 tools/pack.py bundled "packs/$name")" = yes ] || out=build/packs
	python3 tools/pack.py build "packs/$name" -o "$out/$name.cardpack" >/dev/null
done
# The schemas and vocabularies the client's pack tools check with (game/pack_check.gd; docs/ is not in the game).
mkdir -p packs/schema
cp docs/packs/schema/*.json packs/schema/
