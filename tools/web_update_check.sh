#!/bin/sh
# Checks for real that the web build always runs the newest published build (web/update.js)
# and still starts offline: headless Chrome loads build 1, the served files become build 2,
# a normal reload must run build 2; then with the server gone a reload must start build 2 again.
# Usage: tools/web_update_check.sh <web export 1> <web export 2> [port]
#   make the two with tools/export_all.sh web and two different config/version values, copying
#   build/release/web away after each. The server sends Cache-Control: max-age=600 like GitHub Pages.
# Prints the checks and the screenshots' paths (the menu's version label, bottom right); exit 0 = OK.
set -e
V1=$(cd "$1" && pwd); V2=$(cd "$2" && pwd)
PORT=${3:-8813}
CDP=$((PORT + 1))
for p in $PORT $CDP; do
	! lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1 || { echo "port $p is taken" >&2; exit 1; }
done
T=$(mktemp -d /tmp/chs_web_update.XXXXXX)
mkdir "$T/site"
cp -R "$V1"/. "$T/site/"
cat > "$T/serve.py" <<'EOF'
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "max-age=600")
        super().end_headers()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
EOF
python3 "$T/serve.py" "$PORT" "$T/site" & SRV=$!
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --remote-debugging-port=$CDP \
	--user-data-dir="$T/chrome" --use-angle=swiftshader --enable-unsafe-swiftshader --window-size=1280,720 \
	--no-first-run about:blank >/dev/null 2>&1 & CHR=$!
trap 'kill $SRV $CHR 2>/dev/null; wait 2>/dev/null; rm -rf "$T/chrome" "$T/site"' EXIT
cat > "$T/check.mjs" <<'EOF'
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
const [port, cdp, dir, v1, v2, srvPid] = process.argv.slice(2);
const build = (d) => JSON.parse(readFileSync(d + "/version.json")).build;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = {};
for (let i = 0; ; i++) {
	try {
		const t = (await (await fetch(`http://127.0.0.1:${cdp}/json`)).json()).find((x) => x.type === "page");
		ws = new WebSocket(t.webSocketDebuggerUrl); break;
	} catch (e) { if (i > 50) throw e; await sleep(200); }
}
await new Promise((r) => (ws.onopen = r));
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (wait[d.id]) { wait[d.id](d); delete wait[d.id]; } };
const send = (method, params = {}) => new Promise((r) => { wait[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
const js = async (e) => (await send("Runtime.evaluate", { expression: e, awaitPromise: true, returnByValue: true })).result?.result?.value;
let failed = false;
const check = (ok, what) => { console.log((ok ? "OK   " : "FAIL ") + what); failed ||= !ok; };
async function started(what) {  // the engine started (Godot removes #status), then the menu draws
	for (let i = 0; i < 240; i++) {
		if (await js("!!window.chsBuild && !document.getElementById('status')")) break;
		await sleep(500);
	}
	await sleep(6000);
	const shot = `${dir}/${what}.png`;
	writeFileSync(shot, Buffer.from((await send("Page.captureScreenshot")).result.data, "base64"));
	return { build: await js("window.chsBuild"), shot,
		caches: await js("caches.keys()"),
		cached: await js("caches.keys().then((k) => k.length ? caches.open(k[0]).then((c) => c.keys()).then((r) => r.map((x) => x.url.split('/').pop())) : [])") };
}
await send("Page.enable"); await send("Runtime.enable"); await send("Network.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
const b1 = build(v1), b2 = build(v2);
await send("Page.navigate", { url: `http://127.0.0.1:${port}/` });
let s = await started("1-first-visit");
check(s.build === b1, `first visit runs build 1 (${s.build}) ${s.shot}`);
for (const type of ["mousePressed", "mouseReleased"])  // the first run asks the language: English
	await send("Input.dispatchMouseEvent", { type, x: 471, y: 285, button: "left", clickCount: 1 });
await sleep(3000);
await send("Page.reload"); s = await started("2-second-visit");
check(s.build === b1 && s.cached.includes("index.pck"), `second visit: build 1, the service worker keeps index.pck (${s.caches}) ${s.shot}`);
execSync(`rm -rf "${dir}/site"/* && cp -R "${v2}"/. "${dir}/site/"`);  // publish build 2
await send("Page.reload"); s = await started("3-after-publish");
check(s.build === b2, `a normal reload after the publish runs build 2 (${s.build}) ${s.shot}`);
check(s.caches.length === 1 && s.caches[0].endsWith(b2), `only build 2's cache is left (${s.caches})`);
check(["index.pck", "index.wasm", "index.js", "rules.wasm", "update.js"].every((f) => s.cached.includes(f)), `build 2's cache holds the game (${s.cached})`);
process.kill(+srvPid);  // offline: no server at all, and the browser told so
await send("Network.emulateNetworkConditions", { offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
await send("Page.reload"); s = await started("4-offline");
check(s.build === b2, `offline the cached build 2 starts (${s.build}) ${s.shot}`);
ws.close();
process.exit(failed ? 1 : 0);
EOF
node "$T/check.mjs" "$PORT" "$CDP" "$T" "$V1" "$V2" "$SRV"
echo "web update check OK (screenshots in $T)"
