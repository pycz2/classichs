//! Sub-server management: admin invites make sub-servers, the quota, the limits (an admin only lowers them),
//! suspend / unavailable / delete, the common pack library.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::entity::{account, audit, pack, role, subserver};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, perm, router, subservers, App, AppRef, Timers};
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, PaginatorTrait, QueryFilter, Set, Unchanged};
use serde_json::{json, Value};
use std::net::SocketAddr;
use tower::ServiceExt;

async fn call(app: &axum::Router, req: Request<Body>) -> (StatusCode, Value, Vec<String>) {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let cookies = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).collect();
    let body = axum::body::to_bytes(res.into_body(), 4 << 20).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null), cookies)
}

fn get(uri: &str, s: &(String, String)) -> Request<Body> {
    Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, &s.0).body(Body::empty()).unwrap()
}

fn post(uri: &str, s: Option<&(String, String)>, body: Value) -> Request<Body> {
    let mut r = Request::post(uri).header(header::HOST, "admin.test").header(header::ORIGIN, "http://admin.test").header(header::CONTENT_TYPE, "application/json");
    if let Some((cookie, csrf)) = s {
        r = r.header(header::COOKIE, cookie).header("x-csrf-token", csrf);
    }
    r.body(Body::from(body.to_string())).unwrap()
}

async fn setup() -> (AppRef, axum::Router) {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let state = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
    let hash = auth::hash_password("rootpassword");
    let root = db::make_superuser(&state.db, "root", &hash).await.unwrap();
    let _ = root;
    let id = db::id_by_name(&state.db, "root").await.unwrap().unwrap();
    perm::make_super(&state.db, id).await.unwrap(); // FOUNDATION: the foundation's make_superuser does it
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));
    (state, app)
}

