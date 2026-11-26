//! Sub-servers (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §1): the migration of a database of
//! before, the routing of `/s/<name>/…`, and that no data crosses two sub-servers.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_engine::deck;
use classichs_server::entity::{account, deck as decks, event, standing, subserver};
use classichs_server::packs::GameRules;
use classichs_server::storage::Storage;
use classichs_server::{auth, db, perm, router, spawn_background, App, AppRef, Timers};
use futures_util::{SinkExt, StreamExt};
use sea_orm::{ActiveModelTrait, ColumnTrait, ConnectionTrait, DbBackend, EntityTrait, QueryFilter, Set, Statement};
use sea_orm_migration::MigratorTrait;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;
use tower::ServiceExt;

fn store() -> Storage {
    Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap()
}

/// A sub-server row (the management of sub-servers makes them; here by hand).
async fn add_sub(app: &AppRef, name: &str) -> i64 {
    let row = subserver::ActiveModel {
        name: Set(name.into()),
        title: Set(name.into()),
        owner: Set(None),
        state: Set("active".into()),
        limits: Set("{}".into()),
        created: Set(0),
        ..Default::default()
    };
    let id = row.insert(&app.db).await.unwrap().id;
    for (name, perms) in perm::builtin() {
        let perms = serde_json::to_string(&perms).unwrap();
        app.db
            .execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite, "INSERT INTO role (subserver, name, perms, builtin) VALUES (?, ?, ?, 1)", [id.into(), name.into(), perms.into()]))
            .await
            .unwrap();
    }
    id
}

#[tokio::test]
async fn the_migration_moves_everything_to_main_and_admins_to_super_admin() {
    let path = std::env::temp_dir().join(format!("chs-m15-{}.db", rand::random::<u64>()));
    let url = format!("sqlite://{}?mode=rwc", path.display());
    {
        let c = sea_orm::Database::connect(&url).await.unwrap();
        classichs_server::migration::Migrator::up(&c, Some(14)).await.unwrap();
        for sql in [
            "INSERT INTO accounts (id, name, pass, role, created, last_seen) VALUES (1, 'boss', 'x', 'admin', 0, 0), (2, 'ann', 'x', 'user', 0, 0)",
            "INSERT INTO decks (account, pack, name, hero, cards, created, updated) VALUES (2, 'classic-2014', 'D', 'HERO_08', '[]', 0, 0)",
            "INSERT INTO standings (account, pack, season, rank, stars, streak, ranked_mmr, casual_mmr) VALUES (2, 'classic-2014', 24323, 5, 2, 0, 1600, 1500)",
            "INSERT INTO server_settings (key, value) VALUES ('signup_invite_only', '1')",
            "INSERT INTO arena (account, seed, hero, picks, draft, wins, losses, pack) VALUES (2, 1, 0, '[]', '{}', 3, 1, '')",
        ] {
            c.execute_unprepared(sql).await.unwrap();
        }
    }
    let c = db::open(path.to_str().unwrap()).await.unwrap();
    assert_eq!(subserver::Entity::find_by_id(0).one(&c).await.unwrap().unwrap().name, "main");
    let d = decks::Entity::find().one(&c).await.unwrap().unwrap();
    assert_eq!((d.subserver, d.account), (0, 2));
    let s = standing::Entity::find_by_id((0, 2, "classic-2014".to_string(), 24323)).one(&c).await.unwrap().unwrap();
    assert_eq!((s.rank, s.stars, s.ranked_mmr), (5, 2, 1600.0));
    let app = App::new(c, false, Some(Timers::default()), store());
    assert!(classichs_server::settings::invite_only(&app, 0).await.unwrap(), "main keeps its settings");
    assert!(!classichs_server::settings::invite_only(&app, 7).await.unwrap(), "another sub-server has its own");
    assert!(classichs_server::entity::arena::Entity::find_by_id((0, 2)).one(&app.db).await.unwrap().is_some());
    // the admin of before is a Super admin (every sub-server, the super level); a player has no role
    assert!(perm::has(&app, 1, "subservers.view", 0).await);
    assert!(perm::has(&app, 1, "players.ban", 42).await);
    assert!(perm::all(&app, 2, 0).await.is_empty());
    // main's built-in roles
    let roles: Vec<String> = perm::roles(&app.db, 1, 0).await.unwrap().into_iter().map(|r| r.name).collect();
    assert_eq!(roles, ["Super admin"]);
    let _ = std::fs::remove_file(&path);
}

