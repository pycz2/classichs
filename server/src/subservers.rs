//! Sub-server management (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §5, the plan's §2 and its
//! "Decisions"): admin invites that make a new sub-server of the account that takes them, the sub-server quota per
//! account, the limits (the defaults and per sub-server ones the super admin sets; a sub-server's admin may only lower
//! them), suspend / unavailable, delete, and the common pack library (packs with `subserver` -1).

use crate::admin::{db_err, err, Admin};
use crate::entity::{admin_invite, member, pack, role, subserver, subserver_quota};
use crate::events::Event;
use crate::{auth, db, perm, ranked, settings, App, AppRef};
use axum::extract::{ConnectInfo, Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use sea_orm::sea_query::{Expr, OnConflict};
use sea_orm::{
    ActiveModelTrait, ColumnTrait, ConnectionTrait, DbErr, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Set,
    TransactionTrait, Unchanged,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::net::SocketAddr;

/// The `subserver` of the common pack library every sub-server offers (FOUNDATION: `packs::LIBRARY`).
pub const LIBRARY: i64 = -1;

/// What a sub-server is limited in. Only packs, storage (its own packs' bytes) and players are enforced so far.
// ponytail: bots and tournaments are set and shown, not enforced; check them where those are made when needed.
pub const LIMITS: [&str; 5] = ["storage_mb", "packs", "players", "bots", "tournaments"];

/// The server setting with the super admin's defaults (JSON {limit: number}; a missing one: `builtin_default`).
pub const DEFAULTS: &str = "subserver_limits";

fn builtin_default(k: &str) -> i64 {
    match k {
        "storage_mb" => 1024,
        "packs" => 20,
        "players" => 500,
        "bots" => 10,
        _ => 20,
    }
}

pub type Limits = BTreeMap<String, i64>;

/// A sub-server's address part: 3–32 of `[a-z0-9-]`, not starting or ending with "-".
pub fn valid_name(n: &str) -> bool {
    (3..=32).contains(&n.len()) && n.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-') && !n.starts_with('-') && !n.ends_with('-')
}

/// The built-in roles of a new sub-server (Admin, Moderator, Viewer: `perm::builtin`).
pub async fn builtin_roles(c: &impl ConnectionTrait, sub: i64) -> Result<(), DbErr> {
    for (name, perms) in perm::builtin() {
        let r = role::ActiveModel { subserver: Set(Some(sub)), name: Set(name.into()), perms: Set(json!(perms).to_string()), builtin: Set(true), ..Default::default() };
        role::Entity::insert(r).exec_without_returning(c).await?;
    }
    Ok(())
}

fn numbers(v: &Value) -> Limits {
    LIMITS.iter().filter_map(|k| v.get(*k).and_then(Value::as_i64).map(|n| (k.to_string(), n))).collect()
}

/// The super admin's defaults for every sub-server.
pub async fn defaults(app: &App) -> Result<Limits, DbErr> {
    let set = numbers(&serde_json::from_str(&settings::get(app, DEFAULTS).await?).unwrap_or(Value::Null));
    Ok(LIMITS.iter().map(|k| (k.to_string(), set.get(*k).copied().unwrap_or_else(|| builtin_default(k)))).collect())
}

/// A sub-server's limits: (the most the super admin allows it, what its admin lowered, the ones in force).
/// `subserver.limits` holds the super admin's values and, under "own", its admin's.
pub async fn limits(app: &App, s: &subserver::Model) -> Result<(Limits, Limits, Limits), DbErr> {
    let v: Value = serde_json::from_str(&s.limits).unwrap_or(Value::Null);
    let mut max = defaults(app).await?;
    max.extend(numbers(&v));
    let own = numbers(&v["own"]);
    let now = max.iter().map(|(k, m)| (k.clone(), own.get(k).map_or(*m, |o| (*o).min(*m)))).collect();
    Ok((max, own, now))
}

/// What a sub-server uses: its own packs (count, bytes) and players.
pub async fn usage(c: &impl ConnectionTrait, sub: i64) -> Result<(i64, i64, i64), DbErr> {
    let packs = pack::Entity::find().filter(pack::Column::Subserver.eq(sub)).count(c).await? as i64;
    let bytes: Option<i64> =
        pack::Entity::find().select_only().column_as(pack::Column::Size.sum(), "s").filter(pack::Column::Subserver.eq(sub)).into_tuple().one(c).await?.flatten();
    let players = member::Entity::find().filter(member::Column::Subserver.eq(sub)).count(c).await? as i64;
    Ok((packs, bytes.unwrap_or(0), players))
}

/// Room in the sub-server for one more pack of `size` bytes (main has no limits). Err: why not.
pub async fn pack_room(app: &App, sub: i64, size: i64) -> Result<Result<(), String>, DbErr> {
    let Some(s) = subserver::Entity::find_by_id(sub).one(&app.db).await?.filter(|s| s.id > 0) else { return Ok(Ok(())) };
    let (_, _, lim) = limits(app, &s).await?;
    let (packs, bytes, _) = usage(&app.db, sub).await?;
    if packs >= lim["packs"] {
        return Ok(Err(format!("This server has {} packs at most: delete one first", lim["packs"])));
    }
    if bytes + size > lim["storage_mb"] << 20 {
        return Ok(Err(format!("This server has {} MB for packs: delete one first", lim["storage_mb"])));
    }
    Ok(Ok(()))
}

/// May the account log into the sub-server (its game)? A suspended or unavailable one refuses everybody; a full one
/// refuses those who are not its players yet. Err: (code, message for the player).
pub async fn may_enter(app: &App, sub: i64, account: i64) -> Result<Result<(), (&'static str, String)>, DbErr> {
    let Some(s) = subserver::Entity::find_by_id(sub).one(&app.db).await? else { return Ok(Ok(())) };
    match s.state.as_str() {
        "suspended" => return Ok(Err(("server_suspended", "This server is suspended by the host".into()))),
        "unavailable" => return Ok(Err(("server_unavailable", "This server is not available now: try later".into()))),
        _ => {}
    }
    if s.id == 0 || member::Entity::find_by_id((sub, account)).one(&app.db).await?.is_some() {
        return Ok(Ok(()));
    }
    let (_, _, lim) = limits(app, &s).await?;
    if usage(&app.db, sub).await?.2 >= lim["players"] {
        return Ok(Err(("server_full", "This server has no room for new players".into())));
    }
    Ok(Ok(()))
}

/// The accounts online in a sub-server.
// FOUNDATION: the foundation's `Conn.sub == sub`; here: the connected accounts that are its players.
async fn online(app: &App, sub: i64) -> Result<Vec<i64>, DbErr> {
    let conns: Vec<i64> = app.hub().conns.keys().copied().collect();
    if sub == 0 {
        return Ok(conns);
    }
    let members: HashSet<i64> = member::Entity::find().filter(member::Column::Subserver.eq(sub)).all(&app.db).await?.into_iter().map(|m| m.account).collect();
    Ok(conns.into_iter().filter(|a| members.contains(a)).collect())
}

/// Closes the game connections to a sub-server that stopped (suspended, unavailable, deleted), telling why.
async fn kick_all(app: &App, sub: i64, reason: &str) -> Result<(), DbErr> {
    let ids = online(app, sub).await?;
    let mut hub = app.hub();
    for id in ids {
        hub.send(id, &json!({"t": "kicked", "reason": reason}));
        hub.detach(id, None);
    }
    Ok(())
}

async fn quota_of(c: &impl ConnectionTrait, account: i64) -> Result<i64, DbErr> {
    Ok(subserver_quota::Entity::find_by_id(account).one(c).await?.map_or(0, |q| q.quota))
}

async fn set_quota(c: &impl ConnectionTrait, account: i64, quota: i64) -> Result<(), DbErr> {
    let row = subserver_quota::ActiveModel { account: Set(account), quota: Set(quota) };
    subserver_quota::Entity::insert(row)
        .on_conflict(OnConflict::column(subserver_quota::Column::Account).update_column(subserver_quota::Column::Quota).to_owned())
        .exec_without_returning(c)
        .await?;
    Ok(())
}

async fn owned(c: &impl ConnectionTrait, account: i64) -> Result<Vec<subserver::Model>, DbErr> {
    subserver::Entity::find().filter(subserver::Column::Owner.eq(account)).all(c).await
}

/// Makes a sub-server owned by `owner`, with its built-in roles, him its Admin and its first player.
/// Err: "bad_name" | "name_taken".
async fn create(c: &impl ConnectionTrait, owner: i64, name: &str, title: &str) -> Result<Result<i64, &'static str>, DbErr> {
    if !valid_name(name) {
        return Ok(Err("bad_name"));
    }
    if subserver::Entity::find().filter(subserver::Column::Name.eq(name)).one(c).await?.is_some() {
        return Ok(Err("name_taken"));
    }
    let title = if title.trim().is_empty() { name.to_string() } else { title.trim().chars().take(60).collect() };
    let row = subserver::ActiveModel {
        name: Set(name.into()),
        title: Set(title),
        owner: Set(Some(owner)),
        state: Set("active".into()),
        limits: Set("{}".into()),
        created: Set(ranked::now()),
        ..Default::default()
    };
    let id = subserver::Entity::insert(row).exec(c).await?.last_insert_id;
    builtin_roles(c, id).await?;
    perm::give_builtin(c, owner, id, "Admin").await?;
    let m = member::ActiveModel { subserver: Set(id), account: Set(owner), joined: Set(ranked::now()), suspended: Set(false) };
    member::Entity::insert(m).on_conflict_do_nothing().exec_without_returning(c).await?;
    Ok(Ok(id))
}

fn refusal(code: &str) -> Response {
    let text = match code {
        "bad_name" => "A server's name is 3 to 32 small Latin letters, digits or -",
        "name_taken" => "This server name is taken",
        "invite_invalid" => "This admin invite is unknown, used or revoked",
        "taken" => "This account name is taken",
        "quota" => "You own as many servers as you may: ask the host for more",
        _ => "Refused",
    };
    (StatusCode::CONFLICT, Json(json!({"error": text, "code": code}))).into_response()
}

fn run(r: Result<Response, DbErr>) -> Response {
    r.unwrap_or_else(db_err)
}

/// FORBIDDEN unless the admin has the permission in the sub-server (a global role: in every one).
async fn need(app: &App, a: &Admin, p: &str, sub: i64) -> Option<Response> {
    (!perm::has(app, a.me.id, p, sub).await).then(|| err(StatusCode::FORBIDDEN, "You don't have the permission for this"))
}

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/subservers", get(list).post(create_own))
        .route("/admin/api/subservers/defaults", post(set_defaults))
        .route("/admin/api/subservers/quota", post(quota))
        .route("/admin/api/subservers/{id}/limits", get(limits_get).post(limits_set))
        .route("/admin/api/subservers/{id}/{action}", post(action))
        .route("/admin/api/library/{pack}/{action}", post(library))
        .route("/admin/api/admin_invites", get(invites).post(invite_create))
        .route("/admin/api/admin_invites/{id}/revoke", post(invite_revoke))
}

