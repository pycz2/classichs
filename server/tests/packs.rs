//! Game packs: players' uploads, downloads and deletes (local-directory storage), the
//! `packs` message, the limits, the admin API and the bundled packs.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, HeaderMap, Request, StatusCode};
use classichs_server::entity::{event, friend, pack};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, packs, router, spawn_background, App, AppRef, Timers};
use futures_util::{SinkExt, StreamExt};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, Set};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::{Cursor, Write};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;
use tower::ServiceExt;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

fn temp_dir() -> PathBuf {
    std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))
}

/// A running server (for WebSockets) and its router (for HTTP calls in-process).
async fn server() -> (SocketAddr, AppRef, axum::Router) {
    let app = App::new(db::open(":memory:").await.unwrap(), false, Timers::default(), Storage::dir(&temp_dir()).unwrap());
    spawn_background(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    let http = router(app.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    (addr, app, http)
}

struct C {
    ws: Ws,
    token: String,
}

impl C {
    async fn register(addr: SocketAddr, name: &str) -> C {
        let (ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
        let mut c = C { ws, token: String::new() };
        c.send(json!({"t": "register", "user": name, "password": "password123"})).await;
        c.token = c.want("auth").await["token"].as_str().unwrap().to_string();
        c
    }

    async fn send(&mut self, v: Value) {
        self.ws.send(Message::text(v.to_string())).await.unwrap();
    }

    async fn want(&mut self, t: &str) -> Value {
        loop {
            let m = tokio::time::timeout(Duration::from_secs(10), self.ws.next()).await.expect(t).unwrap().unwrap();
            if let Message::Text(s) = m {
                let v: Value = serde_json::from_str(s.as_str()).unwrap();
                if v["t"] == t {
                    return v;
                }
                assert!(v["t"] != "error" || t == "error", "unexpected error while waiting for {t}: {v}");
            }
        }
    }
}

struct Res {
    status: StatusCode,
    headers: HeaderMap,
    body: Vec<u8>,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }
}

async fn call(app: &axum::Router, req: Request<Body>) -> Res {
    let res = app.clone().oneshot(req).await.unwrap();
    let (status, headers) = (res.status(), res.headers().clone());
    let body = axum::body::to_bytes(res.into_body(), 1 << 30).await.unwrap().to_vec();
    Res { status, headers, body }
}

fn upload(token: Option<&str>, zip: &[u8]) -> Request<Body> {
    let mut r = Request::post("/packs").header(header::CONTENT_TYPE, "application/zip");
    if let Some(t) = token {
        r = r.header(header::AUTHORIZATION, format!("Bearer {t}"));
    }
    r.body(Body::from(zip.to_vec())).unwrap()
}

fn download(hash: &str, token: Option<&str>) -> axum::http::request::Builder {
    let r = Request::get(format!("/packs/{hash}.cardpack"));
    match token {
        Some(t) => r.header(header::AUTHORIZATION, format!("Bearer {t}")),
        None => r,
    }
}

fn zip_of(files: &[(&str, &str)]) -> Vec<u8> {
    let mut w = zip::ZipWriter::new(Cursor::new(vec![]));
    for (name, body) in files {
        w.start_file(*name, zip::write::SimpleFileOptions::default()).unwrap();
        w.write_all(body.as_bytes()).unwrap();
    }
    w.finish().unwrap().into_inner()
}

/// A valid pack: id, version, and some content.
fn pack_zip(id: &str, version: &str, cards: &str) -> Vec<u8> {
    let manifest = json!({"format": 1, "id": id, "version": version, "name": {"en": "Test pack", "ru": "Тестовый"}});
    zip_of(&[("manifest.json", &manifest.to_string()), ("rules.json", "{}"), ("cards.json", cards), ("art/a.webp", "art")])
}

fn sha(b: &[u8]) -> String {
    Sha256::digest(b).iter().map(|x| format!("{x:02x}")).collect()
}

async fn kinds(app: &AppRef, kind: &str, want: usize) -> Vec<event::Model> {
    for _ in 0..100 {
        let v = event::Entity::find().filter(event::Column::Kind.eq(kind)).all(&app.db).await.unwrap();
        if v.len() >= want {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("fewer than {want} {kind} events");
}

#[tokio::test]
async fn players_upload_list_download_and_delete() {
    let (addr, app, http) = server().await;
    let mut pia = C::register(addr, "pia").await;
    let mut bob = C::register(addr, "bob").await;
    let zip = pack_zip("org.test.mine", "1.0.0", "[]");
    let hash = sha(&zip);

    // Upload: the session token is needed, the file must be a pack.
    assert_eq!(call(&http, upload(None, &zip)).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(call(&http, upload(Some("nonsense"), &zip)).await.status, StatusCode::UNAUTHORIZED);
    let r = call(&http, upload(Some(&pia.token), b"not a zip")).await;
    assert_eq!((r.status, r.json()["code"].as_str()), (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid")));
    assert!(r.json()["error"].as_str().unwrap().contains("not a zip"));
    kinds(&app, "pack_rejected", 1).await;
    let r = call(&http, upload(Some(&pia.token), &zip)).await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&r.body));
    let p = &r.json()["pack"];
    assert_eq!((p["id"].as_str(), p["version"].as_str(), p["name"]["ru"].as_str()), (Some("org.test.mine"), Some("1.0.0"), Some("Тестовый")));
    assert_eq!((p["content_hash"].as_str(), p["size"].as_u64()), (Some(hash.as_str()), Some(zip.len() as u64)));
    assert_eq!(p["url"], format!("/packs/{hash}.cardpack"));
    assert_eq!(p["rules_hash"].as_str().unwrap().len(), 64);
    assert_eq!(r.headers[header::ACCESS_CONTROL_ALLOW_ORIGIN], "*");
    // The uploader's game gets the new list at once; the same file again is refused.
    let m = pia.want("packs").await;
    assert_eq!((m["server"].as_array().unwrap().len(), m["mine"][0]["content_hash"].as_str()), (0, Some(hash.as_str())));
    assert_eq!(call(&http, upload(Some(&pia.token), &zip)).await.json()["code"], "exists");
    assert!(app.store.exists(&hash).await.unwrap());
    kinds(&app, "pack_upload", 1).await;

    // packs {}: server packs (none yet) and mine.
    pia.send(json!({"t": "packs"})).await;
    let m = pia.want("packs").await;
    assert_eq!(m["server"], json!([]));
    assert_eq!(m["mine"].as_array().unwrap().len(), 1);
    assert_eq!(m["mine"][0]["enabled"], true);
    bob.send(json!({"t": "packs"})).await;
    assert_eq!(bob.want("packs").await["mine"], json!([]));

    // Download: by header or ?token=, with an ETag; a 304 for the cached copy.
    let r = call(&http, download(&hash, Some(&pia.token)).body(Body::empty()).unwrap()).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.body, zip);
    let etag = format!("\"{hash}\"");
    assert_eq!(r.headers[header::ETAG], etag.as_str());
    assert_eq!(r.headers[header::CONTENT_TYPE], "application/zip");
    assert_eq!(r.headers[header::CONTENT_LENGTH], zip.len().to_string().as_str());
    assert!(r.headers[header::CACHE_CONTROL].to_str().unwrap().contains("immutable"));
    let r = call(&http, Request::get(format!("/packs/{hash}.cardpack?token={}", pia.token)).body(Body::empty()).unwrap()).await;
    assert_eq!((r.status, r.body == zip), (StatusCode::OK, true));
    let r = call(&http, download(&hash, Some(&pia.token)).header(header::IF_NONE_MATCH, &etag).body(Body::empty()).unwrap()).await;
    assert_eq!((r.status, r.body.len()), (StatusCode::NOT_MODIFIED, 0));
    assert_eq!(call(&http, download(&hash, None).body(Body::empty()).unwrap()).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(call(&http, download("nothex", Some(&pia.token)).body(Body::empty()).unwrap()).await.status, StatusCode::NOT_FOUND);
    // Another player's pack: only for the owner's friends.
    assert_eq!(call(&http, download(&hash, Some(&bob.token)).body(Body::empty()).unwrap()).await.status, StatusCode::NOT_FOUND);
    let (a, b) = (db::id_by_name(&app.db, "pia").await.unwrap().unwrap(), db::id_by_name(&app.db, "bob").await.unwrap().unwrap());
    friend::Entity::insert_many([friend::ActiveModel { a: Set(a), b: Set(b) }, friend::ActiveModel { a: Set(b), b: Set(a) }])
        .exec(&app.db)
        .await
        .unwrap();
    assert_eq!(call(&http, download(&hash, Some(&bob.token)).body(Body::empty()).unwrap()).await.status, StatusCode::OK);
    let row = pack::Entity::find().filter(pack::Column::ContentHash.eq(&hash)).one(&app.db).await.unwrap().unwrap();
    assert_eq!(row.downloads, 3);
    kinds(&app, "pack_download", 3).await;
    // CORS preflight for the web build.
    let r = call(&http, Request::options("/packs").body(Body::empty()).unwrap()).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);
    assert!(r.headers[header::ACCESS_CONTROL_ALLOW_HEADERS].to_str().unwrap().contains("authorization"));

    // The same file uploaded by two players is stored once; it goes when the last row goes.
    assert_eq!(call(&http, upload(Some(&bob.token), &zip)).await.status, StatusCode::CREATED);
    assert_eq!(bob.want("packs").await["mine"].as_array().unwrap().len(), 1);
    bob.send(json!({"t": "pack_delete", "content_hash": hash})).await;
    assert_eq!(bob.want("packs").await["mine"], json!([]));
    assert!(app.store.exists(&hash).await.unwrap());
    bob.send(json!({"t": "pack_delete", "content_hash": hash})).await;
    assert_eq!(bob.want("error").await["code"], "not_found");
    pia.send(json!({"t": "pack_delete", "content_hash": hash})).await;
    assert_eq!(pia.want("packs").await["mine"], json!([]));
    assert!(!app.store.exists(&hash).await.unwrap());
    kinds(&app, "pack_delete", 2).await;
    assert_eq!(call(&http, download(&hash, Some(&pia.token)).body(Body::empty()).unwrap()).await.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn limits() {
    let (addr, _app, http) = server().await;
    let c = C::register(addr, "lim").await;
    // Ten packs a player.
    for i in 0..10 {
        let r = call(&http, upload(Some(&c.token), &pack_zip("org.test.many", &format!("1.0.{i}"), "[]"))).await;
        assert_eq!(r.status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&r.body));
    }
    let r = call(&http, upload(Some(&c.token), &pack_zip("org.test.many", "2.0.0", "[]"))).await;
    assert_eq!((r.status, r.json()["code"].as_str()), (StatusCode::CONFLICT, Some("too_many")));
    // 100 MB: refused by the declared length, and while streaming.
    let mut big = upload(Some(&c.token), b"x");
    big.headers_mut().insert(header::CONTENT_LENGTH, (packs::MAX_PLAYER_PACK + 1).to_string().parse().unwrap());
    let r = call(&http, big).await;
    assert_eq!((r.status, r.json()["code"].as_str()), (StatusCode::CONFLICT, Some("too_many")), "the count is checked first");
    let err = packs::receive(&HeaderMap::new(), Body::from(vec![0u8; 3000]), 2048).await.err().unwrap();
    assert_eq!((err.0, err.1), (StatusCode::PAYLOAD_TOO_LARGE, "too_large"));
    let mut h = HeaderMap::new();
    h.insert(header::CONTENT_LENGTH, "5000".parse().unwrap());
    assert_eq!(packs::receive(&h, Body::from(vec![0u8; 10]), 2048).await.err().unwrap().0, StatusCode::PAYLOAD_TOO_LARGE);
    let ok = packs::receive(&HeaderMap::new(), Body::from(vec![7u8; 2048]), 2048).await.unwrap();
    assert_eq!((ok.size, ok.hash.as_str()), (2048, sha(&[7u8; 2048]).as_str()));
    let tmp = ok.path.clone();
    drop(ok);
    assert!(!tmp.exists(), "the temp file goes with the upload");
    let d = C::register(addr, "lim2").await;
    let mut big = upload(Some(&d.token), b"x");
    big.headers_mut().insert(header::CONTENT_LENGTH, (packs::MAX_PLAYER_PACK + 1).to_string().parse().unwrap());
    let r = call(&http, big).await;
    assert_eq!((r.status, r.json()["code"].as_str()), (StatusCode::PAYLOAD_TOO_LARGE, Some("too_large")));
    let r = call(&http, upload(Some(&d.token), b"")).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
}

// --- the admin API -------------------------------------------------------------------------------

async fn admin_session(app: &AppRef, http: &axum::Router) -> (String, String) {
    db::make_superuser(&app.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
    let r = call(
        http,
        Request::post("/admin/api/login")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({"user": "root", "password": "rootpassword"}).to_string()))
            .unwrap(),
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
    let c = r.headers.get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap()).find(|c| c.starts_with("chs_admin=")).unwrap();
    (c.split(';').next().unwrap().to_string(), r.json()["csrf"].as_str().unwrap().to_string())
}

fn admin_post(uri: &str, cookie: &str, csrf: Option<&str>, origin: &str, ctype: &str, body: Vec<u8>) -> Request<Body> {
    let mut r = Request::post(uri)
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, origin)
        .header(header::COOKIE, cookie)
        .header(header::CONTENT_TYPE, ctype);
    if let Some(t) = csrf {
        r = r.header("x-csrf-token", t);
    }
    r.body(Body::from(body)).unwrap()
}

#[tokio::test]
async fn admin_manages_packs() {
    let (addr, app, http) = server().await;
    let (cookie, csrf) = admin_session(&app, &http).await;
    let ok_origin = "http://admin.test";
    let zip = pack_zip("org.test.server", "1.0.0", "[]");
    let hash = sha(&zip);
    let up = |csrf: Option<&str>, origin: &str, body: &[u8]| admin_post("/admin/api/packs", &cookie, csrf, origin, "application/zip", body.to_vec());

    // Not logged in, no CSRF token, a wrong one, another site: refused.
    let mut anon = up(Some(&csrf), ok_origin, &zip);
    anon.headers_mut().remove(header::COOKIE);
    assert_eq!(call(&http, anon).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(call(&http, up(None, ok_origin, &zip)).await.status, StatusCode::FORBIDDEN);
    assert_eq!(call(&http, up(Some("wrong"), ok_origin, &zip)).await.status, StatusCode::FORBIDDEN);
    assert_eq!(call(&http, up(Some(&csrf), "https://evil.example", &zip)).await.status, StatusCode::FORBIDDEN);
    // A player's token is not an admin session.
    let mut c = C::register(addr, "gus").await;
    let mut as_player = up(None, ok_origin, &zip);
    as_player.headers_mut().remove(header::COOKIE);
    as_player.headers_mut().insert(header::AUTHORIZATION, format!("Bearer {}", c.token).parse().unwrap());
    assert_eq!(call(&http, as_player).await.status, StatusCode::UNAUTHORIZED);

    let r = call(&http, up(Some(&csrf), ok_origin, b"PK broken")).await;
    assert_eq!((r.status, r.json()["code"].as_str()), (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid")));
    let r = call(&http, up(Some(&csrf), ok_origin, &zip)).await;
    assert_eq!(r.status, StatusCode::OK, "{}", String::from_utf8_lossy(&r.body));
    let id = r.json()["pack"]["id"].as_i64().unwrap();
    assert_eq!(r.json()["pack"]["owner"], Value::Null);
    assert_eq!(call(&http, up(Some(&csrf), ok_origin, &zip)).await.json()["code"], "exists");

    // Players see it in `server` and download it.
    c.send(json!({"t": "packs"})).await;
    let m = c.want("packs").await;
    assert_eq!((m["server"][0]["content_hash"].as_str(), m["server"][0]["id"].as_str()), (Some(hash.as_str()), Some("org.test.server")));
    assert_eq!(call(&http, download(&hash, Some(&c.token)).body(Body::empty()).unwrap()).await.status, StatusCode::OK);
    let mine = pack_zip("org.test.gus", "0.1.0", "[1]");
    assert_eq!(call(&http, upload(Some(&c.token), &mine)).await.status, StatusCode::CREATED);
    c.want("packs").await;

    // The list: server packs, players' packs with their owner, the stats.
    let r = call(&http, Request::get("/admin/api/packs").header(header::COOKIE, &cookie).body(Body::empty()).unwrap()).await;
    let v = r.json();
    assert_eq!(v["server"].as_array().unwrap().len(), 1);
    assert_eq!((v["server"][0]["downloads"].as_i64(), v["server"][0]["enabled"].as_bool()), (Some(1), Some(true)));
    assert_eq!((v["players"][0]["owner"]["user"].as_str(), v["players"][0]["pack_id"].as_str()), (Some("gus"), Some("org.test.gus")));
    let s = &v["stats"];
    assert_eq!((s["server"].as_i64(), s["players"].as_i64(), s["uploaders"].as_i64(), s["downloads"].as_i64()), (Some(1), Some(1), Some(1), Some(1)));
    assert_eq!(s["bytes"].as_u64(), Some((zip.len() + mine.len()) as u64));
    assert!(s["storage"].as_str().unwrap().starts_with("dir "));

    // Disable: gone for players (list and download); enable again; delete.
    let act = |a: &str| admin_post(&format!("/admin/api/packs/{id}/{a}"), &cookie, Some(&csrf), ok_origin, "application/json", b"{}".to_vec());
    assert_eq!(call(&http, admin_post(&format!("/admin/api/packs/{id}/disable"), &cookie, None, ok_origin, "application/json", b"{}".to_vec())).await.status, StatusCode::FORBIDDEN);
    assert_eq!(call(&http, act("disable")).await.status, StatusCode::OK);
    c.send(json!({"t": "packs"})).await;
    assert_eq!(c.want("packs").await["server"], json!([]));
    assert_eq!(call(&http, download(&hash, Some(&c.token)).body(Body::empty()).unwrap()).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&http, act("enable")).await.status, StatusCode::OK);
    c.send(json!({"t": "packs"})).await;
    assert_eq!(c.want("packs").await["server"].as_array().unwrap().len(), 1);
    assert_eq!(call(&http, act("explode")).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&http, act("delete")).await.status, StatusCode::OK);
    assert!(!app.store.exists(&hash).await.unwrap());
    assert_eq!(call(&http, act("delete")).await.status, StatusCode::NOT_FOUND);
    // A player's pack, deleted by the admin: the player's game gets the new list.
    let theirs = pack::Entity::find().filter(pack::Column::Owner.is_not_null()).one(&app.db).await.unwrap().unwrap();
    let r = call(&http, admin_post(&format!("/admin/api/packs/{}/delete", theirs.id), &cookie, Some(&csrf), ok_origin, "application/json", b"{}".to_vec())).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(c.want("packs").await["mine"], json!([]));

    // Every action is in the log (by the admin, the player as `other`).
    for k in ["pack_upload", "pack_enable", "pack_disable", "pack_rejected"] {
        kinds(&app, k, 1).await;
    }
    let dels = kinds(&app, "pack_delete", 2).await;
    assert!(dels.iter().any(|e| e.user.as_deref() == Some("root") && e.other.as_deref() == Some("gus")), "{dels:?}");
}

#[tokio::test]
async fn bundled_packs_are_installed_once() {
    let (_addr, app, http) = server().await;
    let dir = temp_dir();
    std::fs::create_dir_all(&dir).unwrap();
    let neon = pack_zip("org.classichs.neon", "1.0.0", "[]");
    std::fs::write(dir.join("neon.cardpack"), &neon).unwrap();
    std::fs::write(dir.join("broken.cardpack"), b"nope").unwrap();
    std::fs::write(dir.join("readme.txt"), b"not a pack").unwrap();
    assert_eq!(packs::import_bundled(&app, &dir).await, 1);
    let rows = pack::Entity::find().all(&app.db).await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!((rows[0].pack_id.as_str(), rows[0].owner, rows[0].enabled), ("org.classichs.neon", None, true));
    assert!(app.store.exists(&sha(&neon)).await.unwrap());
    kinds(&app, "pack_import", 1).await;
    kinds(&app, "pack_rejected", 1).await;
    // Again: nothing new. Deleted by the admin: stays deleted after a restart.
    assert_eq!(packs::import_bundled(&app, &dir).await, 0);
    let (cookie, csrf) = admin_session(&app, &http).await;
    let r = call(&http, admin_post(&format!("/admin/api/packs/{}/delete", rows[0].id), &cookie, Some(&csrf), "http://admin.test", "application/json", b"{}".to_vec())).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(packs::import_bundled(&app, &dir).await, 0);
    assert!(pack::Entity::find().all(&app.db).await.unwrap().is_empty());
    // A new version in the directory is installed.
    std::fs::write(dir.join("neon.cardpack"), pack_zip("org.classichs.neon", "1.1.0", "[]")).unwrap();
    assert_eq!(packs::import_bundled(&app, &dir).await, 1);
    assert_eq!(packs::import_bundled(&app, &temp_dir()).await, 0, "a missing directory is fine");
}
