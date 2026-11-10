//! admin_extra.rs: the server's version, the database and pack store sizes, a pack file by
//! hash and the replay player's files (the admin guard, their MIME types and CSP).

mod common;

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, router, App, AppRef, Timers};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::path::PathBuf;
use tower::ServiceExt;

struct Res {
    status: StatusCode,
    headers: axum::http::HeaderMap,
    body: Vec<u8>,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }
    fn header(&self, h: header::HeaderName) -> String {
        self.headers.get(h).map(|v| v.to_str().unwrap().to_string()).unwrap_or_default()
    }
}

async fn call(app: &axum::Router, req: Request<Body>) -> Res {
    let res = app.clone().oneshot(req).await.unwrap();
    let (status, headers) = (res.status(), res.headers().clone());
    let body = axum::body::to_bytes(res.into_body(), 64 << 20).await.unwrap().to_vec();
    Res { status, headers, body }
}

fn get(uri: &str, cookie: &str) -> Request<Body> {
    Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, cookie).body(Body::empty()).unwrap()
}

fn tmp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("chs-extra-{name}-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// A server on a database file (its size is measured) and a pack store dir; root logged in.
async fn setup(dir: &std::path::Path) -> (AppRef, axum::Router, String) {
    let store = Storage::dir(&dir.join("store")).unwrap();
    let state = App::new(db::open(dir.join("t.db").to_str().unwrap()).await.unwrap(), false, Some(Timers::default()), store);
    db::make_superuser(&state.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    let login = Request::post("/admin/api/login")
        .header(header::HOST, "admin.test")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(json!({"user": "root", "password": "rootpassword"}).to_string()))
        .unwrap();
    let r = call(&app, login).await;
    assert_eq!(r.status, StatusCode::OK);
    let c = r.header(header::SET_COOKIE);
    (state, app, c.split(';').next().unwrap().to_string())
}

#[tokio::test]
async fn version_and_storage_sizes() {
    let dir = tmp("sizes");
    let (state, app, cookie) = setup(&dir).await;
    let me = call(&app, get("/admin/api/me", &cookie)).await.json();
    let godot = std::fs::read_to_string("../project.godot").unwrap();
    let want = godot.lines().find_map(|l| l.strip_prefix("config/version=\"")?.strip_suffix('"')).unwrap();
    assert_eq!(me["version"], want, "the release version (project.godot)");
    assert_eq!(classichs_server::VERSION, want);

    state.store.put_bytes(&"a".repeat(64), vec![7; 1000]).await.unwrap();
    state.store.put_bytes(&"b".repeat(64), vec![7; 234]).await.unwrap();
    let r = call(&app, get("/admin/api/storage", &cookie)).await;
    assert_eq!(r.status, StatusCode::OK);
    let s = r.json();
    let file = std::fs::metadata(dir.join("t.db")).unwrap().len();
    let wal = std::fs::metadata(dir.join("t.db-wal")).map_or(0, |m| m.len());
    assert!(s["db"]["path"].as_str().unwrap().ends_with("t.db"), "{s}");
    assert_eq!(s["db"]["file"], file);
    assert!(wal > 0, "WAL mode: the writes are in the -wal file");
    assert_eq!(s["db"]["wal"], wal);
    assert_eq!(s["db"]["total"], file + wal);
    assert_eq!((s["packs"]["bytes"].as_u64(), s["packs"]["files"].as_u64()), (Some(1234), Some(2)));
    assert!(s["packs"]["what"].as_str().unwrap().starts_with("dir "));
    assert_eq!(call(&app, get("/admin/api/storage", "")).await.status, StatusCode::UNAUTHORIZED);
    std::fs::remove_dir_all(&dir).unwrap();
}

#[tokio::test]
async fn pack_file_by_content_or_rules_hash() {
    let dir = tmp("pack");
    let (state, app, cookie) = setup(&dir).await;
    let bytes = common::pack_bytes("org.test.extra", "1.0.0", &[], &[]);
    let f = dir.join("p.cardpack");
    std::fs::write(&f, &bytes).unwrap();
    let p = classichs_server::packs::add(&state, &f, bytes.len() as u64, Some(1)).await.unwrap();
    for h in [&p.content_hash, &p.rules_hash] {
        let r = call(&app, get(&format!("/admin/api/pack_files/{h}"), &cookie)).await;
        assert_eq!(r.status, StatusCode::OK, "by {h}");
        assert_eq!(r.body, bytes);
        assert_eq!(r.header(header::CONTENT_TYPE), "application/zip");
        assert_eq!(call(&app, get(&format!("/admin/api/pack_files/{h}"), "")).await.status, StatusCode::UNAUTHORIZED, "admins only");
    }
    assert_eq!(call(&app, get(&format!("/admin/api/pack_files/{}", "0".repeat(64)), &cookie)).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&app, get("/admin/api/pack_files/..%2Fx", &cookie)).await.status, StatusCode::NOT_FOUND);
    std::fs::remove_dir_all(&dir).unwrap();
}