/// Outside the admin session: taking an admin invite.
pub fn public_routes() -> Router<AppRef> {
    Router::new().route("/admin/api/claim", post(claim))
}

/// The super admin's list: every sub-server with its owner, state, players (online), packs, storage and limits.
async fn list(State(app): State<AppRef>, Extension(a): Extension<Admin>) -> Response {
    if let Some(r) = need(&app, &a, "subservers.view", 0).await {
        return r;
    }
    run(async {
        let rows = subserver::Entity::find().order_by_asc(subserver::Column::Id).all(&app.db).await?;
        let mut out = vec![];
        for s in rows {
            let (packs, bytes, players) = usage(&app.db, s.id).await?;
            let (max, own, now) = limits(&app, &s).await?;
            let owner = match s.owner {
                Some(o) => Some(json!({"id": o, "user": db::name_of(&app.db, o).await?, "quota": quota_of(&app.db, o).await?})),
                None => None,
            };
            out.push(json!({"id": s.id, "name": s.name, "title": s.title, "state": s.state, "created": s.created, "owner": owner,
                "players": players, "online": online(&app, s.id).await?.len(), "packs": packs, "storage": bytes,
                "max": max, "own": own, "limits": now}));
        }
        Ok(Json(json!({"list": out, "defaults": defaults(&app).await?, "keys": LIMITS})).into_response())
    }
    .await)
}

