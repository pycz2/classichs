#!/usr/bin/env python3
"""Puts the art styles side by side in one local page: for each card of
tools/gen_art_styles.py — the original art (art/original, local only), the current
generated art (art/cards) and every new style (build/art_styles/<style>).
Result: build/art_styles/page/index.html (open it in a browser; the images are copied next to it).
With --all: every card that has a picture in any new style (e.g. after gen_art_styles.py --all).
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_art_styles import CARDS, OUT, ROOT, STYLES, prompt_for  # noqa: E402
import gen_card_art  # noqa: E402

PAGE = os.path.join(OUT, "page")
SETS = [("original", "Оригинал (Blizzard)", os.path.join(ROOT, "art", "original")),
        ("generated", "Сейчас в игре", os.path.join(ROOT, "art", "cards"))]
SETS += [(s, {"cartoon": "Мультяшный 2D", "simple": "Простой рисованный", "photo": "Фото, мало деталей"}.get(s, s),
          os.path.join(OUT, s)) for s in STYLES]


def main():
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = {c["id"]: c for c in (data if isinstance(data, list) else data.values())}
    os.makedirs(os.path.join(PAGE, "img"), exist_ok=True)
    ids = CARDS
    if "--all" in sys.argv:
        drawn = {f[:-4] for s in STYLES if os.path.isdir(os.path.join(OUT, s)) for f in os.listdir(os.path.join(OUT, s)) if f.endswith(".jpg")}
        ids = CARDS + sorted(drawn - set(CARDS))
    # The Codex prompt of each set (None: no prompt, e.g. the original art): the text is the same for every
    # card except its own line, so the page keeps one template per set (CARD marks the line) and each card's line.
    some = cards[ids[0]]
    line = lambda cid: f"- ID {cid}: {gen_card_art.describe(cards[cid])}"
    templates = [None, gen_card_art.prompt_for([some]).replace(line(some["id"]), "\x00CARD")]
    templates += [prompt_for(st, [some["id"]], cards).replace(line(some["id"]), "\x00CARD") for st in STYLES]
    rows = []
    for cid in ids:
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
                     "type": c["type"], "cls": c.get("cardClass") or "NEUTRAL", "rarity": c.get("rarity") or "NONE",
                     "cost": c.get("cost"), "cells": cells, "line": line(cid)})
    sets = [{"key": k, "label": l, "prompt": t} for (k, l, _f), t in zip(SETS, templates)]
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
.bar { position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--line); padding:10px 16px; display:flex; flex-wrap:wrap; gap:10px; align-items:center; }
#filters { padding:10px 16px 4px; display:flex; flex-direction:column; gap:6px; border-bottom:1px solid var(--line); }
#filters.off { display:none; }
.frow { display:flex; flex-wrap:wrap; gap:6px; align-items:center; }
.flabel { color:var(--muted); font-size:13px; width:92px; flex:none; }
.chips { display:flex; flex-wrap:wrap; gap:5px; }
.chip { font-size:13px; padding:3px 10px; border-radius:999px; }
.chip small { color:var(--muted); margin-left:4px; }
input[type=search], select { font:inherit; border:1px solid var(--line); background:var(--panel); color:var(--text); border-radius:8px; padding:6px 10px; }
input[type=search] { width:min(320px, 100%); }
.star { border:none; background:none; padding:0 4px 0 0; font-size:17px; color:var(--muted); line-height:1; }
.star.on { color:var(--gold); }
.meta { display:block; color:var(--muted); font-size:12px; }
.empty { color:var(--muted); padding:30px 0; text-align:center; }
h1 { margin:0 12px 0 0; font-size:20px; color:var(--gold); }
button { font:inherit; border:1px solid var(--line); background:var(--panel); color:var(--text); border-radius:8px; padding:6px 12px; cursor:pointer; }
button.on { border-color:var(--gold); color:var(--gold); }
label { color:var(--muted); font-size:14px; }
main { padding:12px 16px 60px; }
.grid { display:grid; gap:10px; align-items:start; }
.head { position:sticky; top:var(--hh, 58px); z-index:3; background:var(--bg); padding:6px 0; font-weight:600; color:var(--gold); text-align:center; }
.name { align-self:center; }
.name b { font-size:16px; }
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
.cell { display:flex; flex-direction:column; gap:4px; }
.pbtn { font-size:12px; padding:3px 8px; border-radius:6px; align-self:flex-start; }
.pbtn.todo { border-style:dashed; color:var(--muted); }
#pbox { position:fixed; inset:0; z-index:30; background:rgba(0,0,0,.75); display:none; align-items:center; justify-content:center; padding:20px; }
#pbox.on { display:flex; }
#pbox .card { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:16px 18px; max-width:860px; width:100%; max-height:88vh; display:flex; flex-direction:column; gap:10px; }
#pbox h3 { margin:0; color:var(--gold); font-size:17px; }
#pbox .note { color:var(--muted); font-size:13.5px; }
#pbox pre { margin:0; white-space:pre-wrap; overflow:auto; background:var(--bg); border:1px solid var(--line); border-radius:10px; padding:12px; font:13px/1.5 ui-monospace, Menlo, monospace; }
#pbox pre mark { background:color-mix(in srgb, var(--gold) 35%, transparent); color:inherit; border-radius:3px; }
#pbox .row { display:flex; gap:8px; justify-content:flex-end; }
#box .pbtn { margin-top:4px; }
</style>
</head>
<body>
<div class="bar" id="bar">
  <h1>Стили артов</h1>
  <button id="byCard" class="on">По картам</button>
  <button id="byStyle">По стилям</button>
  <input type="search" id="q" placeholder="Поиск: имя (рус./англ.) или ID">
  <select id="sort" title="Порядок">
    <option value="gen">Порядок генерации</option><option value="cost">По мане</option>
    <option value="name">По имени</option><option value="cls">По классу</option><option value="rarity">По редкости</option>
  </select>
  <label><input type="range" id="zoom" min="110" max="320" value="170"> размер</label>
  <button id="toggleF" class="on">Фильтры</button>
  <button id="reset">Сбросить</button>
  <span id="count" class="hint"></span>
</div>
<div id="filters">
  <div class="frow"><span class="flabel">Стили</span><div id="fSets" class="chips"></div></div>
  <div class="frow"><span class="flabel">Класс</span><div id="fCls" class="chips"></div></div>
  <div class="frow"><span class="flabel">Редкость</span><div id="fRar" class="chips"></div></div>
  <div class="frow"><span class="flabel">Мана</span><div id="fCost" class="chips"></div></div>
  <div class="frow"><span class="flabel">Тип</span><div id="fType" class="chips"></div></div>
  <div class="frow"><span class="flabel">Наличие</span><div id="fHave" class="chips"></div></div>
  <div class="frow"><span class="flabel">Отмеченные</span><button id="onlyPicked" class="chip"></button><button id="clearPicked" class="chip">Снять все отметки</button>
    <span class="hint">☆ у имени — отметить карту, потом «Только отмеченные» — сравнить только их.</span></div>
  <div class="hint">Внутри одной строки фильтра — «или», между строками — «и». Щелчок по картинке — на весь экран; ← → — соседние; Esc — закрыть; «Промпт» — по какому тексту нарисовано (или будет нарисовано).</div>
</div>
<main id="main"></main>
<div id="box"><img alt=""><p></p><button class="pbtn" id="boxPrompt">Промпт</button></div>
<div id="pbox"><div class="card"><h3></h3><div class="note"></div><pre></pre><div class="row"><button id="pcopy">Копировать</button><button id="pclose">Закрыть</button></div></div></div>
<script>
const ROWS = __ROWS__, SETS = __SETS__;
let mode = "card", flat = [], at = 0;
const CLS = {DRUID:"Друид", HUNTER:"Охотник", MAGE:"Маг", PALADIN:"Паладин", PRIEST:"Жрец", ROGUE:"Разбойник", SHAMAN:"Шаман",
  WARLOCK:"Чернокнижник", WARRIOR:"Воин", NEUTRAL:"Нейтральные", DREAM:"Сны", DEMONHUNTER:"Охотник на демонов"};
const RAR = {FREE:"Базовая", COMMON:"Обычная", RARE:"Редкая", EPIC:"Эпическая", LEGENDARY:"Легендарная", NONE:"Без редкости"};
const TYPE = {MINION:"Существо", SPELL:"Заклинание", WEAPON:"Оружие", HERO:"Герой", HERO_POWER:"Сила героя"};
const COSTS = ["0", "1", "2", "3", "4", "5", "6", "7", "8+", "—"];
const costKey = (r) => r.cost == null ? "—" : r.cost >= 8 ? "8+" : String(r.cost);
const order = (o) => (v) => { const i = Object.keys(o).indexOf(v); return i < 0 ? 99 : i; };
const F = {q: "", cls: new Set(), rar: new Set(), cost: new Set(), type: new Set(), have: "all", only: false,
  sets: new Set(SETS.map((_, k) => k)), picked: new Set()};
try { F.picked = new Set(JSON.parse(localStorage.getItem("artPicked") || "[]")); } catch (e) {}
const savePicked = () => { try { localStorage.setItem("artPicked", JSON.stringify([...F.picked])); } catch (e) {} };
const shownSets = () => [...F.sets].sort((a, b) => a - b);
function visible() {
  const q = F.q.trim().toLowerCase(), ks = shownSets();
  const out = ROWS.filter((r) => (!q || (r.name + " " + r.en + " " + r.id).toLowerCase().includes(q))
    && (!F.cls.size || F.cls.has(r.cls)) && (!F.rar.size || F.rar.has(r.rarity))
    && (!F.cost.size || F.cost.has(costKey(r))) && (!F.type.size || F.type.has(r.type))
    && (!F.only || F.picked.has(r.id))
    && (F.have === "all" || (F.have === "full") === ks.every((k) => r.cells[k])));
  const by = document.getElementById("sort").value, nm = (a, b) => a.name.localeCompare(b.name, "ru");
  const cost = (r) => r.cost == null ? 99 : r.cost;
  if (by === "cost") out.sort((a, b) => cost(a) - cost(b) || nm(a, b));
  if (by === "name") out.sort(nm);
  if (by === "cls") out.sort((a, b) => order(CLS)(a.cls) - order(CLS)(b.cls) || cost(a) - cost(b) || nm(a, b));
  if (by === "rarity") out.sort((a, b) => order(RAR)(a.rarity) - order(RAR)(b.rarity) || cost(a) - cost(b) || nm(a, b));
  return out;
}
function chips(id, labels, set, key) {
  const el = document.getElementById(id); el.innerHTML = "";
  const n = {}; for (const r of ROWS) n[key(r)] = (n[key(r)] || 0) + 1;
  for (const [v, l] of Object.entries(labels)) {
    if (!n[v]) continue;
    const b = document.createElement("button"); b.className = "chip" + (set.has(v) ? " on" : "");
    b.append(l); const sm = document.createElement("small"); sm.textContent = n[v]; b.append(sm);
    b.onclick = () => { set.has(v) ? set.delete(v) : set.add(v); b.classList.toggle("on"); render(); };
    el.append(b);
  }
}
function filters() {
  chips("fCls", CLS, F.cls, (r) => r.cls);
  chips("fRar", RAR, F.rar, (r) => r.rarity);
  chips("fCost", Object.fromEntries(COSTS.map((c) => [c, c === "—" ? "без цены" : c])), F.cost, costKey);
  chips("fType", TYPE, F.type, (r) => r.type);
  const fs = document.getElementById("fSets"); fs.innerHTML = "";
  SETS.forEach((s, k) => {
    const b = document.createElement("button"); b.className = "chip" + (F.sets.has(k) ? " on" : ""); b.textContent = s.label;
    b.onclick = () => { if (F.sets.has(k) && F.sets.size > 1) F.sets.delete(k); else F.sets.add(k); b.classList.toggle("on", F.sets.has(k)); render(); };
    fs.append(b);
  });
  const fh = document.getElementById("fHave"); fh.innerHTML = "";
  for (const [v, l] of [["all", "Все карты"], ["full", "Есть во всех выбранных стилях"], ["miss", "Где-то нет картинки"]]) {
    const b = document.createElement("button"); b.className = "chip" + (F.have === v ? " on" : ""); b.textContent = l;
    b.onclick = () => { F.have = v; fh.querySelectorAll(".chip").forEach((x) => x.classList.toggle("on", x === b)); render(); };
    fh.append(b);
  }
}
function star(r) {
  const b = document.createElement("button"); const on = F.picked.has(r.id);
  b.className = "star" + (on ? " on" : ""); b.textContent = on ? "★" : "☆"; b.title = "Отметить для сравнения";
  b.onclick = (e) => { e.stopPropagation(); F.picked.has(r.id) ? F.picked.delete(r.id) : F.picked.add(r.id); savePicked();
    if (F.only) render(); else { document.querySelectorAll(`.star[data-id="${r.id}"]`).forEach((x) => { const o = F.picked.has(r.id); x.classList.toggle("on", o); x.textContent = o ? "★" : "☆"; }); counts(); } };
  b.dataset.id = r.id;
  return b;
}
function counts(n) {
  if (n != null) document.getElementById("count").textContent = `Показано ${n} из ${ROWS.length}`;
  const op = document.getElementById("onlyPicked");
  op.textContent = `Только отмеченные (${F.picked.size})`; op.classList.toggle("on", F.only);
}
const main = document.getElementById("main"), box = document.getElementById("box");
function promptOf(r, k) {
  const t = SETS[k].prompt;
  return t ? t.replace("\u0000CARD", r.line) : null;
}
function showPrompt(r, k) {
  const p = promptOf(r, k), drawn = !!r.cells[k], pb = document.getElementById("pbox");
  pb.querySelector("h3").textContent = `${r.name} — ${SETS[k].label}`;
  pb.querySelector(".note").textContent = drawn
    ? "Картинка нарисована по этому промпту. Codex рисовал по 5 карт за раз; здесь — промпт с одной этой картой (её строка выделена)."
    : "Картинки ещё нет: она будет нарисована по этому промпту (python3 tools/gen_art_styles.py --styles " + SETS[k].key + " --all — дорисует все недостающие).";
  const pre = pb.querySelector("pre"); pre.textContent = "";
  const [a, b] = p.split(r.line);
  pre.append(a); const m = document.createElement("mark"); m.textContent = r.line; pre.append(m); pre.append(b || "");
  pb.dataset.text = p; pb.classList.add("on");
}
function cell(r, k, caption, withName) {
  const wrap = document.createElement("div"); wrap.className = "cell";
  const src = r.cells[k], f = document.createElement("figure");
  if (!src) { f.className = "none"; f.textContent = "нет"; }
  else {
    const img = document.createElement("img"); img.src = src; img.alt = caption; img.loading = "lazy"; f.append(img);
    const i = flat.push([src, caption, r, k]) - 1; f.onclick = () => open(i);
  }
  if (withName) { const cap = document.createElement("figcaption"); cap.append(star(r), r.name); cap.onclick = (e) => e.stopPropagation(); f.append(cap); }
  wrap.append(f);
  if (SETS[k].prompt) {
    const b = document.createElement("button"); b.className = "pbtn" + (src ? "" : " todo");
    b.textContent = src ? "Промпт" : "Промпт (ещё не нарисовано)";
    b.onclick = (e) => { e.stopPropagation(); showPrompt(r, k); };
    wrap.append(b);
  }
  return wrap;
}
function render() {
  main.innerHTML = ""; flat = [];
  const size = document.getElementById("zoom").value + "px", list = visible(), ks = shownSets();
  counts(list.length);
  if (!list.length) { main.innerHTML = "<p class='empty'>Нет карт под эти фильтры.</p>"; return; }
  if (mode === "card") {
    const g = document.createElement("div"); g.className = "grid";
    g.style.gridTemplateColumns = `minmax(130px, 190px) repeat(${ks.length}, ${size})`;
    g.append(document.createElement("div"));
    for (const k of ks) { const h = document.createElement("div"); h.className = "head"; h.textContent = SETS[k].label; g.append(h); }
    for (const r of list) {
      const n = document.createElement("div"); n.className = "name";
      n.innerHTML = "<div></div><span class='meta'></span><span class='meta'></span>";
      const b = document.createElement("b"); b.textContent = r.name; n.firstChild.append(star(r), b);
      n.children[1].textContent = r.en + " · " + r.id;
      n.children[2].textContent = [CLS[r.cls] || r.cls, RAR[r.rarity] || r.rarity, TYPE[r.type] || r.type, r.cost == null ? null : r.cost + " маны"].filter(Boolean).join(" · ");
      g.append(n);
      for (const k of ks) g.append(cell(r, k, `${r.name} — ${SETS[k].label}`, false));
    }
    main.append(g);
  } else {
    ks.forEach((k) => {
      const s = SETS[k], b = document.createElement("section"); b.className = "style-block";
      b.innerHTML = "<h2></h2><div class='cards'></div>"; b.querySelector("h2").textContent = s.label;
      b.querySelector(".cards").style.gridTemplateColumns = `repeat(auto-fill, minmax(${size}, 1fr))`;
      for (const r of list) b.querySelector(".cards").append(cell(r, k, `${r.name} — ${s.label}`, true));
      main.append(b);
    });
  }
}
function open(i) {
  at = (i + flat.length) % flat.length; box.querySelector("img").src = flat[at][0]; box.querySelector("p").textContent = flat[at][1];
  document.getElementById("boxPrompt").hidden = !SETS[flat[at][3]].prompt;
  box.classList.add("on");
}
box.onclick = () => box.classList.remove("on");
document.getElementById("boxPrompt").onclick = (e) => { e.stopPropagation(); showPrompt(flat[at][2], flat[at][3]); };
const pbox = document.getElementById("pbox");
pbox.onclick = (e) => { if (e.target === pbox) pbox.classList.remove("on"); };
document.getElementById("pclose").onclick = () => pbox.classList.remove("on");
document.getElementById("pcopy").onclick = (e) => { navigator.clipboard.writeText(pbox.dataset.text || ""); e.target.textContent = "Скопировано"; setTimeout(() => e.target.textContent = "Копировать", 1200); };
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && pbox.classList.contains("on")) { pbox.classList.remove("on"); return; }
  if (!box.classList.contains("on")) return;
  if (e.key === "Escape") box.classList.remove("on");
  if (e.key === "ArrowRight") open(at + 1);
  if (e.key === "ArrowLeft") open(at - 1);
});
document.getElementById("byCard").onclick = (e) => { mode = "card"; e.target.classList.add("on"); document.getElementById("byStyle").classList.remove("on"); render(); };
document.getElementById("byStyle").onclick = (e) => { mode = "style"; e.target.classList.add("on"); document.getElementById("byCard").classList.remove("on"); render(); };
document.getElementById("zoom").oninput = render;
document.getElementById("sort").onchange = render;
let qt; document.getElementById("q").oninput = (e) => { clearTimeout(qt); qt = setTimeout(() => { F.q = e.target.value; render(); }, 150); };
document.getElementById("onlyPicked").onclick = () => { F.only = !F.only; render(); };
document.getElementById("clearPicked").onclick = () => { F.picked.clear(); savePicked(); render(); };
document.getElementById("toggleF").onclick = (e) => { e.target.classList.toggle("on", document.getElementById("filters").classList.toggle("off") === false); };
document.getElementById("reset").onclick = () => {
  Object.assign(F, {q: "", have: "all", only: false}); for (const s of [F.cls, F.rar, F.cost, F.type]) s.clear();
  SETS.forEach((_, k) => F.sets.add(k)); document.getElementById("q").value = ""; document.getElementById("sort").value = "gen";
  filters(); render();
};
const bar = document.getElementById("bar");
new ResizeObserver(() => document.documentElement.style.setProperty("--hh", bar.offsetHeight + "px")).observe(bar);
filters();
render();
</script>
</body>
</html>
'''

if __name__ == "__main__":
    main()
