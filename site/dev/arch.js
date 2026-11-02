// The architecture map (dev/<lang>/architecture.html): window.ARCH comes from tools/arch_page.py
// (tools/arch_data.py with every source reference resolved to a GitHub line). Three levels on one
// page, addressed by the URL hash: #/ the system, #/c/<component> its parts, #/f/<flow> the steps
// of one flow. Plain SVG; drag to pan, the buttons or Ctrl + wheel / pinch to zoom.
"use strict";
(() => {
  const A = window.ARCH, W = A.words, NS = "http://www.w3.org/2000/svg";
  const root = document.getElementById("arch");
  const comps = Object.fromEntries(A.comps.map((c) => [c.id, c]));
  const flows = Object.fromEntries(A.flows.map((f) => [f.id, f]));
  const col = (layer) => (A.layers[layer] || A.layers.ext).color;
  const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]);
  const plain = (html) => { const d = document.createElement("div"); d.innerHTML = html; return d.textContent; };
  const el = (tag, attrs, parent, text) => {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    if (parent) parent.appendChild(e);
    return e;
  };
  const refs = (list) => (list || []).map((r) => `<a class="ref" href="${r.href}" target="_blank" rel="noopener">${esc(r.label)}</a>`).join(" ");
  const tag = (layer) => `<span class="layer-tag" style="--c:${col(layer)}">${esc((A.layers[layer] || A.layers.ext).name)}</span>`;

  root.innerHTML = `
    <div class="arch-bar">
      <div class="crumbs" role="navigation" aria-label="${esc(W.where)}"></div>
      <div class="arch-search">
        <input type="search" placeholder="${esc(W.search)}" aria-label="${esc(W.search)}" autocomplete="off">
        <ul class="hits" role="listbox" hidden></ul>
      </div>
    </div>
    <div class="stage-wrap">
      <svg class="stage" role="img"></svg>
      <div class="stage-foot">
        <p class="stage-hint"></p>
        <div class="zoom" role="group" aria-label="${esc(W.zoom)}">
          <button type="button" data-z="1.25" title="${esc(W.zoom_in)}" aria-label="${esc(W.zoom_in)}">+</button>
          <button type="button" data-z="0.8" title="${esc(W.zoom_out)}" aria-label="${esc(W.zoom_out)}">−</button>
          <button type="button" data-z="0" title="${esc(W.fit)}" aria-label="${esc(W.fit)}">⤢</button>
        </div>
      </div>
    </div>
    <div class="legend"></div>
    <div class="arch-body"></div>`;
  const svg = root.querySelector(".stage"), body = root.querySelector(".arch-body");
  const crumbs = root.querySelector(".crumbs"), hint = root.querySelector(".stage-hint");

  // --- pan and zoom: the viewBox moves, the picture stays sharp -------------------------------
  let box = { x: 0, y: 0, w: 100, h: 100 }, full = box, moved = false;
  const setBox = (b) => { box = b; svg.setAttribute("viewBox", `${b.x} ${b.y} ${b.w} ${b.h}`); };
  const zoom = (k, cx = box.x + box.w / 2, cy = box.y + box.h / 2) => {
    const w = Math.min(full.w * 1.5, Math.max(full.w / 6, box.w / k)), r = w / box.w;
    setBox({ x: cx - (cx - box.x) * r, y: cy - (cy - box.y) * r, w, h: box.h * r });
  };
  const toSvg = (e) => {  // a client point in viewBox units (the picture is centred: preserveAspectRatio meet)
    const r = svg.getBoundingClientRect(), s = Math.max(box.w / r.width, box.h / r.height);
    return [box.x + (e.clientX - r.left - (r.width - box.w / s) / 2) * s, box.y + (e.clientY - r.top - (r.height - box.h / s) / 2) * s, s];
  };
  root.querySelector(".zoom").addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (b) +b.dataset.z ? zoom(+b.dataset.z) : setBox(full);
  });
  svg.addEventListener("wheel", (e) => {  // a trackpad pinch arrives as Ctrl + wheel
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    const [x, y] = toSvg(e);
    zoom(Math.exp(-e.deltaY / 300), x, y);
  }, { passive: false });
  const touches = new Map();
  let drag = null;
  svg.addEventListener("pointerdown", (e) => {
    touches.set(e.pointerId, [e.clientX, e.clientY]);
    moved = false;
    drag = { x: e.clientX, y: e.clientY, b: box, d: null };
    if (touches.size === 2) {
      const [p, q] = [...touches.values()];
      drag.d = Math.hypot(p[0] - q[0], p[1] - q[1]);
    }
  });
  svg.addEventListener("pointermove", (e) => {
    if (!drag || !touches.has(e.pointerId)) return;
    touches.set(e.pointerId, [e.clientX, e.clientY]);
    const s = toSvg(e)[2];
    if (touches.size === 2 && drag.d) {
      const [p, q] = [...touches.values()], d = Math.hypot(p[0] - q[0], p[1] - q[1]);
      const [x, y] = toSvg({ clientX: (p[0] + q[0]) / 2, clientY: (p[1] + q[1]) / 2 });
      zoom(d / drag.d, x, y);
      drag.d = d;
      moved = true;
      return;
    }
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!moved && Math.hypot(dx, dy) < 6) return;
    if (!moved) svg.setPointerCapture(e.pointerId);
    moved = true;
    setBox({ ...drag.b, x: drag.b.x - dx * s, y: drag.b.y - dy * s });
  });
  const up = (e) => { touches.delete(e.pointerId); if (!touches.size) drag = null; };
  svg.addEventListener("pointerup", up);
  svg.addEventListener("pointercancel", up);
  svg.addEventListener("click", (e) => { if (moved) { e.stopPropagation(); e.preventDefault(); } }, true);

  // --- drawing ------------------------------------------------------------------------------
  function start(w, h, label) {
    svg.textContent = "";
    svg.setAttribute("aria-label", label);
    svg.style.aspectRatio = `${w} / ${h}`;
    svg.style.maxWidth = `${Math.round(w * 1.15)}px`;  // a small diagram is not blown up
    const defs = el("defs", {}, svg);
    for (const [id, c] of [["mk", "var(--muted)"], ["mkh", "var(--cyan)"]]) {
      const m = el("marker", { id, viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" }, defs);
      el("path", { d: "M0 0 L10 5 L0 10 z", style: `fill:${c}` }, m);
    }
    full = { x: 0, y: 0, w, h };
    setBox(full);
    const vw = Math.max(h * 0.8, Math.min(w, 620));
    if (svg.getBoundingClientRect().width < 600 && vw < w) {  // a phone: a crop at a readable size, dragged sideways
      svg.style.aspectRatio = `${vw} / ${h}`;
      setBox({ x: 0, y: 0, w: vw, h });
    }
    svg.classList.remove("enter");
    void svg.getBoundingClientRect();
    svg.classList.add("enter");
  }
  function clip(n, tx, ty) {  // where the line from the box centre towards (tx, ty) leaves the box
    const cx = n.x + n.w / 2, cy = n.y + n.h / 2, dx = tx - cx, dy = ty - cy;
    const t = Math.min((n.w / 2 + 5) / Math.abs(dx || 1e-9), (n.h / 2 + 5) / Math.abs(dy || 1e-9));
    return [cx + dx * t, cy + dy * t];
  }
  function fit(t, w) {  // a text longer than its box is squeezed to fit
    if (t.getComputedTextLength() > w) { t.setAttribute("textLength", w); t.setAttribute("lengthAdjust", "spacingAndGlyphs"); }
    return t;
  }
  function label(g, x, y, text, above) {  // above: on a horizontal arrow the label sits over the line
    const lines = String(text).split("\n");
    const t = el("text", { x, y: above ? y - 7 - (lines.length - 1) * 14 : y - (lines.length - 1) * 7 + 4, "text-anchor": "middle", class: "lbl" }, g);
    lines.forEach((s, i) => el("tspan", { x, dy: i ? 14 : 0 }, t, s));
  }
  // nodes: {id, x, y, w, h, name, sub, layer, ghost, badge}; edges: {from, to, label, both, dash, d, lx, ly}
  function boxes(nodes, edges, onPick, hot) {
    const at = Object.fromEntries(nodes.map((n) => [n.id, n]));
    const gE = el("g", { class: "edges" }, svg), gN = el("g", { class: "nodes" }, svg), drawn = [];
    for (const e of edges) {
      const a = at[e.from], b = at[e.to];
      const g = el("g", { class: "edge" + (e.dash ? " dash" : "") }, gE);
      let d = e.d, lx = e.lx, ly = e.ly, flat = false;
      if (!d) {
        const [x1, y1] = clip(a, b.x + b.w / 2, b.y + b.h / 2), [x2, y2] = clip(b, a.x + a.w / 2, a.y + a.h / 2);
        d = `M${x1} ${y1} L${x2} ${y2}`;
        flat = Math.abs(y1 - y2) < 1;
        if (lx == null) { lx = (x1 + x2) / 2; ly = (y1 + y2) / 2; }
      }
      const p = el("path", { d, "marker-end": "url(#mk)" }, g);
      if (e.both) p.setAttribute("marker-start", "url(#mk)");
      if (e.label) label(g, lx, ly, e.label, flat);
      el("title", {}, g, `${a.name} → ${b.name}: ${String(e.label || "").replace(/\n/g, " ")}`);
      drawn.push({ g, p, e });
    }
    const light = (id) => {
      for (const { g, p, e } of drawn) {
        const on = id && (e.from === id || e.to === id);
        g.classList.toggle("hot", !!on);
        g.classList.toggle("dim", !!id && !on);
        p.setAttribute("marker-end", on ? "url(#mkh)" : "url(#mk)");
        if (e.both) p.setAttribute("marker-start", on ? "url(#mkh)" : "url(#mk)");
      }
      for (const n of nodes) n.g.classList.toggle("sel", n.id === id);
    };
    for (const n of nodes) {
      const g = n.g = el("g", { class: "node" + (n.ghost ? " ghost" : ""), tabindex: 0, role: "link", style: `--c:${col(n.layer)}`, "data-id": n.id }, gN);
      el("rect", { x: n.x, y: n.y, width: n.w, height: n.h, rx: 9 }, g);
      el("rect", { x: n.x, y: n.y, width: 5, height: n.h, rx: 2, class: "bar" }, g);
      fit(el("text", { x: n.x + 16, y: n.y + (n.sub ? n.h / 2 - 3 : n.h / 2 + 5), class: "nm" }, g, n.name), n.w - 26);
      if (n.sub) fit(el("text", { x: n.x + 16, y: n.y + n.h / 2 + 16, class: "sub" }, g, n.sub), n.w - 26);
      if (n.badge) el("text", { x: n.x + n.w - 10, y: n.y + 17, class: "badge-n", "text-anchor": "end" }, g, n.badge);
      el("title", {}, g, n.tip || n.name);
      g.addEventListener("mouseenter", () => light(n.id));
      g.addEventListener("mouseleave", () => light(hot || null));
      g.addEventListener("focus", () => light(n.id));
      g.addEventListener("click", () => onPick(n));
      g.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onPick(n); } });
    }
    light(hot || null);
    return light;
  }
  function frame(nodes, pad = 30) {
    const w = Math.max(...nodes.map((n) => n.x + n.w)) + pad, h = Math.max(...nodes.map((n) => n.y + n.h)) + pad;
    return [w, h];
  }

  // --- the three levels -----------------------------------------------------------------------
  function crumb(items) {
    crumbs.innerHTML = items.map(([t, href], i) => (i < items.length - 1 ? `<a href="${href}">${esc(t)}</a><span class="sep">›</span>` : `<b>${esc(t)}</b>`)).join("");
  }
  function legend(kinds) {
    const layers = kinds.map((k) => `<span class="lg" style="--c:${col(k)}"><i></i>${esc(A.layers[k].name)}</span>`).join("");
    root.querySelector(".legend").innerHTML = layers +
      `<span class="lg line"><svg width="34" height="10"><path d="M2 5 H30" /></svg>${esc(W.runtime)}</span>` +
      `<span class="lg line dash"><svg width="34" height="10"><path d="M2 5 H30" /></svg>${esc(W.buildtime)}</span>`;
  }
  const flowCard = (f) => `<a class="flow-card" href="#/f/${f.id}" style="--c:${col(comps[f.home].layer)}"><b>${esc(f.title)}</b><span>${f.short}</span><small>${f.steps.length} ${esc(W.steps)}</small></a>`;
  const chip = (id) => `<a class="chip" href="#/c/${id}" style="--c:${col(comps[id].layer)}">${esc(comps[id].name)}</a>`;

  function showSystem() {
    crumb([[W.system, "#/"]]);
    const nodes = A.comps.map((c) => ({ ...c, w: c.w || 215, h: c.h || 74, tip: plain(c.short) }));
    const [w, h] = frame(nodes, 50);
    start(w, h, W.system);
    boxes(nodes, A.arrows, (n) => go(`#/c/${n.id}`));
    hint.textContent = W.hint_system;
    legend([...new Set(A.comps.map((c) => c.layer))]);
    const groups = [...new Set(A.comps.map((c) => c.layer))];
    body.innerHTML = `<section class="intro">${A.system.text}</section>
      <h2>${esc(W.components)}</h2>` + groups.map((k) => `<h3 class="group" style="--c:${col(k)}">${esc(A.layers[k].name)}</h3><div class="cards">` +
        A.comps.filter((c) => c.layer === k).map((c) => `<a class="comp-card" href="#/c/${c.id}" style="--c:${col(c.layer)}"><b>${esc(c.name)}</b><code>${esc(c.sub || "")}</code><span>${c.short}</span><small>${c.parts.length} ${esc(W.parts)} · ${c.flows.length} ${esc(W.flows_n)}</small></a>`).join("") + "</div>").join("") +
      `<h2>${esc(W.flows)}</h2><div class="cards flows">${A.flows.map(flowCard).join("")}</div>`;
  }

  function showComp(c, pick) {
    crumb([[W.system, "#/"], [c.name, `#/c/${c.id}`]]);
    const GX = c.gx || 300, GY = c.gy || 116, BW = c.bw || 214, BH = 66;
    const nodes = c.parts.map((p) => ({
      ...p, x: 24 + p.x * GX, y: 24 + p.y * GY, w: (p.span || 1) * BW + ((p.span || 1) - 1) * (GX - BW), h: BH,
      layer: p.ext ? comps[p.ext].layer : c.layer, ghost: !!p.ext, tip: plain(p.text || p.name),
    }));
    const [w, h] = frame(nodes, 24);
    start(w, h, c.name);
    let light = null;
    const pickPart = (n) => {
      if (n.ext) return go(`#/c/${n.ext}`);
      light(n.id);
      const card = document.getElementById("part-" + n.id);
      if (card) { card.scrollIntoView({ behavior: "smooth", block: "nearest" }); card.classList.remove("flash"); void card.offsetWidth; card.classList.add("flash"); }
      history.replaceState(null, "", `#/c/${c.id}/${n.id}`);
    };
    light = boxes(nodes, c.arrows, pickPart, pick);
    hint.textContent = W.hint_comp;
    legend([...new Set([c.layer, ...nodes.map((n) => n.layer)])]);
    const near = [...new Set(A.arrows.filter((a) => a.from === c.id || a.to === c.id).map((a) => (a.from === c.id ? a.to : a.from)))];
    const dl = (rows) => `<dl class="facts">${rows.map(([t, d]) => `<dt>${t}</dt><dd>${d}</dd>`).join("")}</dl>`;
    body.innerHTML = `<section class="comp-head" style="--c:${col(c.layer)}">${tag(c.layer)}<h2>${esc(c.name)}</h2><p class="lead">${c.short}</p>${c.text || ""}
        ${near.length ? `<p class="near">${esc(W.talks_to)} ${near.map(chip).join(" ")}</p>` : ""}</section>
      ${c.flows.length ? `<h3>${esc(W.flows)}</h3><div class="cards flows">${c.flows.map((id) => flowCard(flows[id])).join("")}</div>` : ""}
      <h3>${esc(W.parts)}</h3><div class="cards parts">${c.parts.filter((p) => !p.ext).map((p) => `<article class="part-card" id="part-${p.id}" style="--c:${col(c.layer)}"><b>${esc(p.name)}</b>${p.sub ? `<code>${esc(p.sub)}</code>` : ""}<p>${p.text || ""}</p>${p.files && p.files.length ? `<p class="files">${refs(p.files)}</p>` : ""}</article>`).join("")}</div>
      ${c.data && c.data.length ? `<h3>${esc(W.data)}</h3>${dl(c.data)}` : ""}
      ${c.protocol && c.protocol.length ? `<h3>${esc(W.protocol)}</h3>${dl(c.protocol)}` : ""}`;
    if (pick) setTimeout(() => pickPart(nodes.find((n) => n.id === pick) || {}), 50);
  }

  function showFlow(f, pick) {
    const home = comps[f.home];
    crumb([[W.system, "#/"], [home.name, `#/c/${home.id}`], [f.title, `#/f/${f.id}`]]);
    const LW = 200, top = 22, HH = 54, SY = 70, y0 = top + HH + 44;
    const lanes = f.lanes.map((l, i) => ({ ...l, x: 20 + i * LW, cx: 20 + i * LW + LW / 2 }));
    const at = Object.fromEntries(lanes.map((l) => [l.id, l]));
    const w = 40 + lanes.length * LW, h = y0 + f.steps.length * SY + 10;
    start(w, h, f.title);
    for (const l of lanes) {
      const g = el("g", { class: "lane" + (l.comp ? " link" : ""), style: `--c:${col(l.layer)}`, tabindex: l.comp ? 0 : -1 }, svg);
      el("line", { x1: l.cx, y1: top + HH, x2: l.cx, y2: h - 6, class: "life" }, g);
      el("rect", { x: l.x + 10, y: top, width: LW - 20, height: HH, rx: 9 }, g);
      fit(el("text", { x: l.cx, y: top + (l.sub ? 23 : 32), "text-anchor": "middle", class: "nm" }, g, l.name), LW - 36);
      if (l.sub) fit(el("text", { x: l.cx, y: top + 41, "text-anchor": "middle", class: "sub" }, g, l.sub), LW - 36);
      if (l.comp && l.comp !== f.home) g.addEventListener("click", () => go(`#/c/${l.comp}`));
    }
    const gs = f.steps.map((s, i) => {
      const y = y0 + i * SY, a = at[s.from], b = at[s.to];
      const g = el("g", { class: "step", tabindex: 0, role: "button", "data-i": i }, svg);
      el("rect", { x: 0, y: y - 36, width: w, height: SY, class: "hit" }, g);
      if (a === b) {
        el("path", { d: `M${a.cx} ${y - 8} h46 v18 h-40`, class: "arrow", "marker-end": "url(#mk)" }, g);
        el("text", { x: a.cx + 56, y: y + 5, class: "lbl", "text-anchor": "start" }, g, s.label);
      } else {
        const dir = Math.sign(b.cx - a.cx);
        el("path", { d: `M${a.cx + dir * 6} ${y} L${b.cx - dir * 8} ${y}`, class: "arrow", "marker-end": "url(#mk)" }, g);
        el("text", { x: (a.cx + b.cx) / 2, y: y - 10, class: "lbl", "text-anchor": "middle" }, g, s.label);
      }
      el("circle", { cx: a.cx, cy: y, r: 11, class: "num" }, g);
      el("text", { x: a.cx, y: y + 4, class: "num-t", "text-anchor": "middle" }, g, i + 1);
      el("title", {}, g, plain(s.text));
      const pickStep = () => select(i, true);
      g.addEventListener("click", pickStep);
      g.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pickStep(); } });
      return g;
    });
    hint.textContent = W.hint_flow;
    legend([...new Set(lanes.map((l) => l.layer))]);
    body.innerHTML = `<section class="comp-head" style="--c:${col(home.layer)}">${tag(home.layer)}<h2>${esc(f.title)}</h2><p class="lead">${f.short}</p>
        <p class="near">${esc(W.takes_part)} ${[...new Set(f.lanes.map((l) => l.comp).filter(Boolean))].map(chip).join(" ")}</p></section>
      <ol class="flow-steps">${f.steps.map((s, i) => `<li id="step-${i}" data-i="${i}"><div class="who"><span style="--c:${col(at[s.from].layer)}">${esc(at[s.from].name)}</span>${s.from !== s.to ? ` → <span style="--c:${col(at[s.to].layer)}">${esc(at[s.to].name)}</span>` : ""}</div><b>${esc(s.label)}</b><p>${s.text}</p>${s.refs && s.refs.length ? `<p class="files">${refs(s.refs)}</p>` : ""}</li>`).join("")}</ol>
      ${f.more ? `<div class="more-flow">${f.more}</div>` : ""}`;
    const items = body.querySelectorAll(".flow-steps li");
    function select(i, scroll) {
      gs.forEach((g, k) => g.classList.toggle("sel", k === i));
      items.forEach((li, k) => li.classList.toggle("sel", k === i));
      gs.forEach((g, k) => g.querySelector(".arrow").setAttribute("marker-end", k === i ? "url(#mkh)" : "url(#mk)"));
      if (scroll && items[i]) items[i].scrollIntoView({ behavior: "smooth", block: "nearest" });
      history.replaceState(null, "", `#/f/${f.id}/${i + 1}`);
    }
    items.forEach((li) => li.addEventListener("click", (e) => { if (!e.target.closest("a")) select(+li.dataset.i, false); }));
    if (pick) setTimeout(() => select(pick - 1, true), 50);
  }

  // --- search -----------------------------------------------------------------------------------
  const index = [];
  for (const c of A.comps) {
    index.push({ kind: W.k_comp, title: c.name, text: plain(`${c.name} ${c.sub || ""} ${c.short} ${c.text || ""}`), href: `#/c/${c.id}`, layer: c.layer });
    for (const p of c.parts.filter((p) => !p.ext))
      index.push({ kind: c.name, title: p.name, text: plain(`${p.name} ${p.sub || ""} ${p.text || ""} ${(p.files || []).map((r) => r.label).join(" ")}`), href: `#/c/${c.id}/${p.id}`, layer: c.layer });
  }
  for (const f of A.flows) {
    index.push({ kind: W.k_flow, title: f.title, text: plain(`${f.title} ${f.short}`), href: `#/f/${f.id}`, layer: comps[f.home].layer });
    f.steps.forEach((s, i) => index.push({ kind: f.title, title: `${i + 1}. ${s.label}`, text: plain(`${s.label} ${s.text} ${(s.refs || []).map((r) => r.label).join(" ")}`), href: `#/f/${f.id}/${i + 1}`, layer: comps[f.home].layer }));
  }
  for (const it of index) it.low = (it.title + " " + it.text).toLowerCase();
  const input = root.querySelector(".arch-search input"), hits = root.querySelector(".hits");
  let found = [], cur = 0;
  function showHits() {
    hits.innerHTML = found.length ? found.map((it, i) => `<li role="option"${i === cur ? ' aria-selected="true"' : ""}><a href="${it.href}" style="--c:${col(it.layer)}"><b>${esc(it.title)}</b><small>${esc(it.kind)}</small></a></li>`).join("")
      : `<li class="none">${esc(W.nothing)}</li>`;
    hits.hidden = false;
  }
  input.addEventListener("input", () => {
    const words = input.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) { hits.hidden = true; return; }
    found = index.filter((it) => words.every((w) => it.low.includes(w)))
      .sort((a, b) => (b.title.toLowerCase().includes(words[0]) - a.title.toLowerCase().includes(words[0]))).slice(0, 14);
    cur = 0;
    showHits();
  });
  input.addEventListener("keydown", (e) => {
    if (hits.hidden || !found.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); cur = (cur + (e.key === "ArrowDown" ? 1 : found.length - 1)) % found.length; showHits(); }
    if (e.key === "Enter") { e.preventDefault(); go(found[cur].href); }
    if (e.key === "Escape") hits.hidden = true;
  });
  hits.addEventListener("click", (e) => { const a = e.target.closest("a"); if (a) { e.preventDefault(); go(a.getAttribute("href")); } });
  document.addEventListener("click", (e) => { if (!e.target.closest(".arch-search")) hits.hidden = true; });

  // --- routing --------------------------------------------------------------------------------
  function go(href) {
    hits.hidden = true;
    input.blur();
    if (location.hash === href) route(); else location.hash = href;
  }
  function route() {
    const [kind, id, sub] = location.hash.replace(/^#\/?/, "").split("/");
    if (kind === "c" && comps[id]) showComp(comps[id], sub);
    else if (kind === "f" && flows[id]) showFlow(flows[id], +sub || 0);
    else showSystem();
    document.title = `${crumbs.textContent.split("›").pop().trim()} — ${A.doc_title}`;
    if (kind && (comps[id] || flows[id])) root.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  addEventListener("hashchange", route);
  route();
})();