#[derive(Deserialize)]
struct NewIn {
    name: String,
    #[serde(default)]
    title: String,
}

/// An admin makes one more sub-server of his own, within his quota.
async fn create_own(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<NewIn>) -> Response {
    run(async {
        let mine = owned(&app.db, a.me.id).await?;
        let mut allowed = perm::has(&app, a.me.id, "subservers.create_own", 0).await;
        for s in &mine {
            allowed = allowed || perm::has(&app, a.me.id, "subservers.create_own", s.id).await;
        }
        if !allowed {
            return Ok(err(StatusCode::FORBIDDEN, "You don't have the permission for this"));
        }
        let txn = app.db.begin().await?;
        if owned(&txn, a.me.id).await?.len() as i64 >= quota_of(&txn, a.me.id).await? {
            return Ok(refusal("quota"));
        }
        let id = match create(&txn, a.me.id, &f.name, &f.title).await? {
            Ok(id) => id,
            Err(code) => return Ok(refusal(code)),
        };
        perm::audit(&txn, a.me.id, id, "subserver.create", &f.name, Value::Null, json!({"owner": a.me.id})).await;
        txn.commit().await?;
        app.event(a.ev(format!("{} made the server {}", a.me.name, f.name)));
        Ok(Json(json!({"ok": true, "id": id, "name": f.name, "url": format!("/s/{}/admin", f.name)})).into_response())
    }
    .await)
}

