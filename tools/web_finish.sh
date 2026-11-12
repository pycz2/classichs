#!/bin/sh
# Finishes a web export (tools/export_all.sh web, tools/build_site.sh): puts the rules engine
# next to index.html and makes the page always run the newest published build (web/update.js).
# Usage: tools/web_finish.sh <the export's directory>
set -e
cd "$(dirname "$0")/.."
D=$1
SW="$D/index.service.worker.js"
VER=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
BUILD=$(sed -n "s/^const CACHE_VERSION = '\(.*\)';/\1/p" "$SW")  # Godot's: export time|size, the cache's name
[ -n "$BUILD" ] || { echo "no CACHE_VERSION in $SW" >&2; exit 1; }
cp web/rules.js web/update.js rules/bin/rules.wasm rules/LICENSE.opus "$D/"  # loaded by index.html (html/head_include); the .opus decoder's licence
perl -pi -e "s/__CHS_BUILD__/$BUILD/" "$D/update.js"
printf '{"version": "%s", "build": "%s"}\n' "$VER" "$BUILD" > "$D/version.json"
# the engine starts once update.js has checked version.json
perl -pi -e 's/^(const engine = new Engine\(GODOT_CONFIG\);)$/$1\nchsGate(engine);/' "$D/index.html"
grep -q '^chsGate(engine);$' "$D/index.html" || { echo "index.html: no engine start to gate" >&2; exit 1; }
# The service worker: offline play keeps the engine, update.js and the splash too; a new build's
# worker takes over at once (no waiting for every tab to close) and takes the files past the
# browser's HTTP cache, so a new cache never gets an old file; a page opened as the folder
# (.../play/, not .../play/index.html) is index.html too, so it opens offline.
perl -0pi -e '
	s/(const CACHED_FILES = \[.*?)\];/$1,"update.js","index.png"];/;
	s/const CACHEABLE_FILES = \[/const CACHEABLE_FILES = ["rules.js","rules.wasm",/;
	s/cache\.addAll\(CACHED_FILES\)/cache.addAll(CACHED_FILES.map((f) => new Request(f, { cache: "no-cache" })))/;
	s/(self\.addEventListener\(.install., \(event\) => \{)/$1\n\tself.skipWaiting();/;
	s/(self\.addEventListener\(.activate., \(event\) => \{)/$1\n\tevent.waitUntil(self.clients.claim());/;
	s/self\.fetch\(event\.request\)/self.fetch(event.request, { cache: "no-cache" })/;
	s/let cached = await cache\.match\(event\.request\);/let cached = await cache.match(isNavigate ? CACHED_FILES[0] : event.request);/;
' "$SW"
for s in ',"update.js","index.png"];' 'cache.match(isNavigate ? CACHED_FILES[0]' '"rules.js","rules.wasm",' 'cache: "no-cache" })))' 'self.skipWaiting();' 'event.waitUntil(self.clients.claim());' 'self.fetch(event.request, { cache: "no-cache" })'; do
	grep -qF "$s" "$SW" || { echo "$SW: the patch for $s did not apply (a new Godot template?)" >&2; exit 1; }
done
