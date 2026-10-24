//! The admin panel's API: login, Origin and CSRF checks, the session cookie, accounts,
//! actions, the event log, the dashboard, the static files and their CSP.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::entity::account;
use classichs_server::storage::Storage;
use classichs_server::{auth, db, router, App, AppRef, Timers};
use sea_orm::EntityTrait;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::time::Duration;
use tower::ServiceExt;

struct Res {
    status: StatusCode,
    cookies: Vec<String>,
    headers: axum::http::HeaderMap,
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
    let headers = res.headers().clone();
    let cookies = headers.get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).collect();
    let body = axum::body::to_bytes(res.into_body(), 4 << 20).await.unwrap();
    Res { status, cookies, headers, body: String::from_utf8_lossy(&body).into_owned() }
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

async fn setup() -> (AppRef, axum::Router, i64) {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let state = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
    let hash = auth::hash_password("rootpassword");
    db::make_superuser(&state.db, "root", &hash).await.unwrap();
    let victim = db::create_account(&state.db, "victim", &hash, "user").await.unwrap().unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    (state, app, victim)
}

/// Logs in as root: (cookie header, CSRF token).
async fn log_in(app: &axum::Router) -> (String, String) {
    let r = call(app, post("/admin/api/login", "", None, json!({"user": "root", "password": "rootpassword"}))).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let c = r.cookies.iter().find(|c| c.starts_with("chs_admin=")).unwrap();
    assert!(c.contains("HttpOnly") && c.contains("SameSite=Strict") && c.contains("Path=/admin") && c.contains("Max-Age=2592000"));
    assert!(!c.contains("Secure"));
    let token = c["chs_admin=".len()..].split(';').next().unwrap();
    (format!("chs_admin={token}"), r.json()["csrf"].as_str().unwrap().to_string())
}

