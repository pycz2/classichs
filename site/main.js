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
}

function src(name) { return `screens/${lang}/${name}.png`; }

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
    document.querySelectorAll(".fcard").forEach((c) => {
      const d = Number(c.dataset.depth);
      c.style.transform = `translate(${-x * d}px, ${-y * d}px)`;
    });
  });
}

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