#[tokio::test]
async fn replay_player_files_guard_and_headers() {
    let dir = tmp("viewer");
    let (_state, app, cookie) = setup(&dir).await;
    let www = dir.join("www");
    std::fs::create_dir_all(&www).unwrap();
    let inline = "const GODOT_CONFIG = {};";
    std::fs::write(www.join("index.html"), format!("<html><script src=\"index.js\"></script><script>{inline}</script></html>")).unwrap();
    std::fs::write(www.join("index.wasm"), b"\0asm\x01\0\0\0").unwrap();
    std::fs::write(www.join("index.js"), b"var x;").unwrap();
    std::fs::write(dir.join("secret.txt"), b"no").unwrap();
    classichs_server::admin_extra::set_replay_dir(www.clone());

    let r = call(&app, get("/admin/replay/index.html?game=g1", "")).await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED, "behind the admin guard");
    let r = call(&app, get("/admin/replay/index.html?game=g1", &cookie)).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.header(header::CONTENT_TYPE), "text/html; charset=utf-8");
    let csp = r.header(header::CONTENT_SECURITY_POLICY);
    use base64::Engine;
    use sha2::Digest;
    let hash = base64::engine::general_purpose::STANDARD.encode(sha2::Sha256::digest(inline.as_bytes()));
    for want in ["script-src 'self' 'wasm-unsafe-eval'", &format!("'sha256-{hash}'"), "worker-src 'self' blob:", "frame-ancestors 'self'", "connect-src 'self'"] {
        assert!(csp.contains(want), "{want} in {csp}");
    }
    assert!(!csp.contains("'unsafe-eval'"), "no plain eval: {csp}");
    assert_eq!(r.header(header::X_FRAME_OPTIONS), "SAMEORIGIN", "the panel frames it");
    assert_eq!(r.header(header::X_CONTENT_TYPE_OPTIONS), "nosniff");
    let r = call(&app, get("/admin/replay/index.wasm", &cookie)).await;
    assert_eq!((r.status, r.header(header::CONTENT_TYPE)), (StatusCode::OK, "application/wasm".into()));
    assert_eq!(r.body, b"\0asm\x01\0\0\0");
    let etag = r.header(header::ETAG);
    let again = Request::get("/admin/replay/index.wasm").header(header::COOKIE, &cookie).header(header::IF_NONE_MATCH, &etag).body(Body::empty()).unwrap();
    assert_eq!(call(&app, again).await.status, StatusCode::NOT_MODIFIED, "unchanged: from the cache");
    assert_eq!(call(&app, get("/admin/replay/index.js", &cookie)).await.header(header::CONTENT_TYPE), "text/javascript; charset=utf-8");
    for bad in ["/admin/replay/../secret.txt", "/admin/replay/..%2Fsecret.txt", "/admin/replay/.hidden", "/admin/replay/nope.js"] {
        assert_eq!(call(&app, get(bad, &cookie)).await.status, StatusCode::NOT_FOUND, "{bad}");
    }
    // the panel itself keeps its strict CSP, and may frame only its own pages
    let r = call(&app, get("/admin", "")).await;
    let csp = r.header(header::CONTENT_SECURITY_POLICY);
    assert!(csp.contains("default-src 'none'") && csp.contains("frame-src 'self'") && csp.contains("frame-ancestors 'none'") && !csp.contains("wasm"), "{csp}");
    assert_eq!(r.header(header::X_FRAME_OPTIONS), "DENY");
    std::fs::remove_dir_all(&dir).unwrap();
}
