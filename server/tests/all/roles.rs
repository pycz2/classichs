//! Roles and permissions in the admin API (admin_roles.rs, perm.rs): each endpoint's permission, giving
//! only what one has, the last Super admin, the audit log, panel.open for the login.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::storage::Storage;
use classichs_server::{auth, db, router, App, Timers};
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

fn get(uri: &str, cookie: &str) -> Request<Body> {
    Request::get(uri).header(header::HOST, "admin.test").header(header::COOKIE, cookie).body(Body::empty()).unwrap()
}

fn post(uri: &str, cookie: &str, csrf: &str, body: Value) -> Request<Body> {
    Request::post(uri)
        .header(header::HOST, "admin.test")
        .header(header::ORIGIN, "http://admin.test")
        .header(header::COOKIE, cookie)
        .header(header::CONTENT_TYPE, "application/json")
        .header("x-csrf-token", csrf)
        .body(Body::from(body.to_string()))
        .unwrap()
}

/// A logged-in admin: (cookie header, CSRF token).
struct S(String, String);

impl S {
    async fn get(&self, app: &axum::Router, uri: &str) -> (StatusCode, Value) {
        let (s, v, _) = call(app, get(uri, &self.0)).await;
        (s, v)
    }

    async fn post(&self, app: &axum::Router, uri: &str, body: Value) -> (StatusCode, Value) {
        let (s, v, _) = call(app, post(uri, &self.0, &self.1, body)).await;
        (s, v)
    }
}

async fn setup() -> axum::Router {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let state = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
    db::make_superuser(&state.db, "root", &auth::hash_password("rootpassword")).await.unwrap();
    router(state).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))))
}

async fn try_log_in(app: &axum::Router, user: &str, password: &str) -> Option<S> {
    let (status, v, cookies) = call(app, post("/admin/api/login", "", "", json!({"user": user, "password": password}))).await;
    if status != StatusCode::OK {
        return None;
    }
    let c = cookies.iter().find(|c| c.starts_with("chs_admin="))?;
    Some(S(c.split(';').next()?.to_string(), v["csrf"].as_str()?.to_string()))
}

async fn log_in(app: &axum::Router, user: &str) -> S {
    try_log_in(app, user, &format!("{user}password")).await.expect("logged in")
}

