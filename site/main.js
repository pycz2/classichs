// Landing page: RU/EN texts, screenshot gallery, reveal on scroll, parallax cards, game start.
"use strict";

const TEXT = {
  en: {
    "nav.features": "Features", "nav.screens": "Screenshots", "nav.play": "Play",
    "hero.eyebrow": "Fan remake · June 2014 · Classic",
    "hero.lead": "Hearthstone as it was before Naxxramas: all 382 cards, nine classes, the original tutorial — and online play with a friend straight from the browser, no servers.",
    "hero.play": "Play now", "hero.source": "Source code",
    "hero.note": "Free. Works offline against the bot. No account.",
    "features.title": "Everything from the original",
    "f1.t": "All 382 cards", "f1.d": "Every Basic and Classic card with its original values and mechanics: Secrets, Choose One, Overload, Combo, Enrage, Deathrattle.",
    "f2.t": "Training with a bot", "f2.d": "Practise any deck against a simple bot of any class. Works without the internet.",
    "f3.t": "Online without servers", "f3.d": "WebRTC connects two browsers directly. Exchange a text code in any messenger — and play.",
    "f4.t": "The original tutorial", "f4.d": "Six missions as Jaina: Hogger, Millhouse, Lorewalker Cho, King Mukla, Hemet and Illidan.",
    "f5.t": "Collection and decks", "f5.d": "All cards unlocked, unlimited decks saved in the browser, deck codes compatible with Hearthstone.",
    "f6.t": "Deck tracker and history", "f6.d": "Cards left in your deck with the chance to draw each one, what the opponent played, and the full move log.",
    "f7.t": "Debug table", "f7.d": "Set up any position and test any card or combo against the bot or for both sides.",
    "f8.t": "8 languages, sound, voice", "f8.d": "English, Русский, Deutsch, Français, Español, Português, Italiano, Polski. Legendary minions say their names.",
    "screens.title": "Screenshots",
    "online.title": "Play with a friend in three steps",
    "online.s1": "Press “Create Game” and send the invite code to a friend.",
    "online.s2": "The friend presses “Join Game” and sends back the answer code.",
    "online.s3": "Paste the answer and press “Connect”. The browsers talk directly.",
    "play.title": "Play right here", "play.start": "▶ Start the game", "play.size": "About 40 MB on first load",
    "play.full": "Open in a separate tab (full screen)",
    "footer.legal": "Classic HS is a non-commercial fan project and is not affiliated with Blizzard Entertainment. Hearthstone, card names and texts are trademarks and property of Blizzard Entertainment. All art in the game is drawn by code.",
    "footer.changes": "Changelog",
  },
  ru: {
    "nav.features": "Возможности", "nav.screens": "Скриншоты", "nav.play": "Играть",
    "hero.eyebrow": "Фанатский ремейк · июнь 2014 · Classic",
    "hero.lead": "Hearthstone, каким он был до Наксрамаса: все 382 карты, девять классов, оригинальное обучение — и игра с другом по сети прямо в браузере, без серверов.",
    "hero.play": "Играть", "hero.source": "Исходный код",
    "hero.note": "Бесплатно. С ботом — без интернета. Без регистрации.",
    "features.title": "Всё как в оригинале",
    "f1.t": "Все 382 карты", "f1.d": "Все базовые и классические карты с оригинальными значениями и механиками: секреты, «Выберите одно», перегрузка, серия приёмов, исступление, предсмертный хрип.",
    "f2.t": "Тренировка с ботом", "f2.d": "Любая колода против простого бота любого класса. Работает без интернета.",
    "f3.t": "Сеть без серверов", "f3.d": "WebRTC соединяет два браузера напрямую. Обменяйтесь текстовым кодом в любом мессенджере — и играйте.",
    "f4.t": "Оригинальное обучение", "f4.d": "Шесть миссий за Джайну: Дробитель, Миллхаус Манашторм, Хранитель истории Чо, Король Мукла, Хеминг Эрнестуэй и Иллидан.",
    "f5.t": "Коллекция и колоды", "f5.d": "Все карты открыты, колод сколько угодно, они хранятся в браузере; коды колод совместимы с Hearthstone.",
    "f6.t": "Дектрекер и история", "f6.d": "Что осталось в колоде и шанс взять каждую карту, что сыграл соперник, полный журнал ходов.",
    "f7.t": "Отладочный стол", "f7.d": "Соберите любую позицию и проверьте любую карту или комбинацию против бота или за обе стороны.",
    "f8.t": "8 языков, звук, голос", "f8.d": "English, Русский, Deutsch, Français, Español, Português, Italiano, Polski. Легендарные существа называют себя вслух.",
    "screens.title": "Скриншоты",
    "online.title": "Игра с другом в три шага",
    "online.s1": "Нажмите «Создать игру» и отправьте другу код приглашения.",
    "online.s2": "Друг нажимает «Присоединиться» и присылает код ответа.",
    "online.s3": "Вставьте ответ и нажмите «Подключить». Браузеры общаются напрямую.",
    "play.title": "Играйте прямо здесь", "play.start": "▶ Запустить игру", "play.size": "Около 40 МБ при первой загрузке",
    "play.full": "Открыть в отдельной вкладке (во весь экран)",
    "footer.legal": "Classic HS — некоммерческий фанатский проект, не связанный с Blizzard Entertainment. Hearthstone, названия и тексты карт — товарные знаки и собственность Blizzard Entertainment. Весь арт в игре нарисован кодом.",
    "footer.changes": "Журнал изменений",
  },
};

