// Landing page: texts in the game's 8 languages, screenshot gallery, reveal on scroll, parallax cards, game start.
"use strict";

const LANGS = {en: "English", ru: "Русский", de: "Deutsch", fr: "Français", es: "Español", pt_BR: "Português (Brasil)", it: "Italiano", pl: "Polski"};
const TEXT = window.TEXT;
const SHOTS = ["match", "tracker", "history", "collection", "tutorial", "online", "menu", "settings", "changelog"];
const $ = (s) => document.querySelector(s);

// A supported language for a browser locale ("de-AT" -> "de", "pt-PT" -> "pt_BR"); English otherwise.
function pick(locale) {
  const l = (locale || "").replace("-", "_");
  if (TEXT[l]) return l;
  const base = l.split("_")[0].toLowerCase();
  if (base === "pt") return "pt_BR";
  return TEXT[base] ? base : "en";
}
function savedLang() {
  try { return localStorage.getItem("lang"); } catch (e) { return null; }  // storage blocked
}
let lang = pick(savedLang() || navigator.language);
let current = 0;
const t = (key) => (TEXT[lang] && TEXT[lang][key]) || TEXT.en[key];

function applyLang() {
  document.documentElement.lang = lang.replace("_", "-");
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  $("#lang").value = lang;
  buildGallery();
  buildCards();
}

// --- cards: pictures drawn by the game itself (tools/site_cards.gd), in the page language ---
const CLASS_COLORS = {WARRIOR: "#8e1002", SHAMAN: "#0070de", ROGUE: "#4c4d48", PALADIN: "#aa8f00", HUNTER: "#016e01",
  DRUID: "#703606", WARLOCK: "#7624ad", MAGE: "#0092ab", PRIEST: "#b8b090", NEUTRAL: "#6b6b6b"};
let DATA = {heroes: [], cards: []};

function cardEl(c, withBack) {
  const el = document.createElement("div");
  el.className = "card";
  const name = c.name[lang] || c.name.en;
  el.innerHTML = `<div class="face"><img src="cards/${lang}/${c.id}.webp" alt="" loading="lazy"><div class="gloss"><div class="shine-sweep"></div></div></div>`
    + (withBack ? '<div class="back"><img src="cards/back.webp" alt="" loading="lazy"></div>' : "");
  el.querySelector("img").alt = name;
  el.title = name;
  return el;
}

function buildCards() {
  if (!DATA.cards.length) return;
  const hc = $("#heroCards");
  hc.innerHTML = "";
  DATA.cards.slice(0, 6).forEach((c, i) => {
    const el = cardEl(c);
    el.dataset.depth = [18, 30, 12, 24, 36, 20][i];
    hc.append(el);
  });
  const fan = $("#fan");
  fan.innerHTML = "";
  const list = DATA.cards.slice(0, 9);
  list.forEach((c, i) => {
    const el = cardEl(c, true);
    const k = i - (list.length - 1) / 2;
    el.style.transform = `rotate(${k * 6}deg) translateY(${Math.abs(k) * Math.abs(k) * 4}px)`;
    el.onclick = () => el.classList.toggle("flipped");
    fan.append(el);
  });
  const row = $("#heroRow");
  row.innerHTML = "";
  DATA.heroes.forEach((h) => {
    const tile = document.createElement("div");
    tile.className = "hero-tile";
    tile.style.setProperty("--cls", CLASS_COLORS[h.cls]);
    tile.innerHTML = `<div class="portrait"><img src="art/${h.id}.jpg" alt="" loading="lazy"></div><div class="name"></div><div class="power"></div>`;
    tile.querySelector(".name").textContent = h.name[lang] || h.name.en;
    tile.querySelector(".power").textContent = h.power ? (h.power[lang] || h.power.en) : "";
    tile.querySelector("img").alt = tile.querySelector(".name").textContent;
    row.append(tile);
  });
}

fetch("data.json").then((r) => r.json()).then((d) => { DATA = d; buildCards(); }).catch(() => {});

function src(name) { return `screens/en/${name}.png`; }  // screenshots are in English

function buildGallery() {
  const tabs = $(".tabs"), thumbs = $(".thumbs");
  tabs.innerHTML = ""; thumbs.innerHTML = "";
  SHOTS.forEach((name, i) => {
    const b = document.createElement("button");
    b.setAttribute("role", "tab");
    b.textContent = t(`shot.${name}.tab`);
    b.onclick = () => show(i);
    tabs.append(b);
    const img = document.createElement("img");
    img.src = src(name); img.alt = t(`shot.${name}.cap`); img.loading = "lazy";
    img.onclick = () => show(i);
    thumbs.append(img);
  });
  show(current, true);
}