/// Waits for the event writer.
async fn events(app: &axum::Router, cookie: &str, query: &str, want: usize) -> Value {
    for _ in 0..50 {
        let r = call(app, get(&format!("/admin/api/events?{query}"), cookie)).await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.body);
        let v = r.json();
        if v["list"].as_array().unwrap().len() >= want {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("fewer than {want} events for {query}");
}

#[tokio::test]
async fn login_origin_csrf_and_session() {
    let (state, app, victim) = setup().await;

    // Not logged in.
    assert_eq!(call(&app, get("/admin/api/me", "")).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(call(&app, get("/admin/api/accounts", "chs_admin=nonsense")).await.status, StatusCode::UNAUTHORIZED);

    // Login: JSON only, same Origin only, a wrong password sets no cookie.
    let form = Request::post("/admin/api/login")
        .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from("user=root&password=rootpassword"))
        .unwrap();
    assert_eq!(call(&app, form).await.status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let mut cross = post("/admin/api/login", "", None, json!({"user": "root", "password": "rootpassword"}));
    cross.headers_mut().insert(header::ORIGIN, "https://evil.example".parse().unwrap());
    assert_eq!(call(&app, cross).await.status, StatusCode::FORBIDDEN);
    let r = call(&app, post("/admin/api/login", "", None, json!({"user": "root", "password": "wrongpass"}))).await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    assert!(r.cookies.is_empty());
    let r = call(&app, post("/admin/api/login", "", None, json!({"user": "victim", "password": "rootpassword"}))).await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED, "players are not admins");

    let (session, csrf) = log_in(&app).await;
    let me = call(&app, get("/admin/api/me", &session)).await.json();
    assert_eq!((me["user"].as_str(), me["role"].as_str(), me["csrf"].as_str()), (Some("root"), Some("super"), Some(csrf.as_str())));

    // State changes need the CSRF header and the same Origin.
    let uri = format!("/admin/api/accounts/{victim}/suspend");
    assert_eq!(call(&app, post(&uri, &session, None, json!({}))).await.status, StatusCode::FORBIDDEN);
    assert_eq!(call(&app, post(&uri, &session, Some("wrong"), json!({}))).await.status, StatusCode::FORBIDDEN);
    let mut cross = post(&uri, &session, Some(&csrf), json!({}));
    cross.headers_mut().insert(header::ORIGIN, "https://evil.example".parse().unwrap());
    assert_eq!(call(&app, cross).await.status, StatusCode::FORBIDDEN);
    let suspended = || async { account::Entity::find_by_id(victim).one(&state.db).await.unwrap().unwrap().suspended };
    assert!(!suspended().await);
    let r = call(&app, post(&uri, &session, Some(&csrf), json!({}))).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert!(suspended().await);

    // The superuser is changed from the command line only.
    let r = call(&app, post("/admin/api/accounts/1/suspend", &session, Some(&csrf), json!({}))).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);

    // A sliding session: an old one is renewed (a new cookie), a fresh one is not.
    assert!(call(&app, get("/admin/api/me", &session)).await.cookies.is_empty());
    use sea_orm::{ColumnTrait, QueryFilter};
    classichs_server::entity::session::Entity::update_many()
        .col_expr(classichs_server::entity::session::Column::Expires, (classichs_server::ranked::now() + 86400).into())
        .filter(classichs_server::entity::session::Column::Kind.eq("admin"))
        .exec(&state.db)
        .await
        .unwrap();
    let r = call(&app, get("/admin/api/me", &session)).await;
    assert!(r.cookies.iter().any(|c| c.starts_with(&format!("{session};")) && c.contains("Max-Age=2592000")), "{:?}", r.cookies);

    // Log out: the session is gone.
    assert_eq!(call(&app, post("/admin/api/logout", &session, Some(&csrf), json!({}))).await.status, StatusCode::OK);
    assert_eq!(call(&app, get("/admin/api/me", &session)).await.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn accounts_actions_and_event_log() {
    let (_state, app, victim) = setup().await;
    let (session, csrf) = log_in(&app).await;

    // Create, then search and filter.
    let r = call(&app, post("/admin/api/accounts", &session, Some(&csrf), json!({"user": "helper", "password": "password123", "role": "admin"}))).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let helper = r.json()["id"].as_i64().unwrap();
    let r = call(&app, post("/admin/api/accounts", &session, Some(&csrf), json!({"user": "helper", "password": "password123"}))).await;
    assert_eq!(r.status, StatusCode::CONFLICT);
    let list = call(&app, get("/admin/api/accounts?q=VIC", &session)).await.json();
    assert_eq!(list["total"], 1);
    assert_eq!(list["list"][0]["user"], "victim");
    assert_eq!(list["list"][0]["status"], "offline");
    let admins = call(&app, get("/admin/api/accounts?role=admin", &session)).await.json();
    assert_eq!(admins["list"][0]["id"], helper);
    let sorted = call(&app, get("/admin/api/accounts?sort=user&dir=asc", &session)).await.json();
    let names: Vec<&str> = sorted["list"].as_array().unwrap().iter().map(|a| a["user"].as_str().unwrap()).collect();
    assert_eq!(names, ["helper", "root", "victim"]);

    // The account page.
    let page = call(&app, get(&format!("/admin/api/accounts/{victim}"), &session)).await.json();
    assert_eq!(page["account"]["user"], "victim");
    assert_eq!(page["may_manage"], true);
    assert_eq!(call(&app, get("/admin/api/accounts/999", &session)).await.status, StatusCode::NOT_FOUND);

    // Password reset, a delete needs the name typed.
    let uri = |a: &str| format!("/admin/api/accounts/{victim}/{a}");
    assert_eq!(call(&app, post(&uri("password"), &session, Some(&csrf), json!({"password": "short"}))).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(call(&app, post(&uri("password"), &session, Some(&csrf), json!({"password": "newpassword1"}))).await.status, StatusCode::OK);
    assert_eq!(call(&app, post(&uri("delete"), &session, Some(&csrf), json!({"confirm": "nope"}))).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(call(&app, post(&uri("delete"), &session, Some(&csrf), json!({"confirm": "victim"}))).await.status, StatusCode::OK);
    assert_eq!(call(&app, get(&format!("/admin/api/accounts/{victim}"), &session)).await.status, StatusCode::NOT_FOUND);

    // Everything is in the event log: filter by kind, by user, by text.
    let admin = events(&app, &session, "kind=admin", 3).await;
    let texts: Vec<&str> = admin["list"].as_array().unwrap().iter().map(|e| e["text"].as_str().unwrap()).collect();
    assert_eq!(texts[0], "root deleted the account victim", "newest first: {texts:?}");
    assert!(texts.contains(&"root reset the password of victim"));
    assert_eq!(admin["list"][0]["user"], "root");
    assert_eq!(admin["list"][0]["other"], "victim");
    let logins = events(&app, &session, "kind=admin_login&user=ROOT", 1).await;
    assert_eq!(logins["total"], 1);
    let found = events(&app, &session, "q=password%20of", 1).await;
    assert_eq!(found["total"], 1);
    let asc = events(&app, &session, "dir=asc&size=1", 1).await;
    assert_eq!(asc["list"][0]["kind"], "admin_login");
    assert_eq!(asc["total"], 4);

    // The dashboard counts today's events.
    let d = call(&app, get("/admin/api/dashboard", &session)).await.json();
    assert_eq!(d["totals"]["accounts"], 2);
    assert_eq!(d["today"]["admin"], 3);
    assert_eq!(d["chart"]["series"]["login"].as_array().unwrap().len(), 24);
    assert!(d["live"]["online"].is_array());
}

#[tokio::test]
async fn static_files_and_csp() {
    let (_state, app, _) = setup().await;
    let r = call(&app, get("/admin", "")).await;
    assert_eq!(r.status, StatusCode::OK);
    let csp = r.headers[header::CONTENT_SECURITY_POLICY].to_str().unwrap();
    assert!(csp.contains("default-src 'none'") && csp.contains("script-src 'self' 'sha256-") && csp.contains("frame-ancestors 'none'"), "{csp}");
    assert!(r.body.contains("importmap"));
    assert!(r.body.contains(r#"<link rel="icon" type="image/svg+xml" href="/admin/static/favicon.svg">"#));
    let r = call(&app, get("/admin/static/favicon.svg", "")).await;
    assert_eq!((r.status, r.headers[header::CONTENT_TYPE].to_str().unwrap()), (StatusCode::OK, "image/svg+xml"));
    assert!(r.body.starts_with("<svg"));
    let r = call(&app, get("/admin/static/app.js", "")).await;
    assert_eq!(r.headers[header::CONTENT_TYPE], "text/javascript; charset=utf-8");
    assert_eq!(r.headers[header::X_CONTENT_TYPE_OPTIONS], "nosniff");
    let r = call(&app, get("/admin/static/vendor/preact.module.js", "")).await;
    assert_eq!(r.status, StatusCode::OK);
    assert!(r.body.len() > 1000);
    assert_eq!(call(&app, get("/admin/static/../Cargo.toml", "")).await.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn live_feed_over_websocket() {
    use tokio_tungstenite::tungstenite::client::IntoClientRequest;
    let (state, app, _) = setup().await;
    let (session, csrf) = log_in(&app).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(state.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    let req = |origin: &str, cookie: &str| {
        let mut r = format!("ws://{addr}/admin/ws").into_client_request().unwrap();
        r.headers_mut().insert("origin", origin.parse().unwrap());
        r.headers_mut().insert("cookie", cookie.parse().unwrap());
        r
    };
    // Another site's page cannot open it, nor can a stranger.
    assert!(tokio_tungstenite::connect_async(req("https://evil.example", &session)).await.is_err());
    assert!(tokio_tungstenite::connect_async(req(&format!("http://{addr}"), "chs_admin=x")).await.is_err());
    let (mut ws, _) = tokio_tungstenite::connect_async(req(&format!("http://{addr}"), &session)).await.unwrap();
    let hello = next(&mut ws).await;
    assert_eq!(hello["t"], "hello");
    assert!(hello["live"]["games"].is_array());
    // An admin action shows up live.
    let r = call(&app, post("/admin/api/accounts", &session, Some(&csrf), json!({"user": "newbie", "password": "password123"}))).await;
    assert_eq!(r.status, StatusCode::OK);
    loop {
        let m = next(&mut ws).await;
        if m["t"] == "event" {
            assert_eq!(m["e"]["kind"], "admin");
            assert_eq!(m["e"]["other"], "newbie");
            break;
        }
    }
}

async fn next<S: futures_util::Stream<Item = Result<tokio_tungstenite::tungstenite::Message, tokio_tungstenite::tungstenite::Error>> + Unpin>(ws: &mut S) -> Value {
    use futures_util::StreamExt;
    match tokio::time::timeout(Duration::from_secs(5), ws.next()).await.unwrap().unwrap().unwrap() {
        tokio_tungstenite::tungstenite::Message::Text(t) => serde_json::from_str(t.as_str()).unwrap(),
        m => panic!("{m:?}"),
    }
}
