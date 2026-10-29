//! End-to-end: real WebSocket clients against the server, which runs every game in the
//! rules engine. The tests that play keep a mirror engine (same decks, the seed from the
//! event log) to choose moves (the engine's bot) and to check every `state` exactly.

use classichs_engine::api::{events_for, snapshot};
use classichs_engine::state::Ev as Events;
use classichs_engine::{bot, deck, ruleset, Game};
use classichs_server::entity::{event, pack, standing};
use classichs_server::game::DOES_NOT_ADD_UP;
use classichs_server::storage::Storage;
use classichs_server::{db, packs, router, spawn_background, App, AppRef, Timers};
use futures_util::{SinkExt, StreamExt};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, QueryOrder};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

mod common;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// A pack storage in a fresh temp directory.
fn temp_store() -> Storage {
    Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap()
}

async fn server(timers: Timers) -> (SocketAddr, AppRef) {
    server_with(Some(timers)).await
}

/// timers None: each pack's own (rules.json).
async fn server_with(timers: Option<Timers>) -> (SocketAddr, AppRef) {
    // RUST_LOG=classichs_server::ws=debug shows the connections' logs of a failed test
    let _ = tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).with_test_writer().try_init();
    let app = App::new(db::open(":memory:").await.unwrap(), false, timers, temp_store());
    spawn_background(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    (addr, app)
}

fn std_server() -> Timers {
    Timers::default()
}

struct C {
    ws: Ws,
    token: String,
}

impl C {
    async fn connect(addr: SocketAddr) -> C {
        let (ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
        C { ws, token: String::new() }
    }

    async fn send(&mut self, v: Value) {
        self.ws.send(Message::text(v.to_string())).await.unwrap();
    }

    /// The next message of type `t` (others, like queue_status, are skipped).
    async fn want(&mut self, t: &str) -> Value {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        loop {
            let m = tokio::time::timeout_at(deadline, self.ws.next())
                .await
                .unwrap_or_else(|_| panic!("timed out waiting for {t}"))
                .unwrap_or_else(|| panic!("closed while waiting for {t}"))
                .unwrap();
            if let Message::Text(s) = m {
                let v: Value = serde_json::from_str(s.as_str()).unwrap();
                if v["t"] == t {
                    return v;
                }
                assert!(v["t"] != "error" || t == "error", "unexpected error while waiting for {t}: {v}");
                assert!(v["t"] != "act_error" || t == "act_error", "unexpected act_error while waiting for {t}: {v}");
            }
        }
    }

    async fn register(addr: SocketAddr, name: &str) -> C {
        let mut c = C::connect(addr).await;
        c.send(json!({"t": "register", "user": name, "password": "password123"})).await;
        let a = c.want("auth").await;
        assert_eq!(a["me"]["user"], name);
        assert_eq!(a["me"]["rank"]["rank"], 25);
        c.token = a["token"].as_str().unwrap().to_string();
        c
    }
}

/// A Basic deck of the class.
fn deck(class: &str) -> Value {
    json!({"name": "Test", "hero": deck::hero(class).unwrap(), "cards": deck::basic(class)})
}

/// A player in a game: the connection, the seat (`you`) and the deck.
struct P {
    c: C,
    deck: Value,
}

/// Both players' side of one game, by seat, and the mirror engine.
struct Table {
    game: String,
    p: [P; 2],
    mirror: Game,
}

impl Table {
    /// Two players queue in `mode` (a Mage and a Warrior) and get their match.
    async fn queue(addr: SocketAddr, app: &AppRef, a: &str, b: &str, mode: &str) -> Table {
        let mut ca = C::register(addr, a).await;
        let mut cb = C::register(addr, b).await;
        ca.send(json!({"t": "queue", "mode": mode, "deck": deck("MAGE")})).await;
        ca.want("queued").await;
        cb.send(json!({"t": "queue", "mode": mode, "deck": deck("WARRIOR")})).await;
        cb.want("queued").await;
        Table::matched(app, [(ca, deck("MAGE")), (cb, deck("WARRIOR"))], mode).await
    }

    /// Reads both `match` messages and the opening `state`s.
    async fn matched(app: &AppRef, mut cs: [(C, Value); 2], mode: &str) -> Table {
        let ma = cs[0].0.want("match").await;
        let mb = cs[1].0.want("match").await;
        assert_eq!(ma["game"], mb["game"]);
        assert_eq!(ma["mode"], mode);
        assert_eq!(mb["mode"], mode);
        assert!(ma.get("seed").is_none() && ma.get("host").is_none(), "{ma}");
        let (sa, sb) = (ma["you"].as_u64().unwrap(), mb["you"].as_u64().unwrap());
        assert_eq!(sa + sb, 1, "seats {ma} {mb}");
        let [x, y] = cs;
        let (p0, p1) = if sa == 0 { (x, y) } else { (y, x) };
        let game = ma["game"].as_str().unwrap().to_string();
        let seed = seed_of(app, &game).await;
        let d = |v: &Value| (v["hero"].as_str().unwrap().to_string(), cards(v));
        let ((h0, c0), (h1, c1)) = (d(&p0.1), d(&p1.1));
        let rs = ruleset::get(ma["pack"].as_str().unwrap()).expect("the game's pack is loaded");
        let mirror = Game::new_in(rs, &h0, &c0, &h1, &c1, seed, -1, true);
        let mut t = Table { game, p: [P { c: p0.0, deck: p0.1 }, P { c: p1.0, deck: p1.1 }], mirror };
        let opening: Vec<Events> = t.mirror.history[0].events();
        for q in 0..2 {
            let s = t.p[q].c.want("state").await;
            check_state(&s, &t.mirror, &opening, q);
        }
        t
    }