async fn call(app: &axum::Router, req: Request<Body>) -> (StatusCode, Vec<String>, Value) {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let cookies = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).collect();
    let body = axum::body::to_bytes(res.into_body(), 4 << 20).await.unwrap();
    (status, cookies, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

fn login(path: &str, user: &str) -> Request<Body> {
    Request::post(path)
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, "http://admin.test")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(json!({"user": user, "password": "rootpassword"}).to_string()))
        .unwrap()
}

fn get(path: &str, cookie: &str) -> Request<Body> {
    Request::get(path).header(header::HOST, "admin.test").header(header::COOKIE, cookie).body(Body::empty()).unwrap()
}

#[tokio::test]
async fn routing_by_path_and_the_panel_of_a_sub_server() {
    let state = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store());
    let hash = auth::hash_password("rootpassword");
    db::make_superuser(&state.db, "root", &hash).await.unwrap();
    let boss = db::create_account(&state.db, "boss", &hash, "admin").await.unwrap().unwrap(); // main's Admin
    let two = add_sub(&state, "two").await;
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));

    assert_eq!(call(&app, get("/s/nope/admin/api/me", "")).await.0, StatusCode::NOT_FOUND, "no such sub-server");
    assert_eq!(call(&app, get("/s/two/admin", "")).await.0, StatusCode::OK, "the panel's page");
    // the super admin enters both; the cookie is the sub-server's own
    let (st, cookies, _) = call(&app, login("/s/two/admin/api/login", "root")).await;
    assert_eq!(st, StatusCode::OK);
    let c = cookies.iter().find(|c| c.starts_with("chs_admin=")).unwrap();
    assert!(c.contains("Path=/s/two/admin"), "{c}");
    let cookie = c.split(';').next().unwrap();
    let (st, _, me) = call(&app, get("/s/two/admin/api/me", cookie)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(me["subserver"], json!({"id": two, "prefix": "/s/two"}));
    assert!(me["perms"].as_array().unwrap().iter().any(|p| p == "subservers.view"));
    // main's Admin is nobody in "two"
    assert_eq!(call(&app, login("/admin/api/login", "boss")).await.0, StatusCode::OK);
    assert_eq!(call(&app, login("/s/two/admin/api/login", "boss")).await.0, StatusCode::UNAUTHORIZED);
    perm::give_builtin(&state.db, boss, two, "Viewer").await.unwrap();
    let (st, cookies, _) = call(&app, login("/s/two/admin/api/login", "boss")).await;
    assert_eq!(st, StatusCode::OK);
    let cookie = cookies[0].split(';').next().unwrap().to_string();
    assert_eq!(call(&app, get("/s/two/admin/api/accounts", &cookie)).await.0, StatusCode::OK, "a Viewer views");
    let mut post = login("/s/two/admin/api/settings", "x");
    post.headers_mut().insert(header::COOKIE, cookie.parse().unwrap());
    assert_eq!(call(&app, post).await.0, StatusCode::FORBIDDEN, "but changes nothing");
}

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn want(ws: &mut Ws, t: &str) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let m = tokio::time::timeout_at(deadline, ws.next()).await.unwrap_or_else(|_| panic!("timed out waiting for {t}")).unwrap().unwrap();
        if let Message::Text(s) = m {
            let v: Value = serde_json::from_str(s.as_str()).unwrap();
            if v["t"] == t {
                return v;
            }
            assert!(v["t"] != "error" || t == "error", "unexpected error while waiting for {t}: {v}");
        }
    }
}

async fn send(ws: &mut Ws, v: Value) {
    ws.send(Message::text(v.to_string())).await.unwrap();
}

/// Logs in (registering the first time) at `ws://addr<path>`.
async fn player(addr: SocketAddr, path: &str, name: &str, register: bool) -> Ws {
    let (mut ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}{path}")).await.unwrap();
    send(&mut ws, json!({"t": if register { "register" } else { "login" }, "user": name, "password": "password123"})).await;
    want(&mut ws, "auth").await;
    ws
}