#[derive(Deserialize)]
struct LimitsIn {
    limits: serde_json::Map<String, Value>,
}

/// Checks a limits change: known names, whole numbers 0..=1e9 or null (back to the default).
fn parse_change(f: &LimitsIn) -> Result<Vec<(String, Option<i64>)>, Response> {
    f.limits
        .iter()
        .map(|(k, v)| {
            if !LIMITS.contains(&k.as_str()) {
                return Err(err(StatusCode::BAD_REQUEST, &format!("No limit {k}")));
            }
            match v {
                Value::Null => Ok((k.clone(), None)),
                v => v.as_i64().filter(|n| (0..=1_000_000_000).contains(n)).map(|n| (k.clone(), Some(n))).ok_or_else(|| err(StatusCode::BAD_REQUEST, "A limit is a whole number, 0 or more")),
            }
        })
        .collect()
}

fn apply(v: &mut Value, change: &[(String, Option<i64>)]) {
    if !v.is_object() {
        *v = json!({});
    }
    for (k, n) in change {
        match n {
            Some(n) => v[k] = json!(n),
            None => {
                v.as_object_mut().map(|o| o.remove(k));
            }
        }
    }
}

/// The defaults of every sub-server (the super admin's).
async fn set_defaults(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<LimitsIn>) -> Response {
    if let Some(r) = need(&app, &a, "limits.edit", 0).await {
        return r;
    }
    let change = match parse_change(&f) {
        Ok(c) => c,
        Err(r) => return r,
    };
    run(async {
        let before: Value = serde_json::from_str(&settings::get(&app, DEFAULTS).await?).unwrap_or(json!({}));
        let mut after = before.clone();
        apply(&mut after, &change);
        settings::set(&app, DEFAULTS, &after.to_string()).await?;
        perm::audit(&app.db, a.me.id, 0, "limits.defaults", "every server", before, after).await;
        app.event(a.ev(format!("{} changed the default limits of the servers", a.me.name)));
        Ok(Json(json!({"ok": true, "defaults": defaults(&app).await?})).into_response())
    }
    .await)
}

#[derive(Deserialize)]
struct QuotaIn {
    user: String,
    quota: i64,
}