function show(i, now) {
  current = i;
  const img = $("#shot"), name = SHOTS[i];
  const swap = () => {
    img.src = src(name); img.alt = t(`shot.${name}.cap`);
    $("#caption").textContent = img.alt;
    img.classList.remove("fade");
  };
  if (now) swap(); else { img.classList.add("fade"); setTimeout(swap, 200); }
  document.querySelectorAll(".tabs button").forEach((b, k) => b.setAttribute("aria-selected", k === i));
  document.querySelectorAll(".thumbs img").forEach((m, k) => m.classList.toggle("on", k === i));
}

for (const code in LANGS) $("#lang").add(new Option(LANGS[code], code));
$("#lang").onchange = (e) => {
  lang = e.target.value;
  try { localStorage.setItem("lang", lang); } catch (err) { /* storage blocked */ }
  applyLang();
};

// Lightbox and a gentle tilt of the big screenshot.
const box = $("#lightbox");
$("#shot").onclick = () => { box.querySelector("img").src = $("#shot").src; box.hidden = false; };
box.onclick = () => { box.hidden = true; };
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") box.hidden = true;
});
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
$(".stage").addEventListener("mousemove", (e) => {
  if (reduced) return;
  const r = e.currentTarget.getBoundingClientRect();
  const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
  $("#shot").style.transform = `rotateY(${x * 6}deg) rotateX(${-y * 6}deg)`;
});
$(".stage").addEventListener("mouseleave", () => { $("#shot").style.transform = ""; });

// Floating cards follow the mouse a little (depth from data-depth).
if (!reduced) {
  document.addEventListener("mousemove", (e) => {
    const x = e.clientX / innerWidth - 0.5, y = e.clientY / innerHeight - 0.5;
    document.querySelectorAll("#heroCards .card").forEach((c) => {
      const d = Number(c.dataset.depth);
      c.style.transform = `translate(${-x * d}px, ${-y * d}px)`;
    });
  });
}

// Feature panels glow where the mouse is.
document.querySelectorAll(".feature").forEach((f) => f.addEventListener("mousemove", (e) => {
  const r = f.getBoundingClientRect();
  f.style.setProperty("--mx", `${e.clientX - r.left}px`);
  f.style.setProperty("--my", `${e.clientY - r.top}px`);
}));

// Numbers count up when they come into view.
const counted = new IntersectionObserver((list) => list.forEach((en) => {
  if (!en.isIntersecting) return;
  counted.unobserve(en.target);
  const end = Number(en.target.dataset.count), t0 = performance.now(), dur = reduced ? 0 : 1400;
  const step = (now) => {
    const p = dur ? Math.min(1, (now - t0) / dur) : 1;
    en.target.textContent = Math.round(end * (1 - Math.pow(1 - p, 3)));
    if (p < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}), { threshold: 0.5 });
document.querySelectorAll("[data-count]").forEach((el) => counted.observe(el));

// Embers drift up behind the page.
(function embers() {
  const cv = $("#embers"), ctx = cv.getContext("2d");
  if (!ctx || reduced) return;
  let w, h, parts = [];
  const resize = () => { w = cv.width = innerWidth; h = cv.height = innerHeight; };
  resize();
  addEventListener("resize", resize);
  for (let i = 0; i < 70; i++) parts.push({x: Math.random() * w, y: Math.random() * h, r: 0.6 + Math.random() * 2.2, v: 0.2 + Math.random() * 0.7, s: Math.random() * 6});
  const tick = () => {
    ctx.clearRect(0, 0, w, h);
    for (const p of parts) {
      p.y -= p.v; p.s += 0.02; p.x += Math.sin(p.s) * 0.4;
      if (p.y < -10) { p.y = h + 10; p.x = Math.random() * w; }
      const a = 0.35 + 0.35 * Math.sin(p.s * 1.7);
      ctx.beginPath();
      ctx.fillStyle = `rgba(255, ${150 + (p.r * 30) | 0}, 60, ${a})`;
      ctx.shadowColor = "rgba(255,170,60,.8)"; ctx.shadowBlur = 8;
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
    requestAnimationFrame(tick);
  };
  tick();
})();

// Sections appear when they scroll into view.
const io = new IntersectionObserver((list) => list.forEach((en) => {
  if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
}), { threshold: 0.12 });
document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

// The game loads only on demand: the page stays light.
$("#start").onclick = () => {
  const f = $("#game");
  f.src = "play/index.html";
  f.hidden = false;
  $("#start").remove();
  f.focus();
};

applyLang();
