//! reports.rs: a player's problem report (text, picture, voice, the context and the games), its
//! limits, its thread (the admin and the player write), and the admin's side: the list and its filters,
//! a report, state, note, merging duplicates, the files, the export (zip, JSON, Markdown), delete and purge.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use classichs_server::storage::Storage;
use classichs_server::{auth, db, replays, router, App, AppRef, Timers};
use serde_json::{json, Value};
use std::io::Read;
use std::net::SocketAddr;
use tower::ServiceExt;

struct Res {
    status: StatusCode,
    body: Vec<u8>,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }
}

async fn call(app: &axum::Router, req: Request<Body>) -> Res {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let body = axum::body::to_bytes(res.into_body(), 64 << 20).await.unwrap().to_vec();
    Res { status, body }
}

struct T {
    state: AppRef,
    app: axum::Router,
    cookie: String,
    csrf: String,
}

impl T {
    async fn new() -> T {
        let dir = std::env::temp_dir().join(format!("chs-reports-{}", rand::random::<u64>()));
        let state = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), Storage::dir(&dir).unwrap());
        db::make_superuser(&state.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
        let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
        let login = Request::post("/admin/api/login")
            .header(header::HOST, "admin.test")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({"user": "root", "password": "rootpassword"}).to_string()))
            .unwrap();
        let res = app.clone().oneshot(login).await.unwrap();
        let cookie = res.headers()[header::SET_COOKIE].to_str().unwrap().split(';').next().unwrap().to_string();
        let body = axum::body::to_bytes(res.into_body(), 1 << 20).await.unwrap();
        let csrf = serde_json::from_slice::<Value>(&body).unwrap()["csrf"].as_str().unwrap().to_string();
        T { state, app, cookie, csrf }
    }

    /// A player and a game session token.
    async fn player(&self, name: &str) -> (i64, String) {
        let (id, _) = db::register(&self.state.db, 0, name, &auth::hash_password("password1"), None).await.unwrap().unwrap();
        (id, db::new_session(&self.state.db, id, "game", 3600, "").await.unwrap())
    }

    async fn send(&self, token: &str, body: Value) -> Res {
        let req = Request::post("/reports")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();
        call(&self.app, req).await
    }

    async fn get(&self, uri: &str) -> Res {
        call(&self.app, Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, &self.cookie).body(Body::empty()).unwrap()).await
    }

    async fn post(&self, uri: &str, body: Value) -> Res {
        let req = Request::post(uri)
            .header(header::HOST, "admin.test")
            .header(header::COOKIE, &self.cookie)
            .header("x-csrf-token", &self.csrf)
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();
        call(&self.app, req).await
    }
}

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n not really the rest of a picture";

/// A 16 kHz mono 16-bit WAV of `secs` seconds (what the game records).
fn wav(secs: f64) -> Vec<u8> {
    let n = (16000.0 * secs) as usize;
    let data: Vec<u8> = (0..n).flat_map(|i| (((i as f64 * 0.2).sin() * 8000.0) as i16).to_le_bytes()).collect();
    let mut b = b"RIFF".to_vec();
    b.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    b.extend_from_slice(b"WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00");
    b.extend_from_slice(&16000u32.to_le_bytes());
    b.extend_from_slice(&32000u32.to_le_bytes());
    b.extend_from_slice(b"\x02\x00\x10\x00data");
    b.extend_from_slice(&(data.len() as u32).to_le_bytes());
    b.extend_from_slice(&data);
    b
}

impl T {
    /// A player's call with his game token: GET (no body) or POST.
    async fn mine(&self, token: &str, uri: &str, body: Option<Value>) -> Res {
        let b = match body {
            Some(v) => Request::post(uri).header(header::CONTENT_TYPE, "application/json").header(header::AUTHORIZATION, format!("Bearer {token}")).body(Body::from(v.to_string())),
            None => Request::get(uri).header(header::AUTHORIZATION, format!("Bearer {token}")).body(Body::empty()),
        };
        call(&self.app, b.unwrap()).await
    }
}

fn context(version: &str) -> Value {
    json!({"version": version, "platform": "macOS", "screen": "1920x1080", "language": "ru",
           "pack": {"id": "classic-2014", "version": "1.0.0", "rules_hash": "abc"}, "game": ""})
}

fn zip_names(z: &mut zip::ZipArchive<std::io::Cursor<Vec<u8>>>) -> Vec<String> {
    let mut names: Vec<String> = z.file_names().map(|n| n.unwrap().to_string()).collect();
    names.sort();
    names
}