/// How many sub-servers an account may own.
async fn quota(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<QuotaIn>) -> Response {
    if let Some(r) = need(&app, &a, "quotas.edit", 0).await {
        return r;
    }
    if !(0..=1000).contains(&f.quota) {
        return err(StatusCode::BAD_REQUEST, "A quota is 0 to 1000");
    }
    run(async {
        let Some(t) = db::account_by_name(&app.db, &f.user).await? else { return Ok(err(StatusCode::NOT_FOUND, "No such account")) };
        let before = quota_of(&app.db, t.id).await?;
        set_quota(&app.db, t.id, f.quota).await?;
        perm::audit(&app.db, a.me.id, 0, "quota", &t.name, json!(before), json!(f.quota)).await;
        app.event(a.ev(format!("{} set the server quota of {} to {}", a.me.name, t.name, f.quota)));
        Ok(Json(json!({"ok": true, "user": t.name, "quota": f.quota})).into_response())
    }
    .await)
}

async fn find(app: &App, id: i64) -> Result<Option<subserver::Model>, DbErr> {
    subserver::Entity::find_by_id(id).one(&app.db).await
}

/// A sub-server's limits for its admin (`limits.view`) or the super admin.
async fn limits_get(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    if let Some(r) = need(&app, &a, "limits.view", id).await {
        return r;
    }
    run(async {
        let Some(s) = find(&app, id).await? else { return Ok(err(StatusCode::NOT_FOUND, "No such server")) };
        let (max, own, now) = limits(&app, &s).await?;
        let (packs, bytes, players) = usage(&app.db, id).await?;
        let edit = perm::has(&app, a.me.id, "limits.edit", id).await;
        Ok(Json(json!({"max": max, "own": own, "limits": now, "keys": LIMITS, "edit_max": edit,
            "used": {"packs": packs, "storage_mb": bytes >> 20, "players": players}}))
        .into_response())
    }
    .await)
}

/// The super admin (`limits.edit`) sets the sub-server's limits; its admin (`settings.edit` there) only lowers them
/// for his sub-server, never above what the super admin gives.
async fn limits_set(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<LimitsIn>) -> Response {
    let change = match parse_change(&f) {
        Ok(c) => c,
        Err(r) => return r,
    };
    let as_super = perm::has(&app, a.me.id, "limits.edit", id).await;
    if !as_super {
        if let Some(r) = need(&app, &a, "settings.edit", id).await {
            return r;
        }
    }
    run(async {
        let Some(s) = find(&app, id).await? else { return Ok(err(StatusCode::NOT_FOUND, "No such server")) };
        let before: Value = serde_json::from_str(&s.limits).unwrap_or(json!({}));
        let mut after = before.clone();
        if as_super {
            apply(&mut after, &change);
        } else {
            let (max, _, _) = limits(&app, &s).await?;
            if change.iter().any(|(k, n)| n.is_some_and(|n| n > max[k])) {
                return Ok(err(StatusCode::FORBIDDEN, "You can only lower the limits the host gave this server"));
            }
            let mut own = after["own"].take();
            apply(&mut own, &change);
            if !after.is_object() {
                after = json!({});
            }
            after["own"] = own;
        }
        subserver::ActiveModel { id: Unchanged(id), limits: Set(after.to_string()), ..Default::default() }.update(&app.db).await?;
        perm::audit(&app.db, a.me.id, id, "limits", &s.name, before, after).await;
        app.event(a.ev(format!("{} changed the limits of the server {}", a.me.name, s.name)));
        let s = find(&app, id).await?.unwrap_or(s);
        let (max, own, now) = limits(&app, &s).await?;
        Ok(Json(json!({"ok": true, "max": max, "own": own, "limits": now})).into_response())
    }
    .await)
}

#[derive(Deserialize, Default)]
struct ActionIn {
    #[serde(default)]
    confirm: String,
}