    async fn send(&mut self, p: usize, action: Value) {
        let game = self.game.clone();
        self.p[p].c.send(json!({"t": "act", "game": game, "action": action})).await;
    }

    /// Player p plays `action` (legal): both players get the state the mirror has after it.
    async fn act(&mut self, p: usize, action: Value) {
        self.send(p, action.clone()).await;
        let r = self.mirror.apply(&action);
        assert!(r.ok, "the mirror refused {action}: {}", r.error);
        for q in 0..2 {
            let s = self.p[q].c.want("state").await;
            check_state(&s, &self.mirror, &r.events, q);
        }
    }

    /// The next action by the engine's bot: (player, action).
    fn next(&self) -> (usize, Value) {
        let g = &self.mirror;
        let p = if g.phase == "MULLIGAN" {
            (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
        } else {
            g.pending.as_ref().map_or(g.current, |c| c.player)
        };
        let a = bot::choose(g, p).map_or(json!({"type": "end_turn", "player": p}), Value::Object);
        (p, a)
    }
}

fn cards(d: &Value) -> Vec<String> {
    d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect()
}

/// The seed of a game, from the event log (admins see it; players never get it).
async fn seed_of(app: &AppRef, game: &str) -> i64 {
    for _ in 0..100 {
        let m = event::Entity::find().filter(event::Column::Game.eq(game)).filter(event::Column::Kind.eq("match")).one(&app.db).await.unwrap();
        if let Some(m) = m {
            let d: Value = serde_json::from_str(m.data.as_deref().unwrap()).unwrap();
            return d["seed"].as_i64().unwrap();
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("no match event for {game}");
}

/// A `state` is exactly the mirror's view and events for player p, and hides the opponent's cards.
fn check_state(s: &Value, g: &Game, events: &[Events], p: usize) {
    assert_eq!(s["view"], snapshot(g, p as i64), "view of player {p}");
    assert_eq!(s["events"], events_for(g, events, p as i64), "events for player {p}");
    let r = &s["result"];
    assert_eq!((r["over"].as_bool(), r["winner"].as_i64(), r["turn"].as_i64()), (Some(g.game_over), Some(g.winner), Some(g.turn)));
    assert_eq!((r["current"].as_u64(), r["phase"].as_str()), (Some(g.current as u64), Some(g.phase)));
    assert!(r["deadline"].is_u64(), "{r}");
    assert_no_leak(s, g, p);
}

/// No card of an entity in the opponent's hand, deck or secrets anywhere in what player p gets:
/// every object with a non-empty "card" is tied to an entity (the key in `entities`, or
/// `entity`/`to` in an event) that p may see now; no RNG state, no deck lists.
fn assert_no_leak(s: &Value, g: &Game, p: usize) {
    let hidden = |id: i64| g.ent(id).is_some_and(|e| e.controller != p && matches!(e.zone, "DECK" | "HAND" | "SECRET"));
    fn walk(v: &Value, owner: Option<i64>, hidden: &dyn Fn(i64) -> bool, path: &str) {
        match v {
            Value::Object(o) => {
                let id = o.get("entity").or_else(|| o.get("to")).and_then(Value::as_i64).or(owner);
                if let Some(c) = o.get("card").and_then(Value::as_str).filter(|c| !c.is_empty()) {
                    let id = id.unwrap_or_else(|| panic!("card {c} without an entity at {path}"));
                    assert!(!hidden(id), "hidden card {c} (entity {id}) leaks at {path}");
                }
                for (k, x) in o {
                    let owner = if path.ends_with(".entities") { k.parse().ok() } else { id };
                    walk(x, owner, hidden, &format!("{path}.{k}"));
                }
            }
            Value::Array(a) => a.iter().enumerate().for_each(|(i, x)| walk(x, owner, hidden, &format!("{path}[{i}]"))),
            _ => {}
        }
    }
    walk(s, None, &hidden, "");
    let view = &s["view"];
    assert!(view.get("rng").is_none() && view.get("start_decks").is_none());
    for q in 0..2 {
        assert_eq!(view["players"][q]["deck"], json!([]));
    }
    for id in g.players[1 - p].hand.iter().chain(&g.players[1 - p].secrets) {
        assert_eq!(view["entities"][id.to_string()]["card"], "", "opponent's entity {id}");
    }
    for id in &g.players[1 - p].deck {
        assert!(view["entities"].get(id.to_string()).is_none(), "opponent's deck entity {id} shown");
    }
}

/// Plays the game to its end with the engine's bot on both sides; returns both game_overs by seat.
async fn play_out(t: &mut Table) -> [Value; 2] {
    let mut n = 0;
    while !t.mirror.game_over {
        let (p, a) = t.next();
        t.act(p, a).await;
        n += 1;
        assert!(n < 3000, "the game does not end");
    }
    let (g0, g1) = (t.p[0].c.want("game_over").await, t.p[1].c.want("game_over").await);
    let w = t.mirror.winner;
    for (p, g) in [&g0, &g1].into_iter().enumerate() {
        let want = if w < 0 { "draw" } else if w == p as i64 { "win" } else { "loss" };
        assert_eq!((g["result"].as_str(), g["reason"].as_str()), (Some(want), Some("over")), "{g}");
    }
    eprintln!("game {}: {n} actions, turn {}, winner {w}", t.game, t.mirror.turn);
    [g0, g1]
}

#[tokio::test]
async fn casual_game_played_out_by_bots() {
    let (addr, app) = server(std_server()).await;
    let mut t = Table::queue(addr, &app, "alice", "bob", "casual").await;
    // Emotes and intents go to the opponent with the sender's seat.
    t.p[0].c.send(json!({"t": "emote", "game": t.game, "id": "greetings"})).await;
    let e = t.p[1].c.want("emote").await;
    assert_eq!((e["id"].as_str(), e["from"].as_u64(), e["game"].as_str()), (Some("greetings"), Some(0), Some(t.game.as_str())));
    t.p[1].c.send(json!({"t": "intent", "i": {"k": "hover", "i": 3}})).await;
    let i = t.p[0].c.want("intent").await;
    assert_eq!((i["i"]["k"].as_str(), i["from"].as_u64()), (Some("hover"), Some(1)));
    let start = std::time::Instant::now();
    let n0 = t.mirror.history.len();
    play_out(&mut t).await;
    let n = t.mirror.history.len() - n0;
    eprintln!("{n} actions over WebSocket in {:?} ({:.0} actions/s, with the mirror and the checks)", start.elapsed(),
              n as f64 / start.elapsed().as_secs_f64());
    if t.mirror.winner >= 0 {
        let mmrs: Vec<(String, f64)> = standing::Entity::find().order_by_asc(standing::Column::CasualMmr).all(&app.db).await.unwrap()
            .iter().map(|s| (s.pack.clone(), s.casual_mmr)).collect();
        assert_eq!(mmrs, vec![("classic-2014".into(), 1484.0), ("classic-2014".into(), 1516.0)]);
    }
    assert!(app.hub().games.is_empty());
    // Free to queue again.
    t.p[0].c.send(json!({"t": "queue", "mode": "casual", "deck": t.p[0].deck})).await;
    t.p[0].c.want("queued").await;
}

#[tokio::test]
async fn ranked_game_played_out_by_bots() {
    let (addr, app) = server(std_server()).await;
    let mut t = Table::queue(addr, &app, "carol", "dave", "ranked").await;
    let [g0, g1] = play_out(&mut t).await;
    if t.mirror.winner >= 0 {
        let w = t.mirror.winner as usize;
        let (gw, gl) = if w == 0 { (g0, g1) } else { (g1, g0) };
        assert_eq!(gw["rank"]["stars"], 1);
        assert_eq!((gl["rank"]["rank"].as_i64(), gl["rank"]["stars"].as_i64()), (Some(25), Some(0)));
    }
}

#[tokio::test]
async fn refused_actions_and_three_strikes() {
    let (addr, app) = server(std_server()).await;
    let mut t = Table::queue(addr, &app, "erin", "frank", "casual").await;
    // Another seat's action, nonsense, a card that is not in the hand: refused, nothing changes.
    t.send(0, json!({"type": "mulligan", "player": 1, "replace": []})).await;
    let e = t.p[0].c.want("act_error").await;
    assert_eq!(e["game"], t.game.as_str());
    assert!(e["error"].as_str().unwrap().contains("player 0"), "{e}");
    t.send(0, json!("end_turn")).await;
    t.p[0].c.want("act_error").await;
    // A legal move still works after two refusals.
    t.act(0, json!({"type": "mulligan", "player": 0, "replace": []})).await;
    t.act(1, json!({"type": "mulligan", "player": 1, "replace": []})).await;
    // The other player's refusals count for them alone.
    t.send(1, json!({"type": "mulligan", "player": 1, "replace": []})).await;
    assert!(t.p[1].c.want("act_error").await["error"].as_str().unwrap().contains("illegal"));
    // The third refusal ends the game: player 0 loses, both get the message.
    t.send(0, json!({"type": "attack", "player": 0, "attacker": 999, "defender": 1})).await;
    t.p[0].c.want("act_error").await;
    let (g0, g1) = (t.p[0].c.want("game_over").await, t.p[1].c.want("game_over").await);
    assert_eq!((g0["result"].as_str(), g0["reason"].as_str()), (Some("loss"), Some("illegal")));
    assert_eq!((g1["result"].as_str(), g1["reason"].as_str()), (Some("win"), Some("illegal")));
    assert_eq!(g0["message"], DOES_NOT_ADD_UP);
    assert_eq!(g1["message"], DOES_NOT_ADD_UP);
    assert!(DOES_NOT_ADD_UP.starts_with("Something does not add up"));
    // The event log: every applied action with turn and hash, the end with the refused moves.
    let evs = game_events(&app, &t.game).await;
    let kinds: Vec<&str> = evs.iter().map(|e| e.kind.as_str()).collect();
    assert_eq!(kinds, ["match", "game_start", "game_action", "game_action", "game_end"]);
    let act: Value = serde_json::from_str(evs[2].data.as_deref().unwrap()).unwrap();
    assert!(act["hash"].as_str().unwrap().len() == 64 && act["turn"].is_i64() && act["events"].is_array(), "{act}");
    assert!(evs[2].text.ends_with(": mulligan replaces 0"), "{}", evs[2].text);
    let end: Value = serde_json::from_str(evs[4].data.as_deref().unwrap()).unwrap();
    assert_eq!(end["reason"], "illegal");
    assert_eq!(end["refused"].as_array().unwrap().len(), 3);
    assert_eq!(end["message"]["type"], "attack");
}

/// The game's events once game_end is logged.
async fn game_events(app: &AppRef, game: &str) -> Vec<event::Model> {
    for _ in 0..100 {
        let evs = event::Entity::find().filter(event::Column::Game.eq(game)).order_by_asc(event::Column::Id).all(&app.db).await.unwrap();
        if evs.last().is_some_and(|e| e.kind == "game_end") {
            return evs;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("no game_end for {game}");
}

#[tokio::test]
async fn timeout_moves() {
    let ms = Duration::from_millis;
    let (addr, app) = server(Timers { turn: ms(400), mulligan: ms(300), slack: ms(100), ..Timers::default() }).await;
    let mut t = Table::queue(addr, &app, "gina", "hank", "casual").await;
    // Nobody moves: the server keeps both hands, then ends the turns.
    for p in 0..2 {
        let a = json!({"type": "mulligan", "player": p, "replace": []});
        let r = t.mirror.apply(&a);
        assert!(r.ok);
        for q in 0..2 {
            check_state(&t.p[q].c.want("state").await, &t.mirror, &r.events, q);
        }
    }
    assert_eq!(t.mirror.phase, "PLAY");
    for _ in 0..2 {
        let cur = t.mirror.current;
        let r = t.mirror.apply(&json!({"type": "end_turn", "player": cur}));
        for q in 0..2 {
            let s = t.p[q].c.want("state").await;
            check_state(&s, &t.mirror, &r.events, q);
            assert_eq!(s["result"]["current"], 1 - cur);
        }
    }
    // A move in time keeps the game going; then the opponent's turn times out again.
    let (p, a) = t.next();
    t.act(p, a).await;
    t.p[0].c.send(json!({"t": "act", "action": {"type": "concede", "player": 0}})).await;
    t.mirror.apply(&json!({"type": "concede", "player": 0}));
    t.p[0].c.want("game_over").await;
    let evs = game_events(&app, &t.game).await;
    let timeouts = evs
        .iter()
        .filter(|e| e.kind == "game_action")
        .filter(|e| serde_json::from_str::<Value>(e.data.as_deref().unwrap()).unwrap()["timeout"] == true)
        .count();
    assert!(timeouts >= 4, "{timeouts} timeout moves");
}

#[tokio::test]
async fn rejoin_and_disconnect() {
    let (addr, app) = server(Timers { away: Duration::from_millis(800), ..Timers::default() }).await;
    let mut t = Table::queue(addr, &app, "ivan", "judy", "casual").await;
    t.act(0, json!({"type": "mulligan", "player": 0, "replace": []})).await;
    // Player 0 drops out and logs in again: match (rejoin) and a fresh state.
    let token = t.p[0].c.token.clone();
    let old = std::mem::replace(&mut t.p[0].c, C::connect(addr).await);
    drop(old);
    tokio::time::sleep(Duration::from_millis(100)).await;
    t.p[0].c.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(t.p[0].c.want("auth").await["ok"], true);
    let m = t.p[0].c.want("match").await;
    assert_eq!((m["rejoin"].as_bool(), m["you"].as_u64(), m["game"].as_str()), (Some(true), Some(0), Some(t.game.as_str())));
    let s = t.p[0].c.want("state").await;
    check_state(&s, &t.mirror, &[], 0);
    assert_eq!(s["events"], json!([]));
    // The game goes on.
    t.act(1, json!({"type": "mulligan", "player": 1, "replace": []})).await;
    let (p, a) = t.next();
    t.act(p, a).await;
    // Gone for good: the other player wins after the grace time.
    drop(std::mem::replace(&mut t.p[1].c, C::connect(addr).await));
    let g = t.p[0].c.want("game_over").await;
    assert_eq!((g["result"].as_str(), g["reason"].as_str()), (Some("win"), Some("disconnect")));
}

#[tokio::test]
async fn social_and_friendly_invite() {
    let (addr, app) = server(std_server()).await;
    let mut a = C::register(addr, "mona").await;
    let mut b = C::register(addr, "ned").await;
    a.send(json!({"t": "set_tag", "tag": "Mona"})).await;
    assert_eq!(a.want("me").await["me"]["tag"], "Mona");
    b.send(json!({"t": "set_tag", "tag": "mONA"})).await;
    assert_eq!(b.want("error").await["code"], "tag_taken");
    b.send(json!({"t": "set_tag", "tag": "Ned"})).await;
    b.want("me").await;
    a.send(json!({"t": "friend_add", "tag": "ned"})).await;
    assert_eq!(a.want("friends").await["requests_out"][0]["user"], "ned");
    assert_eq!(b.want("friends").await["requests_in"][0]["user"], "mona");
    b.send(json!({"t": "friend_accept", "user": "mona"})).await;
    let f = b.want("friends").await;
    assert_eq!(f["list"][0]["user"], "mona");
    assert_eq!(f["list"][0]["online"], true);
    a.want("friends").await;
    a.send(json!({"t": "msg", "to": "ned", "text": "hi"})).await;
    a.want("msg_sent").await;
    let m = b.want("msg").await;
    assert_eq!((m["from"].as_str(), m["text"].as_str()), (Some("mona"), Some("hi")));
    b.send(json!({"t": "history", "with": "mona"})).await;
    assert_eq!(b.want("history").await["list"][0]["text"], "hi");
    a.send(json!({"t": "msg", "to": "ned", "text": ""})).await;
    assert_eq!(a.want("error").await["code"], "bad_text");

    // Decks are checked by the engine.
    let mut bad = deck("MAGE");
    bad["cards"][0] = json!(deck::basic("WARRIOR")[0]);
    a.send(json!({"t": "invite", "to": "ned", "deck": bad})).await;
    assert_eq!(a.want("error").await["text"], "This card belongs to another class");

    // Friendly game by invite; a concede ends it.
    a.send(json!({"t": "invite", "to": "ned", "deck": deck("MAGE")})).await;
    a.want("invited").await;
    assert_eq!(b.want("invite").await["from"], "mona");
    b.send(json!({"t": "invite_accept", "from": "mona", "deck": deck("WARRIOR")})).await;
    let mut t = Table::matched(&app, [(a, deck("MAGE")), (b, deck("WARRIOR"))], "friendly").await;
    t.act(1, json!({"type": "concede", "player": 1})).await;
    let g = t.p[0].c.want("game_over").await;
    assert_eq!((g["result"].as_str(), g["reason"].as_str()), (Some("win"), Some("over")));
    assert!(g.get("rank").is_none());
    t.p[1].c.want("game_over").await;
    let mona_first = t.p[0].deck["hero"] == "HERO_08";
    let [P { c: x, .. }, P { c: y, .. }] = t.p;
    let (mut a, mut b) = if mona_first { (x, y) } else { (y, x) };

    // A block ends the friendship and stops messages and invites.
    b.send(json!({"t": "block", "user": "mona"})).await;
    assert_eq!(b.want("friends").await["blocked"][0]["user"], "mona");
    a.send(json!({"t": "msg", "to": "ned", "text": "hello?"})).await;
    assert_eq!(a.want("error").await["code"], "not_friends");
    a.send(json!({"t": "friend_add", "tag": "Ned"})).await;
    assert_eq!(a.want("error").await["code"], "not_found");
    a.send(json!({"t": "invite", "to": "ned", "deck": deck("MAGE")})).await;
    assert_eq!(a.want("error").await["code"], "not_friends");
}

#[tokio::test]
async fn arena_run() {
    let (addr, app) = server(std_server()).await;
    let mut cs = vec![];
    for name in ["olga", "pete"] {
        let mut c = C::register(addr, name).await;
        c.send(json!({"t": "arena_start"})).await;
        let s = c.want("arena").await;
        assert_eq!(s["state"]["heroes"].as_array().unwrap().len(), 3);
        c.send(json!({"t": "arena_queue"})).await;
        assert_eq!(c.want("error").await["code"], "not_ready");
        c.send(json!({"t": "arena_hero", "i": 1})).await;
        let s = c.want("arena").await;
        assert_eq!(s["state"]["hero"], s["state"]["heroes"][1]);
        let mut last = s;
        for k in 0..30 {
            assert_eq!(last["state"]["offer"].as_array().unwrap().len(), 3);
            c.send(json!({"t": "arena_pick", "i": k % 3})).await;
            last = c.want("arena").await;
        }
        assert_eq!(last["state"]["done"], true);
        assert_eq!(last["state"]["cards"].as_array().unwrap().len(), 30);
        c.send(json!({"t": "arena_pick", "i": 0})).await;
        assert_eq!(c.want("error").await["code"], "bad_request");
        c.send(json!({"t": "arena_queue"})).await;
        assert_eq!(c.want("queued").await["mode"], "arena");
        let d = json!({"hero": last["state"]["hero"], "cards": last["state"]["cards"], "arena": true});
        cs.push((c, d));
    }
    let cs: [(C, Value); 2] = cs.try_into().ok().unwrap();
    let mut t = Table::matched(&app, cs, "arena").await;
    t.act(0, json!({"type": "concede", "player": 0})).await;
    let h = t.p[0].c.want("game_over").await;
    assert_eq!(h["arena"]["losses"], 1);
    assert_eq!(h["arena"]["over"], false);
    assert_eq!(t.p[1].c.want("game_over").await["arena"]["wins"], 1);
    t.p[0].c.send(json!({"t": "arena_retire"})).await;
    assert_eq!(t.p[0].c.want("arena").await["state"], Value::Null);
}

#[tokio::test]
async fn auth_rules_and_abuse() {
    let (addr, _app) = server(std_server()).await;
    let mut c = C::connect(addr).await;
    c.send(json!({"t": "friends"})).await;
    assert_eq!(c.want("error").await["code"], "auth_required");
    c.send(json!({"t": "register", "user": "x", "password": "password123"})).await;
    assert_eq!(c.want("error").await["code"], "bad_user");
    c.send(json!({"t": "register", "user": "quinn", "password": "short"})).await;
    assert_eq!(c.want("error").await["code"], "bad_password");
    c.send(json!({"t": "register", "user": "quinn", "password": "password123", "extra": 1})).await;
    assert_eq!(c.want("error").await["code"], "bad_request");
    c.send(json!({"t": "register", "user": "quinn", "password": "password123"})).await;
    let token = c.want("auth").await["token"].as_str().unwrap().to_string();
    // The old relay message is gone; actions outside a game are dropped.
    c.send(json!({"t": "game", "m": {"t": "hello"}})).await;
    assert_eq!(c.want("error").await["code"], "bad_request");
    c.send(json!({"t": "act", "action": {"type": "end_turn", "player": 0}})).await;
    c.send(json!({"t": "ping"})).await;
    c.want("pong").await;

    // Wrong password, then resume with the token on a new connection.
    let mut d = C::connect(addr).await;
    d.send(json!({"t": "login", "user": "quinn", "password": "wrongpassword"})).await;
    assert_eq!(d.want("error").await["code"], "bad_login");
    d.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(d.want("auth").await["me"]["user"], "quinn");
    assert_eq!(c.want("kicked").await["reason"], "another_login");
    d.send(json!({"t": "logout"})).await;
    d.want("logged_out").await;
    d.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(d.want("error").await["code"], "bad_token");

    // Garbage again and again: the server hangs up.
    let mut e = C::connect(addr).await;
    let mut sent = 0;
    for _ in 0..25 {
        if e.ws.send(Message::text("{not json")).await.is_err() {
            break;
        }
        sent += 1;
    }
    // What came back, for the message when it fails (CI once saw no close here, 2026-10-24).
    let (mut closed, mut replies, mut silent) = (false, 0, 0);
    while !closed && silent < 3 {
        match tokio::time::timeout(Duration::from_secs(5), e.ws.next()).await {
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) | Ok(Some(Err(_))) => closed = true,
            Ok(Some(Ok(Message::Text(_)))) => replies += 1,
            Ok(Some(Ok(_))) => {}
            Err(_) => silent += 1,
        }
    }
    assert!(closed, "not closed: {sent} bad messages sent, {replies} replies, then {silent} silent waits of 5 s");
}

#[tokio::test]
async fn presence_chats_and_read() {
    let (addr, app) = server(std_server()).await;
    let mut a = C::connect(addr).await;
    a.send(json!({"t": "register", "user": "uma", "password": "password123"})).await;
    let token = a.want("auth").await["token"].as_str().unwrap().to_string();
    let mut b = C::register(addr, "vic").await;
    b.send(json!({"t": "set_tag", "tag": "Vic"})).await;
    b.want("me").await;
    a.send(json!({"t": "friend_add", "tag": "vic"})).await;
    b.want("friends").await;
    b.send(json!({"t": "friend_accept", "user": "uma"})).await;
    let p = a.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some("vic"), Some(true), Some("online")));
    assert_eq!(b.want("presence").await["user"], "uma");

    // No messages yet; then two, unread until read.
    b.send(json!({"t": "chats"})).await;
    let c = b.want("chats").await;
    assert_eq!(c["list"][0]["with"], "uma");
    assert_eq!(c["list"][0]["status"], "online");
    assert_eq!((c["list"][0]["last"].clone(), c["list"][0]["unread"].as_i64()), (Value::Null, Some(0)));
    for text in ["hello", "again"] {
        a.send(json!({"t": "msg", "to": "vic", "text": text})).await;
        a.want("msg_sent").await;
        assert_eq!(b.want("msg").await["text"], text);
    }
    b.send(json!({"t": "msg", "to": "uma", "text": "hi"})).await;
    b.want("msg_sent").await;
    b.send(json!({"t": "chats"})).await;
    let c = b.want("chats").await;
    assert_eq!(c["list"][0]["unread"], 2);
    assert_eq!((c["list"][0]["last"]["from"].as_str(), c["list"][0]["last"]["text"].as_str()), (Some("vic"), Some("hi")));
    a.send(json!({"t": "chats"})).await;
    assert_eq!(a.want("chats").await["list"][0]["unread"], 1);
    b.send(json!({"t": "read", "with": "uma"})).await;
    assert_eq!(b.want("read_ok").await["with"], "uma");
    b.send(json!({"t": "chats"})).await;
    assert_eq!(b.want("chats").await["list"][0]["unread"], 0);
    b.send(json!({"t": "read", "with": "nobody_here"})).await;
    assert_eq!(b.want("error").await["code"], "not_found");

    // Searching, back online, offline, back by token.
    a.send(json!({"t": "queue", "mode": "casual", "deck": deck("MAGE")})).await;
    assert_eq!(b.want("presence").await["status"], "searching");
    a.send(json!({"t": "unqueue"})).await;
    assert_eq!(b.want("presence").await["status"], "online");
    drop(a);
    let p = b.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some("uma"), Some(false), Some("offline")));