// [file, tab EN, tab RU, caption EN, caption RU]
const SHOTS = [
  ["match", "Match", "Матч", "A match: Secrets, weapons, Taunt, legendary minions", "Матч: секреты, оружие, провокация, легендарные существа"],
  ["tracker", "Deck tracker", "Дектрекер", "Deck tracker: cards left and the chance to draw each", "Дектрекер: что осталось в колоде и шанс взять каждую карту"],
  ["history", "History", "История", "Full move history from the start of the match", "Полная история ходов с начала матча"],
  ["collection", "Collection", "Коллекция", "Collection: every card, filters by class and cost", "Коллекция: все карты, фильтры по классу и стоимости"],
  ["tutorial", "Tutorial", "Обучение", "Tutorial: six missions, like the original", "Обучение: шесть миссий, как в оригинале"],
  ["online", "Online", "Сеть", "Online: a text code instead of a server", "Сетевая игра: текстовый код вместо сервера"],
  ["menu", "Menu", "Меню", "Main menu", "Главное меню"],
  ["settings", "Settings", "Настройки", "Settings: language, sound, voice, screen shake", "Настройки: язык, звук, голос, тряска экрана"],
  ["changelog", "Changelog", "Журнал", "The whole change history, one click on the version", "Вся история изменений — по клику на версию"],
];

let lang = (localStorage.getItem("lang") || navigator.language || "en").toLowerCase().startsWith("ru") ? "ru" : "en";
let current = 0;
const $ = (s) => document.querySelector(s);

function applyLang() {
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const t = TEXT[lang][el.dataset.i18n];
    if (t) el.textContent = t;
  });
  $("#lang").textContent = lang === "ru" ? "EN" : "RU";
  buildGallery();
}

function src(name) { return `screens/${lang}/${name}.png`; }

function buildGallery() {
  const tabs = $(".tabs"), thumbs = $(".thumbs");
  tabs.innerHTML = ""; thumbs.innerHTML = "";
  SHOTS.forEach((s, i) => {
    const b = document.createElement("button");
    b.setAttribute("role", "tab");
    b.textContent = s[lang === "ru" ? 2 : 1];
    b.onclick = () => show(i);
    tabs.append(b);
    const t = document.createElement("img");
    t.src = src(s[0]); t.alt = s[lang === "ru" ? 4 : 3]; t.loading = "lazy";
    t.onclick = () => show(i);
    thumbs.append(t);
  });
  show(current, true);
}

function show(i, now) {
  current = i;
  const img = $("#shot"), s = SHOTS[i];
  const swap = () => {
    img.src = src(s[0]); img.alt = s[lang === "ru" ? 4 : 3];
    $("#caption").textContent = img.alt;
    img.classList.remove("fade");
  };
  if (now) swap(); else { img.classList.add("fade"); setTimeout(swap, 200); }
  document.querySelectorAll(".tabs button").forEach((b, k) => b.setAttribute("aria-selected", k === i));
  document.querySelectorAll(".thumbs img").forEach((t, k) => t.classList.toggle("on", k === i));
}

$("#lang").onclick = () => {
  lang = lang === "ru" ? "en" : "ru";
  try { localStorage.setItem("lang", lang); } catch (e) { /* private mode */ }
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