/// Makes an account by the API (as root): its id.
async fn account(app: &axum::Router, root: &S, user: &str) -> i64 {
    let (s, v) = root.post(app, "/admin/api/accounts", json!({"user": user, "password": format!("{user}password")})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v["id"].as_i64().unwrap()
}

async fn role_id(app: &axum::Router, root: &S, name: &str) -> i64 {
    let (s, v) = root.get(app, "/admin/api/roles").await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v["list"].as_array().unwrap().iter().find(|r| r["name"] == name).unwrap_or_else(|| panic!("no role {name}: {v}"))["id"].as_i64().unwrap()
}

async fn give(app: &axum::Router, by: &S, role: i64, account: i64) -> StatusCode {
    by.post(app, &format!("/admin/api/roles/{role}/assign"), json!({"account": account})).await.0
}

#[tokio::test]
async fn a_viewer_sees_but_changes_nothing() {
    let app = setup().await;
    let root = log_in(&app, "root").await;
    let id = account(&app, &root, "watcher").await;
    assert!(try_log_in(&app, "watcher", "watcherpassword").await.is_none(), "a player can't open the panel");
    let viewer = role_id(&app, &root, "Viewer").await;
    assert_eq!(give(&app, &root, viewer, id).await, StatusCode::OK);
    let w = log_in(&app, "watcher").await;
    let me = w.get(&app, "/admin/api/me").await.1;
    let perms: Vec<&str> = me["perms"].as_array().unwrap().iter().map(|p| p.as_str().unwrap()).collect();
    assert!(perms.contains(&"players.view") && !perms.contains(&"players.edit") && !perms.contains(&"subservers.view"), "{perms:?}");
    for uri in [
        "/admin/api/dashboard",
        "/admin/api/accounts",
        "/admin/api/settings",
        "/admin/api/packs",
        "/admin/api/bots",
        "/admin/api/signup_keys",
        "/admin/api/tournaments",
        "/admin/api/games",
        "/admin/api/events",
        "/admin/api/roles",
        "/admin/api/audit",
        &format!("/admin/api/accounts/{id}/roles"),
    ] {
        let (s, v) = w.get(&app, uri).await;
        assert_eq!(s, StatusCode::OK, "GET {uri}: {v}");
    }
    for uri in [
        "/admin/api/accounts",
        "/admin/api/settings",
        "/admin/api/packs",
        "/admin/api/bots",
        "/admin/api/signup_keys",
        "/admin/api/tournaments/1/cancel",
        "/admin/api/roles",
        &format!("/admin/api/roles/{viewer}/assign"),
    ] {
        let (s, v) = w.post(&app, uri, json!({"user": "someone", "password": "longpassword", "name": "X", "perms": [], "account": id})).await;
        assert_eq!(s, StatusCode::FORBIDDEN, "POST {uri}: {v}");
    }
}

#[tokio::test]
async fn one_gives_only_what_one_has() {
    let app = setup().await;
    let root = log_in(&app, "root").await;
    let m = account(&app, &root, "moder").await;
    let other = account(&app, &root, "other").await;
    let (moderator, admin) = (role_id(&app, &root, "Moderator").await, role_id(&app, &root, "Admin").await);
    // a role that lets one give roles: unknown and super level permissions are refused
    let (s, _) = root.post(&app, "/admin/api/roles", json!({"name": "Giver", "perms": ["panel.open", "nonsense"]})).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let (s, _) = root.post(&app, "/admin/api/roles", json!({"name": "Giver", "perms": ["panel.open", "superadmins.manage"]})).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let (s, v) = root.post(&app, "/admin/api/roles", json!({"name": "Giver", "perms": ["panel.open", "roles.view", "roles.assign", "roles.edit"]})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let giver = v["id"].as_i64().unwrap();
    let (s, _) = root.post(&app, "/admin/api/roles", json!({"name": "Giver", "perms": []})).await;
    assert_eq!(s, StatusCode::CONFLICT, "the name is taken");
    assert_eq!(give(&app, &root, giver, m).await, StatusCode::OK);
    assert_eq!(give(&app, &root, moderator, m).await, StatusCode::OK);

    let md = log_in(&app, "moder").await;
    assert_eq!(give(&app, &md, admin, other).await, StatusCode::FORBIDDEN, "a moderator lacks the Admin's permissions");
    assert_eq!(give(&app, &md, moderator, other).await, StatusCode::OK);
    let (s, v) = md.get(&app, &format!("/admin/api/accounts/{other}/roles")).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["list"][0]["name"], "Moderator");
    // nor puts into a role what he lacks; built-in roles are read-only
    let (s, _) = md.post(&app, "/admin/api/roles", json!({"name": "Mine", "perms": ["settings.edit"]})).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = md.post(&app, "/admin/api/roles", json!({"name": "Mine", "perms": ["players.ban", "chats.*"]})).await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{moderator}"), json!({"name": "Moderator", "perms": []})).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{moderator}/delete"), json!({})).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // the Super admin role is given only with superadmins.manage
    let sup = role_id(&app, &root, "Super admin").await;
    assert_eq!(give(&app, &md, sup, other).await, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn the_last_super_admin_and_the_audit() {
    let app = setup().await;
    let root = log_in(&app, "root").await;
    let me = root.get(&app, "/admin/api/me").await.1["id"].as_i64().unwrap();
    let sup = role_id(&app, &root, "Super admin").await;
    let unassign = |a: i64| json!({"account": a});
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{sup}/unassign"), unassign(me)).await;
    assert_eq!(s, StatusCode::CONFLICT);
    let two = account(&app, &root, "second").await;
    assert_eq!(give(&app, &root, sup, two).await, StatusCode::OK);
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{sup}/unassign"), unassign(two)).await;
    assert_eq!(s, StatusCode::OK);

    // a role without panel.open: no login
    let (s, v) = root.post(&app, "/admin/api/roles", json!({"name": "Blind", "perms": ["players.view"]})).await;
    assert_eq!(s, StatusCode::OK);
    let blind = v["id"].as_i64().unwrap();
    assert_eq!(give(&app, &root, blind, two).await, StatusCode::OK);
    assert!(try_log_in(&app, "second", "secondpassword").await.is_none());
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{blind}"), json!({"name": "Sighted", "perms": ["players.view", "panel.open"]})).await;
    assert_eq!(s, StatusCode::OK);
    assert!(try_log_in(&app, "second", "secondpassword").await.is_some());
    let (s, _) = root.post(&app, &format!("/admin/api/roles/{blind}/delete"), json!({})).await;
    assert_eq!(s, StatusCode::OK);
    assert!(try_log_in(&app, "second", "secondpassword").await.is_none(), "its holders lost it");

    let (s, v) = root.get(&app, "/admin/api/audit").await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let actions: Vec<&str> = v["list"].as_array().unwrap().iter().map(|r| r["action"].as_str().unwrap()).collect();
    assert_eq!(actions, ["role.delete", "role.edit", "role.assign", "role.create", "role.unassign", "role.assign"], "newest first");
    assert_eq!(v["list"][0]["user"], "root");
    assert_eq!(v["list"][1]["before"]["name"], "Blind");
    assert_eq!(v["list"][1]["after"]["name"], "Sighted");
    let (_, v) = root.get(&app, "/admin/api/audit?action=role.assign&size=1").await;
    assert_eq!((v["total"].as_u64(), v["list"].as_array().unwrap().len()), (Some(2), 1));
    let (_, v) = root.get(&app, "/admin/api/audit?account=second").await;
    assert_eq!(v["total"], 0);
}