    // The token is renewed on use: 30 days from now again.
    use classichs_server::entity::session;
    let soon = classichs_server::ranked::now() + 60;
    session::Entity::update_many().col_expr(session::Column::Expires, soon.into()).exec(&app.db).await.unwrap();
    let mut a = C::connect(addr).await;
    a.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(a.want("auth").await["me"]["user"], "uma");
    assert_eq!(b.want("presence").await["status"], "online");
    let s = session::Entity::find().filter(session::Column::Account.eq(1)).one(&app.db).await.unwrap().unwrap();
    assert!(s.expires > soon + 29 * 86400, "renewed: {}", s.expires);
}

#[tokio::test]
async fn presence_follows_a_game() {
    let (addr, app) = server(std_server()).await;
    let mut f = C::register(addr, "yuri").await;
    let mut t = Table::queue(addr, &app, "zack", "abby", "casual").await;
    f.send(json!({"t": "set_tag", "tag": "Yuri"})).await;
    f.want("me").await;
    t.p[0].c.send(json!({"t": "me"})).await;
    let name = t.p[0].c.want("me").await["me"]["user"].as_str().unwrap().to_string();
    t.p[0].c.send(json!({"t": "friend_add", "tag": "yuri"})).await;
    f.want("friends").await;
    f.send(json!({"t": "friend_accept", "user": name})).await;
    let p = f.want("presence").await;
    assert_eq!((p["user"].as_str(), p["status"].as_str()), (Some(name.as_str()), Some("in_game")));
    t.act(0, json!({"type": "concede", "player": 0})).await;
    t.p[0].c.want("game_over").await;
    t.p[1].c.want("game_over").await;
    let p = f.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some(name.as_str()), Some(true), Some("online")));
}

