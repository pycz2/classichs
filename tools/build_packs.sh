#!/bin/sh
# Builds the game's built-in packs into packs/*.cardpack (res://packs, read by game/packs.gd).
# The pack sources are packs/<name>/ (docs/packs/format.md); the .cardpack files are not in git.
set -e
cd "$(dirname "$0")/.."
for src in classic neon; do
	python3 tools/pack.py build "packs/$src" -o "packs/$src.cardpack" >/dev/null
done