/// Logs into the admin panel: (cookie header, CSRF token).
async fn log_in(app: &axum::Router, user: &str, password: &str) -> (String, String) {
    let (st, v, cookies) = call(app, post("/admin/api/login", None, json!({"user": user, "password": password}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    let c = cookies.iter().find(|c| c.starts_with("chs_admin=")).unwrap();
    (c.split(';').next().unwrap().to_string(), v["csrf"].as_str().unwrap().to_string())
}

/// A new admin invite's key.
async fn invite(app: &axum::Router, root: &(String, String)) -> String {
    let (st, v, _) = call(app, post("/admin/api/admin_invites", Some(root), json!({"note": "for alice"}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    v["key"].as_str().unwrap().to_string()
}

async fn claim(app: &axum::Router, body: Value) -> (StatusCode, Value) {
    let (st, v, _) = call(app, post("/admin/api/claim", None, body)).await;
    (st, v)
}

async fn sub_named(app: &App, name: &str) -> subserver::Model {
    subserver::Entity::find().filter(subserver::Column::Name.eq(name)).one(&app.db).await.unwrap().unwrap()
}

/// alice takes an invite (a new account) and owns the sub-server "alices"; she may open the admin panel.
// FOUNDATION: in this branch the panel still admits by `accounts.role`; the foundation's guard admits by `panel.open`.
async fn alice(state: &AppRef, app: &axum::Router, root: &(String, String)) -> (i64, (String, String)) {
    let key = invite(app, root).await;
    let (st, v) = claim(app, json!({"key": key, "user": "alice", "password": "alicepassword", "register": true, "name": "alices", "title": "Alice's"})).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert_eq!(v["url"], "/s/alices/admin");
    let a = db::account_by_name(&state.db, "alice").await.unwrap().unwrap();
    account::ActiveModel { id: Unchanged(a.id), role: Set("admin".into()), ..Default::default() }.update(&state.db).await.unwrap();
    (v["id"].as_i64().unwrap(), log_in(app, "alice", "alicepassword").await)
}

fn pack_row(sub: i64, n: usize, size: i64) -> pack::ActiveModel {
    pack::ActiveModel {
        subserver: Set(sub),
        pack_id: Set(format!("org.test.p{sub}x{n}")),
        version: Set("1.0.0".into()),
        name: Set("{}".into()),
        rules_hash: Set(format!("r{sub}x{n}")),
        content_hash: Set(format!("c{sub}x{n}")),
        size: Set(size),
        owner: Set(None),
        enabled: Set(true),
        created: Set(0),
        downloads: Set(0),
        hashes: Set(1),
        is_default: Set(false),
        ..Default::default()
    }
}

#[tokio::test]
async fn admin_invite_makes_a_subserver() {
    let (state, app) = setup().await;
    let root = log_in(&app, "root", "rootpassword").await;
    let (sub, _) = alice(&state, &app, &root).await;
    let s = sub_named(&state, "alices").await;
    let a = db::id_by_name(&state.db, "alice").await.unwrap().unwrap();
    assert_eq!((s.id, s.owner, s.title.as_str(), s.state.as_str()), (sub, Some(a), "Alice's", "active"));
    // the Admin role there, nothing at the super level, nothing in main
    assert!(perm::has(&state, a, "players.ban", sub).await && perm::has(&state, a, "limits.view", sub).await);
    assert!(!perm::has(&state, a, "subservers.view", sub).await && !perm::has(&state, a, "players.ban", 0).await);
    assert_eq!(role::Entity::find().filter(role::Column::Subserver.eq(sub)).count(&state.db).await.unwrap(), 3);
    // a used key, a bad name, a taken name; an existing account takes another invite by its password
    let used = classichs_server::entity::admin_invite::Entity::find().one(&state.db).await.unwrap().unwrap();
    let (st, v) = claim(&app, json!({"key": used.key, "user": "bob", "password": "bobpassword", "register": true, "name": "bobs"})).await;
    assert_eq!((st, v["code"].as_str()), (StatusCode::CONFLICT, Some("invite_invalid")));
    assert!(db::account_by_name(&state.db, "bob").await.unwrap().is_none(), "no account without a valid invite");
    let key = invite(&app, &root).await;
    let (_, v) = claim(&app, json!({"key": key, "user": "alice", "password": "alicepassword", "name": "Bad Name"})).await;
    assert_eq!(v["code"], "bad_name");
    let (_, v) = claim(&app, json!({"key": key, "user": "alice", "password": "alicepassword", "name": "alices"})).await;
    assert_eq!(v["code"], "name_taken");
    let (st, _) = claim(&app, json!({"key": key, "user": "alice", "password": "wrong-password", "name": "alice2"})).await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
    let (st, v) = claim(&app, json!({"key": key, "user": "alice", "password": "alicepassword", "name": "alice2"})).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    // the super admin's list: both, with their owner and quota (2: one per invite)
    let (st, v, _) = call(&app, get("/admin/api/subservers", &root)).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    let names: Vec<&str> = v["list"].as_array().unwrap().iter().map(|s| s["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["main", "alices", "alice2"]);
    assert_eq!(v["list"][2]["owner"]["quota"], 2);
    assert_eq!(v["list"][1]["players"], 1);
    let (_, v, _) = call(&app, get("/admin/api/admin_invites", &root)).await;
    assert_eq!(v["list"][0]["used_by"], "alice");
    assert_eq!(v["list"][0]["subserver"], "alice2");
}

#[tokio::test]
async fn quota_and_super_level() {
    let (state, app) = setup().await;
    let root = log_in(&app, "root", "rootpassword").await;
    let (sub, al) = alice(&state, &app, &root).await;
    // the invite gave one: no more
    let (st, v, _) = call(&app, post("/admin/api/subservers", Some(&al), json!({"name": "second"}))).await;
    assert_eq!((st, v["code"].as_str()), (StatusCode::CONFLICT, Some("quota")), "{v}");
    // an admin can't change quotas, see the list, make invites, suspend
    for (uri, body) in [
        ("/admin/api/subservers/quota", json!({"user": "alice", "quota": 5})),
        ("/admin/api/admin_invites", json!({})),
        (&*format!("/admin/api/subservers/{sub}/suspend"), json!({})),
    ] {
        assert_eq!(call(&app, post(uri, Some(&al), body)).await.0, StatusCode::FORBIDDEN, "{uri}");
    }
    assert_eq!(call(&app, get("/admin/api/subservers", &al)).await.0, StatusCode::FORBIDDEN);
    let (st, _, _) = call(&app, post("/admin/api/subservers/quota", Some(&root), json!({"user": "alice", "quota": 2}))).await;
    assert_eq!(st, StatusCode::OK);
    let (st, v, _) = call(&app, post("/admin/api/subservers", Some(&al), json!({"name": "second"}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    let a = db::id_by_name(&state.db, "alice").await.unwrap().unwrap();
    assert!(perm::has(&state, a, "settings.edit", v["id"].as_i64().unwrap()).await);
    let (_, v, _) = call(&app, post("/admin/api/subservers", Some(&al), json!({"name": "third"}))).await;
    assert_eq!(v["code"], "quota");
    assert!(audit::Entity::find().filter(audit::Column::Action.eq("quota")).one(&state.db).await.unwrap().is_some());
}

#[tokio::test]
async fn limits_admin_only_lowers() {
    let (state, app) = setup().await;
    let root = log_in(&app, "root", "rootpassword").await;
    let (sub, al) = alice(&state, &app, &root).await;
    let uri = format!("/admin/api/subservers/{sub}/limits");
    let (st, v, _) = call(&app, get(&uri, &al)).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert_eq!((v["limits"]["packs"].as_i64(), v["used"]["players"].as_i64(), v["edit_max"].as_bool()), (Some(20), Some(1), Some(false)));
    // the super admin: 5 packs here; the admin lowers to 3, can't raise to 6, can't touch the defaults
    assert_eq!(call(&app, post(&uri, Some(&root), json!({"limits": {"packs": 5}}))).await.0, StatusCode::OK);
    let (st, v, _) = call(&app, post(&uri, Some(&al), json!({"limits": {"packs": 3, "players": 2}}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert_eq!((v["limits"]["packs"].as_i64(), v["max"]["packs"].as_i64(), v["limits"]["players"].as_i64()), (Some(3), Some(5), Some(2)));
    let (st, v, _) = call(&app, post(&uri, Some(&al), json!({"limits": {"packs": 6}}))).await;
    assert_eq!(st, StatusCode::FORBIDDEN, "{v}");
    assert_eq!(call(&app, post("/admin/api/subservers/defaults", Some(&al), json!({"limits": {"packs": 99}}))).await.0, StatusCode::FORBIDDEN);
    assert_eq!(call(&app, post(&uri, Some(&al), json!({"limits": {"nope": 1}}))).await.0, StatusCode::BAD_REQUEST);
    // the super admin lowers the max under the admin's own: the lower wins
    call(&app, post(&uri, Some(&root), json!({"limits": {"packs": 2}}))).await;
    let s = sub_named(&state, "alices").await;
    assert_eq!(subservers::limits(&state, &s).await.unwrap().2["packs"], 2);
    // defaults reach a sub-server without its own value
    let (st, v, _) = call(&app, post("/admin/api/subservers/defaults", Some(&root), json!({"limits": {"storage_mb": 1}}))).await;
    assert_eq!((st, v["defaults"]["storage_mb"].as_i64()), (StatusCode::OK, Some(1)));
    // enforced: packs and storage
    assert_eq!(subservers::pack_room(&state, sub, 1000).await.unwrap(), Ok(()));
    assert!(subservers::pack_room(&state, sub, 2 << 20).await.unwrap().unwrap_err().contains("1 MB"));
    for n in 0..2 {
        pack_row(sub, n, 10).insert(&state.db).await.unwrap();
    }
    assert!(subservers::pack_room(&state, sub, 10).await.unwrap().unwrap_err().contains("2 packs"));
    assert_eq!(subservers::pack_room(&state, 0, 1 << 40).await.unwrap(), Ok(()), "main has no limits");
    // players: 2 (alice and one more)
    let hash = auth::hash_password("password1");
    let b = db::create_account(&state.db, "bob", &hash, "user").await.unwrap().unwrap();
    let c = db::create_account(&state.db, "carol", &hash, "user").await.unwrap().unwrap();
    assert_eq!(subservers::may_enter(&state, sub, b).await.unwrap(), Ok(()));
    let m = classichs_server::entity::member::ActiveModel { subserver: Set(sub), account: Set(b), joined: Set(0), suspended: Set(false) };
    m.insert(&state.db).await.unwrap();
    assert_eq!(subservers::may_enter(&state, sub, c).await.unwrap().unwrap_err().0, "server_full");
    assert_eq!(subservers::may_enter(&state, sub, b).await.unwrap(), Ok(()), "its players still come in");
}

#[tokio::test]
async fn suspend_unavailable_delete() {
    let (state, app) = setup().await;
    let root = log_in(&app, "root", "rootpassword").await;
    let (sub, _) = alice(&state, &app, &root).await;
    let a = db::id_by_name(&state.db, "alice").await.unwrap().unwrap();
    let act = |what: &str| format!("/admin/api/subservers/{sub}/{what}");
    assert_eq!(call(&app, post(&act("suspend"), Some(&root), json!({}))).await.0, StatusCode::OK);
    let (code, text) = subservers::may_enter(&state, sub, a).await.unwrap().unwrap_err();
    assert_eq!((code, text.as_str()), ("server_suspended", "This server is suspended by the host"));
    call(&app, post(&act("resume"), Some(&root), json!({}))).await;
    assert_eq!(subservers::may_enter(&state, sub, a).await.unwrap(), Ok(()));
    call(&app, post(&act("unavailable"), Some(&root), json!({}))).await;
    assert_eq!(subservers::may_enter(&state, sub, a).await.unwrap().unwrap_err().0, "server_unavailable");
    assert_eq!(call(&app, post("/admin/api/subservers/0/suspend", Some(&root), json!({}))).await.0, StatusCode::BAD_REQUEST);
    assert_eq!(subservers::may_enter(&state, 0, a).await.unwrap(), Ok(()));
    // delete: only with its name typed; its data goes, the audit stays
    pack_row(sub, 0, 10).insert(&state.db).await.unwrap();
    let (st, _, _) = call(&app, post(&act("delete"), Some(&root), json!({"confirm": "nope"}))).await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
    let (st, v, _) = call(&app, post(&act("delete"), Some(&root), json!({"confirm": "alices"}))).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert!(subserver::Entity::find_by_id(sub).one(&state.db).await.unwrap().is_none());
    assert_eq!(pack::Entity::find().filter(pack::Column::Subserver.eq(sub)).count(&state.db).await.unwrap(), 0);
    assert_eq!(role::Entity::find().filter(role::Column::Subserver.eq(sub)).count(&state.db).await.unwrap(), 0);
    assert!(!perm::has(&state, a, "players.ban", sub).await);
    assert!(audit::Entity::find().filter(audit::Column::Action.eq("subserver.delete")).one(&state.db).await.unwrap().is_some());
    assert!(audit::Entity::find().filter(audit::Column::Action.eq("subserver.state")).one(&state.db).await.unwrap().is_some());
}

#[tokio::test]
async fn library_and_own_packs() {
    let (state, app) = setup().await;
    let root = log_in(&app, "root", "rootpassword").await;
    let (sub, al) = alice(&state, &app, &root).await;
    let main_pack = pack_row(0, 0, 10).insert(&state.db).await.unwrap();
    let own = pack_row(sub, 1, 10).insert(&state.db).await.unwrap();
    let other = pack_row(99, 2, 10).insert(&state.db).await.unwrap();
    let ids = |v: Vec<pack::Model>| v.into_iter().map(|p| p.id).collect::<Vec<_>>();
    assert_eq!(ids(subservers::packs_of(&state.db, sub).await.unwrap()), [own.id]);
    // only the super admin offers a pack to everybody
    let uri = format!("/admin/api/library/{}/add", main_pack.id);
    assert_eq!(call(&app, post(&uri, Some(&al), json!({}))).await.0, StatusCode::FORBIDDEN);
    assert_eq!(call(&app, post(&uri, Some(&root), json!({}))).await.0, StatusCode::OK);
    assert_eq!(ids(subservers::packs_of(&state.db, sub).await.unwrap()), [main_pack.id, own.id]);
    assert_eq!(ids(subservers::packs_of(&state.db, 99).await.unwrap()), [main_pack.id, other.id]);
    assert_eq!(ids(subservers::packs_of(&state.db, 0).await.unwrap()), [main_pack.id]);
    // a sub-server's own pack never goes into the library; the library's goes back to main
    let (st, _, _) = call(&app, post(&format!("/admin/api/library/{}/add", own.id), Some(&root), json!({}))).await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
    assert_eq!(call(&app, post(&format!("/admin/api/library/{}/remove", main_pack.id), Some(&root), json!({}))).await.0, StatusCode::OK);
    assert_eq!(ids(subservers::packs_of(&state.db, sub).await.unwrap()), [own.id]);
}
