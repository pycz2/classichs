//! One bot's life: log in (a session token made by the server for its account, or a name and
//! password over the network), find the Classic pack, finish a game a restart left, then forever:
//! read its settings again (the admin may change them at any time), wait for its daily window,
//! a random pause, then a game — ranked and casual in turn, one of them, or Arena runs (draft, play the
//! run to its end, a new one). It decides from what its player sees only (`brain`).

use super::brain::{self, Knowledge, Level};
use super::cards::{class_of, Library};
use super::status::{self, Statuses};
use super::transport::Transport;
use super::{arena, BotConfig};
use crate::events::Event;
use crate::AppRef;
use rand::Rng;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tokio::time::{sleep, Instant};

pub type BoxFut<T> = std::pin::Pin<Box<dyn std::future::Future<Output = T> + Send>>;
/// Opens a connection (the adapter: `Transport::local` or `Transport::net`).
pub type ConnectFn = Arc<dyn Fn() -> BoxFut<Result<Transport, String>> + Send + Sync>;
/// Reads the bot's settings (None: the bot is gone).
pub type LoadFn = Arc<dyn Fn() -> BoxFut<Option<BotConfig>> + Send + Sync>;

/// How a bot gets in: a token (the server's own bots), or a name and password (any server).
#[derive(Clone)]
pub enum Auth {
    Token(String),
    Password(String, String),
}

/// What a running bot needs besides its connection.
#[derive(Clone)]
pub struct Ctx {
    pub id: i64,
    pub name: String,
    pub status: Statuses,
    /// thinking at once (CPU): the server's players come first
    pub think: Arc<Semaphore>,
    /// the server's event log (None: a bot of another server)
    pub app: Option<AppRef>,
}

impl Ctx {
    fn log(&self, m: impl AsRef<str>) {
        self.status.log(self.id, m);
    }

    fn error(&self, m: impl AsRef<str>) {
        let m = m.as_ref().to_string();
        self.status.error(self.id, &m);
        if let Some(app) = &self.app {
            app.event(Event::new("bot", format!("bot {}: {m}", self.name)).other(&self.name).data(json!({"bot": self.id, "error": m})));
        }
    }

    fn state(&self, s: &str) {
        self.status.set_state(self.id, s);
    }
}

pub struct Conn {
    t: Transport,
}

impl Conn {
    async fn send(&mut self, v: Value) -> Result<(), String> {
        self.t.send(v).await
    }

    async fn next(&mut self, wait: Duration) -> Result<Option<Value>, String> {
        self.t.next(wait).await
    }

    /// Waits for a message of type `t` (others are skipped), at most `wait`.
    async fn want(&mut self, t: &str, wait: Duration) -> Result<Value, String> {
        let end = Instant::now() + wait;
        loop {
            let left = end.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Err(format!("no answer `{t}`"));
            }
            if let Some(m) = self.next(left).await? {
                if m["t"] == t {
                    return Ok(m);
                }
                if m["t"] == "error" {
                    return Err(format!("{}: {}", m["code"].as_str().unwrap_or("?"), m["text"].as_str().unwrap_or("")));
                }
                if m["t"] == "kicked" {
                    return Err("kicked: another login took this account".into());
                }
            }
        }
    }
}

/// Is `now` (minutes of the day, UTC) inside the window [from, to)? from = to: all day.
pub fn in_window(from: i64, to: i64, now: i64) -> bool {
    if from == to {
        return true;
    }
    if from < to { now >= from && now < to } else { now >= from || now < to }
}

pub fn minute_of_day() -> i64 {
    (status::now() % 86400) / 60
}

