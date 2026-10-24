//! One bot's life on the server (its WebSocket JSON protocol, server/README.md): log in (or register),
//! find the Classic pack, then forever: a 5-15 s pause, a game (ladder: ranked and casual in turn with a
//! random deck of the library; Arena: draft, then games until the run ends, then a new run).

use crate::arena;
use crate::brain::{self, Knowledge};
use crate::cards::{class_of, Library};
use crate::status::{self, Shared};
use futures_util::{SinkExt, StreamExt};
use rand::Rng;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{sleep, timeout, Instant};
use tokio_tungstenite::tungstenite::Message;

#[derive(Clone)]
pub struct Config {
    pub server: String,
    pub state_dir: PathBuf,
    pub think: Duration,
    pub pause: (u64, u64),
    pub pack_id: String,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Ladder,
    Arena,
}

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// The bots' accounts (name → password, token), in <state_dir>/accounts.json.
fn accounts_path(cfg: &Config) -> PathBuf {
    cfg.state_dir.join("accounts.json")
}

fn load_accounts(cfg: &Config) -> HashMap<String, Value> {
    std::fs::read_to_string(accounts_path(cfg)).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

fn save_account(cfg: &Config, name: &str, entry: Value) {
    // (one process writes it; bots save one at a time under this lock)
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _g = LOCK.lock();
    let mut all = load_accounts(cfg);
    all.insert(name.to_string(), entry);
    let _ = std::fs::create_dir_all(&cfg.state_dir);
    let _ = std::fs::write(accounts_path(cfg), serde_json::to_string_pretty(&all).unwrap_or_default());
}

fn password() -> String {
    let mut r = rand::thread_rng();
    (0..24).map(|_| char::from(b"abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"[r.gen_range(0..56)])).collect()
}

struct Conn {
    ws: Ws,
}

impl Conn {
    async fn send(&mut self, v: Value) -> Result<(), String> {
        self.ws.send(Message::text(v.to_string())).await.map_err(|e| format!("send: {e}"))
    }

    /// The next JSON message (None: nothing within `wait`); Err when the connection is gone.
    async fn next(&mut self, wait: Duration) -> Result<Option<Value>, String> {
        match timeout(wait, self.ws.next()).await {
            Err(_) => Ok(None),
            Ok(None) => Err("the server closed the connection".into()),
            Ok(Some(Err(e))) => Err(format!("connection: {e}")),
            Ok(Some(Ok(Message::Text(t)))) => Ok(serde_json::from_str(t.as_str()).ok()),
            Ok(Some(Ok(Message::Close(c)))) => Err(format!("closed by the server: {}", c.map_or(String::new(), |c| c.reason.to_string()))),
            Ok(Some(Ok(_))) => Ok(None),
        }
    }

    /// Waits for a message of type `t` (others are handed to `other`), at most `wait`.
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

/// Logs in with the saved token or password, or registers the name on the first run.
async fn login(cfg: &Config, sh: &Shared, i: usize, name: &str) -> Result<(Conn, Value), String> {
    let (ws, _) = tokio_tungstenite::connect_async(cfg.server.as_str()).await.map_err(|e| format!("connect {}: {e}", cfg.server))?;
    let mut c = Conn { ws };
    let acc = load_accounts(cfg).get(name).cloned();
    let auth = if let Some(tok) = acc.as_ref().and_then(|a| a["token"].as_str()).filter(|t| !t.is_empty()) {
        c.send(json!({"t": "resume", "token": tok})).await?;
        c.want("auth", Duration::from_secs(20)).await.ok()
    } else {
        None
    };
    let auth = match auth {
        Some(a) => a,
        None => match acc.as_ref().and_then(|a| a["password"].as_str()) {
            Some(pw) => {
                c.send(json!({"t": "login", "user": name, "password": pw})).await?;
                c.want("auth", Duration::from_secs(20)).await?
            }
            None => {
                let pw = password();
                c.send(json!({"t": "register", "user": name, "password": pw})).await?;
                let a = c.want("auth", Duration::from_secs(20)).await?;
                sh.log(i, format!("зарегистрирован аккаунт {name}"));
                save_account(cfg, name, json!({"password": pw, "token": ""}));
                a
            }
        },
    };
    let mut entry = acc.unwrap_or_else(|| load_accounts(cfg).get(name).cloned().unwrap_or(json!({})));
    entry["token"] = auth["token"].clone();
    save_account(cfg, name, entry);
    Ok((c, auth))
}

/// The rules_hash of the Classic pack on the server.
async fn classic_hash(c: &mut Conn, pack_id: &str) -> Result<String, String> {
    c.send(json!({"t": "packs"})).await?;
    let p = c.want("packs", Duration::from_secs(20)).await?;
    p["server"]
        .as_array()
        .and_then(|a| a.iter().find(|x| x["id"] == pack_id))
        .and_then(|x| x["rules_hash"].as_str())
        .map(String::from)
        .ok_or_else(|| format!("the server has no pack `{pack_id}`"))
}

/// The bot, forever: reconnects after a lost connection (5-15 s), waits 2 min after being kicked.
pub async fn run(cfg: Config, lib: Arc<Library>, sh: Shared, i: usize, name: String, kind: Kind) {
    let mut ladder_turn = rand::thread_rng().gen_range(0..2u64);
    let mut fails = 0u32;
    loop {
        sh.set_state(i, "подключение");
        let t0 = Instant::now();
        let r = session(&cfg, &lib, &sh, i, &name, kind, &mut ladder_turn).await;
        sh.update(i, |b| {
            b.online = false;
            b.game.clear();
            b.opponent.clear();
            b.my_turn = false;
        });
        // a session that ended at once counts as a failure: the waits grow (logins are limited per address)
        fails = if t0.elapsed() > Duration::from_secs(300) { 0 } else { fails + 1 };
        let wait = match &r {
            Err(e) if e.contains("kicked") => 120,
            _ => (10u64 << fails.min(5)).min(300) + rand::thread_rng().gen_range(0..10),
        };
        if let Err(e) = &r {
            sh.error(i, e);
        }
        sh.set_state(i, &format!("нет связи, повтор через {wait} с"));
        sleep(Duration::from_secs(wait)).await;
    }
}

async fn pause(cfg: &Config, sh: &Shared, i: usize, c: &mut Conn) -> Result<(), String> {
    let s = rand::thread_rng().gen_range(cfg.pause.0..=cfg.pause.1);
    sh.set_state(i, &format!("пауза {s} с"));
    let end = Instant::now() + Duration::from_secs(s);
    // keep reading (presence and the like) so the connection stays healthy
    while Instant::now() < end {
        if let Some(m) = c.next(end.saturating_duration_since(Instant::now())).await? {
            if m["t"] == "kicked" {
                return Err("kicked: another login took this account".into());
            }
        }
    }
    Ok(())
}

async fn session(cfg: &Config, lib: &Arc<Library>, sh: &Shared, i: usize, name: &str, kind: Kind, ladder_turn: &mut u64) -> Result<(), String> {
    let (mut c, auth) = login(cfg, sh, i, name).await?;
    sh.update(i, |b| {
        b.online = true;
        b.rank = auth["me"]["rank"].clone();
    });
    sh.log(i, "вход выполнен");
    let pack = classic_hash(&mut c, &cfg.pack_id).await?;
    // a game left by a lost connection or a restart comes back as `match {rejoin}`: finish it first
    if let Some(m) = wait_match(&mut c, sh, i, Duration::from_secs(2)).await? {
        sh.log(i, "возврат в незаконченную игру");
        let arena = m["mode"] == "arena";
        let deck: Vec<String> = if arena {
            c.send(json!({"t": "me", "pack": pack})).await?;
            let me = c.want("me", Duration::from_secs(20)).await?;
            me["me"]["arena"]["cards"].as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        } else {
            vec![] // (the deck list was lost with the old process: the own deck is guessed from the class)
        };
        play(cfg, lib, sh, i, &mut c, m, deck, arena).await?;
    }
    loop {
        match kind {
            Kind::Ladder => {
                pause(cfg, sh, i, &mut c).await?;
                *ladder_turn += 1;
                let mode = if *ladder_turn % 2 == 1 { "ranked" } else { "casual" };
                let deck = {
                    let mut r = rand::thread_rng();
                    lib.decks[r.gen_range(0..lib.decks.len())].clone()
                };
                sh.update(i, |b| {
                    b.mode = mode.into();
                    b.deck = deck.name.clone();
                });
                let mut mode = mode;
                let m = loop {
                    c.send(json!({"t": "queue", "mode": mode, "pack": pack, "deck": {"hero": deck.hero, "cards": deck.cards, "name": deck.name}})).await?;
                    c.want("queued", Duration::from_secs(20)).await?;
                    sh.update(i, |b| b.mode = mode.into());
                    sh.set_state(i, &format!("в очереди: {}", if mode == "ranked" { "рейтинг" } else { "обычная" }));
                    sh.log(i, format!("очередь {mode} с колодой «{}»", deck.name));
                    let patience = rand::thread_rng().gen_range(45..120);
                    match wait_match(&mut c, sh, i, Duration::from_secs(patience)).await? {
                        Some(m) => break m,
                        None => {
                            // nobody in this queue: the other one (the ladder bots alternate their modes)
                            c.send(json!({"t": "unqueue"})).await?;
                            // (a match may have crossed the unqueue)
                            if let Some(m) = wait_match(&mut c, sh, i, Duration::from_secs(2)).await? {
                                break m;
                            }
                            mode = if mode == "ranked" { "casual" } else { "ranked" };
                            sh.log(i, format!("{patience} с без соперника: другая очередь"));
                        }
                    }
                };
                play(cfg, lib, sh, i, &mut c, m, deck.cards.clone(), false).await?;
                c.send(json!({"t": "me", "pack": pack})).await?;
                if let Ok(me) = c.want("me", Duration::from_secs(20)).await {
                    sh.update(i, |b| b.rank = me["me"]["rank"].clone());
                }
            }
            Kind::Arena => {
                c.send(json!({"t": "me", "pack": pack})).await?;
                let me = c.want("me", Duration::from_secs(20)).await?;
                let mut st = me["me"]["arena"].clone();
                if st.is_null() || st["pack"].as_str().is_some_and(|p| p != pack) {
                    if !st.is_null() {
                        c.send(json!({"t": "arena_retire"})).await?;
                        c.want("arena", Duration::from_secs(20)).await?;
                    }
                    pause(cfg, sh, i, &mut c).await?;
                    c.send(json!({"t": "arena_start", "pack": pack})).await?;
                    st = c.want("arena", Duration::from_secs(20)).await?["state"].clone();
                    sh.update(i, |b| b.arena_runs += 1);
                    sh.log(i, "новая арена");
                }
                st = draft(lib, sh, i, &mut c, st).await?;
                sh.update(i, |b| b.arena_now = json!({"hero": lib.name(st["hero"].as_str().unwrap_or("")), "wins": st["wins"], "losses": st["losses"]}));
                pause(cfg, sh, i, &mut c).await?;
                c.send(json!({"t": "arena_queue"})).await?;
                c.want("queued", Duration::from_secs(20)).await?;
                sh.set_state(i, "в очереди: арена");
                sh.update(i, |b| {
                    b.mode = "arena".into();
                    b.deck = format!("арена: {}", lib.name(st["hero"].as_str().unwrap_or("")));
                });
                let cards: Vec<String> = st["cards"].as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect());
                let Some(m) = wait_match(&mut c, sh, i, Duration::from_secs(3600)).await? else {
                    c.send(json!({"t": "unqueue"})).await?;
                    continue;
                };
                let over = play(cfg, lib, sh, i, &mut c, m, cards, true).await?;
                if let Some(a) = over {
                    let (w, l) = (a["wins"].as_i64().unwrap_or(0), a["losses"].as_i64().unwrap_or(0));
                    sh.update(i, |b| b.arena_now = json!({"hero": b.arena_now["hero"], "wins": w, "losses": l}));
                    if a["over"] == true {
                        sh.update(i, |b| b.arena_best = b.arena_best.max(w));
                        sh.log(i, format!("арена окончена: {w} побед, {l} поражений"));
                    }
                }
            }
        }
    }
}

/// The draft until the deck is done: the hero first, then 30 cards.
async fn draft(lib: &Library, sh: &Shared, i: usize, c: &mut Conn, mut st: Value) -> Result<Value, String> {
    let strs = |v: &Value| -> Vec<String> { v.as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()) };
    for _ in 0..40 {
        if st["done"] == true {
            return Ok(st);
        }
        sh.set_state(i, "арена: выбор карт");
        if st["hero"].as_str().unwrap_or("").is_empty() {
            let heroes = strs(&st["heroes"]);
            let k = arena::pick_hero(lib, &heroes);
            sh.log(i, format!("арена: герой {}", lib.name(&heroes.get(k).cloned().unwrap_or_default())));
            c.send(json!({"t": "arena_hero", "i": k})).await?;
        } else {
            let class = class_of(lib.rs, st["hero"].as_str().unwrap_or(""));
            let (picked, offer) = (strs(&st["cards"]), strs(&st["offer"]));
            let k = arena::pick_card(lib, &class, &picked, &offer);
            c.send(json!({"t": "arena_pick", "i": k})).await?;
        }
        let ms = rand::thread_rng().gen_range(300..900);
        sleep(Duration::from_millis(ms)).await;
        st = c.want("arena", Duration::from_secs(20)).await?["state"].clone();
    }
    Err("the draft does not end".into())
}

