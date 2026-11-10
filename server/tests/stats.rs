//! The admin's statistics (stats.rs): what one game adds (the rows, mirrors, the mulligan and the
//! cards played from the replay's actions, brackets, periods, bots), the backfill from kept
//! replays, the admin API, and a real game of two server bots counted at its end.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_engine::{bot, deck, ruleset, Game};
use classichs_server::packs::GameRules;
use classichs_server::stats::{self, Facts};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, replays, router, App, AppRef, Timers};
use sea_orm::{ConnectionTrait, DbBackend, Statement};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::Duration;
use tower::ServiceExt;

/// 2026-11-10 14:05 UTC.
const T: i64 = 1_794_319_500;

async fn app() -> AppRef {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-stats-{}", rand::random::<u64>()))).unwrap();
    App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store)
}

/// What the engine says happened, to check the replay's facts against: each player's plays of
/// their deck's cards (the `play` events) and the opening hands.
#[derive(Default)]
struct Seen {
    played: [HashMap<String, i64>; 2],
    hands: [Vec<String>; 2],
}

/// A whole game of the engine's bot, as the replay game.rs keeps. `replace`: player 0's
/// mulligan replaces the first n cards of the opening hand (None: the bot decides).
fn play(classes: [&str; 2], names: [&str; 2], mode: &str, seed: i64, ended: i64, replace: Option<usize>) -> (Value, Seen) {
    let rs = ruleset::classic();
    let decks: Vec<(String, Vec<String>)> = classes.iter().map(|c| (deck::hero(c).unwrap().to_string(), deck::basic(c))).collect();
    let mut g = Game::new_in(rs, &decks[0].0, &decks[0].1, &decks[1].0, &decks[1].1, seed, -1, true);
    let mut seen = Seen::default();
    let card = |g: &Game, e: i64| g.ent(e).unwrap().card_id.to_string();
    for p in 0..2 {
        seen.hands[p] = g.players[p].hand.iter().map(|&e| card(&g, e)).collect();
    }
    for _ in 0..2000 {
        if g.game_over {
            break;
        }
        let movers: Vec<usize> = if g.phase == "MULLIGAN" {
            (0..2).filter(|&p| !g.players[p].mulliganed).collect()
        } else if let Some(p) = &g.pending {
            vec![p.player]
        } else {
            vec![g.current]
        };
        for p in movers {
            let a = match (g.phase, p, replace) {
                ("MULLIGAN", 0, Some(n)) => json!({"type": "mulligan", "player": 0, "replace": g.players[0].hand[..n].to_vec()}),
                _ => match bot::choose(&g, p) {
                    Some(a) => Value::Object(a),
                    None => continue,
                },
            };
            let r = g.apply(&a);
            assert!(r.ok, "{a}: {}", r.error);
            for e in r.events() {
                if e["type"] == "play" && e["card"].is_string() {
                    let (p, c) = (e["player"].as_u64().unwrap() as usize, e["card"].as_str().unwrap().to_string());
                    if decks[p].1.contains(&c) {
                        *seen.played[p].entry(c).or_default() += 1;
                    }
                }
            }
        }
    }
    assert!(g.game_over, "the game ended");
    let actions: Vec<Value> = g.history.iter().skip(1).map(|h| Value::Object(h.action.clone())).collect();
    let players: Vec<Value> = (0..2).map(|p| json!({"name": names[p], "hero": decks[p].0, "cards": decks[p].1})).collect();
    let r = json!({"format": "classichs-replay", "v": 1, "game": format!("g{seed}"), "mode": mode, "pack": rs.rules_hash, "pack_id": rs.id,
                   "pack_name": "Classic", "started": ended - 600, "ended": ended, "players": players, "seed": seed, "first": -1,
                   "actions": actions, "result": {"winner": g.winner, "reason": "over", "turns": g.turn}, "hash": g.state_hash()});
    (r, seen)
}

fn facts(r: &Value) -> Facts {
    stats::facts(ruleset::classic(), r).unwrap()
}

async fn rows(c: &impl ConnectionTrait, sql: &str) -> Vec<Value> {
    c.query_all_raw(Statement::from_string(DbBackend::Sqlite, sql)).await.unwrap().iter().map(|r| sea_orm::JsonValue::from_query_result(r, "").unwrap()).collect()
}

