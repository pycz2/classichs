// The performance harness in the browser: serves a web build (tools/perf/build_web.sh), opens it in
// headless Chrome (a fresh profile, SwiftShader WebGL) with ?perf=1&drive=1 (PerfLog and
// tools/perf_drive.gd: it plays tournaments by itself on the given server) and records for the given minutes:
//   godot.csv   PerfLog's rows (window.chsPerf), one a second
//   chrome.csv  Chrome's own metrics every 10 s (Performance.getMetrics: JS heap, DOM nodes, layouts,
//               task/script time), the WebAssembly memories (Godot's, the rules engine's, the decoder's) and,
//               once a minute, the live Web Audio buffers (count, MB)
//   console.log the page's console (the driver's DRIVE: lines, errors)
//   cpu-<min>.cpuprofile  a 20 s CPU profile now and then (Chrome DevTools opens them)
//   shot-<min>.png        a screenshot every 5 minutes
// Usage: node tools/perf/web_run.mjs --web DIR --server ws://127.0.0.1:PORT --user NAME --minutes 60 --out DIR
//          [--gl metal|swiftshader] [--profile-every MINUTES]
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const arg = (k, d) => {
	const i = process.argv.indexOf("--" + k);
	return i > 0 ? process.argv[i + 1] : d;
};
const WEB = arg("web", "/tmp/classichs-perf/web");
const SERVER = arg("server");
const USER = arg("user", "perfweb");
const MINUTES = Number(arg("minutes", "60"));
const OUT = arg("out", "/tmp/classichs-perf/web-run");
const PROFILE_EVERY = Number(arg("profile-every", "10")); // minutes between CPU profiles
const CHROME = arg("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
if (!SERVER) throw new Error("--server ws://127.0.0.1:PORT is needed");
fs.mkdirSync(OUT, { recursive: true });

const freePort = () => new Promise((ok) => {
	const s = net.createServer();
	s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => ok(p)); });
});
const wait = (ms) => new Promise((ok) => setTimeout(ok, ms));
const log = (s) => { const line = `${new Date().toISOString()} ${s}`; console.log(line); fs.appendFileSync(path.join(OUT, "console.log"), line + "\n"); };

