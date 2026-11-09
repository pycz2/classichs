//! Tournaments end to end: real WebSocket clients create, join and play them (the games are
//! decided by concedes); the clock is moved by setting `start_at` and the step deadlines in the
//! database, then `tournament::tick`.

use classichs_engine::deck;
use classichs_server::entity::tournament::{self as tour, matches as tmatch};
use classichs_server::entity::game as played;
use classichs_server::events::now_ms;
use classichs_server::packs::GameRules;
use classichs_server::storage::Storage;
use classichs_server::{db, router, spawn_background, tournament, App, AppRef, Timers};
use futures_util::{SinkExt, StreamExt};
use sea_orm::sea_query::Expr;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

const MIN: i64 = 60_000;
const CLASSES: [&str; 9] = ["MAGE", "WARRIOR", "HUNTER", "PRIEST", "ROGUE", "SHAMAN", "PALADIN", "WARLOCK", "DRUID"];

async fn server_on(path: &str) -> (SocketAddr, AppRef) {
    let _ = tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).with_test_writer().try_init();
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let app = App::new(db::open(path).await.unwrap(), false, Some(Timers::default()), store);
    spawn_background(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    (addr, app)
}

async fn server() -> (SocketAddr, AppRef) {
    server_on(":memory:").await
}

struct C {
    ws: Ws,
    name: String,
}