/// The bot until its settings say stop (`load` returns None or a disabled bot): logs in, plays, and
/// after a lost connection tries again with growing waits. `load` reads the settings each time.
pub async fn run(ctx: Ctx, connect: ConnectFn, auth: Auth, load: LoadFn) {
    let mut ladder_turn = rand::thread_rng().gen_range(0..2u64);
    let mut fails = 0u32;
    loop {
        let Some(cfg) = load().await.filter(|c| c.enabled) else {
            ctx.state("stopped");
            return;
        };
        if !in_window(cfg.from_min, cfg.to_min, minute_of_day()) {
            ctx.state(&format!("off: plays {:02}:{:02}–{:02}:{:02} UTC", cfg.from_min / 60, cfg.from_min % 60, cfg.to_min / 60, cfg.to_min % 60));
            sleep(Duration::from_secs(30)).await;
            continue;
        }
        ctx.state("connecting");
        let t0 = Instant::now();
        let r = session(&ctx, &connect, &auth, &load, &mut ladder_turn).await;
        ctx.status.update(ctx.id, |b| {
            b.online = false;
            b.game.clear();
            b.opponent.clear();
            b.my_turn = false;
        });
        match r {
            Ok(()) => {
                fails = 0;
                continue; // (settings or the window said: look again)
            }
            Err(e) => {
                fails = if t0.elapsed() > Duration::from_secs(300) { 0 } else { fails + 1 };
                let wait = if e.contains("kicked") { 120 } else { (10u64 << fails.min(5)).min(300) + rand::thread_rng().gen_range(0..10) };
                ctx.error(&e);
                ctx.state(&format!("disconnected, again in {wait} s"));
                sleep(Duration::from_secs(wait)).await;
            }
        }
    }
}

async fn session(ctx: &Ctx, connect: &ConnectFn, auth: &Auth, load: &LoadFn, ladder_turn: &mut u64) -> Result<(), String> {
    let lib = Library::get();
    let mut c = Conn { t: connect().await? };
    match auth {
        Auth::Token(t) => c.send(json!({"t": "resume", "token": t})).await?,
        Auth::Password(u, p) => c.send(json!({"t": "login", "user": u, "password": p})).await?,
    }
    let a = c.want("auth", Duration::from_secs(20)).await?;
    ctx.status.update(ctx.id, |b| {
        b.online = true;
        b.rank = a["me"]["rank"].clone();
    });
    ctx.log("logged in");
    c.send(json!({"t": "packs"})).await?;
    let p = c.want("packs", Duration::from_secs(20)).await?;
    let list = p["server"].as_array().cloned().unwrap_or_default();
    // the Classic pack; a server without packs plays its built-in Classic (no `pack` field then)
    let pack: Option<String> = match list.iter().find(|x| x["id"] == "classic-2014").and_then(|x| x["rules_hash"].as_str()) {
        Some(h) => Some(h.to_string()),
        None if list.is_empty() => None,
        None => return Err("the server has no Classic pack (classic-2014)".into()),
    };
    // a game left by a lost connection or a restart comes back as `match {rejoin}`: finish it first
    if let Some(m) = wait_match(ctx, &mut c, Duration::from_secs(2)).await? {
        ctx.log("back in an unfinished game");
        let arena = m["mode"] == "arena";
        let deck = if arena { arena_cards(&mut c, &pack).await? } else { vec![] };
        let level = load().await.and_then(|c| Level::parse(&c.level)).unwrap_or(Level::Medium);
        play(ctx, &mut c, m, deck, arena, level).await?;
    }
    loop {
        let Some(cfg) = load().await.filter(|c| c.enabled) else { return Ok(()) };
        if !in_window(cfg.from_min, cfg.to_min, minute_of_day()) {
            return Ok(());
        }
        let level = Level::parse(&cfg.level).unwrap_or(Level::Medium);
        pause(ctx, &mut c, cfg.pause_min.max(0) as u64, cfg.pause_max.max(cfg.pause_min).max(0) as u64).await?;
        if cfg.modes == "arena" {
            arena_game(ctx, &mut c, &pack, level).await?;
            continue;
        }
        *ladder_turn += 1;
        let mut mode = match cfg.modes.as_str() {
            "ranked" => "ranked",
            "casual" => "casual",
            _ => if *ladder_turn % 2 == 1 { "ranked" } else { "casual" },
        };
        let deck = lib.decks[rand::thread_rng().gen_range(0..lib.decks.len())].clone();
        ctx.status.update(ctx.id, |b| b.deck = deck.name.clone());
        let m = loop {
            c.send(with_pack(json!({"t": "queue", "mode": mode, "deck": {"hero": deck.hero, "cards": deck.cards, "name": deck.name}}), &pack)).await?;
            c.want("queued", Duration::from_secs(20)).await?;
            ctx.status.update(ctx.id, |b| b.mode = mode.into());
            ctx.state(&format!("queued: {mode}"));
            ctx.log(format!("queue {mode} with “{}”", deck.name));
            let patience = rand::thread_rng().gen_range(45..120);
            match wait_match(ctx, &mut c, Duration::from_secs(patience)).await? {
                Some(m) => break m,
                None => {
                    c.send(json!({"t": "unqueue"})).await?;
                    // (a match may have crossed the unqueue)
                    if let Some(m) = wait_match(ctx, &mut c, Duration::from_secs(2)).await? {
                        break m;
                    }
                    if cfg.modes == "ladder" {
                        // nobody there: the other ladder queue (bots alternate their modes)
                        mode = if mode == "ranked" { "casual" } else { "ranked" };
                        ctx.log(format!("{patience} s without an opponent: the other queue"));
                    }
                    if load().await.is_none_or(|c| !c.enabled) {
                        return Ok(());
                    }
                }
            }
        };
        play(ctx, &mut c, m, deck.cards.clone(), false, level).await?;
        c.send(with_pack(json!({"t": "me"}), &pack)).await?;
        if let Ok(me) = c.want("me", Duration::from_secs(20)).await {
            ctx.status.update(ctx.id, |b| b.rank = me["me"]["rank"].clone());
        }
    }
}