/// suspend | resume | unavailable | available (`subservers.suspend`), delete (`subservers.delete`, the body's
/// `confirm` is the server's name). Main (0) stays.
async fn action(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path((id, action)): Path<(i64, String)>, body: axum::body::Bytes) -> Response {
    let state = match action.as_str() {
        "suspend" => "suspended",
        "unavailable" => "unavailable",
        "resume" | "available" => "active",
        "delete" => "",
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    };
    let p = if state.is_empty() { "subservers.delete" } else { "subservers.suspend" };
    if let Some(r) = need(&app, &a, p, id).await {
        return r;
    }
    run(async {
        let Some(s) = find(&app, id).await? else { return Ok(err(StatusCode::NOT_FOUND, "No such server")) };
        if id == 0 {
            return Ok(err(StatusCode::BAD_REQUEST, "The main server can't be suspended or deleted"));
        }
        if state.is_empty() {
            let f: ActionIn = serde_json::from_slice(&body).unwrap_or_default();
            if f.confirm != s.name {
                return Ok(err(StatusCode::BAD_REQUEST, "Type the server's name to delete it"));
            }
            kick_all(&app, id, "server_deleted").await?;
            delete(&app, id).await?;
            perm::audit(&app.db, a.me.id, 0, "subserver.delete", &s.name, json!({"id": id, "owner": s.owner, "state": s.state}), Value::Null).await;
            app.event(a.ev(format!("{} deleted the server {}", a.me.name, s.name)));
            return Ok(Json(json!({"ok": true})).into_response());
        }
        subserver::ActiveModel { id: Unchanged(id), state: Set(state.into()), ..Default::default() }.update(&app.db).await?;
        if state != "active" {
            kick_all(&app, id, if state == "suspended" { "server_suspended" } else { "server_unavailable" }).await?;
        }
        perm::audit(&app.db, a.me.id, id, "subserver.state", &s.name, json!(s.state), json!(state)).await;
        app.event(a.ev(format!("{} set the server {} {state}", a.me.name, s.name)));
        Ok(Json(json!({"ok": true, "state": state})).into_response())
    }
    .await)
}

/// Deletes a sub-server and all its data: the rows of every table with a `subserver` column (but the audit log and
/// the admin invites, the history), then the pack files no one else has.
async fn delete(app: &AppRef, id: i64) -> Result<(), DbErr> {
    let hashes: Vec<String> = pack::Entity::find().filter(pack::Column::Subserver.eq(id)).all(&app.db).await?.into_iter().map(|p| p.content_hash).collect();
    let tables: Vec<String> = app
        .db
        .query_all_raw(sea_orm::Statement::from_string(
            app.db.get_database_backend(),
            "SELECT m.name FROM sqlite_schema m, pragma_table_info(m.name) p WHERE m.type = 'table' AND p.name = 'subserver' \
             AND m.name NOT IN ('audit', 'admin_invite')",
        ))
        .await?
        .iter()
        .map(|r| r.try_get::<String>("", "name"))
        .collect::<Result<_, _>>()?;
    let txn = app.db.begin().await?;
    for t in tables {
        txn.execute_unprepared(&format!("DELETE FROM \"{t}\" WHERE subserver = {id}")).await?;
    }
    subserver::Entity::delete_by_id(id).exec(&txn).await?;
    txn.commit().await?;
    for h in hashes {
        crate::packs::gc(app, &h).await;
    }
    Ok(())
}

/// add: a server pack of main goes into the common library (every sub-server offers it); remove: back to main.
/// The library is the sub-server -1: only a global role gives its permissions.
async fn library(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path((id, action)): Path<(i64, String)>) -> Response {
    let (from, to) = match action.as_str() {
        "add" => (0, LIBRARY),
        "remove" => (LIBRARY, 0),
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    };
    if let Some(r) = need(&app, &a, "packs.enable", LIBRARY).await {
        return r;
    }
    run(async {
        let Some(p) = pack::Entity::find_by_id(id).one(&app.db).await? else { return Ok(err(StatusCode::NOT_FOUND, "No such pack")) };
        if p.subserver != from || p.owner.is_some() {
            return Ok(err(StatusCode::BAD_REQUEST, "Only the main server's own server packs go into the library"));
        }
        pack::ActiveModel { id: Unchanged(id), subserver: Set(to), is_default: Set(false), ..Default::default() }.update(&app.db).await?;
        perm::audit(&app.db, a.me.id, 0, "library", &crate::packs::label(&p), json!(from), json!(to)).await;
        app.event(a.ev(format!("{} {} the pack library: {}", a.me.name, if to == LIBRARY { "added to" } else { "removed from" }, crate::packs::label(&p))));
        Ok(Json(json!({"ok": true})).into_response())
    }
    .await)
}