impl C {
    async fn register(addr: SocketAddr, name: &str) -> C {
        let (ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
        let mut c = C { ws, name: name.into() };
        c.send(json!({"t": "register", "user": name, "password": "password123"})).await;
        c.want("auth").await;
        c
    }

    async fn send(&mut self, v: Value) {
        self.ws.send(Message::text(v.to_string())).await.unwrap();
    }

    async fn next(&mut self) -> Value {
        loop {
            let m = tokio::time::timeout(Duration::from_secs(20), self.ws.next())
                .await
                .unwrap_or_else(|_| panic!("{}: timed out", self.name))
                .expect("closed")
                .unwrap();
            if let Message::Text(s) = m {
                return serde_json::from_str(s.as_str()).unwrap();
            }
        }
    }

    /// The next message of type `t` (an error fails the test unless it is wanted).
    async fn want(&mut self, t: &str) -> Value {
        loop {
            let v = self.next().await;
            if v["t"] == t {
                return v;
            }
            assert!(v["t"] != "error", "{}: error while waiting for {t}: {v}", self.name);
        }
    }

    /// The text of the error the last message gets.
    async fn refused(&mut self, v: Value) -> String {
        self.send(v).await;
        let e = self.want("error").await;
        e["text"].as_str().unwrap().to_string()
    }

    /// The next `tournament` push.
    async fn tournament(&mut self) -> Value {
        self.want("tournament").await["tournament"].clone()
    }

    /// The next message of type `t` that `f` likes.
    async fn until(&mut self, t: &str, f: impl Fn(&Value) -> bool) -> Value {
        loop {
            let v = self.want(t).await;
            if f(&v) {
                return v;
            }
        }
    }
}

fn decks(n: usize) -> Value {
    json!(CLASSES[..n].iter().map(|c| json!({"name": format!("{c} deck"), "hero": deck::hero(c).unwrap(), "cards": deck::basic(c)})).collect::<Vec<_>>())
}

fn classic() -> String {
    GameRules::classic().rules_hash.clone()
}

/// Creates a tournament (Classic, starting in 12 minutes) with these options over the defaults.
async fn create(c: &mut C, o: Value) -> Value {
    let mut m = json!({"t": "t_create", "name": "Cup", "pack": classic(), "format": "elimination", "options": {}, "series": "conquest",
                       "best_of": 1, "bans": 0, "start_at": now_ms() + 12 * MIN, "max_players": 8});
    for (k, v) in o.as_object().unwrap() {
        m[k] = v.clone();
    }
    c.send(m).await;
    // (pushes of the player's other tournaments may come first)
    c.until("tournament", |v| v["tournament"]["status"] == "open" && v["tournament"]["entrants"] == json!([])).await["tournament"].clone()
}

async fn join(c: &mut C, id: i64, n: usize) -> Value {
    c.send(json!({"t": "t_join", "id": id, "decks": decks(n)})).await;
    let me = c.name.clone();
    let mine = |v: &Value| v["tournament"]["id"] == id && v["tournament"]["entrants"].as_array().unwrap().iter().any(|e| e["name"] == me.as_str());
    c.until("tournament", mine).await["tournament"].clone()
}

/// Moves the start (the server's clock stays) and ticks.
async fn start_at(app: &AppRef, id: i64, at: i64) {
    tour::Entity::update_many().col_expr(tour::Column::StartAt, Expr::value(at)).filter(tour::Column::Id.eq(id)).exec(&app.db).await.unwrap();
    tournament::tick(app).await;
}

async fn status(app: &AppRef, id: i64) -> tour::Model {
    tour::Entity::find_by_id(id).one(&app.db).await.unwrap().unwrap()
}

/// What a player saw of its matches.
#[derive(Default)]
struct Seen {
    /// The last `t_match` of each match.
    last: HashMap<i64, Value>,
    /// Picks made per match: (score before, deck index).
    picks: Vec<(i64, i64, i64)>,
    games: Vec<String>,
    /// The `t_match`es in a pick step where the player had nothing to pick (LHS: kept deck).
    kept: Vec<Value>,
}

/// Plays the player's matches until the tournament is over: accepts, bans the opponent's first
/// usable deck, picks its own first usable one, and in each game concedes when `loses(me,
/// opponent)`. Returns the player, the final tournament and what it saw.
async fn autoplay(mut c: C, id: i64, loses: fn(&str, &str) -> bool) -> (C, Value, Seen) {
    let mut seen = Seen::default();
    let mut acted = HashSet::new();
    loop {
        let v = c.next().await;
        match v["t"].as_str().unwrap() {
            "t_match" if v["tournament"] == id => {
                let m = v["match"].as_i64().unwrap();
                let played = v["score"][0].as_i64().unwrap() + v["score"][1].as_i64().unwrap();
                let phase = v["phase"].as_str().unwrap().to_string();
                if v["status"] == "pick" && phase == "wait" && v["pick"].is_u64() {
                    seen.kept.push(v.clone());
                }
                seen.last.insert(m, v.clone());
                if !acted.insert((m, phase.clone(), played)) {
                    continue;
                }
                let first = |side: &str| v[side].as_array().unwrap().iter().position(|d| d["state"] == "ok").unwrap() as i64;
                match phase.as_str() {
                    "accept" => c.send(json!({"t": "t_accept", "match": m})).await,
                    "ban" => c.send(json!({"t": "t_ban", "match": m, "deck": first("theirs")})).await,
                    "pick" => {
                        let d = first("mine");
                        seen.picks.push((m, played, d));
                        c.send(json!({"t": "t_pick", "match": m, "deck": d})).await
                    }
                    _ => {}
                }
            }
            "match" => {
                assert_eq!(v["mode"], "tournament", "{v}");
                assert_eq!(v["tournament"], id);
                seen.games.push(v["game"].as_str().unwrap().to_string());
                if loses(&c.name, v["opponent"]["user"].as_str().unwrap()) {
                    c.send(json!({"t": "act", "game": v["game"], "action": {"type": "concede", "player": v["you"]}})).await;
                }
            }
            "tournament" if v["tournament"]["id"] == id && v["tournament"]["status"] == "finished" => return (c, v["tournament"].clone(), seen),
            "error" => panic!("{}: {v}", c.name),
            _ => {}
        }
    }
}

/// Registers players p0..p(n-1) with this prefix; the first creates the tournament; all join.
async fn field(addr: SocketAddr, prefix: &str, n: usize, o: Value) -> (Vec<C>, i64, Value) {
    let mut cs = vec![];
    for i in 0..n {
        cs.push(C::register(addr, &format!("{prefix}{i}")).await);
    }
    let t = create(&mut cs[0], o).await;
    let id = t["id"].as_i64().unwrap();
    let k = t["decks_per_entrant"].as_u64().unwrap() as usize;
    for c in cs.iter_mut() {
        join(c, id, k).await;
    }
    (cs, id, t)
}

/// Starts the tournament now and plays it out; returns each player's final view and what it saw.
async fn play(app: &AppRef, cs: Vec<C>, id: i64, loses: fn(&str, &str) -> bool) -> Vec<(C, Value, Seen)> {
    let tasks: Vec<_> = cs.into_iter().map(|c| tokio::spawn(autoplay(c, id, loses))).collect();
    start_at(app, id, now_ms() - 1000).await;
    let mut out = vec![];
    for t in tasks {
        out.push(tokio::time::timeout(Duration::from_secs(120), t).await.expect("the tournament did not end").unwrap());
    }
    out
}

/// The lower name wins.
fn by_name(me: &str, opp: &str) -> bool {
    me > opp
}

fn places(t: &Value) -> HashMap<String, i64> {
    t["entrants"].as_array().unwrap().iter().map(|e| (e["name"].as_str().unwrap().to_string(), e["place"].as_i64().unwrap())).collect()
}

#[tokio::test]
async fn single_elimination_bo3_conquest_with_bans() {
    let (addr, app) = server().await;
    let (cs, id, t) = field(addr, "se", 4, json!({"best_of": 3, "bans": 1, "spectators": true})).await;
    assert_eq!((t["decks_per_entrant"].as_u64(), t["wins_needed"].as_u64()), (Some(3), Some(2)));
    let out = play(&app, cs, id, by_name).await;
    let fin = &out[0].1;
    // the seeds are random: se0 wins, the other finalist is second, the semi-final losers third
    let pl = places(fin);
    let ms = fin["matches"].as_array().unwrap();
    assert_eq!(ms.len(), 3);
    let fin_loser = ms.iter().find(|m| m["round"] == 2).unwrap()["p"].as_array().unwrap().iter().find(|p| *p != "se0").unwrap().clone();
    assert_eq!(pl["se0"], 1, "{fin}");
    assert_eq!(pl[fin_loser.as_str().unwrap()], 2);
    assert_eq!(pl.values().filter(|&&p| p == 3).count(), 2);
    assert_eq!(fin["entrants"][0]["name"], "se0", "the list is by place");
    for m in fin["matches"].as_array().unwrap() {
        assert_eq!(m["status"], "done");
        assert_eq!(m["games"].as_array().unwrap().len(), 2, "two straight wins: {m}");
        assert!(m["score"] == json!([2, 0]) || m["score"] == json!([0, 2]), "{m}");
    }
    // Conquest: the winner won with two different decks; each side lost one deck to the ban
    for (c, _, seen) in &out {
        for (_, last) in &seen.last {
            assert_eq!(last["phase"], "done");
            let mine = last["mine"].as_array().unwrap();
            let count = |s: &str| mine.iter().filter(|d| d["state"] == s).count();
            assert_eq!(count("banned"), 1, "{}: {last}", c.name);
            if last["winner"] == c.name.as_str() {
                assert_eq!(count("won"), 2, "{last}");
            } else {
                assert_eq!(count("won"), 0, "{last}");
            }
        }
    }
    // tournament games: mode tournament, no rating change, the replays are open once it is over
    let g = &out[0].2.games[0];
    let row = played::Entity::find_by_id(g).one(&app.db).await.unwrap().unwrap();
    assert_eq!(row.mode, "tournament");
    let outsider = db::create_account(&app.db, "outsider", "x", "user").await.unwrap().unwrap();
    assert!(classichs_server::replays::can_view(&app, outsider, g).await);
    let st = classichs_server::entity::standing::Entity::find().all(&app.db).await.unwrap();
    assert!(st.iter().all(|s| s.casual_mmr == 1500.0 && s.ranked_mmr == 1500.0), "no rating change");
}

#[tokio::test]
async fn round_robin_three_bo1() {
    let (addr, app) = server().await;
    let (cs, id, _) = field(addr, "rr", 3, json!({"format": "round_robin", "options": {"rounds": 1}})).await;
    let out = play(&app, cs, id, by_name).await;
    let fin = &out[0].1;
    let pl = places(fin);
    assert_eq!((pl["rr0"], pl["rr1"], pl["rr2"]), (1, 2, 3));
    let ms = fin["matches"].as_array().unwrap();
    assert_eq!(ms.len(), 3, "every pair once");
    let pts: Vec<i64> = fin["entrants"].as_array().unwrap().iter().map(|e| e["points"].as_i64().unwrap()).collect();
    assert_eq!(pts, [2, 1, 0]);
}

#[tokio::test]
async fn swiss_five_with_byes() {
    let (addr, app) = server().await;
    let (cs, id, _) = field(addr, "sw", 5, json!({"format": "swiss"})).await;
    let out = play(&app, cs, id, by_name).await;
    let fin = &out[0].1;
    assert_eq!(fin["options"]["rounds"], 3, "ceil(log2 5)");
    assert_eq!(fin["rounds"], 3, "the options at the top level too");
    let ms = fin["matches"].as_array().unwrap();
    assert!(ms.iter().all(|m| m["status"] == if m["p"][1].is_null() { "bye" } else { "done" }));
    let mut pairs = HashSet::new();
    for r in 1..=3 {
        let round: Vec<&Value> = ms.iter().filter(|m| m["round"] == r).collect();
        assert_eq!(round.len(), 3, "two pairs and a bye in round {r}");
        assert_eq!(round.iter().filter(|m| m["p"][1].is_null()).count(), 1, "one bye in round {r}");
        for m in round.iter().filter(|m| !m["p"][1].is_null()) {
            let (a, b) = (m["p"][0].as_str().unwrap(), m["p"][1].as_str().unwrap());
            assert!(pairs.insert((a.min(b).to_string(), a.max(b).to_string())), "rematch {a} {b}");
        }
    }
    let byes: HashSet<&str> = ms.iter().filter(|m| m["p"][1].is_null()).map(|m| m["p"][0].as_str().unwrap()).collect();
    assert_eq!(byes.len(), 3, "a new player gets each bye");
    let pts: i64 = fin["entrants"].as_array().unwrap().iter().map(|e| e["points"].as_i64().unwrap()).sum();
    assert_eq!(pts, 9, "a point a match, byes too");
    // sw0 wins all (a bye may leave it behind another unbeaten player on game wins)
    let first = &fin["entrants"][0];
    assert_eq!((first["place"].as_i64(), first["points"].as_i64()), (Some(1), Some(3)), "{fin}");
    let sw0 = fin["entrants"].as_array().unwrap().iter().find(|e| e["name"] == "sw0").unwrap();
    assert_eq!(sw0["points"], 3);
}

#[tokio::test]
async fn double_elimination_four() {
    let (addr, app) = server().await;
    // sd1 beats sd0 in the winners' final; sd0 comes back through the losers' bracket and takes the grand final
    let (cs, id, _) = field(addr, "sd", 4, json!({"options": {"losses": 2}})).await;
    // each counts its own meetings with the other (only its own task touches its counter)
    static MET: [std::sync::atomic::AtomicU32; 2] = [std::sync::atomic::AtomicU32::new(0), std::sync::atomic::AtomicU32::new(0)];
    fn loses(me: &str, opp: &str) -> bool {
        let met = |i: usize| MET[i].fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        match (me, opp) {
            ("sd0", "sd1") => met(0) == 1,
            ("sd1", "sd0") => met(1) == 2,
            _ => me > opp,
        }
    }
    let out = play(&app, cs, id, loses).await;
    let fin = &out[0].1;
    let ms = fin["matches"].as_array().unwrap();
    assert_eq!(ms.iter().filter(|m| m["bracket"] == "gf").count(), 1, "one grand final (no reset)");
    let gf = ms.iter().find(|m| m["bracket"] == "gf").unwrap();
    assert_eq!((gf["p"].clone(), gf["winner"].clone()), (json!(["sd1", "sd0"]), json!("sd0")), "{fin}");
    let pl = places(fin);
    assert_eq!((pl["sd0"], pl["sd1"], pl["sd2"], pl["sd3"]), (1, 2, 3, 4));
}

#[tokio::test]
async fn scheveningen_four() {
    let (addr, app) = server().await;
    let (cs, id, _) = field(addr, "sc", 4, json!({"format": "scheveningen"})).await;
    let out = play(&app, cs, id, by_name).await;
    let fin = &out[0].1;
    let team: HashMap<String, i64> = fin["entrants"].as_array().unwrap().iter().map(|e| (e["name"].as_str().unwrap().into(), e["team"].as_i64().unwrap())).collect();
    let ms = fin["matches"].as_array().unwrap();
    assert_eq!(ms.len(), 4, "2 × 2");
    for m in ms {
        assert_ne!(team[m["p"][0].as_str().unwrap()], team[m["p"][1].as_str().unwrap()]);
    }
}

#[tokio::test]
async fn last_hero_standing() {
    let (addr, app) = server().await;
    let (cs, id, _) = field(addr, "lh", 2, json!({"series": "lhs", "best_of": 3})).await;
    let out = play(&app, cs, id, by_name).await;
    let (winner, loser) = (&out[0].2, &out[1].2);
    assert_eq!(winner.games.len(), 2);
    let last = winner.last.values().next().unwrap();
    assert_eq!(last["score"], json!([2, 0]));
    let states = |v: &Value, k: &str| v[k].as_array().unwrap().iter().map(|d| d["state"].as_str().unwrap().to_string()).collect::<Vec<_>>();
    assert_eq!(states(last, "mine"), ["ok", "ok"], "the winner kept its deck");
    assert_eq!(states(last, "theirs"), ["lost", "lost"], "each losing deck is out");
    // the winner picked once and kept that deck (no pick for game 2); the loser picked twice
    assert_eq!(winner.picks.len(), 1, "{:?}", winner.picks);
    assert!(!winner.kept.is_empty(), "a pick step with the deck kept");
    assert_eq!(loser.picks.iter().map(|p| p.2).collect::<Vec<_>>(), [0, 1]);
}

#[tokio::test]
async fn a_missed_accept_forfeits() {
    let (addr, app) = server().await;
    let (mut cs, id, _) = field(addr, "ma", 2, json!({"best_of": 3})).await;
    start_at(&app, id, now_ms() - 1000).await;
    let m = cs[0].want("t_match").await;
    assert_eq!((m["phase"].as_str(), m["status"].as_str()), (Some("accept"), Some("accept")));
    assert!(m["deadline"].as_i64().unwrap() > now_ms() + 50_000);
    let mid = m["match"].as_i64().unwrap();
    cs[0].send(json!({"t": "t_accept", "match": mid})).await;
    let w = cs[0].want("t_match").await;
    assert_eq!(w["phase"], "wait");
    // the deadline passes: ma1 loses the game; a new accept for game 2
    let expire = || tmatch::Entity::update_many().col_expr(tmatch::Column::Deadline, Expr::value(1)).filter(tmatch::Column::Id.eq(mid)).exec(&app.db);
    expire().await.unwrap();
    tournament::tick(&app).await;
    let played = |m: &Value| m["score"][0].as_i64().unwrap() + m["score"][1].as_i64().unwrap();
    let m = cs[1].until("t_match", |m| played(m) == 1).await;
    assert_eq!((m["phase"].clone(), m["score"].clone()), (json!("accept"), json!([0, 1])), "{m}");
    // both miss it: one of them loses the game
    expire().await.unwrap();
    tournament::tick(&app).await;
    let m = cs[1].until("t_match", |m| played(m) == 2).await;
    if m["phase"] != "done" {
        expire().await.unwrap();
        tournament::tick(&app).await;
    }
    let t = status(&app, id).await;
    assert_eq!(t.status, "finished");
    let ms = tmatch::Entity::find().filter(tmatch::Column::Tournament.eq(id)).all(&app.db).await.unwrap();
    assert!(ms[0].winner.is_some());
    assert!(played::Entity::find().all(&app.db).await.unwrap().is_empty(), "no game was played");
}

#[tokio::test]
async fn lock_close_and_the_steps_of_time() {
    let (addr, app) = server().await;
    let mut a = C::register(addr, "lk0").await;
    let mut b = C::register(addr, "lk1").await;
    let mut c = C::register(addr, "lk2").await;
    // too few at T−10: closed
    let t = create(&mut a, json!({"min_players": 3})).await;
    let id = t["id"].as_i64().unwrap();
    assert_eq!(t["can"], json!({"edit": true, "reschedule": true, "cancel": true, "join": true, "leave": false, "decks": false, "spectate": false}));
    join(&mut a, id, 1).await;
    join(&mut b, id, 1).await;
    start_at(&app, id, now_ms() + 9 * MIN).await;
    let t = status(&app, id).await;
    assert_eq!((t.status.as_str(), t.reason.as_str()), ("closed", "not enough players"));
    assert!(c.refused(json!({"t": "t_join", "id": id, "decks": decks(1)})).await.contains("Joining ended"));
    c.send(json!({"t": "t_list", "tab": "closed"})).await;
    let l = c.want("t_list").await;
    assert_eq!(l["list"][0]["id"], id);
    // enough: locked at T−10 (rules and decks frozen, joining open), seeded at T−1 (joining over)
    let id = create(&mut a, json!({})).await["id"].as_i64().unwrap();
    join(&mut a, id, 1).await;
    join(&mut b, id, 1).await;
    start_at(&app, id, now_ms() + 9 * MIN).await;
    assert_eq!(status(&app, id).await.status, "locked");
    assert!(a.refused(json!({"t": "t_edit", "id": id, "name": "Other"})).await.contains("frozen"));
    assert!(a.refused(json!({"t": "t_decks", "id": id, "decks": decks(1)})).await.contains("frozen"));
    assert!(a.refused(json!({"t": "t_reschedule", "id": id, "start_at": now_ms() + 60 * MIN})).await.contains("frozen"));
    join(&mut c, id, 1).await;
    c.send(json!({"t": "t_leave", "id": id})).await;
    let t = c.tournament().await;
    assert_eq!(t["entrants"].as_array().unwrap().len(), 2);
    start_at(&app, id, now_ms() + 30_000).await;
    assert_eq!(status(&app, id).await.status, "seeded");
    assert!(c.refused(json!({"t": "t_join", "id": id, "decks": decks(1)})).await.contains("Joining ended"));
    assert!(b.refused(json!({"t": "t_leave", "id": id})).await.contains("Leaving ended"));
    let seeds: Vec<i64> = classichs_server::entity::tournament::entrant::Entity::find().all(&app.db).await.unwrap().iter()
        .filter(|e| e.tournament == id).map(|e| e.seed).collect();
    let mut s = seeds.clone();
    s.sort();
    assert_eq!(s, [0, 1]);
    // the creator cancels: everyone watching hears it
    a.send(json!({"t": "t_cancel", "id": id})).await;
    loop {
        let t = b.tournament().await;
        if t["status"] == "cancelled" {
            break;
        }
    }
}

#[tokio::test]
async fn limits_and_checks() {
    let (addr, app) = server().await;
    let mut a = C::register(addr, "li0").await;
    let mut b = C::register(addr, "li1").await;
    let base = |o: Value| {
        let mut m = json!({"t": "t_create", "name": "Cup", "pack": classic(), "format": "elimination", "series": "conquest", "best_of": 3,
                           "bans": 1, "start_at": now_ms() + 12 * MIN, "max_players": 2});
        for (k, v) in o.as_object().unwrap() {
            m[k] = v.clone();
        }
        m
    };
    // the options
    assert!(a.refused(base(json!({"start_at": now_ms() + 5 * MIN}))).await.contains("11 minutes"));
    assert!(a.refused(base(json!({"start_at": now_ms() + 15 * 24 * 60 * MIN}))).await.contains("14 days"));
    assert!(a.refused(base(json!({"name": "ab"}))).await.contains("3 to 40"));
    assert!(a.refused(base(json!({"max_players": 129}))).await.contains("2 to 128"));
    assert!(a.refused(base(json!({"min_players": 3}))).await.contains("minimum"));
    assert!(a.refused(base(json!({"best_of": 2}))).await.contains("Best of"));
    assert!(a.refused(base(json!({"series": "x"}))).await.contains("conquest"));
    assert!(a.refused(base(json!({"format": "swiss", "options": {"rounds": 11}}))).await.contains("Swiss"));
    assert!(a.refused(base(json!({"pack": "nope"}))).await.contains("does not have"));
    a.send(base(json!({}))).await;
    let t = a.tournament().await;
    let id = t["id"].as_i64().unwrap();
    assert_eq!(t["decks_per_entrant"], 3);
    // only the creator edits; fixed fields stay
    assert!(b.refused(json!({"t": "t_edit", "id": id, "name": "Mine"})).await.contains("Only the creator"));
    assert!(b.refused(json!({"t": "t_cancel", "id": id})).await.contains("Only the creator"));
    assert!(a.refused(json!({"t": "t_edit", "id": id, "series": "lhs"})).await.contains("fixed"));
    assert!(a.refused(json!({"t": "t_edit", "id": id, "best_of": 5})).await.contains("fixed"));
    a.send(json!({"t": "t_edit", "id": id, "name": "Spring cup", "format": "round_robin", "options": {"rounds": 2}, "deck_reveal": false})).await;
    let t = a.tournament().await;
    assert_eq!((t["name"].as_str(), t["format"].as_str(), t["options"]["rounds"].as_i64()), (Some("Spring cup"), Some("round_robin"), Some(2)));
    let start = t["start_at"].as_i64().unwrap();
    assert!(a.refused(json!({"t": "t_reschedule", "id": id, "start_at": start - 1000})).await.contains("later"));
    a.send(json!({"t": "t_reschedule", "id": id, "start_at": start + MIN})).await;
    assert_eq!(a.tournament().await["start_at"], start + MIN);
    // decks: the count, distinct classes, valid
    assert!(b.refused(json!({"t": "t_join", "id": id, "decks": decks(2)})).await.contains("needs 3 decks"));
    let mut same = decks(3);
    same[2] = same[0].clone();
    assert!(b.refused(json!({"t": "t_join", "id": id, "decks": same})).await.contains("another class"));
    let mut bad = decks(3);
    bad[1]["cards"].as_array_mut().unwrap().pop();
    assert!(!b.refused(json!({"t": "t_join", "id": id, "decks": bad})).await.is_empty());
    join(&mut b, id, 3).await;
    assert!(a.refused(json!({"t": "t_edit", "id": id, "bans": 0})).await.contains("Bans"));
    join(&mut a, id, 3).await;
    let mut c = C::register(addr, "li2").await;
    assert!(c.refused(json!({"t": "t_join", "id": id, "decks": decks(3)})).await.contains("full"));
    // the decks are hidden from others (deck_reveal off), own always shown
    c.send(json!({"t": "t_get", "id": id})).await;
    let t = c.tournament().await;
    assert!(t["entrants"].as_array().unwrap().iter().all(|e| e.get("decks").is_none()));
    b.send(json!({"t": "t_get", "id": id})).await;
    let t = b.tournament().await;
    let shown: Vec<&str> = t["entrants"].as_array().unwrap().iter().filter(|e| e.get("decks").is_some()).map(|e| e["name"].as_str().unwrap()).collect();
    assert_eq!(shown, ["li1"]);
    // deck_reveal: from T−10 everyone sees every deck
    a.send(json!({"t": "t_edit", "id": id, "deck_reveal": true})).await;
    a.tournament().await;
    start_at(&app, id, now_ms() + 9 * MIN).await;
    c.send(json!({"t": "t_get", "id": id})).await;
    let shown = |v: &Value| v["tournament"]["entrants"].as_array().unwrap().iter().all(|e| e["decks"].as_array().is_some_and(|d| d.len() == 3));
    c.until("tournament", shown).await;
    // 3 not over per creator
    for i in 0..2 {
        a.send(base(json!({"name": format!("Cup {i}")}))).await;
        a.tournament().await;
    }
    assert!(a.refused(base(json!({}))).await.contains("not over"));
    // 10 a day: cancelled ones count too (the locked one stays: 2 more at a time)
    let mut made = 3;
    while made < 10 {
        let ids: Vec<i64> = tour::Entity::find().filter(tour::Column::Status.eq("open")).all(&app.db).await.unwrap().iter().map(|t| t.id).collect();
        for x in ids {
            a.send(json!({"t": "t_cancel", "id": x})).await;
            a.tournament().await;
        }
        for _ in 0..2.min(10 - made) {
            a.send(base(json!({}))).await;
            a.tournament().await;
            made += 1;
        }
    }
    for x in tour::Entity::find().filter(tour::Column::Status.eq("open")).all(&app.db).await.unwrap().iter().map(|t| t.id) {
        a.send(json!({"t": "t_cancel", "id": x})).await;
        a.tournament().await;
    }
    assert!(a.refused(base(json!({}))).await.contains("10 tournaments a day"));
    // the lists
    a.send(json!({"t": "t_list", "tab": "upcoming"})).await;
    let l = a.want("t_list").await;
    assert_eq!(l["list"].as_array().unwrap().len(), 1, "the locked one");
    assert_eq!(l["list"][0]["joined"], true);
}

#[tokio::test]
async fn a_restart_carries_on() {
    let path = std::env::temp_dir().join(format!("chs-tour-{}.db", rand::random::<u64>()));
    let path = path.to_str().unwrap().to_string();
    let (addr, app) = server_on(&path).await;
    let (cs, id, _) = field(addr, "rs", 2, json!({})).await;
    drop(cs);
    tour::Entity::update_many().col_expr(tour::Column::StartAt, Expr::value(now_ms() - 1000)).filter(tour::Column::Id.eq(id)).exec(&app.db).await.unwrap();
    // another process on the same database (no scheduler of its own: ticked by hand)
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let app2 = App::new(db::open(&path).await.unwrap(), false, Some(Timers::default()), store);
    let _lock = app.tour.lock.lock().await; // the first server's scheduler stays out
    tournament::tick(&app2).await;
    let ms = tmatch::Entity::find().filter(tmatch::Column::Tournament.eq(id)).all(&app2.db).await.unwrap();
    assert_eq!((status(&app2, id).await.status.as_str(), ms[0].status.as_str()), ("running", "accept"));
    // a game the other process was running is gone: the match asks for it again
    let state = json!({"acc": [true, true], "pick": [0, 0], "decks": [["ok"], ["ok"]], "game": "gone", "boot": 1, "n": 1}).to_string();
    tmatch::Entity::update_many()
        .col_expr(tmatch::Column::Status, Expr::value("playing"))
        .col_expr(tmatch::Column::State, Expr::value(state))
        .filter(tmatch::Column::Id.eq(ms[0].id))
        .exec(&app2.db)
        .await
        .unwrap();
    tournament::tick(&app2).await;
    let m = tmatch::Entity::find_by_id(ms[0].id).one(&app2.db).await.unwrap().unwrap();
    assert_eq!((m.status.as_str(), m.score_a, m.score_b), ("accept", 0, 0));
    drop(_lock);
    let _ = std::fs::remove_file(&path);
}
