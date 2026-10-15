// The Classic HS rules engine in the browser (rust/wasm): loads rules.wasm next to
// index.html and exposes window.ClassicRules.call_json(request) -> reply (JSON
// strings, synchronous). Godot reaches it through JavaScriptBridge (game/rules.gd)
// and waits for ClassicRules.ready; a failed load leaves the reason in .error.
(function () {
  const api = { ready: false, error: "" };
  const enc = new TextEncoder(), dec = new TextDecoder();
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
  fetch("rules.wasm")
    .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject("rules.wasm: HTTP " + r.status)))
    .then((b) => WebAssembly.instantiate(b, {}))
    .then((r) => { ex = r.instance.exports; api.ready = true; })
    .catch((e) => { api.error = String(e); });
  window.ClassicRules = api;
})();