async fn one(c: &impl ConnectionTrait, sql: &str) -> i64 {
    let r = c.query_one_raw(Statement::from_string(DbBackend::Sqlite, sql)).await.unwrap().unwrap();
    r.try_get_by_index::<Option<i64>>(0).unwrap().unwrap_or(0)
}

use sea_orm::FromQueryResult;

#[tokio::test]
async fn one_game_adds_exactly_its_rows() {
    let db = db::open(":memory:").await.unwrap();
    let (r, seen) = play(["MAGE", "WARRIOR"], ["alice", "bob"], "ranked", 7, T, None);
    let f = facts(&r);
    let w = r["result"]["winner"].as_i64().unwrap();
    for p in 0..2 {
        assert_eq!(f.sides[p].played, seen.played[p], "player {p}: the cards played, as the engine's events");
    }
    stats::write(&db, &f, &["6-10".into(), "Legend".into()]).await.unwrap();
    // 6 periods × 2 players, nothing else
    assert_eq!(one(&db, "SELECT COUNT(*) FROM stats_class").await, 12);
    let all = rows(&db, "SELECT class, bracket, bots, games, wins, mirrors FROM stats_class WHERE period = 'all' ORDER BY class").await;
    assert_eq!(all, [json!({"class": "MAGE", "bracket": "6-10", "bots": 0, "games": 1, "wins": i64::from(w == 0), "mirrors": 0}),
                     json!({"class": "WARRIOR", "bracket": "Legend", "bots": 0, "games": 1, "wins": i64::from(w == 1), "mirrors": 0})]);
    let b: Vec<Value> = rows(&db, "SELECT period, bucket FROM stats_class WHERE class = 'MAGE' ORDER BY period").await;
    assert_eq!(b, [("all", "all"), ("day", "2026-11-10"), ("hour", "2026-11-10T14"), ("month", "2026-11"), ("week", "2026-11-09"), ("year", "2026")]
        .map(|(p, k)| json!({"period": p, "bucket": k})));
    // decks and cards: one row per player and period (but hours and days older than kept: `prune`)
    let distinct = |c: &str| { let mut v = deck::basic(c); v.sort(); v.dedup(); v.len() as i64 };
    let periods = one(&db, "SELECT COUNT(DISTINCT period) FROM stats_deck").await;
    assert_eq!(one(&db, "SELECT COUNT(*) FROM stats_deck").await, 2 * periods);
    assert_eq!(one(&db, "SELECT COUNT(*) FROM stats_card").await, periods * (distinct("MAGE") + distinct("WARRIOR")));
    assert_eq!(one(&db, "SELECT COUNT(*) FROM stats_decks").await, 2);
    let mage = rows(&db, "SELECT card, decks, copies, deck_wins, played, played_wins, plays FROM stats_card WHERE period = 'all' AND class = 'MAGE'").await;
    for row in &mage {
        let c = row["card"].as_str().unwrap();
        let plays = seen.played[0].get(c).copied().unwrap_or(0);
        let copies = deck::basic("MAGE").iter().filter(|x| *x == c).count() as i64;
        assert_eq!(row, &json!({"card": c, "decks": 1, "copies": copies, "deck_wins": i64::from(w == 0), "played": i64::from(plays > 0),
                                "played_wins": i64::from(plays > 0 && w == 0), "plays": plays}));
    }
    // the same game again: the same rows, every count doubled
    stats::write(&db, &f, &["6-10".into(), "Legend".into()]).await.unwrap();
    assert_eq!(one(&db, "SELECT COUNT(*) FROM stats_class").await, 12);
    assert_eq!(one(&db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await, 4);
    assert_eq!(one(&db, "SELECT SUM(decks) FROM stats_card WHERE period = 'year'").await, 2 * (distinct("MAGE") + distinct("WARRIOR")));
}

#[tokio::test]
async fn a_mirror_counts_no_win_or_loss_for_the_class() {
    let db = db::open(":memory:").await.unwrap();
    let (r, _) = play(["MAGE", "MAGE"], ["alice", "bob"], "casual", 8, T, None);
    stats::write(&db, &facts(&r), &["all".into(), "all".into()]).await.unwrap();
    let all = rows(&db, "SELECT class, games, wins, mirrors FROM stats_class WHERE period = 'all'").await;
    assert_eq!(all, [json!({"class": "MAGE", "games": 2, "wins": 0, "mirrors": 2})]);
    // decks and cards still count the winner: the same deck won once and lost once
    assert_eq!(rows(&db, "SELECT games, wins FROM stats_deck WHERE period = 'all'").await, [json!({"games": 2, "wins": 1})]);
}

#[tokio::test]
async fn the_mulligan_from_the_replay_actions() {
    let db = db::open(":memory:").await.unwrap();
    let (r, seen) = play(["PRIEST", "HUNTER"], ["alice", "bob"], "casual", 9, T, Some(2));
    let f = facts(&r);
    let count = |v: &[String]| {
        let mut m: HashMap<String, i64> = HashMap::new();
        for c in v {
            *m.entry(c.clone()).or_default() += 1;
        }
        m
    };
    assert_eq!(f.sides[0].replaced, count(&seen.hands[0][..2]));
    assert_eq!(f.sides[0].kept, count(&seen.hands[0][2..]));
    let mut both = f.sides[1].kept.clone();
    for (c, n) in &f.sides[1].replaced {
        *both.entry(c.clone()).or_default() += n;
    }
    assert_eq!(both, count(&seen.hands[1]), "the bot's opening hand, kept or replaced");
    assert_eq!(seen.hands[0].len() + seen.hands[1].len(), 7, "3 and 4 cards");
    stats::write(&db, &f, &["all".into(), "all".into()]).await.unwrap();
    let won = i64::from(r["result"]["winner"] == 0);
    assert_eq!(one(&db, "SELECT SUM(replaced) FROM stats_card WHERE period = 'all' AND class = 'PRIEST'").await, 2);
    assert_eq!(one(&db, "SELECT SUM(kept) FROM stats_card WHERE period = 'all' AND class = 'PRIEST'").await, seen.hands[0].len() as i64 - 2);
    assert_eq!(one(&db, "SELECT SUM(kept_wins) FROM stats_card WHERE period = 'all' AND class = 'PRIEST'").await, won);
}

#[tokio::test]
async fn periods_buckets_bots_and_games_without_a_winner() {
    let db = db::open(":memory:").await.unwrap();
    let now = classichs_server::ranked::now();
    let (a, _) = play(["MAGE", "ROGUE"], ["alice", "AutoBot_1"], "casual", 10, now, None);
    let (b, _) = play(["MAGE", "ROGUE"], ["alice", "carol"], "casual", 11, now - 3600, None);
    for r in [&a, &b] {
        stats::write(&db, &facts(r), &["all".into(), "all".into()]).await.unwrap();
    }
    let k = stats::buckets(now);
    assert_eq!(one(&db, &format!("SELECT SUM(games) FROM stats_class WHERE period = 'hour' AND bucket = '{}'", k[0])).await, 2, "this hour: one game");
    assert_eq!(one(&db, "SELECT COUNT(DISTINCT bucket) FROM stats_card WHERE period = 'hour'").await, 2, "kept: hours of the last 2 days");
    assert_eq!(one(&db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await, 4);
    assert_eq!(one(&db, "SELECT SUM(games) FROM stats_class WHERE period = 'all' AND bots = 1").await, 2, "AutoBot_ played one");
    // no winner (aborted): not counted
    let mut c = b.clone();
    c["result"]["winner"] = json!(-1);
    assert_eq!(stats::facts(ruleset::classic(), &c).unwrap_err(), stats::NO_WINNER);
}

// --- the admin API and the backfill --------------------------------------------------------------------

async fn admin(state: &AppRef) -> (axum::Router, String) {
    let hash = auth::hash_password("rootpassword");
    db::make_superuser(&state.db, "root", &hash).await.unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    let req = Request::post("/admin/api/login")
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, "http://admin.test")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(json!({"user": "root", "password": "rootpassword"}).to_string()))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let c = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).find(|c| c.starts_with("chs_admin=")).unwrap();
    (app, c.split(';').next().unwrap().to_string())
}