#[tokio::test]
async fn send_limits_and_the_admin_side() {
    let t = T::new().await;
    let (pia, token) = t.player("pia").await;
    let (bob, _) = t.player("bob").await;
    for (i, g) in ["g1", "g2", "g3", "g4", "g5", "g6"].iter().enumerate() {
        replays::save(&t.state.db, 0, g, "abc", [pia, bob], 1000 + i as i64, &json!({"mode": "casual", "players": [{"name": "pia"}, {"name": "bob"}], "result": {"winner": 0}})).await.unwrap();
    }

    // not logged in; the limits
    assert_eq!(t.send("nope", json!({"text": "hi"})).await.status, StatusCode::UNAUTHORIZED);
    let r = t.send(&token, json!({"text": "  "})).await;
    assert_eq!((r.status, r.json()["code"].clone()), (StatusCode::BAD_REQUEST, json!("bad_text")));
    assert_eq!(t.send(&token, json!({"text": "x".repeat(4001)})).await.json()["code"], "bad_text");
    assert_eq!(t.send(&token, json!({"text": "hi", "screen": STANDARD.encode(b"GIF89a")})).await.json()["code"], "bad_screen");
    let big = t.send(&token, json!({"text": "hi", "screen": STANDARD.encode(vec![0u8; (10 << 20) + 10])})).await;
    assert_eq!((big.status, big.json()["code"].clone()), (StatusCode::PAYLOAD_TOO_LARGE, json!("too_large")), "10 MB at most");
    assert_eq!(t.send(&token, json!({"text": "hi", "voice": STANDARD.encode(wav(62.0))})).await.json()["code"], "bad_voice");

    // a report with everything; a 9 MB picture is fine
    let mut nine = PNG.to_vec();
    nine.resize(9 << 20, 7);
    let r = t
        .send(&token, json!({"text": "The board froze", "written_at": 1234, "context": context("0.74.0"),
                             "screen": STANDARD.encode(&nine), "voice": STANDARD.encode(wav(1.0))}))
        .await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&r.body));
    let first = r.json()["report"]["id"].as_i64().unwrap();
    for i in 0..4 {
        let r = t.send(&token, json!({"text": format!("more {i}"), "context": context(if i == 0 { "0.73.0" } else { "0.74.0" })})).await;
        assert_eq!(r.status, StatusCode::CREATED);
    }
    let r = t.send(&token, json!({"text": "sixth"})).await;
    assert_eq!((r.status, r.json()["code"].clone()), (StatusCode::TOO_MANY_REQUESTS, json!("too_many")), "5 an hour");

    // the list, its filters, the counts
    let l = t.get("/admin/api/reports").await.json();
    assert_eq!((l["total"].clone(), l["counts"].clone()), (json!(5), json!({"new": 5, "answers": 0})));
    assert_eq!(l["versions"], json!(["0.74.0", "0.73.0"]));
    assert_eq!(l["list"][0]["state"], "open");
    assert_eq!(t.get("/admin/api/reports?version=0.73.0").await.json()["total"], 1);
    assert_eq!(t.get("/admin/api/reports?player=pi").await.json()["total"], 5);
    assert_eq!(t.get("/admin/api/reports?player=bob").await.json()["total"], 0);
    assert_eq!(t.get("/admin/api/dashboard").await.json()["totals"]["reports_new"], 5);

    // one report: its games (the last 5), the files; opened, it is not new any more
    let one = t.get(&format!("/admin/api/reports/{first}")).await.json();
    assert_eq!((one["text"].clone(), one["written_at"].clone(), one["account"]["user"].clone()), (json!("The board froze"), json!(1234), json!("pia")));
    assert_eq!(one["context"]["screen"], "1920x1080");
    let games: Vec<&str> = one["games"].as_array().unwrap().iter().map(|g| g["game"].as_str().unwrap()).collect();
    assert_eq!(games, ["g6", "g5", "g4", "g3", "g2"]);
    assert_eq!(one["games"][0]["players"], json!(["pia", "bob"]));
    assert_eq!(one["thread"].as_array().unwrap().len(), 1, "the report itself");
    assert_eq!(t.get(&format!("/admin/api/reports/{first}/screen.png")).await.body, nine);
    assert!(t.get(&format!("/admin/api/reports/{first}/voice.ogg")).await.body.starts_with(b"OggS"), "the WAV is kept as Ogg Opus");
    assert_eq!(t.get("/admin/api/reports/counts").await.json(), json!({"new": 4, "answers": 0}));

    // the thread: the admin answers, the player sees it, answers back with a picture
    assert_eq!(t.mine(&token, "/reports", None).await.json()["unread"], 0);
    t.post(&format!("/admin/api/reports/{first}/answer"), json!({"text": "Which card did you play?"})).await;
    let mine = t.mine(&token, "/reports", None).await.json();
    assert_eq!(mine["unread"], 1);
    let row = mine["list"].as_array().unwrap().iter().find(|r| r["id"] == first).unwrap().clone();
    assert_eq!((row["unread"].clone(), row["state"].clone(), row["messages"].clone()), (json!(true), json!("open"), json!(2)));
    let th = t.mine(&token, &format!("/reports/{first}"), None).await.json();
    let from: Vec<&str> = th["messages"].as_array().unwrap().iter().map(|m| m["from"].as_str().unwrap()).collect();
    assert_eq!(from, ["you", "admin"]);
    assert_eq!(th["messages"][1]["text"], "Which card did you play?");
    assert_eq!(t.mine(&token, "/reports", None).await.json()["unread"], 0, "opening the thread clears it");
    assert_eq!(t.mine(&token, "/reports/999", None).await.status, StatusCode::NOT_FOUND);
    let r = t.mine(&token, &format!("/reports/{first}"), Some(json!({"text": "Leeroy", "screen": STANDARD.encode(PNG)}))).await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&r.body));
    let reply = r.json()["message"]["id"].as_i64().unwrap();
    assert_eq!(t.get("/admin/api/reports/counts").await.json(), json!({"new": 4, "answers": 1}));
    let one = t.get(&format!("/admin/api/reports/{first}")).await.json();
    let texts: Vec<&str> = one["thread"].as_array().unwrap().iter().map(|m| m["text"].as_str().unwrap()).collect();
    assert_eq!(texts, ["The board froze", "Which card did you play?", "Leeroy"]);
    assert_eq!(t.get(&format!("/admin/api/reports/{first}/m{reply}.png")).await.body, PNG);
    assert_eq!(t.get("/admin/api/reports/counts").await.json(), json!({"new": 4, "answers": 0}));

    // state and note; the player sees "closed"
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/state"), json!({"state": "lost"})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/state"), json!({"state": "resolved"})).await.json()["state"], "resolved");
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/note"), json!({"note": "a known bug"})).await.json()["note"], "a known bug");
    let mine = t.mine(&token, "/reports", None).await.json();
    assert_eq!(mine["unread"], 1, "a state change is news for the player");
    assert_eq!(t.mine(&token, &format!("/reports/{first}"), None).await.json()["state"], "closed");
    assert_eq!(t.get("/admin/api/reports?state=resolved").await.json()["total"], 1);

    // one report for an agent: Markdown, and a zip with report.md + report.json + its files
    let md = String::from_utf8(t.get(&format!("/admin/api/reports/{first}/markdown")).await.body).unwrap();
    for want in ["# Problem report", "The board froze", "0.74.0", "classic-2014 1.0.0 (rules_hash abc)", "Which card did you play?", "`g6.chsreplay`", "`voice.ogg`", &format!("m{reply}.png")] {
        assert!(md.contains(want), "{want} in\n{md}");
    }
    let z = t.get(&format!("/admin/api/reports/{first}/export")).await.body;
    let mut z = zip::ZipArchive::new(std::io::Cursor::new(z)).unwrap();
    let names = zip_names(&mut z);
    for f in ["report.md", "report.json", "screen.png", "voice.ogg", "g6.chsreplay", "g2.chsreplay", &format!("m{reply}.png")] {
        assert!(names.contains(&f.to_string()), "{f} in {names:?}");
    }

    // the export of many: JSON of the filtered, a zip of the ticked
    let j: Value = t.get("/admin/api/reports/export?format=json&version=0.73.0").await.json();
    assert_eq!(j.as_array().unwrap().len(), 1);
    let z = t.get(&format!("/admin/api/reports/export?ids={first},{}", first + 1)).await.body;
    let mut z = zip::ZipArchive::new(std::io::Cursor::new(z)).unwrap();
    let names = zip_names(&mut z);
    for f in ["screen.png", "voice.ogg", "g6.chsreplay", "g2.chsreplay"] {
        assert!(names.contains(&format!("{first}/{f}")), "{f} in {names:?}");
    }
    let mut s = String::new();
    z.by_name("reports.json").unwrap().read_to_string(&mut s).unwrap();
    let list: Value = serde_json::from_str(&s).unwrap();
    assert_eq!(list.as_array().unwrap().len(), 2);
    let mine = list.as_array().unwrap().iter().find(|r| r["id"] == first).unwrap();
    assert_eq!(mine["files"]["screen"], format!("{first}/screen.png"));
    assert_eq!(mine["files"]["replays"].as_array().unwrap().len(), 5);
    assert_eq!(mine["thread"].as_array().unwrap().len(), 3);
    let mut replay = String::new();
    z.by_name(&format!("{first}/g6.chsreplay")).unwrap().read_to_string(&mut replay).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&replay).unwrap()["mode"], "casual");

    // deleted with its files
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/delete"), json!({})).await.status, StatusCode::OK);
    assert_eq!(t.get(&format!("/admin/api/reports/{first}")).await.status, StatusCode::NOT_FOUND);
    assert!(t.state.store.read_path(&format!("reports/{first}/screen.png"), 20 << 20).await.is_err());
    assert!(t.state.store.read_path(&format!("reports/{first}/m{reply}.png"), 1 << 20).await.is_err());
}

