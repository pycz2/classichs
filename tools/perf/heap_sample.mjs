// Where the page's JavaScript heap grows: Chrome's sampling heap profiler over a while; what was allocated
// then and is still alive at the end, by the JavaScript stack that allocated it (after a GC).
// Usage: node tools/perf/heap_sample.mjs PORT SECONDS [OUT.json]
import fs from "node:fs";
const [port, secs = "120", out] = process.argv.slice(2);
const target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === "page");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((ok) => ws.addEventListener("open", ok));
let seq = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
	const m = JSON.parse(e.data);
	if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const cdp = (method, params = {}) => new Promise((ok, bad) => {
	const id = ++seq;
	pending.set(id, (m) => (m.error ? bad(new Error(method + ": " + m.error.message)) : ok(m.result)));
	ws.send(JSON.stringify({ id, method, params }));
});
await cdp("HeapProfiler.enable");
await cdp("HeapProfiler.collectGarbage");
await cdp("HeapProfiler.startSampling", { samplingInterval: 32768 });
await new Promise((ok) => setTimeout(ok, Number(secs) * 1000));
await cdp("HeapProfiler.collectGarbage");
const { profile } = await cdp("HeapProfiler.stopSampling");
if (out) fs.writeFileSync(out, JSON.stringify(profile));
// self size per node, with its stack (the frames above it)
const rows = [];
const walk = (n, stack) => {
	const f = n.callFrame;
	const here = `${f.functionName || "(anonymous)"} ${f.url.split("/").pop()}:${f.lineNumber + 1}`;
	const st = [here, ...stack];
	if (n.selfSize > 0) rows.push({ mb: n.selfSize / 1048576, stack: st.slice(0, 6).join(" <- ") });
	for (const c of n.children || []) walk(c, st);
};
walk(profile.head, []);
rows.sort((a, b) => b.mb - a.mb);
const total = rows.reduce((a, b) => a + b.mb, 0);
console.log(`still alive after ${secs} s, allocated meanwhile: ${total.toFixed(1)} MB`);
for (const r of rows.slice(0, 15)) console.log(`${r.mb.toFixed(1).padStart(7)} MB  ${r.stack}`);
ws.close();