async fn get(app: &axum::Router, cookie: &str, uri: &str) -> (StatusCode, Value) {
    let req = Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, cookie).body(Body::empty()).unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let body = axum::body::to_bytes(res.into_body(), 16 << 20).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

#[tokio::test]
async fn the_admin_api_reads_the_rows() {
    let state = app().await;
    let (app, cookie) = admin(&state).await;
    assert_eq!(get(&app, "", "/admin/api/stats").await.0, StatusCode::UNAUTHORIZED);
    let (s, v) = get(&app, &cookie, "/admin/api/stats").await;
    assert_eq!((s, &v["packs"]), (StatusCode::OK, &json!([])), "no games yet: {v}");
    let now = classichs_server::ranked::now();
    let rules = GameRules::classic();
    for (i, (classes, names, mode, b)) in [
        (["MAGE", "WARRIOR"], ["alice", "bob"], "ranked", ["1-5", "1-5"]),
        (["MAGE", "PRIEST"], ["alice", "Bot_Easy_1"], "casual", ["all", "all"]),
        (["MAGE", "WARRIOR"], ["carol", "bob"], "ranked", ["6-10", "1-5"]),
    ]
    .into_iter()
    .enumerate()
    {
        let (r, _) = play(classes, names, mode, 20 + i as i64, now, None);
        stats::record(state.clone(), rules.clone(), r, b.map(String::from)).await;
    }
    let (s, v) = get(&app, &cookie, "/admin/api/stats?period=day&min=1").await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["packs"][0]["games"], 3);
    assert_eq!(v["pack"], rules.rules_hash);
    assert_eq!(v["modes"], json!(["casual", "ranked"]));
    let class = |v: &Value, c: &str| v["classes"].as_array().unwrap().iter().find(|x| x["class"] == c).cloned().unwrap_or(Value::Null);
    assert_eq!(class(&v, "MAGE")["games"], 3);
    assert_eq!(class(&v, "MAGE")["name"], "Mage");
    assert_eq!(v["sides"], 6);
    assert_eq!(v["series"]["hour"].as_array().unwrap().len(), 48);
    assert_eq!(v["series"]["hour"][47][1], 6, "this hour: 3 games, 6 players");
    assert_eq!(v["series"]["day"][29][1], 6);
    let top = v["decks"]["top"].as_array().unwrap();
    assert_eq!(top.len(), 3, "the Mage, Warrior and Priest decks");
    let wr: Vec<f64> = top.iter().map(|d| d["wins"].as_f64().unwrap() / d["games"].as_f64().unwrap()).collect();
    assert!(wr.windows(2).all(|w| w[0] >= w[1]), "the best win rate first: {wr:?}");
    // the basic Mage deck played 3 times: the top deck list with names, cheapest first
    let mage = v["decks"]["by_class"]["MAGE"][0].clone();
    assert_eq!(mage["games"], 3, "{mage}");
    assert_eq!(mage["cards"].as_array().unwrap().iter().map(|c| c["n"].as_i64().unwrap()).sum::<i64>(), 30);
    assert!(mage["cards"].as_array().unwrap().iter().any(|c| c["name"] == "Fireball"), "{mage}");
    let costs: Vec<i64> = mage["cards"].as_array().unwrap().iter().map(|c| c["cost"].as_i64().unwrap()).collect();
    assert!(costs.windows(2).all(|w| w[0] <= w[1]));
    let fireball = v["cards"].as_array().unwrap().iter().find(|c| c["name"] == "Fireball").unwrap().clone();
    assert_eq!((fireball["decks"].as_i64(), fireball["copies"].as_i64()), (Some(3), Some(6)));
    // without bots, one mode, one bracket, one class, a minimum of games
    let (_, v) = get(&app, &cookie, "/admin/api/stats?period=all&bots=0&min=1").await;
    assert_eq!(v["sides"], 4);
    assert!(class(&v, "PRIEST").is_null());
    let (_, v) = get(&app, &cookie, "/admin/api/stats?period=all&mode=ranked&min=1").await;
    assert_eq!(v["brackets"], json!(["1-5", "6-10"]));
    assert_eq!(v["sides"], 4);
    let (_, v) = get(&app, &cookie, "/admin/api/stats?period=all&mode=ranked&bracket=1-5&min=1").await;
    assert_eq!((class(&v, "MAGE")["games"].as_i64(), class(&v, "WARRIOR")["games"].as_i64()), (Some(1), Some(2)));
    let (_, v) = get(&app, &cookie, "/admin/api/stats?period=all&class=WARRIOR&min=1").await;
    assert_eq!(v["sides"], 2);
    assert!(v["cards"].as_array().unwrap().iter().all(|c| c["name"] != "Fireball"));
    let (_, v) = get(&app, &cookie, "/admin/api/stats?period=all&min=4").await;
    assert_eq!(v["decks"]["total"], 0);
    assert_eq!(v["decks"]["top"], json!([]));
}