/// A message with the game's `pack` (none: the server's default game).
fn with_pack(mut v: Value, pack: &Option<String>) -> Value {
    if let Some(p) = pack {
        v["pack"] = json!(p);
    }
    v
}

async fn arena_cards(c: &mut Conn, pack: &Option<String>) -> Result<Vec<String>, String> {
    c.send(with_pack(json!({"t": "me"}), pack)).await?;
    let me = c.want("me", Duration::from_secs(20)).await?;
    Ok(strs(&me["me"]["arena"]["cards"]))
}

fn strs(v: &Value) -> Vec<String> {
    v.as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
}

/// One Arena game: a run is started (and drafted) when there is none.
async fn arena_game(ctx: &Ctx, c: &mut Conn, pack: &Option<String>, level: Level) -> Result<(), String> {
    let lib = Library::get();
    c.send(with_pack(json!({"t": "me"}), pack)).await?;
    let me = c.want("me", Duration::from_secs(20)).await?;
    let mut st = me["me"]["arena"].clone();
    let other_game = pack.as_ref().is_some_and(|p| st["pack"].as_str().is_some_and(|q| q != p));
    if st.is_null() || other_game {
        if !st.is_null() {
            c.send(json!({"t": "arena_retire"})).await?;
            c.want("arena", Duration::from_secs(20)).await?;
        }
        c.send(with_pack(json!({"t": "arena_start"}), pack)).await?;
        st = c.want("arena", Duration::from_secs(20)).await?["state"].clone();
        ctx.status.update(ctx.id, |b| b.arena_runs += 1);
        ctx.log("a new Arena run");
    }
    for _ in 0..40 {
        if st["done"] == true {
            break;
        }
        ctx.state("Arena: drafting");
        if st["hero"].as_str().unwrap_or("").is_empty() {
            let heroes = strs(&st["heroes"]);
            let k = arena::pick_hero(lib, &heroes);
            ctx.log(format!("Arena hero: {}", lib.name(&heroes.get(k).cloned().unwrap_or_default())));
            c.send(json!({"t": "arena_hero", "i": k})).await?;
        } else {
            let class = class_of(lib.rs, st["hero"].as_str().unwrap_or(""));
            let k = arena::pick_card(lib, &class, &strs(&st["cards"]), &strs(&st["offer"]));
            c.send(json!({"t": "arena_pick", "i": k})).await?;
        }
        let ms = rand::thread_rng().gen_range(200..600);
        sleep(Duration::from_millis(ms)).await;
        st = c.want("arena", Duration::from_secs(20)).await?["state"].clone();
    }
    if st["done"] != true {
        return Err("the Arena draft does not end".into());
    }
    let hero = lib.name(st["hero"].as_str().unwrap_or(""));
    ctx.status.update(ctx.id, |b| {
        b.arena_now = json!({"hero": hero, "wins": st["wins"], "losses": st["losses"]});
        b.mode = "arena".into();
        b.deck = format!("Arena: {hero}");
    });
    c.send(json!({"t": "arena_queue"})).await?;
    c.want("queued", Duration::from_secs(20)).await?;
    ctx.state("queued: arena");
    let Some(m) = wait_match(ctx, c, Duration::from_secs(1800)).await? else {
        c.send(json!({"t": "unqueue"})).await?;
        return Ok(());
    };
    if let Some(a) = play(ctx, c, m, strs(&st["cards"]), true, level).await? {
        let (w, l) = (a["wins"].as_i64().unwrap_or(0), a["losses"].as_i64().unwrap_or(0));
        ctx.status.update(ctx.id, |b| b.arena_now = json!({"hero": b.arena_now["hero"], "wins": w, "losses": l}));
        if a["over"] == true {
            ctx.status.update(ctx.id, |b| b.arena_best = b.arena_best.max(w));
            ctx.log(format!("the Arena run ended: {w} wins, {l} losses"));
        }
    }
    Ok(())
}

