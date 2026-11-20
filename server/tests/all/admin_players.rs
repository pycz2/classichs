//! The admin's changes to a player (admin_players.rs): the guard, the checks, the event and the
//! push of each; the decks with their codes, and the deck codes (deck_code.rs) for Classic and
//! Neonfall, also as the client writes them.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_server::deck_code;
use classichs_server::entity::{arena, deck, game_setting, standing};
use classichs_server::packs::GameRules;
use classichs_server::storage::Storage;
use classichs_server::{auth, db, router, AppRef, Out, Timers};
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, QueryFilter, Set};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::time::Duration;
use tokio::sync::mpsc::UnboundedReceiver;
use tower::ServiceExt;

struct Res {
    status: StatusCode,
    body: String,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap_or(Value::Null)
    }
}

async fn call(app: &axum::Router, req: Request<Body>) -> Res {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let body = axum::body::to_bytes(res.into_body(), 8 << 20).await.unwrap();
    Res { status, body: String::from_utf8_lossy(&body).into_owned() }
}

fn get(uri: &str, cookie: &str) -> Request<Body> {
    Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, cookie).body(Body::empty()).unwrap()
}

fn post(uri: &str, cookie: &str, csrf: Option<&str>, body: Value) -> Request<Body> {
    let mut r = Request::post(uri)
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, "http://admin.test")
        .header(header::COOKIE, cookie)
        .header(header::CONTENT_TYPE, "application/json");
    if let Some(t) = csrf {
        r = r.header("x-csrf-token", t);
    }
    r.body(Body::from(body.to_string())).unwrap()
}

/// An admin session: (cookie, CSRF token), and its POST.
struct Admin {
    cookie: String,
    csrf: String,
}

impl Admin {
    async fn new(app: &axum::Router, user: &str) -> Admin {
        let res = app.clone().oneshot(post("/admin/api/login", "", None, json!({"user": user, "password": "rootpassword"}))).await.unwrap();
        let cookie = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).find(|c| c.starts_with("chs_admin=")).unwrap();
        let body = axum::body::to_bytes(res.into_body(), 1 << 20).await.unwrap();
        let v: Value = serde_json::from_slice(&body).unwrap();
        Admin { cookie: cookie.split(';').next().unwrap().to_string(), csrf: v["csrf"].as_str().unwrap().into() }
    }

    async fn post(&self, app: &axum::Router, path: &str, body: Value) -> Res {
        call(app, post(&format!("/admin/api/{path}"), &self.cookie, Some(&self.csrf), body)).await
    }

    async fn page(&self, app: &axum::Router, id: i64) -> Value {
        let r = call(app, get(&format!("/admin/api/accounts/{id}"), &self.cookie)).await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.body);
        r.json()
    }
}

async fn setup() -> (AppRef, axum::Router, i64) {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let state = classichs_server::App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
    let hash = auth::hash_password("rootpassword");
    db::make_superuser(&state.db, "root", &hash).await.unwrap();
    let victim = db::create_account(&state.db, "victim", &hash, "user").await.unwrap().unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    (state, app, victim)
}

/// The player online: what the server pushes to them.
fn online(state: &AppRef, id: i64, name: &str) -> UnboundedReceiver<Out> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    state.hub().attach(id, name, tx);
    rx
}

/// The next pushed message of a kind (others skipped).
async fn pushed(rx: &mut UnboundedReceiver<Out>, t: &str) -> Value {
    loop {
        match tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.expect("a push").expect("open") {
            Out::Text(s) => {
                let v: Value = serde_json::from_str(&s).unwrap();
                if v["t"] == t {
                    return v;
                }
            }
            _ => panic!("closed"),
        }
    }
}

