// What holds the page's memory, asked of a running Chrome (tools/perf/web_run.mjs prints nothing of its port:
// `ps` shows --remote-debugging-port): the live AudioBuffers (Web Audio: Godot's web build keeps a sample per
// AudioStreamWAV it played), ArrayBuffers and WebAssembly memories, by count and MB, after a garbage collection.
// Usage: node tools/perf/probe.mjs PORT
const port = process.argv[2];
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
const sizes = {
	AudioBuffer: "(b) => b.length * b.numberOfChannels * 4",
	ArrayBuffer: "(b) => b.byteLength",
	"WebAssembly.Memory": "(m) => m.buffer.byteLength",
};
const out = { time: new Date().toISOString() };
for (const [name, size] of Object.entries(sizes)) {
	const proto = await cdp("Runtime.evaluate", { expression: `${name}.prototype`, objectGroup: "probe" });
	const objs = await cdp("Runtime.queryObjects", { prototypeObjectId: proto.result.objectId, objectGroup: "probe" });
	const r = await cdp("Runtime.callFunctionOn", { objectId: objs.objects.objectId, returnByValue: true,
		functionDeclaration: `function () { const f = ${size}; const s = this.map(f).sort((a, b) => b - a);
			return { count: s.length, mb: s.reduce((a, b) => a + b, 0) / 1048576, biggest_mb: s.slice(0, 8).map((x) => +(x / 1048576).toFixed(1)) }; }` });
	out[name] = r.result.value;
}
const m = Object.fromEntries((await cdp("Performance.getMetrics")).metrics.map((x) => [x.name, x.value]));
out.JSHeapUsedMB = +(m.JSHeapUsedSize / 1048576).toFixed(1);
await cdp("Runtime.releaseObjectGroup", { objectGroup: "probe" });
console.log(JSON.stringify(out));
ws.close();