async fn pause(ctx: &Ctx, c: &mut Conn, lo: u64, hi: u64) -> Result<(), String> {
    let s = rand::thread_rng().gen_range(lo..=hi);
    ctx.state(&format!("pause {s} s"));
    let end = Instant::now() + Duration::from_secs(s);
    while Instant::now() < end {
        if let Some(m) = c.next(end.saturating_duration_since(Instant::now())).await? {
            if m["t"] == "kicked" {
                return Err("kicked: another login took this account".into());
            }
        }
    }
    Ok(())
}

/// The match, or None when none came within `wait`.
async fn wait_match(ctx: &Ctx, c: &mut Conn, wait: Duration) -> Result<Option<Value>, String> {
    let end = Instant::now() + wait;
    loop {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Ok(None);
        }
        match c.next(left).await? {
            Some(m) if m["t"] == "match" => {
                let opp = m["opponent"]["user"].as_str().unwrap_or("?").to_string();
                ctx.status.update(ctx.id, |b| {
                    b.opponent = opp.clone();
                    b.game = m["game"].as_str().unwrap_or("").to_string();
                });
                ctx.state(&format!("playing {opp}"));
                ctx.log(format!("a match against {opp}"));
                return Ok(Some(m));
            }
            Some(m) if m["t"] == "kicked" => return Err("kicked: another login took this account".into()),
            Some(m) if m["t"] == "error" => return Err(format!("queue: {}", m["text"])),
            _ => {}
        }
    }
}

