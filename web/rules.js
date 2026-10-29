// The Classic HS rules engine in the browser (rust/wasm): loads rules.wasm next to
// index.html and exposes window.ClassicRules.call_json(request) -> reply (JSON
// strings, synchronous). Godot reaches it through JavaScriptBridge (game/rules.gd)
// and waits for ClassicRules.ready; a failed load leaves the reason in .error.
// The game's own bot thinks in a Web Worker with its own instance of the module, so the
// page never stops while it thinks: think_start(request) -> id, think_result(id) -> the
// reply, or "" while it still thinks (game/bot_brain.gd).
(function () {
  const api = { ready: false, error: "" };
  const enc = new TextEncoder(), dec = new TextDecoder();
  const imports = { env: { chs_now_ms: () => performance.now() } };
  let ex = null;
  api.call_json = function (s) {
    if (!ex) return JSON.stringify({ ok: false, error: "rules not loaded: " + (api.error || "loading") });
    try {
      const b = enc.encode(String(s));
      const p = ex.alloc(b.length);
      new Uint8Array(ex.memory.buffer, p, b.length).set(b);
      ex.call(p, b.length);
      ex.dealloc(p, b.length);
      return dec.decode(new Uint8Array(ex.memory.buffer, ex.out_ptr(), ex.out_len()));
    } catch (e) {  // a panic in the engine traps (wasm aborts): its state can't be trusted any more
      ex = null;
      api.ready = false;
      api.error = "engine crashed: " + e;
      return JSON.stringify({ ok: false, error: "internal error" });
    }
  };

  // --- the bot's worker ---
  const WORKER = `
    const enc = new TextEncoder(), dec = new TextDecoder();
    let ex = null, queue = [];
    function run(m) {
      let out;
      try {
        const b = enc.encode(m.req);
        const p = ex.alloc(b.length);
        new Uint8Array(ex.memory.buffer, p, b.length).set(b);
        ex.think(p, b.length);
        ex.dealloc(p, b.length);
        out = dec.decode(new Uint8Array(ex.memory.buffer, ex.out_ptr(), ex.out_len()));
      } catch (e) {  // a trap: a fresh instance next time
        out = JSON.stringify({ ok: false, error: "the bot crashed: " + e });
        ex = null;
        WebAssembly.instantiate(self.mod, { env: { chs_now_ms: () => performance.now() } }).then((i) => { ex = i.exports; });
      }
      postMessage({ id: m.id, out: out });
    }
    onmessage = (e) => {
      if (e.data.module) {
        self.mod = e.data.module;
        WebAssembly.instantiate(self.mod, { env: { chs_now_ms: () => performance.now() } })
          .then((i) => { ex = i.exports; queue.splice(0).forEach(run); });
        return;
      }
      if (ex) run(e.data); else queue.push(e.data);
    };`;
  let worker = null, nextId = 0;
  const results = {};
  api.think_start = function (req) {
    const id = ++nextId;
    if (!worker) {
      results[id] = JSON.stringify({ ok: false, error: "no worker" });
      return id;
    }
    worker.postMessage({ id: id, req: String(req) });
    return id;
  };
  api.think_result = function (id) {
    const r = results[id];
    if (r === undefined) return "";
    delete results[id];
    return r;
  };

  fetch("rules.wasm")
    .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject("rules.wasm: HTTP " + r.status)))
    .then((b) => WebAssembly.compile(b))
    .then((mod) => {
      try {
        worker = new Worker(URL.createObjectURL(new Blob([WORKER], { type: "text/javascript" })));
        worker.onmessage = (e) => { results[e.data.id] = e.data.out; };
        worker.postMessage({ module: mod });
      } catch (e) {
        worker = null;  // (no workers: the bot falls back to thinking on the page)
      }
      return WebAssembly.instantiate(mod, imports);
    })
    .then((inst) => { ex = inst.exports; api.ready = true; })
    .catch((e) => { api.error = String(e); });
  api.has_worker = () => worker !== null;
  window.ClassicRules = api;
})();