/// The packs a sub-server has: its own and the library's (FOUNDATION: `packs::of_sub`).
pub async fn packs_of(c: &impl ConnectionTrait, sub: i64) -> Result<Vec<pack::Model>, DbErr> {
    pack::Entity::find().filter(pack::Column::Subserver.is_in([sub, LIBRARY])).order_by_asc(pack::Column::Id).all(c).await
}

// --- admin invites --------------------------------------------------------------------------------------------------

async fn invites(State(app): State<AppRef>, Extension(a): Extension<Admin>) -> Response {
    if let Some(r) = need(&app, &a, "admin_invites.create", 0).await {
        return r;
    }
    run(async {
        let rows = admin_invite::Entity::find().order_by_desc(admin_invite::Column::Id).all(&app.db).await?;
        let mut out = vec![];
        for k in rows {
            let used_by = match k.used_by {
                Some(u) => Some(db::name_of(&app.db, u).await?),
                None => None,
            };
            let sub = match k.subserver {
                Some(s) => find(&app, s).await?.map(|s| s.name),
                None => None,
            };
            out.push(json!({"id": k.id, "key": k.key, "note": k.note, "created": k.created, "created_by_name": k.created_by_name,
                "revoked": k.revoked, "used_by": used_by, "used_at": k.used_at, "subserver": sub}));
        }
        Ok(Json(json!({"list": out})).into_response())
    }
    .await)
}

#[derive(Deserialize)]
struct InviteIn {
    #[serde(default)]
    note: String,
}

async fn invite_create(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<InviteIn>) -> Response {
    if let Some(r) = need(&app, &a, "admin_invites.create", 0).await {
        return r;
    }
    let note = f.note.trim().to_string();
    if note.chars().count() > 200 {
        return err(StatusCode::BAD_REQUEST, "A note is 200 characters at most");
    }
    let key = auth::new_token().0;
    let row = admin_invite::ActiveModel {
        key: Set(key.clone()),
        note: Set((!note.is_empty()).then(|| note.clone())),
        created: Set(ranked::now()),
        created_by: Set(Some(a.me.id)),
        created_by_name: Set(a.me.name.clone()),
        revoked: Set(false),
        ..Default::default()
    };
    run(async {
        let id = admin_invite::Entity::insert(row).exec(&app.db).await?.last_insert_id;
        perm::audit(&app.db, a.me.id, 0, "admin_invite.create", &note, Value::Null, json!({"id": id})).await;
        app.event(a.ev(format!("{} made an admin invite{}", a.me.name, if note.is_empty() { String::new() } else { format!(": {note}") })));
        Ok(Json(json!({"ok": true, "id": id, "key": key})).into_response())
    }
    .await)
}

async fn invite_revoke(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    if let Some(r) = need(&app, &a, "admin_invites.create", 0).await {
        return r;
    }
    run(async {
        let r = admin_invite::Entity::update_many()
            .col_expr(admin_invite::Column::Revoked, Expr::value(true))
            .filter(admin_invite::Column::Id.eq(id))
            .filter(admin_invite::Column::UsedBy.is_null())
            .exec(&app.db)
            .await?;
        if r.rows_affected != 1 {
            return Ok(err(StatusCode::NOT_FOUND, "No such unused invite"));
        }
        perm::audit(&app.db, a.me.id, 0, "admin_invite.revoke", &id.to_string(), Value::Null, Value::Null).await;
        Ok(Json(json!({"ok": true})).into_response())
    }
    .await)
}

#[derive(Deserialize)]
struct ClaimIn {
    key: String,
    user: String,
    password: String,
    /// A new account (else: an existing one logs in).
    #[serde(default)]
    register: bool,
    name: String,
    #[serde(default)]
    title: String,
}