/// One game until `game_over`; returns the Arena part of the result (Arena games).
async fn play(ctx: &Ctx, c: &mut Conn, m: Value, deck: Vec<String>, arena: bool, level: Level) -> Result<Option<Value>, String> {
    let lib = Library::get();
    let seat = m["you"].as_u64().unwrap_or(0) as usize;
    let game = m["game"].as_str().unwrap_or("").to_string();
    let mode = m["mode"].as_str().unwrap_or("").to_string();
    let budget = match level {
        Level::Easy => Duration::ZERO,
        Level::Medium => Duration::from_millis(300),
        Level::Hard => Duration::from_millis(1000),
    };
    let mut last_acted = (-1i64, -1i64); // (history length, current) of the state acted on
    // both players change cards at once: a state made before ours arrived must not make a second mulligan
    let mut mulligan_sent = false;
    loop {
        let Some(msg) = c.next(Duration::from_secs(300)).await? else {
            return Err("the game went silent for 5 minutes".into());
        };
        match msg["t"].as_str().unwrap_or("") {
            "state" => {
                let v = msg["view"].clone();
                let res = msg["result"].clone();
                let my_move = res["over"] != true
                    && (res["phase"] == "MULLIGAN" || res["current"].as_u64() == Some(seat as u64) || v["pending"]["player"].as_u64() == Some(seat as u64));
                ctx.status.update(ctx.id, |b| {
                    b.board = status::board(lib, &v, seat);
                    b.turn = res["turn"].as_i64().unwrap_or(0);
                    b.my_turn = my_move;
                });
                if !my_move {
                    continue;
                }
                let key = (v["history_len"].as_i64().unwrap_or(0), res["current"].as_i64().unwrap_or(-1));
                if key == last_acted || (res["phase"] == "MULLIGAN" && mulligan_sent) {
                    continue; // (the same position again, or our mulligan is on its way)
                }
                let permit = ctx.think.clone().acquire_owned().await.map_err(|e| e.to_string())?;
                let deck2 = deck.clone();
                let d = tokio::task::spawn_blocking(move || {
                    let _permit = permit;
                    let k = Knowledge { lib, seat, my_deck: deck2, arena };
                    brain::decide(&v, &k, level, budget)
                })
                .await
                .map_err(|e| format!("think: {e}"))?;
                match d {
                    Ok(Some(d)) => {
                        ctx.status.update(ctx.id, |b| {
                            b.decisions += 1;
                            b.think_ms += d.ms as u64;
                            b.decision = json!({"action": d.label, "worlds": d.worlds, "ms": d.ms,
                                "top": d.top.iter().map(|x| json!({"label": x.label, "score": (x.score * 10.0).round() / 10.0})).collect::<Vec<_>>()});
                        });
                        let ms = rand::thread_rng().gen_range(500..1300);
                        sleep(Duration::from_millis(ms)).await;
                        last_acted = key;
                        mulligan_sent |= d.action["type"] == "mulligan";
                        c.send(json!({"t": "act", "game": game, "action": d.action})).await?;
                    }
                    Ok(None) => {}
                    Err(e) => {
                        ctx.error(format!("the view: {e}"));
                        c.send(json!({"t": "act", "game": game, "action": {"type": "end_turn", "player": seat}})).await?;
                    }
                }
            }
            "act_error" => {
                ctx.error(format!("the server refused the move: {}", msg["error"].as_str().unwrap_or("?")));
                last_acted = (-1, -1); // look again at the next state
            }
            "game_over" => {
                let r = msg["result"].as_str().unwrap_or("?").to_string();
                let reason = msg["reason"].as_str().unwrap_or("").to_string();
                ctx.status.update(ctx.id, |b| {
                    b.games += 1;
                    match r.as_str() {
                        "win" => b.wins += 1,
                        "loss" => b.losses += 1,
                        _ => b.draws += 1,
                    }
                    match mode.as_str() {
                        "ranked" => b.ranked += 1,
                        "casual" => b.casual += 1,
                        _ => {}
                    }
                    b.game.clear();
                    b.my_turn = false;
                    if msg["rank"].is_object() {
                        b.rank = msg["rank"].clone();
                    }
                });
                ctx.log(format!("game over: {r} ({reason})"));
                if reason == "illegal" {
                    ctx.error(format!("the game was lost for refused moves: {}", msg["message"].as_str().unwrap_or("")));
                }
                return Ok(msg.get("arena").cloned());
            }
            "kicked" => return Err("kicked: another login took this account".into()),
            _ => {}
        }
    }
}