/// The admin events with this action, waiting for the event writer.
async fn admin_events(app: &axum::Router, a: &Admin, action: &str) -> Vec<Value> {
    for _ in 0..50 {
        let r = call(app, get("/admin/api/events?kind=admin&size=100", &a.cookie)).await.json();
        let l: Vec<Value> = r["list"].as_array().unwrap().iter().filter(|e| e["data"]["action"] == action).cloned().collect();
        if !l.is_empty() {
            return l;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("no admin event {action}");
}

fn classic_game(page: &Value) -> Value {
    let id = &GameRules::classic().id;
    page["per_game"].as_array().unwrap().iter().find(|g| g["pack"] == *id).cloned().expect("Classic on the account page")
}

fn mage_cards() -> Vec<String> {
    classichs_engine::deck::basic("MAGE")
}

#[tokio::test]
async fn only_admins_who_may_manage() {
    let (state, app, victim) = setup().await;
    let hash = auth::hash_password("rootpassword");
    db::create_account(&state.db, "boss", &hash, "admin").await.unwrap();
    let other = db::create_account(&state.db, "boss2", &hash, "admin").await.unwrap().unwrap();
    let pack = GameRules::classic().id.clone();
    let body = json!({"pack": pack, "ranked_mmr": 1700});
    // no session, no CSRF
    assert_eq!(call(&app, post(&format!("/admin/api/accounts/{victim}/standing"), "", None, body.clone())).await.status, StatusCode::UNAUTHORIZED);
    let boss = Admin::new(&app, "boss").await;
    let r = call(&app, post(&format!("/admin/api/accounts/{victim}/standing"), &boss.cookie, None, body.clone())).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "CSRF");
    // an admin changes players, not other admins or the superuser
    for (id, path) in [(other, "standing"), (1, "standing"), (other, "tag"), (other, "arena"), (other, "decks"), (other, "game_settings")] {
        let r = boss.post(&app, &format!("accounts/{id}/{path}"), json!({"pack": pack, "tag": "Abc", "action": "end", "code": "x", "settings": {}})).await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{id} {path}: {}", r.body);
    }
    assert_eq!(boss.post(&app, &format!("accounts/{victim}/standing"), body.clone()).await.status, StatusCode::OK);
    assert_eq!(boss.post(&app, "accounts/999/standing", body).await.status, StatusCode::NOT_FOUND);
    // the superuser changes admins too
    let root = Admin::new(&app, "root").await;
    assert_eq!(root.post(&app, &format!("accounts/{other}/tag"), json!({"tag": "Second"})).await.status, StatusCode::OK);
}

#[tokio::test]
async fn standing_checks_event_push_and_reset() {
    let (state, app, victim) = setup().await;
    let root = Admin::new(&app, "root").await;
    let g = GameRules::classic();
    let path = format!("accounts/{victim}/standing");
    let page = root.page(&app, victim).await;
    let c = classic_game(&page);
    assert_eq!(page["games"], json!([]), "the recent games stay under their own key");
    assert_eq!((c["standing"]["rank"].as_i64(), c["standing"]["kept"].as_bool()), (Some(g.ladder.start.rank), Some(false)), "{c}");
    assert_eq!(c["ladder"]["ranks"].as_array().unwrap().len(), 25);
    for (bad, why) in [
        (json!({"pack": g.id, "rank": 26}), "A rank is"),
        (json!({"pack": g.id, "rank": 5, "stars": 6}), "holds 0–5 stars"),
        (json!({"pack": g.id, "ranked_mmr": -1}), "An MMR"),
        (json!({"pack": g.id, "streak": -1}), "streak"),
        (json!({"pack": "nope"}), "no such game"),
    ] {
        let r = root.post(&app, &path, bad.clone()).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{bad}");
        assert!(r.json()["error"].as_str().unwrap().contains(why), "{bad}: {}", r.body);
    }
    let mut rx = online(&state, victim, "victim");
    let r = root.post(&app, &path, json!({"pack": g.id, "rank": 5, "stars": 3, "streak": 2, "ranked_mmr": 1720, "casual_mmr": 1610})).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let me = pushed(&mut rx, "me").await;
    assert_eq!(me["me"]["rank"], json!({"rank": 5, "stars": 3, "legend": null, "streak": 2}));
    let s = standing::Entity::find().filter(standing::Column::Account.eq(victim)).one(&state.db).await.unwrap().unwrap();
    assert_eq!((s.rank, s.stars, s.streak, s.ranked_mmr, s.casual_mmr), (5, 3, 2, 1720.0, 1610.0));
    let ev = admin_events(&app, &root, "standing").await;
    assert_eq!(ev[0]["data"]["after"]["rank"], 5);
    assert_eq!(ev[0]["other"], "victim");
    // Legend on, then off needs a rank
    assert_eq!(root.post(&app, &path, json!({"pack": g.id, "legend": true})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "me").await["me"]["rank"]["legend"], 1, "Legend #1");
    assert_eq!(root.post(&app, &path, json!({"pack": g.id, "legend": false})).await.status, StatusCode::BAD_REQUEST);
    // the season's start
    assert_eq!(root.post(&app, &path, json!({"pack": g.id, "reset": true})).await.status, StatusCode::OK);
    let me = pushed(&mut rx, "me").await;
    assert_eq!(me["me"]["rank"]["rank"], g.ladder.start.rank);
    let c = classic_game(&root.page(&app, victim).await);
    assert_eq!((c["standing"]["rank"].as_i64(), c["standing"]["ranked_mmr"].as_f64()), (Some(g.ladder.start.rank), Some(1500.0)));
}

#[tokio::test]
async fn arena_set_and_end() {
    let (state, app, victim) = setup().await;
    let root = Admin::new(&app, "root").await;
    let path = format!("accounts/{victim}/arena");
    assert_eq!(root.post(&app, &path, json!({"action": "end"})).await.status, StatusCode::NOT_FOUND, "no run");
    arena::ActiveModel { account: Set(victim), seed: Set(1), hero: Set(0), picks: Set("[]".into()), draft: Set("{}".into()), wins: Set(2), losses: Set(1), pack: Set(String::new()) }
        .insert(&state.db)
        .await
        .unwrap();
    let mut rx = online(&state, victim, "victim");
    let r = root.post(&app, &path, json!({"action": "set", "wins": 12, "losses": 0})).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "12 wins end a run");
    assert!(r.json()["error"].as_str().unwrap().contains("0–11 wins"), "{}", r.body);
    assert_eq!(root.post(&app, &path, json!({"action": "set", "wins": 0, "losses": 3})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(root.post(&app, &path, json!({"action": "set", "wins": 7, "losses": 2})).await.status, StatusCode::OK);
    let a = pushed(&mut rx, "arena").await;
    assert_eq!((a["state"]["wins"].as_i64(), a["state"]["losses"].as_i64()), (Some(7), Some(2)));
    assert_eq!(root.page(&app, victim).await["arena"]["wins"], 7);
    assert_eq!(admin_events(&app, &root, "arena").await[0]["data"]["after"]["wins"], 7);
    assert_eq!(root.post(&app, &path, json!({"action": "end"})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "arena").await["state"], Value::Null);
    assert!(arena::Entity::find_by_id(victim).one(&state.db).await.unwrap().is_none());
}

#[tokio::test]
async fn settings_and_tag() {
    let (state, app, victim) = setup().await;
    let root = Admin::new(&app, "root").await;
    let pack = GameRules::classic().id.clone();
    let mut rx = online(&state, victim, "victim");
    let path = format!("accounts/{victim}/game_settings");
    assert_eq!(root.post(&app, &path, json!({"pack": pack, "settings": {"Bad Key": "x"}})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(root.post(&app, &path, json!({"pack": pack, "settings": {"art": "x".repeat(65)}})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(root.post(&app, &path, json!({"pack": pack, "settings": {"art": "cartoon", "music": "open"}})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "game_settings").await["games"][&pack], json!({"art": "cartoon", "music": "open"}));
    assert_eq!(root.post(&app, &path, json!({"pack": pack, "settings": {"music": null}})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "game_settings").await["games"][&pack], json!({"art": "cartoon"}));
    let row = game_setting::Entity::find_by_id((victim, pack.clone())).one(&state.db).await.unwrap().unwrap();
    assert_eq!(row.value, r#"{"art":"cartoon"}"#);
    assert_eq!(classic_game(&root.page(&app, victim).await)["settings"], json!({"art": "cartoon"}));
    admin_events(&app, &root, "game_settings").await;

    let path = format!("accounts/{victim}/tag");
    assert_eq!(root.post(&app, &path, json!({"tag": "no"})).await.status, StatusCode::BAD_REQUEST);
    let other = db::create_account(&state.db, "other", "x", "user").await.unwrap().unwrap();
    assert_eq!(root.post(&app, &format!("accounts/{other}/tag"), json!({"tag": "Taken1"})).await.status, StatusCode::OK);
    assert_eq!(root.post(&app, &path, json!({"tag": "taken1"})).await.status, StatusCode::CONFLICT, "ignoring case");
    assert_eq!(root.post(&app, &path, json!({"tag": "Victim7"})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "me").await["me"]["tag"], "Victim7");
    assert_eq!(root.post(&app, &path, json!({"tag": ""})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "me").await["me"]["tag"], Value::Null);
    assert_eq!(admin_events(&app, &root, "tag").await.len(), 3);
}

#[tokio::test]
async fn decks_from_codes() {
    let (state, app, victim) = setup().await;
    let root = Admin::new(&app, "root").await;
    let rs = ruleset::classic();
    let pack = GameRules::classic().id.clone();
    let code = deck_code::encode(rs, "HERO_08", &mage_cards()).unwrap();
    let path = format!("accounts/{victim}/decks");
    for (bad, why) in [("hello", "not a deck code"), ("AAECAR8GxwPJBLsFmQfZB/gIDI0B2AGoArUDhwSSBe0G6wfbCe0J", "not a deck code")] {
        let r = root.post(&app, &path, json!({"pack": pack, "code": bad})).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST);
        assert!(r.json()["error"].as_str().unwrap().contains(why), "{}", r.body);
    }
    let short = deck_code::encode(rs, "HERO_08", &mage_cards()[..29]).unwrap();
    let r = root.post(&app, &path, json!({"pack": pack, "code": short})).await;
    assert!(r.json()["error"].as_str().unwrap().contains("exactly 30"), "an incomplete deck: {}", r.body);
    let mut rx = online(&state, victim, "victim");
    // Hearthstone's copied text: the name from "###"
    let r = root.post(&app, &path, json!({"pack": pack, "code": format!("### Frost\n# Class: Mage\n{code}\n# end")})).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let list = pushed(&mut rx, "decks").await["list"].clone();
    assert_eq!((list[0]["name"].as_str(), list[0]["hero"].as_str(), list[0]["pack"].as_str()), (Some("Frost"), Some("HERO_08"), Some(pack.as_str())));
    let id = list[0]["id"].as_i64().unwrap();
    assert_eq!(root.post(&app, &path, json!({"pack": pack, "code": code, "name": "Named"})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "decks").await["list"][1]["name"], "Named");
    let ev = admin_events(&app, &root, "deck_add").await;
    assert_eq!(ev.len(), 2);
    // the page shows each deck with its cards (names, costs) and its code
    let c = classic_game(&root.page(&app, victim).await);
    let d = &c["decks"][0];
    assert_eq!((d["code"].as_str(), d["count"].as_i64(), d["class"].as_str(), d["valid"].as_bool()), (Some(code.as_str()), Some(30), Some("MAGE"), Some(true)));
    assert!(d["cards"].as_array().unwrap().iter().any(|c| c["name"] == "Fireball" && c["cost"] == 4 && c["n"] == 2), "{d}");
    // rename, copy, delete
    let one = |a: &str| format!("accounts/{victim}/decks/{id}/{a}");
    assert_eq!(root.post(&app, &one("rename"), json!({"name": "y".repeat(61)})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(root.post(&app, &one("rename"), json!({"name": "Ice"})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "decks").await["list"][0]["name"], "Ice");
    assert_eq!(root.post(&app, &one("copy"), json!({"to": "nobody"})).await.status, StatusCode::NOT_FOUND);
    assert_eq!(root.post(&app, &one("copy"), json!({"to": "root"})).await.status, StatusCode::FORBIDDEN, "the superuser is not changed");
    let other = db::create_account(&state.db, "other", "x", "user").await.unwrap().unwrap();
    let mut rx2 = online(&state, other, "other");
    assert_eq!(root.post(&app, &one("copy"), json!({"to": "Other"})).await.status, StatusCode::OK);
    let copied = pushed(&mut rx2, "decks").await["list"][0].clone();
    assert_eq!((copied["name"].as_str(), copied["cards"].as_array().unwrap().len()), (Some("Ice"), 30));
    assert_eq!(admin_events(&app, &root, "deck_copy").await[0]["data"]["to"], "other");
    assert_eq!(root.post(&app, &format!("accounts/{other}/decks/{id}/delete"), json!({})).await.status, StatusCode::NOT_FOUND, "not its deck");
    assert_eq!(root.post(&app, &one("delete"), json!({})).await.status, StatusCode::OK);
    assert_eq!(pushed(&mut rx, "decks").await["list"].as_array().unwrap().len(), 1);
    assert!(deck::Entity::find_by_id(id).one(&state.db).await.unwrap().is_none());
    assert_eq!(root.post(&app, &one("rename"), json!({"name": "x"})).await.status, StatusCode::NOT_FOUND);
    admin_events(&app, &root, "deck_delete").await;
}

/// Every other place the panel shows decks gives their codes: a game's players (the replay), a
/// tournament's entrants.
#[tokio::test]
async fn codes_on_game_and_tournament_pages() {
    use classichs_server::entity::tournament::{self as tour, entrant};
    use sea_orm::{IntoActiveModel, NotSet};
    let (state, app, victim) = setup().await;
    let root = Admin::new(&app, "root").await;
    let rs = ruleset::classic();
    let rh = GameRules::classic().rules_hash.clone();
    let code = deck_code::encode(rs, "HERO_08", &mage_cards()).unwrap();
    let data = json!({"format": "classichs-replay", "v": 1, "game": "g1", "pack": rh, "players": [{"name": "victim", "hero": "HERO_08", "cards": mage_cards()},
                      {"name": "x", "hero": "HERO_01", "cards": classichs_engine::deck::basic("WARRIOR")}], "actions": [], "hash": "h"});
    classichs_server::replays::save(&state.db, "g1", &rh, [victim, victim], 5, &data).await.unwrap();
    let page = call(&app, get("/admin/api/games/g1", &root.cookie)).await.json();
    assert_eq!(page["decks"][0]["code"], code);
    assert_eq!(page["decks"][1]["class"], "WARRIOR");
    assert!(page["decks"][0]["cards"].as_array().unwrap().iter().any(|c| c["name"] == "Fireball" && c["n"] == 2), "the cards listed by name");
    assert_eq!(page["decks"][0]["name"], "victim");

    let t = tour::Model {
        id: 0, name: "Cup".into(), creator: victim, pack: rh.clone(), format: "elimination".into(), options: r#"{"losses":1}"#.into(),
        series: "conquest".into(), best_of: 1, bans: 0, start_at: classichs_server::events::now_ms() + 3_600_000, max_players: 8,
        min_players: 2, deck_reveal: false, spectators: false, status: "open".into(), reason: String::new(), created: 0, ended: 0,
    };
    let mut am = t.into_active_model().reset_all();
    am.id = NotSet;
    let t = am.insert(&state.db).await.unwrap();
    let decks = json!([{"name": "m", "hero": "HERO_08", "cards": mage_cards()}]).to_string();
    entrant::Model { tournament: t.id, account: victim, decks, seed: -1, team: -1, place: 0, joined: 1 }.into_active_model().reset_all().insert(&state.db).await.unwrap();
    let page = call(&app, get(&format!("/admin/api/tournaments/{}", t.id), &root.cookie)).await.json();
    assert_eq!(page["entrants"][0]["decks"][0]["code"], code);
}

// --- deck codes -------------------------------------------------------------------------------

fn sorted(mut v: Vec<String>) -> Vec<String> {
    v.sort();
    v
}

fn round_trip(rs: &Ruleset, hero: &str, cards: &[String]) {
    let code = deck_code::encode(rs, hero, cards).unwrap();
    let d = deck_code::decode(rs, &code).unwrap_or_else(|e| panic!("{hero}: {e}"));
    assert_eq!((d.hero.as_str(), sorted(d.cards)), (hero, sorted(cards.to_vec())), "{code}");
}

#[test]
fn classic_codes_round_trip() {
    let rs = ruleset::classic();
    // the pack's ready decks: their Hearthstone codes (from deck sites) read as their cards
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../packs/classic/decks");
    let mut n = 0;
    for f in std::fs::read_dir(dir).unwrap() {
        let t: Value = serde_json::from_str(&std::fs::read_to_string(f.unwrap().path()).unwrap()).unwrap();
        let (hero, cards): (String, Vec<String>) = (serde_json::from_value(t["champion"].clone()).unwrap(), serde_json::from_value(t["cards"].clone()).unwrap());
        let d = deck_code::decode(rs, t["code"].as_str().unwrap()).unwrap();
        assert_eq!((d.hero.as_str(), sorted(d.cards)), (hero.as_str(), sorted(cards.clone())), "{}", t["name"]);
        round_trip(rs, &hero, &cards);
        n += 1;
    }
    assert_eq!(n, 10);
    // the hero's number is Hearthstone's (Jaina: 637) and the header the client's: 0, 1, format 3, one hero
    let code = deck_code::encode(rs, "HERO_08", &mage_cards()).unwrap();
    use base64::Engine;
    let raw = base64::engine::general_purpose::STANDARD.decode(&code).unwrap();
    assert_eq!(&raw[..6], &[0, 1, 3, 1, 0xfd, 0x04]);
}

/// Neonfall has no code numbers: a card's is its id's Godot hash, as the client gives it. The same
/// code is in the client's test (tests/test_deck_model.gd `test_neon_code_matches_the_server`).
#[test]
fn neon_codes_round_trip_and_match_the_client() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../packs/neon.cardpack");
    let Ok(bytes) = std::fs::read(&path) else {
        eprintln!("no packs/neon.cardpack (tools/build_packs.sh): skipped");
        return;
    };
    let rs = ruleset::load(&classichs_engine::pack::read_zip(&bytes).unwrap()).unwrap();
    assert!(rs.templates.len() >= 3);
    for t in &rs.templates {
        round_trip(rs, &t.hero, &t.cards);
    }
    let t: Value = serde_json::from_str(&std::fs::read_to_string(path.with_file_name("neon/decks/hostile_merger.json")).unwrap()).unwrap();
    let cards: Vec<String> = serde_json::from_value(t["cards"].clone()).unwrap();
    assert_eq!(deck_code::encode(rs, t["champion"].as_str().unwrap(), &cards).unwrap(), NEON_CODE);
    // a Classic code means nothing in Neonfall
    let classic = deck_code::encode(ruleset::classic(), "HERO_08", &mage_cards()).unwrap();
    assert!(deck_code::decode(rs, &classic).unwrap_err().contains("does not have"));
}

const NEON_CODE: &str = "AAEDAYjD6UUKj4CH6wP6+dPrA8bV57sIhMG5gQm8/fSKCbeor+UKl8ju9gvt2Y7cDeDLqZMP65OY1Q8KhJ3m0wHYivTPAuSJ76QE/vPw6gWQvKGvB9X+4s0I4Imclg6hnc3ZDp606NsOoP6R9Q4A";