#[tokio::test]
async fn merged_duplicates() {
    let t = T::new().await;
    let (_, pia) = t.player("pia").await;
    let (_, bob) = t.player("bob").await;
    let id = |r: Res| r.json()["report"]["id"].as_i64().unwrap();
    let a = id(t.send(&pia, json!({"text": "Cards vanish", "screen": STANDARD.encode(PNG)})).await);
    let b = id(t.send(&bob, json!({"text": "My cards disappear too"})).await);
    assert_eq!(t.post(&format!("/admin/api/reports/{b}/merge"), json!({"into": b})).await.status, StatusCode::BAD_REQUEST);
    t.post(&format!("/admin/api/reports/{b}/merge"), json!({"into": a})).await;
    let l = t.get("/admin/api/reports").await.json();
    assert_eq!((l["total"].clone(), l["list"][0]["id"].clone(), l["list"][0]["merged"].clone()), (json!(1), json!(a), json!(1)), "the duplicate is under the first");
    let one = t.get(&format!("/admin/api/reports/{a}")).await.json();
    assert_eq!(one["merged"][0]["id"], b);
    assert_eq!(one["thread"].as_array().unwrap().len(), 2);
    // an answer and a state reach both players, each in his own thread
    t.post(&format!("/admin/api/reports/{a}/answer"), json!({"text": "Fixed in 0.74.1"})).await;
    t.post(&format!("/admin/api/reports/{a}/state"), json!({"state": "rejected"})).await;
    for (tok, r) in [(&pia, a), (&bob, b)] {
        let th = t.mine(tok, &format!("/reports/{r}"), None).await.json();
        assert_eq!((th["state"].clone(), th["messages"].as_array().unwrap().len()), (json!("closed"), 2), "{th}");
        assert_eq!(th["messages"][1]["text"], "Fixed in 0.74.1");
    }
    assert_eq!(t.mine(&bob, &format!("/reports/{a}"), None).await.status, StatusCode::NOT_FOUND, "not his");
    let one = t.get(&format!("/admin/api/reports/{a}")).await.json();
    assert_eq!(one["thread"].as_array().unwrap().len(), 3, "the answer once");
    // a third merged into the duplicate lands on the first; a merged one's picture is reachable from the group
    let (_, cid) = t.player("cid").await;
    let c = id(t.send(&cid, json!({"text": "same"})).await);
    t.post(&format!("/admin/api/reports/{c}/merge"), json!({"into": b})).await;
    assert_eq!(t.get(&format!("/admin/api/reports/{a}")).await.json()["merged"].as_array().unwrap().len(), 2);
    assert_eq!(t.get(&format!("/admin/api/reports/{b}/screen.png?of={a}")).await.status, StatusCode::NOT_FOUND, "b's group is b alone");
    // deleting the first frees the others
    t.post(&format!("/admin/api/reports/{a}/delete"), json!({})).await;
    assert_eq!(t.get("/admin/api/reports").await.json()["total"], 2);
}