#[tokio::test]
async fn no_data_crosses_two_sub_servers() {
    let app = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store());
    spawn_background(app.clone());
    let two = add_sub(&app, "two").await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });

    // one account, on main and on "two"
    let mut a = player(addr, "/", "alice", true).await;
    let d = json!({"name": "Main deck", "hero": deck::hero("MAGE").unwrap(), "cards": deck::basic("MAGE")});
    send(&mut a, json!({"t": "deck_save", "deck": d})).await;
    want(&mut a, "deck_saved").await;
    let rules = GameRules::classic();
    let rank = |v: &Value| v["me"]["rank"]["rank"].clone();
    drop(a);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let mut a2 = player(addr, "/s/two/", "alice", false).await;
    send(&mut a2, json!({"t": "decks"})).await;
    assert_eq!(want(&mut a2, "decks").await["list"], json!([]), "main's decks are not two's");
    send(&mut a2, json!({"t": "me", "pack": rules.rules_hash})).await;
    let me = want(&mut a2, "me").await;
    assert_eq!(rank(&me), 25);
    let alice = db::id_by_name(&app.db, "alice").await.unwrap().unwrap();
    let rows = standing::Entity::find().filter(standing::Column::Account.eq(alice)).all(&app.db).await.unwrap();
    assert!(rows.iter().any(|s| s.subserver == two) && rows.iter().any(|s| s.subserver == 0), "a standing in each: {rows:?}");
    // two's settings are two's: invite-only there, main stays open
    classichs_server::settings::set(&app, two, classichs_server::settings::INVITE_ONLY, "1").await.unwrap();
    let (mut b, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/s/two")).await.unwrap();
    send(&mut b, json!({"t": "register", "user": "bob", "password": "password123"})).await;
    assert_eq!(want(&mut b, "error").await["code"], "invite_required");
    let _b = player(addr, "/", "bob", true).await;
    // a tournament of main is not in two's list
    let mut m = player(addr, "/", "carol", true).await;
    send(&mut m, json!({"t": "t_create", "name": "Main cup", "pack": rules.rules_hash, "format": "elimination", "options": {}, "series": "conquest",
                        "best_of": 1, "bans": 0, "start_at": classichs_server::events::now_ms() + 12 * 60_000, "max_players": 8})).await;
    let t = want(&mut m, "tournament").await["tournament"]["id"].as_i64().unwrap();
    send(&mut a2, json!({"t": "t_list", "tab": "upcoming"})).await;
    assert_eq!(want(&mut a2, "t_list").await["list"], json!([]));
    send(&mut a2, json!({"t": "t_get", "id": t})).await;
    assert_eq!(want(&mut a2, "error").await["text"], "No such tournament");
    // the events are each sub-server's
    tokio::time::sleep(Duration::from_millis(300)).await;
    let two_events = event::Entity::find().filter(event::Column::Subserver.eq(two)).all(&app.db).await.unwrap();
    assert!(two_events.iter().any(|e| e.kind == "login" && e.user.as_deref() == Some("alice")), "{two_events:?}");
    assert!(!two_events.iter().any(|e| e.user.as_deref() == Some("carol")));
    // two's players: alice only (bob was refused there); main's: everyone
    let members: Vec<i64> = classichs_server::entity::member::Entity::find()
        .filter(classichs_server::entity::member::Column::Subserver.eq(two))
        .all(&app.db)
        .await
        .unwrap()
        .iter()
        .map(|m| m.account)
        .collect();
    assert_eq!(members, [alice]);
    assert!(account::Entity::find().filter(account::Column::Name.eq("bob")).one(&app.db).await.unwrap().is_some(), "one account for all");
    // the live view of each panel: alice online in two, carol in main
    let live = app.hub().live_json(two);
    let online: Vec<&str> = live["online"].as_array().unwrap().iter().map(|o| o["user"].as_str().unwrap()).collect();
    assert_eq!(online, ["alice"]);
    assert!(!app.hub().live_json(0)["online"].as_array().unwrap().iter().any(|o| o["user"] == "alice"));
}