/// The match, or None when none came within `wait`.
async fn wait_match(c: &mut Conn, sh: &Shared, i: usize, wait: Duration) -> Result<Option<Value>, String> {
    let end = Instant::now() + wait;
    loop {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Ok(None);
        }
        match c.next(left).await? {
            Some(m) if m["t"] == "match" => {
                let opp = format!("{}", m["opponent"]["user"].as_str().unwrap_or("?"));
                sh.update(i, |b| {
                    b.opponent = opp.clone();
                    b.game = m["game"].as_str().unwrap_or("").to_string();
                });
                sh.set_state(i, &format!("игра против {opp}"));
                sh.log(i, format!("матч против {opp}"));
                return Ok(Some(m));
            }
            Some(m) if m["t"] == "kicked" => return Err("kicked: another login took this account".into()),
            Some(m) if m["t"] == "error" => return Err(format!("queue: {}", m["text"])),
            _ => {}
        }
    }
}

/// One game until `game_over`; returns the Arena part of the result (Arena games).
#[allow(clippy::too_many_arguments)]
async fn play(cfg: &Config, lib: &Arc<Library>, sh: &Shared, i: usize, c: &mut Conn, m: Value, deck: Vec<String>, arena: bool) -> Result<Option<Value>, String> {
    let seat = m["you"].as_u64().unwrap_or(0) as usize;
    let game = m["game"].as_str().unwrap_or("").to_string();
    let mode = m["mode"].as_str().unwrap_or("").to_string();
    let mut last_acted_turn = (-1i64, -1i64); // (history length, current) of the state acted on
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
                sh.update(i, |b| {
                    b.board = status::board(lib, &v, seat);
                    b.turn = res["turn"].as_i64().unwrap_or(0);
                    b.my_turn = my_move;
                });
                if !my_move {
                    continue;
                }
                let key = (v["history_len"].as_i64().unwrap_or(0), res["current"].as_i64().unwrap_or(-1));
                if key == last_acted_turn || (res["phase"] == "MULLIGAN" && mulligan_sent) {
                    continue; // (the same position again, or our mulligan is on its way)
                }
                let (lib2, deck2, think) = (lib.clone(), deck.clone(), cfg.think);
                let d = tokio::task::spawn_blocking(move || {
                    let k = Knowledge { lib: &lib2, seat, my_deck: deck2, arena };
                    brain::decide(&v, &k, think)
                })
                .await
                .map_err(|e| format!("think: {e}"))?;
                match d {
                    Ok(Some(d)) => {
                        sh.update(i, |b| {
                            b.decisions += 1;
                            b.think_ms += d.ms as u64;
                            b.decision = json!({"action": d.label, "worlds": d.worlds, "ms": d.ms,
                                "top": d.top.iter().map(|x| json!({"label": x.label, "score": (x.score * 10.0).round() / 10.0})).collect::<Vec<_>>()});
                        });
                        let ms = rand::thread_rng().gen_range(500..1300);
                        sleep(Duration::from_millis(ms)).await;
                        last_acted_turn = key;
                        mulligan_sent |= d.action["type"] == "mulligan";
                        c.send(json!({"t": "act", "game": game, "action": d.action})).await?;
                    }
                    Ok(None) => {}
                    Err(e) => {
                        sh.error(i, format!("the view: {e}"));
                        c.send(json!({"t": "act", "game": game, "action": {"type": "end_turn", "player": seat}})).await?;
                    }
                }
            }
            "act_error" => {
                sh.error(i, format!("the server refused the move: {}", msg["error"].as_str().unwrap_or("?")));
                last_acted_turn = (-1, -1); // look again at the next state
            }
            "game_over" => {
                let r = msg["result"].as_str().unwrap_or("?").to_string();
                let reason = msg["reason"].as_str().unwrap_or("").to_string();
                sh.update(i, |b| {
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
                let word = match r.as_str() {
                    "win" => "победа",
                    "loss" => "поражение",
                    _ => "ничья",
                };
                sh.log(i, format!("игра окончена: {word} ({reason})"));
                if reason == "illegal" {
                    sh.error(i, format!("the game was lost for refused moves: {}", msg["message"].as_str().unwrap_or("")));
                }
                return Ok(msg.get("arena").cloned());
            }
            "kicked" => return Err("kicked: another login took this account".into()),
            _ => {}
        }
    }
}
