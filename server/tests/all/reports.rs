//! reports.rs: a player's problem report (text, picture, voice, the context and the games), its
//! limits, and the admin's side: the list and its filters, a report, state, note, the answer as a
//! private message, the files and the export (zip and JSON).

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use classichs_server::entity::message;
use classichs_server::storage::Storage;
use classichs_server::{auth, db, replays, router, App, AppRef, Timers};
use sea_orm::EntityTrait;
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
        let (id, _) = db::register(&self.state.db, name, &auth::hash_password("password1"), None).await.unwrap().unwrap();
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

fn context(version: &str) -> Value {
    json!({"version": version, "platform": "macOS", "screen": "1920x1080", "language": "ru",
           "pack": {"id": "classic-2014", "version": "1.0.0", "rules_hash": "abc"}, "game": ""})
}

#[tokio::test]
async fn send_limits_and_the_admin_side() {
    let t = T::new().await;
    let (pia, token) = t.player("pia").await;
    let (bob, _) = t.player("bob").await;
    for (i, g) in ["g1", "g2", "g3", "g4", "g5", "g6"].iter().enumerate() {
        replays::save(&t.state.db, g, "abc", [pia, bob], 1000 + i as i64, &json!({"mode": "casual", "players": [{"name": "pia"}, {"name": "bob"}], "result": {"winner": 0}})).await.unwrap();
    }

    // not logged in; the limits
    assert_eq!(t.send("nope", json!({"text": "hi"})).await.status, StatusCode::UNAUTHORIZED);
    let r = t.send(&token, json!({"text": "  "})).await;
    assert_eq!((r.status, r.json()["code"].clone()), (StatusCode::BAD_REQUEST, json!("bad_text")));
    assert_eq!(t.send(&token, json!({"text": "x".repeat(4001)})).await.json()["code"], "bad_text");
    assert_eq!(t.send(&token, json!({"text": "hi", "screen": STANDARD.encode(b"GIF89a")})).await.json()["code"], "bad_screen");
    let big = t.send(&token, json!({"text": "hi", "screen": STANDARD.encode(vec![0u8; (4 << 20) + 10])})).await;
    assert_eq!((big.status, big.json()["code"].clone()), (StatusCode::PAYLOAD_TOO_LARGE, json!("too_large")));
    assert_eq!(t.send(&token, json!({"text": "hi", "voice": STANDARD.encode(wav(62.0))})).await.json()["code"], "bad_voice");

    // a report with everything
    let r = t
        .send(&token, json!({"text": "The board froze", "written_at": 1234, "context": context("0.74.0"),
                             "screen": STANDARD.encode(PNG), "voice": STANDARD.encode(wav(1.0))}))
        .await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&r.body));
    let first = r.json()["report"]["id"].as_i64().unwrap();
    for i in 0..4 {
        let r = t.send(&token, json!({"text": format!("more {i}"), "context": context(if i == 0 { "0.73.0" } else { "0.74.0" })})).await;
        assert_eq!(r.status, StatusCode::CREATED);
    }
    let r = t.send(&token, json!({"text": "sixth"})).await;
    assert_eq!((r.status, r.json()["code"].clone()), (StatusCode::TOO_MANY_REQUESTS, json!("too_many")), "5 an hour");

    // the list, its filters, the dashboard's count
    let l = t.get("/admin/api/reports").await.json();
    assert_eq!((l["total"].clone(), l["new"].clone()), (json!(5), json!(5)));
    assert_eq!(l["versions"], json!(["0.74.0", "0.73.0"]));
    assert_eq!(t.get("/admin/api/reports?version=0.73.0").await.json()["total"], 1);
    assert_eq!(t.get("/admin/api/reports?player=pi").await.json()["total"], 5);
    assert_eq!(t.get("/admin/api/reports?player=bob").await.json()["total"], 0);
    assert_eq!(t.get("/admin/api/dashboard").await.json()["totals"]["reports_new"], 5);

    // one report: opened = seen; its games (the last 5), the files
    let one = t.get(&format!("/admin/api/reports/{first}")).await.json();
    assert_eq!(one["state"], "seen");
    assert_eq!((one["text"].clone(), one["written_at"].clone(), one["account"]["user"].clone()), (json!("The board froze"), json!(1234), json!("pia")));
    assert_eq!(one["context"]["screen"], "1920x1080");
    let games: Vec<&str> = one["games"].as_array().unwrap().iter().map(|g| g["game"].as_str().unwrap()).collect();
    assert_eq!(games, ["g6", "g5", "g4", "g3", "g2"]);
    assert_eq!(one["games"][0]["players"], json!(["pia", "bob"]));
    assert_eq!(t.get(&format!("/admin/api/reports/{first}/screen.png")).await.body, PNG);
    let voice = t.get(&format!("/admin/api/reports/{first}/voice.ogg")).await.body;
    assert!(voice.starts_with(b"OggS"), "the WAV is kept as Ogg Opus");
    assert_eq!(t.get("/admin/api/dashboard").await.json()["totals"]["reports_new"], 4);

    // state, note, answer
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/state"), json!({"state": "lost"})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/state"), json!({"state": "done"})).await.json()["state"], "done");
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/note"), json!({"note": "a known bug"})).await.json()["note"], "a known bug");
    let a = t.post(&format!("/admin/api/reports/{first}/answer"), json!({"text": "Fixed in the next version, thanks!"})).await.json();
    let msg = message::Entity::find_by_id(a["answer_message"].as_i64().unwrap()).one(&t.state.db).await.unwrap().unwrap();
    assert_eq!((msg.src, msg.text.as_str()), (1, "Fixed in the next version, thanks!"), "a private message from the admin (root is account 1)");
    assert!(msg.lo == pia || msg.hi == pia);
    let one = t.get(&format!("/admin/api/reports/{first}")).await.json();
    assert_eq!((one["state"].clone(), one["note"].clone(), one["answer"]["text"].clone()), (json!("done"), json!("a known bug"), json!("Fixed in the next version, thanks!")));
    assert_eq!(t.get("/admin/api/reports?state=done").await.json()["total"], 1);

    // the export: JSON of the filtered, a zip of the ticked
    let j: Value = t.get("/admin/api/reports/export?format=json&version=0.73.0").await.json();
    assert_eq!(j.as_array().unwrap().len(), 1);
    let z = t.get(&format!("/admin/api/reports/export?ids={first},{}", first + 1)).await.body;
    let mut z = zip::ZipArchive::new(std::io::Cursor::new(z)).unwrap();
    let mut names: Vec<String> = z.file_names().map(|n| n.unwrap().to_string()).collect();
    names.sort();
    let want = |f: &str| format!("{first}/{f}");
    for f in ["screen.png", "voice.ogg", "g6.chsreplay", "g2.chsreplay"] {
        assert!(names.contains(&want(f)), "{f} in {names:?}");
    }
    let mut s = String::new();
    z.by_name("reports.json").unwrap().read_to_string(&mut s).unwrap();
    let list: Value = serde_json::from_str(&s).unwrap();
    assert_eq!(list.as_array().unwrap().len(), 2);
    let mine = list.as_array().unwrap().iter().find(|r| r["id"] == first).unwrap();
    assert_eq!(mine["files"]["screen"], want("screen.png"));
    assert_eq!(mine["files"]["replays"].as_array().unwrap().len(), 5);
    let mut replay = String::new();
    z.by_name(&want("g6.chsreplay")).unwrap().read_to_string(&mut replay).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&replay).unwrap()["mode"], "casual");

    // deleted with its files
    assert_eq!(t.post(&format!("/admin/api/reports/{first}/delete"), json!({})).await.status, StatusCode::OK);
    assert_eq!(t.get(&format!("/admin/api/reports/{first}")).await.status, StatusCode::NOT_FOUND);
    assert!(t.state.store.read_path(&format!("reports/{first}/screen.png"), 1 << 20).await.is_err());
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
    // the daily cleanup: nothing is older than an hour ago, everything older than tomorrow
    assert_eq!(classichs_server::reports::prune(&t.state, classichs_server::ranked::now() - 3600).await.unwrap(), 0);
    // an account deleted: its reports and their files go
    let r = t.post(&format!("/admin/api/accounts/{pia}/delete"), json!({"confirm": "pia"})).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(t.get(&format!("/admin/api/reports/{a}")).await.status, StatusCode::NOT_FOUND);
    assert!(t.state.store.read_path(&file(a), 1 << 20).await.is_err());
    assert!(t.state.store.read_path(&file(b), 1 << 20).await.is_ok());
    assert_eq!(classichs_server::reports::prune(&t.state, classichs_server::ranked::now() + 86400).await.unwrap(), 1);
    assert!(t.state.store.read_path(&file(b), 1 << 20).await.is_err());
    assert_eq!(t.get("/admin/api/reports").await.json()["total"], 0);
}
