// The Classic HS rules engine in the browser (rust/wasm): loads rules.wasm next to
// index.html and exposes window.ClassicRules.call_json(request) -> reply (JSON
// strings, synchronous). Godot reaches it through JavaScriptBridge (game/rules.gd)
// and waits for ClassicRules.ready; a failed load leaves the reason in .error.
// The game's own bot thinks in a Web Worker with its own instance of the module, so the
// page never stops while it thinks: think_start(request) -> id, think_result(id) -> the
// reply, or "" while it still thinks (game/bot_brain.gd). The same module decodes the game's .opus
// audio: decode_opus (game/opus.gd).
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

  // --- .opus audio (game/opus.gd), in instances of the module of their own, so a crash or the memory
  // of a long track never touches the engine's. decode_opus(base64 of the file) -> {channels, pcm: the
  // 16-bit samples, interleaved, an ArrayBuffer} at once, or null (the reason in .opus_error); a long
  // track in a Web Worker: opus_start(base64) -> id, opus_done(id), opus_take(id) -> the same.
  function opusDecode(x, b64) {  // (the worker's too: WORKER takes its source)
    const s = atob(String(b64));
    const p = x.alloc(s.length);
    const m = new Uint8Array(x.memory.buffer, p, s.length);
    for (let i = 0; i < s.length; i++) m[i] = s.charCodeAt(i);
    const ch = x.opus_decode(p, s.length);
    x.dealloc(p, s.length);
    if (!ch) return { error: new TextDecoder().decode(new Uint8Array(x.memory.buffer, x.out_ptr(), x.out_len())) };
    return { channels: ch, pcm: new Uint8Array(x.memory.buffer, x.pcm_ptr(), x.pcm_len()).slice().buffer };
  }
  let op = null, opusModule = null, opusWorker = null;
  const opusJobs = {};
  api.opus_error = "";
  function decodeHere(b64) {
    if (!op) return { error: "not loaded" };
    try {
      return opusDecode(op, b64);
    } catch (e) {  // a trap: a fresh instance for the next file
      op = null;
      WebAssembly.instantiate(opusModule, imports).then((i) => { op = i.exports; });
      return { error: "crashed: " + e };
    }
  }
  function opusOut(r) {
    if (r.error === undefined) return r;
    api.opus_error = r.error;
    return null;
  }
  api.decode_opus = (b64) => opusOut(decodeHere(b64));
  api.opus_start = function (b64) {
    const id = ++nextId;
    if (opusWorker) opusWorker.postMessage({ id: id, b64: String(b64) });
    else opusJobs[id] = decodeHere(b64);
    return id;
  };
  api.opus_done = (id) => opusJobs[id] !== undefined;
  api.opus_take = function (id) {
    const r = opusJobs[id] || { error: "no such job" };
    delete opusJobs[id];
    return opusOut(r);
  };

  // --- the bot's worker ---
  const WORKER = `
    const enc = new TextEncoder(), dec = new TextDecoder();
    let ex = null, queue = [];
    ${opusDecode.toString()}
    function run(m) {
      let out;
      try {
        if (m.b64 !== undefined) {  // an .opus file (its samples move to the page, not copied)
          out = opusDecode(ex, m.b64);
          postMessage({ id: m.id, out: out }, out.pcm ? [out.pcm] : []);
          return;
        }
        const b = enc.encode(m.req);
        const p = ex.alloc(b.length);
        new Uint8Array(ex.memory.buffer, p, b.length).set(b);
        ex.think(p, b.length);
        ex.dealloc(p, b.length);
        out = dec.decode(new Uint8Array(ex.memory.buffer, ex.out_ptr(), ex.out_len()));
      } catch (e) {  // a trap: a fresh instance next time
        out = m.b64 !== undefined ? { error: "crashed: " + e } : JSON.stringify({ ok: false, error: "the bot crashed: " + e });
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
        const url = URL.createObjectURL(new Blob([WORKER], { type: "text/javascript" }));
        worker = new Worker(url);
        worker.onmessage = (e) => { results[e.data.id] = e.data.out; };
        worker.postMessage({ module: mod });
        opusWorker = new Worker(url);  // (one of its own: the music never waits for the bot)
        opusWorker.onmessage = (e) => { opusJobs[e.data.id] = e.data.out; };
        opusWorker.postMessage({ module: mod });
      } catch (e) {
        worker = opusWorker = null;  // (no workers: the bot thinks and the music decodes on the page)
      }
      opusModule = mod;
      return Promise.all([WebAssembly.instantiate(mod, imports), WebAssembly.instantiate(mod, imports)]);
    })
    .then(([inst, opus]) => { ex = inst.exports; op = opus.exports; api.ready = true; })
    .catch((e) => { api.error = String(e); });
  api.has_worker = () => worker !== null;
  window.ClassicRules = api;
})();