/// Taking an admin invite: a new account (or an existing one, by its password) gets a new sub-server of its own,
/// with the Admin role there and a quota of at least the sub-servers it owns. JSON only, same Origin, rate-limited.
async fn claim(State(app): State<AppRef>, ConnectInfo(addr): ConnectInfo<SocketAddr>, headers: HeaderMap, Json(f): Json<ClaimIn>) -> Response {
    if !crate::admin::origin_ok(&app, &headers) {
        return err(StatusCode::FORBIDDEN, "Cross-site request refused");
    }
    let ip = crate::client_ip(&app, &headers, addr);
    if !app.login_allowed(&format!("admin:{ip}")) {
        return err(StatusCode::TOO_MANY_REQUESTS, "Too many attempts: wait a minute");
    }
    if !valid_name(&f.name) {
        return refusal("bad_name");
    }
    if f.register && !(auth::valid_new_user(&f.user) && auth::valid_password(&f.password)) {
        return err(StatusCode::BAD_REQUEST, "A name is 3–16 letters, digits or _, a password 8–128 characters");
    }
    let found = if f.register { None } else { db::account_by_name(&app.db, &f.user).await.ok().flatten() };
    let (register, password) = (f.register, f.password.clone());
    let checked = tokio::task::spawn_blocking(move || {
        if register {
            return Some(Err(auth::hash_password(&password)));
        }
        let ok = password.len() <= 1024 && auth::verify_password(&password, found.as_ref().map_or(auth::dummy_hash(), |a| a.pass.as_str()));
        found.filter(|a| ok && !a.suspended).map(Ok)
    })
    .await
    .ok()
    .flatten();
    let Some(who) = checked else { return err(StatusCode::UNAUTHORIZED, "Wrong name or password") };
    run(async {
        let txn = app.db.begin().await?;
        let taken = admin_invite::Entity::update_many()
            .col_expr(admin_invite::Column::UsedAt, Expr::value(ranked::now()))
            .col_expr(admin_invite::Column::UsedBy, Expr::value(0))
            .filter(admin_invite::Column::Key.eq(&f.key))
            .filter(admin_invite::Column::UsedBy.is_null())
            .filter(admin_invite::Column::Revoked.eq(false))
            .exec(&txn)
            .await?;
        if taken.rows_affected != 1 {
            return Ok(refusal("invite_invalid"));
        }
        let (id, name) = match who {
            Ok(a) => (a.id, a.name),
            Err(hash) => match db::create_account(&txn, &f.user, &hash, "user").await? {
                Some(id) => (id, f.user.clone()),
                None => return Ok(refusal("taken")),
            },
        };
        let sub = match create(&txn, id, &f.name, &f.title).await? {
            Ok(s) => s,
            Err(code) => return Ok(refusal(code)),
        };
        admin_invite::Entity::update_many()
            .col_expr(admin_invite::Column::UsedBy, Expr::value(id))
            .col_expr(admin_invite::Column::Subserver, Expr::value(sub))
            .filter(admin_invite::Column::Key.eq(&f.key))
            .exec(&txn)
            .await?;
        let n = owned(&txn, id).await?.len() as i64;
        if quota_of(&txn, id).await? < n {
            set_quota(&txn, id, n).await?;
        }
        perm::audit(&txn, id, sub, "subserver.create", &f.name, Value::Null, json!({"owner": id, "admin_invite": true})).await;
        txn.commit().await?;
        app.event(Event::new("admin", format!("{name} took an admin invite: the server {}", f.name)).user(id, &name).data(json!({"ip": ip.to_string()})));
        Ok(Json(json!({"ok": true, "id": sub, "name": f.name, "user": name, "url": format!("/s/{}/admin", f.name)})).into_response())
    }
    .await)
}

#[cfg(test)]
mod tests {
    #[test]
    fn names() {
        assert!(super::valid_name("abc") && super::valid_name("my-server-2"));
        assert!(!super::valid_name("ab") && !super::valid_name("-abc") && !super::valid_name("abc-") && !super::valid_name("ABC") && !super::valid_name(&"a".repeat(33)));
    }
}
