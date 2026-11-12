#!/bin/sh
# The performance harness's web build: packs, import, the Web export (release, like the site; PERF_EXPORT=debug
# for Godot's debug monitors) into $1 (default /tmp/classichs-perf/web), finished by tools/web_finish.sh.
# Needs rules/bin/rules.wasm (tools/build_rules.sh web).
set -e
cd "$(dirname "$0")/../.."
OUT=${1:-/tmp/classichs-perf/web}
[ -f rules/bin/rules.wasm ] || { echo "rules/bin/rules.wasm is missing: tools/build_rules.sh web" >&2; exit 1; }
tools/build_packs.sh
godot --headless --path . --import >/dev/null 2>&1 || true
rm -rf "$OUT"
mkdir -p "$OUT"
godot --headless --path . --export-"${PERF_EXPORT:-release}" "Web" "$OUT/index.html"
tools/web_finish.sh "$OUT"
echo "web build: $OUT"
