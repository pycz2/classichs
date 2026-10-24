//! The server's bots: two bots of the server play each other through the in-process adapter; a
//! bot over the network (the WebSocket adapter, the same bot code) plays one of them; the admin's
//! Bots API adds, changes, stops and deletes bots. (No packs here: the built-in Classic.)

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::bots::runtime::{self, Auth, ConnectFn, Ctx, LoadFn};
use classichs_server::bots::transport::Transport;
use classichs_server::bots::{self, BotConfig};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, router, App, AppRef, Timers};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower::ServiceExt;

fn app() -> impl std::future::Future<Output = AppRef> {
    async {
        let store = Storage::dir(&std::env::temp_dir().join(format!("chs-bots-{}", rand::random::<u64>()))).unwrap();
        let app = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
        classichs_server::spawn_background(app.clone()); // (the matchmaking)
        app
    }
}

/// Waits until every bot has finished `games` games; the bots' errors fail the test.
async fn wait_games(app: &AppRef, ids: &[i64], games: u64, secs: u64) {
    for _ in 0..secs * 2 {
        let done = ids.iter().all(|&id| app.bots.status.get(id).is_some_and(|s| s.games >= games));
        if done {
            break;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    for &id in ids {
        let s = app.bots.status.get(id).unwrap_or_default();
        let log: Vec<String> = s.log.iter().map(|(_, l)| l.clone()).collect();
        assert!(s.games >= games, "bot {id}: {} games, state `{}`; log: {log:?}", s.games, s.state);
        assert_eq!(s.errors, 0, "bot {id}: {}; log: {log:?}", s.last_error);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_server_bots_play_each_other() {
    let app = app().await;
    let names = bots::create(&app, 2, "easy", "casual", (0, 0), (0, 1)).await.unwrap();
    assert_eq!(names, ["Bot_Easy_1", "Bot_Easy_2"]);
    bots::sync(&app).await.unwrap();
    let ids: Vec<i64> = bots::all(&app).await.unwrap().iter().map(|b| b.id).collect();
    wait_games(&app, &ids, 1, 240).await;
    let s = app.bots.status.get(ids[0]).unwrap();
    assert!(s.decisions > 5, "it thought: {} decisions", s.decisions);
    // stopped: no longer running
    for id in &ids {
        sea_orm::ActiveModelTrait::update(
            classichs_server::entity::bot::ActiveModel { id: sea_orm::Unchanged(*id), enabled: sea_orm::Set(false), ..Default::default() },
            &app.db,
        )
        .await
        .unwrap();
    }
    bots::sync(&app).await.unwrap();
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(ids.iter().all(|&id| !app.bots.is_running(id)), "stopped bots do not run");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_bot_over_the_network_plays_a_server_bot() {
    let app = app().await;
    // the server's bot (the in-process adapter)
    bots::create(&app, 1, "medium", "casual", (0, 0), (0, 1)).await.unwrap();
    bots::sync(&app).await.unwrap();
    let local = bots::all(&app).await.unwrap()[0].id;
    // a listening server for the network bot
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    // the same bot code with the WebSocket adapter and a password, not managed by the server
    let hash = auth::hash_password("netbotpassword");
    let acc = db::create_account(&app.db, "NetBot", &hash, "user").await.unwrap().unwrap();
    let cfg = BotConfig {
        id: 999,
        account: acc,
        name: "NetBot".into(),
        level: "easy".into(),
        modes: "casual".into(),
        enabled: true,
        from_min: 0,
        to_min: 0,
        pause_min: 0,
        pause_max: 1,
    };
    let url = format!("ws://{addr}/");
    let connect: ConnectFn = Arc::new(move || {
        let url = url.clone();
        Box::pin(async move { Transport::net(&url).await })
    });
    let load: LoadFn = Arc::new(move || {
        let c = cfg.clone();
        Box::pin(async move { Some(c) })
    });
    let ctx = Ctx { id: 999, name: "NetBot".into(), status: app.bots.status.clone(), think: Arc::new(tokio::sync::Semaphore::new(1)), app: None };
    tokio::spawn(runtime::run(ctx, connect, Auth::Password("NetBot".into(), "netbotpassword".into()), load));
    wait_games(&app, &[local, 999], 1, 240).await;
}

async fn call(app: &axum::Router, req: Request<Body>) -> (StatusCode, Value) {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let cookies: Vec<String> = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).collect();
    let body = axum::body::to_bytes(res.into_body(), 4 << 20).await.unwrap();
    let mut v: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
    if let Some(c) = cookies.iter().find(|c| c.starts_with("chs_admin=")) {
        v["cookie"] = json!(c.split(';').next().unwrap());
    }
    (status, v)
}

fn req(method: &str, uri: &str, cookie: &str, csrf: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, "http://admin.test")
        .header(header::COOKIE, cookie)
        .header("x-csrf-token", csrf)
        .header(header::CONTENT_TYPE, "application/json")
        .body(if method == "GET" { Body::empty() } else { Body::from(body.to_string()) })
        .unwrap()
}

#[tokio::test]
async fn the_admin_adds_changes_stops_and_deletes_bots() {
    let state = app().await;
    db::make_superuser(&state.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    let (_, login) = call(&app, req("POST", "/admin/api/login", "", "", json!({"user": "root", "password": "rootpassword"}))).await;
    let (cookie, csrf) = (login["cookie"].as_str().unwrap().to_string(), login["csrf"].as_str().unwrap().to_string());
    let r = |m: &str, u: &str, b: Value| req(m, u, &cookie, &csrf, b);
    let (st, v) = call(&app, r("POST", "/admin/api/bots", json!({"count": 2, "level": "hard", "modes": "arena", "from": 480, "to": 1380, "pause_min": 5, "pause_max": 15}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert_eq!(v["names"], json!(["Bot_Hard_1", "Bot_Hard_2"]));
    let (st, v) = call(&app, r("POST", "/admin/api/bots", json!({"count": 1, "level": "genius"}))).await;
    assert_eq!((st, v["error"].as_str()), (StatusCode::BAD_REQUEST, Some("The level is easy, medium or hard")));
    let (_, list) = call(&app, r("GET", "/admin/api/bots", json!(null))).await;
    assert_eq!(list["summary"]["total"], 2);
    let b = &list["bots"][0];
    assert_eq!((b["level"].as_str(), b["modes"].as_str(), b["from"].as_i64(), b["enabled"].as_bool()), (Some("hard"), Some("arena"), Some(480), Some(true)));
    let id = b["id"].as_i64().unwrap();
    let (st, v) = call(&app, r("POST", &format!("/admin/api/bots/{id}/update"), json!({"level": "easy", "modes": "ladder", "from": 0, "to": 0}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    let (_, one) = call(&app, r("GET", &format!("/admin/api/bots/{id}"), json!(null))).await;
    assert_eq!((one["level"].as_str(), one["modes"].as_str(), one["pause_max"].as_i64()), (Some("easy"), Some("ladder"), Some(15)), "{one}");
    let (st, _) = call(&app, r("POST", "/admin/api/bots/all/stop", json!(null))).await;
    assert_eq!(st, StatusCode::OK);
    let (_, list) = call(&app, r("GET", "/admin/api/bots", json!(null))).await;
    assert_eq!(list["summary"]["enabled"], 0);
    let (st, _) = call(&app, r("POST", &format!("/admin/api/bots/{id}/delete"), json!(null))).await;
    assert_eq!(st, StatusCode::OK);
    let (_, list) = call(&app, r("GET", "/admin/api/bots", json!(null))).await;
    assert_eq!(list["summary"]["total"], 1);
    assert!(db::id_by_name(&state.db, "Bot_Hard_1").await.unwrap().is_some(), "the account stays");
}
