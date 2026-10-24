//! The local admin page (no login: bind it to 127.0.0.1): every bot's state, its game as it sees it,
//! its last decision, records, errors and log. `/` the page, `/api/state` the JSON (polled each second).

use crate::status::Shared;
use axum::extract::State;
use axum::response::{Html, IntoResponse};
use axum::routing::get;
use axum::{Json, Router};

pub async fn serve(addr: &str, sh: Shared) -> Result<(), String> {
    let app = Router::new()
        .route("/", get(|| async { Html(PAGE) }))
        .route("/api/state", get(|State(sh): State<Shared>| async move { Json(sh.json()).into_response() }))
        .with_state(sh);
    let listener = tokio::net::TcpListener::bind(addr).await.map_err(|e| format!("admin {addr}: {e}"))?;
    axum::serve(listener, app).await.map_err(|e| format!("admin: {e}"))
}

const PAGE: &str = r##"<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Боты Classic HS</title>
<style>
:root { --bg:#14100c; --panel:#211812; --line:#45362a; --text:#f2e8d4; --muted:#a8977c; --gold:#f2c230; --good:#7bd88f; --bad:#ff7a6b; --blue:#7fb8ff; }
@media (prefers-color-scheme: light) { :root { --bg:#f6efe2; --panel:#fffaf0; --line:#e0d2b8; --text:#2a1f17; --muted:#6b5a44; --gold:#a8741a; --good:#1f8a3a; --bad:#c0392b; --blue:#2266aa; } }
* { box-sizing:border-box; } body { margin:0; background:var(--bg); color:var(--text); font:14.5px/1.45 -apple-system, "Segoe UI", Roboto, sans-serif; }
header { padding:12px 16px; border-bottom:1px solid var(--line); display:flex; flex-wrap:wrap; gap:14px; align-items:baseline; }
h1 { margin:0; font-size:20px; color:var(--gold); } .muted { color:var(--muted); }
main { padding:12px 16px 40px; display:grid; gap:12px; grid-template-columns:repeat(auto-fill, minmax(min(100%, 520px), 1fr)); }
.bot { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:12px 14px; }
.bot h2 { margin:0; font-size:16px; display:flex; gap:8px; align-items:center; }
.dot { width:9px; height:9px; border-radius:50%; background:var(--bad); display:inline-block; } .dot.on { background:var(--good); }
.pill { font-size:12px; padding:1px 8px; border-radius:999px; border:1px solid var(--line); color:var(--muted); }
.state { margin:4px 0 8px; } .stale { color:var(--bad); font-weight:600; }
.nums { display:flex; flex-wrap:wrap; gap:4px 14px; font-size:13.5px; } .nums b { color:var(--gold); }
.err { color:var(--bad); font-size:13px; margin-top:6px; }
.table { margin-top:8px; border-top:1px dashed var(--line); padding-top:8px; font-size:13px; }
.row { display:flex; flex-wrap:wrap; gap:4px; margin:3px 0; align-items:center; }
.m { border:1px solid var(--line); border-radius:6px; padding:1px 6px; } .m .s { color:var(--gold); font-weight:700; }
.m.t { box-shadow:inset 0 0 0 2px var(--muted); } .c { color:var(--blue); font-weight:700; }
.dec { margin-top:6px; font-size:13px; } .dec ol { margin:4px 0 0 18px; padding:0; }
details { margin-top:6px; } summary { cursor:pointer; color:var(--gold); font-size:13px; }
pre { margin:4px 0 0; max-height:240px; overflow:auto; font:12px/1.4 ui-monospace, Menlo, monospace; white-space:pre-wrap; }
</style></head><body>
<header><h1>Боты Classic HS</h1><span class="muted" id="hdr"></span></header>
<main id="bots"></main>
<script>
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const ago = (now, t) => { const s = Math.max(0, now - t); return s < 60 ? s + " с" : s < 3600 ? Math.floor(s / 60) + " мин" : Math.floor(s / 3600) + " ч " + Math.floor(s % 3600 / 60) + " мин"; };
const open = new Set();
function side(s, own) {
  if (!s) return "";
  const minions = s.board.map((m) => `<span class="m ${m.tags.includes("провокация") ? "t" : ""}">${esc(m.name)} <span class="s">${m.atk}/${m.hp}</span>${m.tags.length ? " · " + esc(m.tags.join(", ")) : ""}</span>`).join(" ") || '<span class="muted">стол пуст</span>';
  const hand = Array.isArray(s.hand) ? s.hand.map((h) => `<span class="m"><span class="c">${h.cost}</span> ${esc(h.name)}</span>`).join(" ") : `${s.hand} карт`;
  return `<div class="row"><b>${own ? "Бот" : "Соперник"}:</b> ${esc(s.hero)} ❤ ${s.hp}${s.armor ? " 🛡 " + s.armor : ""} · мана ${s.mana}/${s.max_mana} · колода ${s.deck}${s.secrets ? " · секретов " + s.secrets : ""}${s.weapon ? ` · ⚔ ${esc(s.weapon.name)} ${s.weapon.atk}/${s.weapon.dur}` : ""}</div>
    <div class="row">${minions}</div><div class="row muted">рука: ${hand}</div>`;
}
function rank(r) { if (!r || r.rank === undefined) return ""; return r.rank === 0 ? `Легенда${r.legend ? " #" + r.legend : ""}` : `ранг ${r.rank}, звёзд ${r.stars}`; }
async function tick() {
  let d; try { d = await (await fetch("/api/state")).json(); } catch (e) { document.getElementById("hdr").textContent = "нет связи с процессом ботов"; return; }
  const total = d.bots.reduce((a, b) => a + b.games, 0);
  document.getElementById("hdr").textContent = `сервер ${d.server} · работает ${ago(d.now, d.started)} · ботов ${d.bots.length} · игр сыграно ${total}`;
  document.getElementById("bots").innerHTML = d.bots.map((b, i) => {
    const stale = b.game && d.now - b.since > 600;
    const wr = b.games ? Math.round(100 * b.wins / b.games) + "%" : "—";
    const dec = b.decision && b.decision.action ? `<div class="dec">Последнее решение: <b>${esc(b.decision.action)}</b> <span class="muted">(${b.decision.worlds} миров, ${b.decision.ms} мс)</span>
      ${b.decision.top && b.decision.top.length ? "<ol>" + b.decision.top.map((t) => `<li>${esc(t.label)} — <span class="muted">${t.score}</span></li>`).join("") + "</ol>" : ""}</div>` : "";
    const board = b.game && b.board ? `<div class="table">Игра ${esc(b.game)}, ход ${b.turn}${b.my_turn ? " — <b>ход бота</b>" : ""}${side(b.board.opp, false)}${side(b.board.me, true)}</div>` : "";
    const arena = b.kind === "arena" ? `<span>арен <b>${b.arena_runs}</b></span><span>лучшая <b>${b.arena_best}</b> побед</span>${b.arena_now && b.arena_now.hero ? `<span>сейчас: ${esc(b.arena_now.hero)} ${b.arena_now.wins}–${b.arena_now.losses}</span>` : ""}` : `<span>рейтинг <b>${b.ranked}</b></span><span>обычных <b>${b.casual}</b></span><span>${esc(rank(b.rank))}</span>`;
    return `<section class="bot"><h2><span class="dot ${b.online ? "on" : ""}"></span>${esc(b.name)} <span class="pill">${b.kind === "arena" ? "арена" : "рейтинг/обычная"}</span></h2>
      <div class="state ${stale ? "stale" : ""}">${esc(b.state)} <span class="muted">· ${ago(d.now, b.since)}</span>${stale ? " — давно без изменений" : ""}</div>
      <div class="nums"><span>игр <b>${b.games}</b></span><span>побед <b>${b.wins}</b></span><span>поражений <b>${b.losses}</b></span><span>винрейт <b>${wr}</b></span>${arena}
        <span>колода: ${esc(b.deck || "—")}</span><span>решений ${b.decisions}, в среднем ${b.think_ms_avg} мс</span><span>ошибок <b>${b.errors}</b></span></div>
      ${b.last_error ? `<div class="err">${esc(b.last_error)}</div>` : ""}${board}${dec}
      <details data-i="${i}" ${open.has(i) ? "open" : ""}><summary>Журнал</summary><pre>${esc(b.log.join("\n"))}</pre></details></section>`;
  }).join("");
  document.querySelectorAll("details").forEach((x) => x.ontoggle = () => x.open ? open.add(+x.dataset.i) : open.delete(+x.dataset.i));
}
tick(); setInterval(tick, 1000);
</script></body></html>"##;