const httpPort = await freePort();
const cdpPort = await freePort();
const kids = [];
const http = spawn("python3", ["-m", "http.server", String(httpPort), "--bind", "127.0.0.1", "--directory", WEB], { stdio: "ignore" });
kids.push(http);
const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), "chs-perf-chrome-"));
// --gl swiftshader (software WebGL: the frame's commit waits for it, so FPS means little) or metal (the Mac's GPU)
const GL = arg("gl", "metal");
const glFlags = GL === "swiftshader" ? ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
	: [`--use-angle=${GL}`, "--enable-gpu", "--ignore-gpu-blocklist"];
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${cdpPort}`, `--user-data-dir=${profileDir}`,
	...glFlags, "--no-first-run", "--no-default-browser-check",
	"--autoplay-policy=no-user-gesture-required", "--window-size=1280,720", "--enable-precise-memory-info",
	"--disable-background-timer-throttling", "--disable-renderer-backgrounding", "about:blank"], { stdio: "ignore" });
kids.push(chrome);
const stop = () => { for (const k of kids) try { k.kill(); } catch (e) {} fs.rmSync(profileDir, { recursive: true, force: true }); };
process.on("SIGINT", () => { stop(); process.exit(1); });
process.on("SIGTERM", () => { stop(); process.exit(1); });

let target;
for (let i = 0; i < 100 && !target; i++) {
	await wait(200);
	try { target = (await (await fetch(`http://127.0.0.1:${cdpPort}/json/list`)).json()).find((t) => t.type === "page"); } catch (e) {}
}
if (!target) { stop(); throw new Error("Chrome did not start"); }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((ok) => ws.addEventListener("open", ok));
let seq = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
	const m = JSON.parse(e.data);
	if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
	if (m.method === "Runtime.consoleAPICalled") log("console." + m.params.type + ": " + m.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
	if (m.method === "Runtime.exceptionThrown") log("exception: " + JSON.stringify(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text));
});
const cdp = (method, params = {}) => new Promise((ok, bad) => {
	const id = ++seq;
	pending.set(id, (m) => (m.error ? bad(new Error(method + ": " + m.error.message)) : ok(m.result)));
	ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expr) => (await cdp("Runtime.evaluate", { expression: expr, returnByValue: true })).result.value;

await cdp("Runtime.enable");
await cdp("Performance.enable", { timeDomain: "timeTicks" });
await cdp("Profiler.enable");
await cdp("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
const url = `http://127.0.0.1:${httpPort}/index.html?perf=1&drive=1&server=${encodeURIComponent(SERVER)}&user=${encodeURIComponent(USER)}`;
log("open " + url);
await cdp("Page.navigate", { url });
await cdp("Page.bringToFront");

// The live objects of a kind in the page, each one's size in MB, biggest first (queryObjects: after a GC).
async function sizesOf(proto, size) {
	try {
		const p = await cdp("Runtime.evaluate", { expression: proto + ".prototype", objectGroup: "harness" });
		const objs = await cdp("Runtime.queryObjects", { prototypeObjectId: p.result.objectId, objectGroup: "harness" });
		const r = await cdp("Runtime.callFunctionOn", { objectId: objs.objects.objectId, returnByValue: true,
			functionDeclaration: `function () { const f = ${size}; return this.map((o) => f(o) / 1048576).sort((a, b) => b - a); }` });
		await cdp("Runtime.releaseObjectGroup", { objectGroup: "harness" }).catch(() => {});
		return r.result.value || [];
	} catch (e) { return []; }
}
// the WebAssembly memories in the page (Godot's, the rules engine's, the .opus decoder's)
const wasmMemories = () => sizesOf("WebAssembly.Memory", "(m) => m.buffer.byteLength");
// Web Audio buffers: Godot's web build plays an AudioStreamWAV as a "sample", an AudioBuffer of float32
const audioBuffers = () => sizesOf("AudioBuffer", "(b) => b.length * b.numberOfChannels * 4");

const chromeCsv = path.join(OUT, "chrome.csv");
const godotCsv = path.join(OUT, "godot.csv");
const KEYS = ["JSHeapUsedSize", "JSHeapTotalSize", "Nodes", "JSEventListeners", "LayoutCount", "RecalcStyleCount", "LayoutDuration", "TaskDuration", "ScriptDuration", "Documents", "Frames"];
fs.writeFileSync(chromeCsv, "t,minute," + KEYS.join(",") + ",wasm1_mb,wasm2_mb,wasm3_mb,wasm_total_mb,audio_buffers,audio_buffers_mb\n");
let godotRows = 0, lastAudio = 0, audio = [];
const t0 = Date.now();
let nextProfile = 3, nextShot = 0, lastTick = 0;
while ((Date.now() - t0) / 60000 < MINUTES) {
	await wait(1000);
	const minute = (Date.now() - t0) / 60000;
	try {
		const have = await evaluate("window.chsPerf ? window.chsPerf.rows.length : -1");
		if (have > godotRows) {
			if (godotRows === 0) fs.writeFileSync(godotCsv, (await evaluate("window.chsPerf.header")) + "\n");
			const rows = await evaluate(`window.chsPerf.rows.slice(${godotRows}).join("\\n")`);
			fs.appendFileSync(godotCsv, rows + "\n");
			godotRows = have;
		}
		if (Date.now() - lastTick >= 10000) {
			lastTick = Date.now();
			const m = Object.fromEntries((await cdp("Performance.getMetrics")).metrics.map((x) => [x.name, x.value]));
			const w = await wasmMemories();
			if (Date.now() - lastAudio >= 60000) {  // (a GC each time: once a minute)
				lastAudio = Date.now();
				audio = await audioBuffers();
			}
			fs.appendFileSync(chromeCsv, [new Date().toISOString(), minute.toFixed(2), ...KEYS.map((k) => m[k] ?? ""),
				(w[0] ?? 0).toFixed(1), (w[1] ?? 0).toFixed(1), (w[2] ?? 0).toFixed(1), w.reduce((a, b) => a + b, 0).toFixed(1),
				audio.length, audio.reduce((a, b) => a + b, 0).toFixed(1)].join(",") + "\n");
		}
		if (minute >= nextShot) {
			const s = await cdp("Page.captureScreenshot", { format: "png" });
			fs.writeFileSync(path.join(OUT, `shot-${String(Math.round(minute)).padStart(3, "0")}.png`), Buffer.from(s.data, "base64"));
			nextShot += 5;
		}
		if (minute >= nextProfile) {
			nextProfile += PROFILE_EVERY;
			log(`cpu profile at minute ${minute.toFixed(1)}`);
			await cdp("Profiler.setSamplingInterval", { interval: 500 });
			await cdp("Profiler.start");
			await wait(20000);
			const p = await cdp("Profiler.stop");
			fs.writeFileSync(path.join(OUT, `cpu-${String(Math.round(minute)).padStart(3, "0")}.cpuprofile`), JSON.stringify(p.profile));
		}
	} catch (e) {
		log("harness: " + e.message);
	}
}
log(`done: ${godotRows} PerfLog rows`);
ws.close();
stop();
process.exit(0);