#[tokio::test]
async fn kept_as_long_as_the_account_and_the_keeping_time() {
    let t = T::new().await;
    let (pia, token) = t.player("pia").await;
    let (_, tok2) = t.player("bob").await;
    let shot = json!({"text": "hi", "screen": STANDARD.encode(PNG)});
    let id = |r: Res| r.json()["report"]["id"].as_i64().unwrap();
    let (a, b) = (id(t.send(&token, shot.clone()).await), id(t.send(&tok2, shot).await));
    let file = |i: i64| format!("reports/{i}/screen.png");
    // an account deleted: its reports and their files go
    let r = t.post(&format!("/admin/api/accounts/{pia}/delete"), json!({"confirm": "pia"})).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(t.get(&format!("/admin/api/reports/{a}")).await.status, StatusCode::NOT_FOUND);
    assert!(t.state.store.read_path(&file(a), 1 << 20).await.is_err());
    assert!(t.state.store.read_path(&file(b), 1 << 20).await.is_ok());
    // the purge: nothing is older than a day; `prune` up to tomorrow takes the rest
    assert_eq!(t.post("/admin/api/reports/purge", json!({"days": 0})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(t.post("/admin/api/reports/purge", json!({"days": 1})).await.json()["removed"], 0);
    assert_eq!(classichs_server::reports::prune(&t.state, classichs_server::ranked::now() + 86400).await.unwrap(), 1);
    assert!(t.state.store.read_path(&file(b), 1 << 20).await.is_err());
    assert_eq!(t.get("/admin/api/reports").await.json()["total"], 0);
}
