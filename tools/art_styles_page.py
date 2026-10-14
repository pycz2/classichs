#!/usr/bin/env python3
"""Puts the art styles side by side in one local page: for each card of
tools/gen_art_styles.py — the original art (art/original, local only), the current
generated art (art/cards) and every new style (build/art_styles/<style>).
Result: build/art_styles/page/index.html (open it in a browser; the images are copied next to it).
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_art_styles import CARDS, OUT, ROOT, STYLES  # noqa: E402

PAGE = os.path.join(OUT, "page")
SETS = [("original", "Оригинал (Blizzard)", os.path.join(ROOT, "art", "original")),
        ("generated", "Сейчас в игре", os.path.join(ROOT, "art", "cards"))]
SETS += [(s, {"cartoon": "Мультяшный 2D", "simple": "Простой рисованный", "photo": "Фото, мало деталей"}.get(s, s),
          os.path.join(OUT, s)) for s in STYLES]


def main():
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = {c["id"]: c for c in (data if isinstance(data, list) else data.values())}
    os.makedirs(os.path.join(PAGE, "img"), exist_ok=True)
    rows = []
    for cid in CARDS:
        c = cards[cid]
        cells = []
        for key, _label, folder in SETS:
            src = os.path.join(folder, cid + ".jpg")
            if os.path.exists(src):
                dst = f"img/{key}_{cid}.jpg"
                shutil.copy(src, os.path.join(PAGE, dst))
                cells.append(dst)
            else:
                cells.append("")
        rows.append({"id": cid, "name": c["name"].get("ruRU") or c["name"]["enUS"], "en": c["name"]["enUS"],
                     "type": c["type"], "cells": cells})
    sets = [{"key": k, "label": l} for k, l, _f in SETS]
    html = PAGE_HTML.replace("__ROWS__", json.dumps(rows, ensure_ascii=False)).replace("__SETS__", json.dumps(sets, ensure_ascii=False))
    open(os.path.join(PAGE, "index.html"), "w").write(html)
    print(os.path.join(PAGE, "index.html"))


PAGE_HTML = r'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Стили артов</title>
<style>
:root { --bg:#17110d; --panel:#241a13; --line:#4a3a28; --text:#f4ead5; --muted:#b9a88a; --gold:#f2c230; }
@media (prefers-color-scheme: light) { :root { --bg:#f6efe2; --panel:#fffaf0; --line:#e0d2b8; --text:#2a1f17; --muted:#6b5a44; --gold:#a8741a; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:15px/1.4 -apple-system, "Segoe UI", Roboto, sans-serif; }
header { position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--line); padding:12px 16px; display:flex; flex-wrap:wrap; gap:10px; align-items:center; }
h1 { margin:0 12px 0 0; font-size:20px; color:var(--gold); }
button { font:inherit; border:1px solid var(--line); background:var(--panel); color:var(--text); border-radius:8px; padding:6px 12px; cursor:pointer; }
button.on { border-color:var(--gold); color:var(--gold); }
label { color:var(--muted); font-size:14px; }
main { padding:12px 16px 60px; }
.grid { display:grid; gap:10px; align-items:start; }
.head { position:sticky; top:58px; z-index:3; background:var(--bg); padding:6px 0; font-weight:600; color:var(--gold); text-align:center; }
.name { align-self:center; }
.name b { display:block; font-size:16px; }
.name span { color:var(--muted); font-size:12px; }
figure { margin:0; background:var(--panel); border:1px solid var(--line); border-radius:10px; overflow:hidden; aspect-ratio:1; cursor:zoom-in; }
figure img { width:100%; height:100%; object-fit:cover; display:block; }
figure.none { display:grid; place-items:center; color:var(--muted); font-size:13px; cursor:default; }
.style-block h2 { color:var(--gold); font-size:18px; margin:18px 0 8px; }
.cards { display:grid; grid-template-columns:repeat(auto-fill, minmax(160px, 1fr)); gap:10px; }
.cards figcaption { padding:6px 8px; font-size:13px; }
.cards figure { aspect-ratio:auto; }
.cards figure img { aspect-ratio:1; height:auto; }
#box { position:fixed; inset:0; z-index:20; background:rgba(0,0,0,.92); display:none; align-items:center; justify-content:center; flex-direction:column; gap:10px; cursor:zoom-out; }
#box.on { display:flex; }
#box img { max-width:92vw; max-height:84vh; border-radius:12px; }
#box p { color:#f4ead5; margin:0; }
.hint { color:var(--muted); font-size:13px; }
</style>
</head>
<body>
<header>
  <h1>Стили артов</h1>
  <button id="byCard" class="on">По картам</button>
  <button id="byStyle">По стилям</button>
  <label><input type="range" id="zoom" min="110" max="320" value="170"> размер</label>
  <span class="hint">Щелчок — на весь экран; ← → — соседние; Esc — закрыть.</span>
</header>
<main id="main"></main>
<div id="box"><img alt=""><p></p></div>
<script>
const ROWS = __ROWS__, SETS = __SETS__;
let mode = "card", flat = [], at = 0;
const main = document.getElementById("main"), box = document.getElementById("box");
function fig(src, caption) {
  const f = document.createElement("figure");
  if (!src) { f.className = "none"; f.textContent = "нет"; return f; }
  const img = document.createElement("img"); img.src = src; img.alt = caption; img.loading = "lazy";
  f.append(img);
  const i = flat.push([src, caption]) - 1;
  f.onclick = () => open(i);
  return f;
}
function render() {
  main.innerHTML = ""; flat = [];
  const size = document.getElementById("zoom").value + "px";
  if (mode === "card") {
    const g = document.createElement("div"); g.className = "grid";
    g.style.gridTemplateColumns = `minmax(130px, 170px) repeat(${SETS.length}, ${size})`;
    g.append(document.createElement("div"));
    for (const s of SETS) { const h = document.createElement("div"); h.className = "head"; h.textContent = s.label; g.append(h); }
    for (const r of ROWS) {
      const n = document.createElement("div"); n.className = "name";
      n.innerHTML = "<b></b><span></span>"; n.querySelector("b").textContent = r.name; n.querySelector("span").textContent = r.en + " · " + r.id;
      g.append(n);
      r.cells.forEach((src, k) => g.append(fig(src, `${r.name} — ${SETS[k].label}`)));
    }
    main.append(g);
  } else {
    SETS.forEach((s, k) => {
      const b = document.createElement("section"); b.className = "style-block";
      b.innerHTML = "<h2></h2><div class='cards'></div>"; b.querySelector("h2").textContent = s.label;
      b.querySelector(".cards").style.gridTemplateColumns = `repeat(auto-fill, minmax(${size}, 1fr))`;
      for (const r of ROWS) {
        const f = fig(r.cells[k], `${r.name} — ${s.label}`);
        const cap = document.createElement("figcaption"); cap.textContent = r.name; f.append(cap);
        b.querySelector(".cards").append(f);
      }
      main.append(b);
    });
  }
}
function open(i) { at = (i + flat.length) % flat.length; box.querySelector("img").src = flat[at][0]; box.querySelector("p").textContent = flat[at][1]; box.classList.add("on"); }
box.onclick = () => box.classList.remove("on");
document.addEventListener("keydown", (e) => {
  if (!box.classList.contains("on")) return;
  if (e.key === "Escape") box.classList.remove("on");
  if (e.key === "ArrowRight") open(at + 1);
  if (e.key === "ArrowLeft") open(at - 1);
});
document.getElementById("byCard").onclick = (e) => { mode = "card"; e.target.classList.add("on"); document.getElementById("byStyle").classList.remove("on"); render(); };
document.getElementById("byStyle").onclick = (e) => { mode = "style"; e.target.classList.add("on"); document.getElementById("byCard").classList.remove("on"); render(); };
document.getElementById("zoom").oninput = render;
render();
</script>
</body>
</html>
'''

if __name__ == "__main__":
    main()