#[tokio::test]
async fn the_backfill_counts_the_kept_replays_once() {
    let state = app().await;
    let now = classichs_server::ranked::now();
    let (ids, mut want) = ([1, 2], 0);
    for i in 0..45 {
        let (classes, mode) = if i % 3 == 0 { (["MAGE", "PRIEST"], "ranked") } else { (["HUNTER", "ROGUE"], "casual") };
        let (r, _) = play(classes, ["alice", "bob"], mode, 100 + i, now - 86_400 * (i % 5) - 60, None);
        replays::save(&state.db, r["game"].as_str().unwrap(), r["pack"].as_str().unwrap(), ids, r["ended"].as_i64().unwrap(), &r).await.unwrap();
        want += 1;
    }
    // a game that ends after the backfill starts is counted when it ends, not by the backfill
    let (late, _) = play(["MAGE", "MAGE"], ["alice", "bob"], "casual", 99, now + 1000, None);
    replays::save(&state.db, "late", late["pack"].as_str().unwrap(), ids, now + 1000, &late).await.unwrap();
    assert_eq!(stats::backfill(&state).await.unwrap(), want);
    assert_eq!(one(&state.db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await, 2 * want as i64);
    assert_eq!(one(&state.db, "SELECT SUM(games) FROM stats_class WHERE period = 'all' AND bracket = 'unknown'").await, 2 * 15, "ranked: no rank in a replay");
    assert_eq!(one(&state.db, "SELECT COUNT(*) FROM stats_names WHERE kind = 'card' AND id = 'VAN_CS2_029' AND name = 'Fireball'").await, 1);
    // once: done
    assert_eq!(stats::backfill(&state).await.unwrap(), 0);
    assert_eq!(one(&state.db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await, 2 * want as i64);
    let mark = rows(&state.db, "SELECT value FROM server_settings WHERE key = 'stats_backfill'").await;
    assert_eq!(mark, [json!({"value": "done"})]);
}

#[tokio::test]
async fn the_backfill_resumes_after_a_restart_and_skips_counted_databases() {
    let state = app().await;
    let now = classichs_server::ranked::now();
    for i in 0..5 {
        let (r, _) = play(["MAGE", "PRIEST"], ["alice", "bob"], "casual", 200 + i, now - 100 + i, None);
        replays::save(&state.db, &format!("r{i}"), r["pack"].as_str().unwrap(), [1, 2], now - 100 + i, &r).await.unwrap();
    }
    // stopped after the first two
    let set = |v: String| Statement::from_string(DbBackend::Sqlite, format!("INSERT INTO server_settings (key, value) VALUES ('stats_backfill', '{v}')"));
    state.db.execute_raw(set(format!("{now} {} r1", now - 99))).await.unwrap();
    assert_eq!(stats::backfill(&state).await.unwrap(), 3);
    // a database with stats rows but no mark: nothing more is added
    let other = app().await;
    let (r, _) = play(["MAGE", "PRIEST"], ["alice", "bob"], "casual", 300, now - 50, None);
    stats::write(&other.db, &facts(&r), &["all".into(), "all".into()]).await.unwrap();
    replays::save(&other.db, "x", r["pack"].as_str().unwrap(), [1, 2], now - 50, &r).await.unwrap();
    assert_eq!(stats::backfill(&other).await.unwrap(), 0);
    assert_eq!(one(&other.db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await, 2);
}

/// game.rs: two server bots play a ranked game; at its end the game is counted with their
/// brackets at the start (new accounts: rank 25) and the bots flag.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_finished_server_game_is_counted() {
    let state = app().await;
    classichs_server::spawn_background(state.clone());
    classichs_server::bots::create(&state, 2, "easy", "ranked", (0, 0), (0, 1)).await.unwrap();
    classichs_server::bots::sync(&state).await.unwrap();
    let mut n = 0;
    for _ in 0..480 {
        n = one(&state.db, "SELECT COALESCE(SUM(games), 0) FROM stats_class WHERE period = 'all'").await;
        if n > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    assert!(n >= 2, "no game counted");
    let r = rows(&state.db, "SELECT DISTINCT mode, bracket, bots FROM stats_class WHERE period = 'all'").await;
    assert_eq!(r, [json!({"mode": "ranked", "bracket": "21-25", "bots": 1})]);
    assert_eq!(one(&state.db, "SELECT COUNT(*) FROM stats_names WHERE kind = 'pack'").await, 1);
}

/// Fills a database file with played games for a look at the admin page:
/// `STATS_FILL_DB=/tmp/x.db cargo test --release --test stats -- --ignored fill --nocapture`
/// (log in as root / rootpassword; the decks of the bots' library over the last 30 days).
#[tokio::test]
#[ignore]
async fn fill() {
    let path = std::env::var("STATS_FILL_DB").expect("STATS_FILL_DB");
    let n: i64 = std::env::var("STATS_FILL_GAMES").ok().and_then(|v| v.parse().ok()).unwrap_or(600);
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-stats-{}", rand::random::<u64>()))).unwrap();
    let state = App::new(db::open(&path).await.unwrap(), false, None, store);
    db::make_superuser(&state.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
    let lib = classichs_server::bots::cards::Library::get();
    let (rs, rules, now) = (ruleset::classic(), GameRules::classic(), classichs_server::ranked::now());
    let humans = ["alice", "bob", "carol", "dave", "erin", "frank", "grace", "heidi"];
    // the library's decks and every class's starter deck
    let mut decks: Vec<(String, Vec<String>)> = lib.decks.iter().map(|d| (d.hero.clone(), d.cards.clone())).collect();
    for c in ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"] {
        decks.push((deck::hero(c).unwrap().to_string(), deck::basic(c)));
    }
    let nd = decks.len() as i64;
    for i in 0..n {
        let (a, b) = (&decks[(i * 7 % nd) as usize], &decks[((i * 13 + 5) % nd) as usize]);
        let mut g = Game::new_in(rs, &a.0, &a.1, &b.0, &b.1, 1000 + i, -1, true);
        for _ in 0..3000 {
            if g.game_over {
                break;
            }
            let p = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap() } else if let Some(c) = &g.pending { c.player } else { g.current };
            let Some(x) = bot::choose(&g, p) else { break };
            g.apply(&Value::Object(x));
        }
        if !g.game_over {
            continue;
        }
        let mode = ["ranked", "ranked", "casual", "casual", "arena", "friendly", "tournament"][(i % 7) as usize];
        let names = [humans[(i % 8) as usize], if i % 3 == 0 { "AutoBot_Medium_1" } else { humans[((i + 3) % 8) as usize] }];
        let br = |k: i64| match mode {
            "ranked" => stats::rank_bracket([0, 3, 8, 12, 18, 23, 25][((i + k) % 7) as usize]),
            "arena" => stats::arena_bracket((i + k) % 9).to_string(),
            _ => "all".into(),
        };
        let ended = now - (i * 37 % (30 * 24)) * 3600 - i % 3600;
        let actions: Vec<Value> = g.history.iter().skip(1).map(|h| Value::Object(h.action.clone())).collect();
        let r = json!({"format": "classichs-replay", "v": 1, "game": format!("fill{i}"), "mode": mode, "pack": rs.rules_hash, "pack_id": rs.id,
                       "pack_name": "Classic", "started": ended - 600, "ended": ended,
                       "players": [{"name": names[0], "hero": a.0, "cards": a.1}, {"name": names[1], "hero": b.0, "cards": b.1}],
                       "seed": 1000 + i, "first": -1, "actions": actions, "result": {"winner": g.winner, "reason": "over", "turns": g.turn}, "hash": g.state_hash()});
        replays::save(&state.db, &format!("fill{i}"), &rs.rules_hash, [1, 1], ended, &r).await.unwrap();
        stats::record(state.clone(), rules.clone(), r, [br(0), br(3)]).await;
    }
    let done = Statement::from_string(DbBackend::Sqlite, "INSERT OR REPLACE INTO server_settings (key, value) VALUES ('stats_backfill', 'done')");
    state.db.execute_raw(done).await.unwrap();
    println!("filled {path}: {} games", one(&state.db, "SELECT SUM(games) FROM stats_class WHERE period = 'all'").await / 2);
}