/// Waits until the old connection is closed by the server.
async fn closed(c: &mut C) {
    for _ in 0..40 {
        match tokio::time::timeout(Duration::from_secs(5), c.ws.next()).await {
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) | Ok(Some(Err(_))) => return,
            Ok(Some(Ok(Message::Text(t)))) => panic!("after kicked: {t}"),
            Ok(Some(Ok(_))) => {}
            Err(_) => panic!("not closed"),
        }
    }
}

#[tokio::test]
async fn second_login_kicks_the_first() {
    let (addr, app) = server(std_server()).await;
    let mut f = C::register(addr, "fred").await;
    let mut t = Table::queue(addr, &app, "kim", "lee", "casual").await;
    f.send(json!({"t": "set_tag", "tag": "Fred"})).await;
    f.want("me").await;
    t.p[0].c.send(json!({"t": "me"})).await;
    let name = t.p[0].c.want("me").await["me"]["user"].as_str().unwrap().to_string();
    t.p[0].c.send(json!({"t": "friend_add", "tag": "fred"})).await;
    f.want("friends").await;
    f.send(json!({"t": "friend_accept", "user": name})).await;
    assert_eq!(f.want("presence").await["status"], "in_game");
    t.act(0, json!({"type": "mulligan", "player": 0, "replace": []})).await;

    // The same account logs in on a new connection while the old one is still open (password this time).
    let mut d = C::connect(addr).await;
    d.send(json!({"t": "login", "user": name, "password": "password123"})).await;
    assert_eq!(d.want("auth").await["me"]["user"], name.as_str());
    let k = t.p[0].c.want("kicked").await;
    assert_eq!(k, json!({"t": "kicked", "reason": "another_login"}));
    // The close frame says it again: code 4001, reason "another_login".
    match tokio::time::timeout(Duration::from_secs(5), t.p[0].c.ws.next()).await.unwrap() {
        Some(Ok(Message::Close(Some(f)))) => assert_eq!((u16::from(f.code), f.reason.as_str()), (4001, "another_login")),
        other => panic!("not closed with 4001: {other:?}"),
    }
    closed(&mut t.p[0].c).await;
    // The new connection takes the game over: match (rejoin) and a fresh state.
    let m = d.want("match").await;
    assert_eq!((m["rejoin"].as_bool(), m["you"].as_u64(), m["game"].as_str()), (Some(true), Some(0), Some(t.game.as_str())));
    let s = d.want("state").await;
    check_state(&s, &t.mirror, &[], 0);
    t.p[0].c = d;
    t.act(1, json!({"type": "mulligan", "player": 1, "replace": []})).await;
    let (p, a) = t.next();
    t.act(p, a).await;

    // Still in the game for the friends: no offline in between. A message proves nothing else came.
    f.send(json!({"t": "ping"})).await;
    let mut seen = vec![];
    loop {
        let m = tokio::time::timeout(Duration::from_secs(5), f.ws.next()).await.unwrap().unwrap().unwrap();
        let v: Value = serde_json::from_str(m.to_text().unwrap()).unwrap();
        if v["t"] == "pong" {
            break;
        }
        seen.push(v);
    }
    assert!(seen.iter().all(|v| v["t"] != "presence"), "{seen:?}");
    let id = db::id_by_name(&app.db, &name).await.unwrap().unwrap();
    assert_eq!(app.hub().status(id), "in_game");

    // Logged: kicked, and neither a disconnect nor leaving the game.
    let mut kinds = vec![];
    for _ in 0..50 {
        kinds = event::Entity::find().filter(event::Column::Account.eq(id)).order_by_asc(event::Column::Id).all(&app.db).await.unwrap()
            .into_iter().map(|e| e.kind).collect::<Vec<_>>();
        if kinds.iter().any(|k| k == "game_back") {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(kinds.iter().any(|k| k == "kicked"), "{kinds:?}");
    assert!(!kinds.iter().any(|k| k == "disconnect" || k == "game_left"), "{kinds:?}");
}

// --- games in packs -----------------------------------------------------------------------------

/// Installs a test pack (common::pack_bytes) as a server pack (owner None) or a player's.
async fn install(app: &AppRef, zip: &[u8], owner: Option<i64>) -> pack::Model {
    let path = std::env::temp_dir().join(format!("chs-test-{}.cardpack", rand::random::<u64>()));
    std::fs::write(&path, zip).unwrap();
    let p = packs::add(app, &path, zip.len() as u64, owner).await.unwrap_or_else(|e| panic!("{}", e.2));
    let _ = std::fs::remove_file(path);
    p
}

/// A pack with one-second turns, a three-rank ladder without Legend and a one-win Arena.
fn quick_pack() -> Vec<u8> {
    let ladder = json!({"start": {"rank": 3, "stars": 0}, "ranks": [{"rank": 3, "stars": 1}, {"rank": 2, "stars": 1}, {"rank": 1, "stars": 1}],
        "streak": {"wins": 9, "bonus_stars": 1}, "legend": null, "season": {"length": "month", "reset": {"to_rank": 3, "stars_per_rank_above": 0}}});
    common::pack_bytes("org.test.quick", "1.0.0", &[
        ("/timers", json!({"turn": 1, "fuse": 1, "mulligan": 1, "grace": 1, "away": 2})),
        ("/ranked", ladder),
        ("/modes/arena/wins", json!(1)),
    ], &[])
}

/// Queues and games are per pack; timers and ranks come from the pack's rules.json; ranks are
/// kept per pack; `me {pack}` shows the rank in that pack.
#[tokio::test]
async fn games_in_a_pack_with_its_own_rules() {
    let (addr, app) = server_with(None).await;
    let quick = install(&app, &quick_pack(), None).await;
    let rh = quick.rules_hash.clone();
    let mut a = C::register(addr, "ppa").await;
    let mut b = C::register(addr, "ppb").await;
    let mut c = C::register(addr, "ppc").await;
    a.send(json!({"t": "queue", "mode": "ranked", "deck": deck("MAGE"), "pack": rh})).await;
    assert_eq!(a.want("queued").await["pack"], rh);
    c.send(json!({"t": "queue", "mode": "ranked", "deck": deck("MAGE")})).await; // the default game
    assert_eq!(c.want("queued").await["pack"], packs::GameRules::classic().rules_hash.as_str());
    b.send(json!({"t": "queue", "mode": "ranked", "deck": deck("WARRIOR"), "pack": rh})).await;
    b.want("queued").await;
    // Unknown packs and bad decks for a pack are refused.
    let mut d = C::register(addr, "ppd").await;
    d.send(json!({"t": "queue", "mode": "casual", "deck": deck("MAGE"), "pack": "f".repeat(64)})).await;
    assert_eq!(d.want("error").await["code"], "pack");
    let ma = a.want("match").await;
    let mb = b.want("match").await;
    assert_eq!((ma["pack"].as_str(), mb["pack"].as_str()), (Some(rh.as_str()), Some(rh.as_str())));
    let cid = db::id_by_name(&app.db, "ppc").await.unwrap().unwrap();
    assert!(app.hub().queue.contains_key(&cid), "the other pack's seeker still waits");
    let live = app.hub().live_json();
    assert_eq!(live["games"][0]["pack"], rh.as_str());
    // The pack's clock: one second a mulligan (and one of grace), then the server moves.
    let s = a.want("state").await;
    assert!(s["result"]["deadline"].as_u64().unwrap() <= 1, "{}", s["result"]);
    let t0 = std::time::Instant::now();
    let s = a.want("state").await;
    assert_eq!(s["result"]["phase"], "MULLIGAN");
    assert!(t0.elapsed() >= Duration::from_millis(1500) && t0.elapsed() < Duration::from_secs(4), "{:?}", t0.elapsed());
    // A concede: ranks move on the pack's ladder.
    let pa = ma["you"].as_u64().unwrap();
    a.send(json!({"t": "act", "action": {"type": "concede", "player": pa}})).await;
    let (ga, gb) = (a.want("game_over").await, b.want("game_over").await);
    assert_eq!((ga["rank"]["rank"].as_i64(), ga["rank"]["stars"].as_i64()), (Some(3), Some(0)), "{ga}");
    assert_eq!((gb["rank"]["rank"].as_i64(), gb["rank"]["stars"].as_i64()), (Some(3), Some(1)), "{gb}");
    b.send(json!({"t": "me", "pack": rh})).await;
    let me = b.want("me").await["me"].clone();
    assert_eq!((me["rank"]["rank"].as_i64(), me["rank"]["stars"].as_i64(), me["pack"].as_str()), (Some(3), Some(1), Some(rh.as_str())));
    b.send(json!({"t": "me"})).await;
    let me = b.want("me").await["me"].clone();
    assert_eq!((me["rank"]["rank"].as_i64(), me["rank"]["stars"].as_i64()), (Some(25), Some(0)), "the default game's rank is apart");
    let st = standing::Entity::find().filter(standing::Column::Pack.eq("org.test.quick")).all(&app.db).await.unwrap();
    assert_eq!(st.len(), 2);
    let rows = classichs_server::entity::game::Entity::find().all(&app.db).await.unwrap();
    assert_eq!(rows[0].pack, rh);
}

/// D12: a friendly game in the inviter's own pack; the invite says which (to download it).
#[tokio::test]
async fn friendly_game_in_the_inviters_pack() {
    let (addr, app) = server(std_server()).await;
    let mut a = C::register(addr, "ffa").await;
    let mut b = C::register(addr, "ffb").await;
    a.send(json!({"t": "set_tag", "tag": "Ffa"})).await;
    a.want("me").await;
    b.send(json!({"t": "friend_add", "tag": "ffa"})).await;
    a.want("friends").await;
    a.send(json!({"t": "friend_accept", "user": "ffb"})).await;
    b.want("friends").await;
    let aid = db::id_by_name(&app.db, "ffa").await.unwrap().unwrap();
    let mine = install(&app, &common::pack_bytes("org.test.fa", "0.1.0", &[("/limits/queue_steps", json!(4999))], &[]), Some(aid)).await;
    // Not the inviter's pack: refused (b invites with a's pack).
    b.send(json!({"t": "invite", "to": "ffa", "deck": deck("MAGE"), "pack": mine.rules_hash})).await;
    assert_eq!(b.want("error").await["code"], "pack");
    a.send(json!({"t": "invite", "to": "ffb", "deck": deck("MAGE"), "pack": mine.rules_hash})).await;
    a.want("invited").await;
    let inv = b.want("invite").await;
    assert_eq!((inv["pack"]["content_hash"].as_str(), inv["pack"]["size"].as_i64()), (Some(mine.content_hash.as_str()), Some(mine.size)));
    assert_eq!(inv["pack"]["url"], format!("/packs/{}.cardpack", mine.content_hash));
    b.send(json!({"t": "invite_accept", "from": "ffa", "deck": deck("WARRIOR"), "pack": "0".repeat(64)})).await;
    assert_eq!(b.want("error").await["code"], "pack");
    b.send(json!({"t": "invite_accept", "from": "ffa", "deck": deck("WARRIOR"), "pack": mine.rules_hash})).await;
    let mut t = Table::matched(&app, [(a, deck("MAGE")), (b, deck("WARRIOR"))], "friendly").await;
    assert_eq!(app.hub().games.values().next().unwrap().pack, mine.rules_hash);
    t.act(0, json!({"type": "concede", "player": 0})).await;
    t.p[0].c.want("game_over").await;
}

/// An Arena run in a pack: drafted with its rules, ended by its win count.
#[tokio::test]
async fn arena_run_in_a_pack() {
    let (addr, app) = server(std_server()).await;
    let quick = install(&app, &quick_pack(), None).await;
    let mut cs = vec![];
    for name in ["aaa", "aab"] {
        let mut c = C::register(addr, name).await;
        c.send(json!({"t": "arena_start", "pack": quick.rules_hash})).await;
        let s = c.want("arena").await;
        assert_eq!(s["state"]["pack"], quick.rules_hash.as_str());
        c.send(json!({"t": "arena_hero", "i": 0})).await;
        let mut last = c.want("arena").await;
        while last["state"]["done"] != true {
            c.send(json!({"t": "arena_pick", "i": 0})).await;
            last = c.want("arena").await;
        }
        c.send(json!({"t": "arena_queue"})).await;
        c.want("queued").await;
        cs.push((c, json!({"hero": last["state"]["hero"], "cards": last["state"]["cards"], "arena": true})));
    }
    let cs: [(C, Value); 2] = cs.try_into().ok().unwrap();
    let mut t = Table::matched(&app, cs, "arena").await;
    t.act(0, json!({"type": "concede", "player": 0})).await;
    let (g0, g1) = (t.p[0].c.want("game_over").await, t.p[1].c.want("game_over").await);
    assert_eq!((g0["arena"]["over"].as_bool(), g0["arena"]["losses"].as_i64()), (Some(false), Some(1)));
    assert_eq!((g1["arena"]["over"].as_bool(), g1["arena"]["wins"].as_i64()), (Some(true), Some(1)), "one win ends this pack's run");
}
