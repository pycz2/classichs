//! The admin panel: a single-page app (Preact + htm, plain ES modules embedded in the
//! binary, `server/admin/`) at /admin, its JSON API under /admin/api and a live feed at
//! /admin/ws. Its own login (superuser and admins): a 30-day sliding session in an HttpOnly
//! SameSite=Strict cookie, a CSRF token header on every state-changing call, Origin checks,
//! a strict Content-Security-Policy.

use crate::auth;
use crate::db::{self, Account};
use crate::entity::{account, arena, block, event, game as played, message, pack, request, session};
use crate::packs;
use crate::events::{event_json, now_ms, Event};
use crate::ranked;
use crate::ws::{accounts_in_order, friends_of};
use crate::{presence, App, AppRef};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::body::Body;
use axum::extract::{ConnectInfo, Path, Query, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use rand::RngCore;
use sea_orm::sea_query::{Expr, Func};
use sea_orm::{
    ActiveModelTrait, ColumnTrait, Condition, EntityTrait, Order, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Select, Set,
    Unchanged,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::OnceLock;
use std::time::Duration;
use tokio::sync::broadcast::error::RecvError;

const COOKIE: &str = "chs_admin";
/// 30 days, renewed (at most hourly) while the panel is used.
const SESSION_SECS: i64 = 30 * 86400;

pub fn routes(app: AppRef) -> Router<AppRef> {
    let guarded = Router::new()
        .route("/admin/api/me", get(me))
        .route("/admin/api/logout", post(logout))
        .route("/admin/api/dashboard", get(dashboard))
        .route("/admin/api/live", get(live))
        .route("/admin/api/accounts", get(accounts).post(create))
        .route("/admin/api/accounts/{id}", get(account_page))
        .route("/admin/api/accounts/{id}/{action}", post(account_action))
        .route("/admin/api/events", get(events))
        .route("/admin/api/conversations", get(conversations))
        .route("/admin/api/conversations/{a}/{b}", get(conversation))
        .route("/admin/api/games", get(games))
        .route("/admin/api/games/{id}", get(game_page))
        .route("/admin/api/packs", get(packs_list).post(packs_upload))
        .route("/admin/api/packs/{id}/{action}", post(pack_action))
        .route("/admin/ws", get(feed))
        .route_layer(middleware::from_fn_with_state(app, guard));
    Router::new()
        .route("/admin", get(index))
        .route("/admin/", get(|| async { Redirect::permanent("/admin") }))
        .route("/admin/static/{*path}", get(asset))
        .route("/admin/api/login", post(login))
        .merge(guarded)
        .layer(middleware::map_response(security_headers))
}

// --- static files ----------------------------------------------------------------

macro_rules! assets {
    ($($p:literal),* $(,)?) => { &[$(($p, include_str!(concat!("../admin/", $p)))),*] };
}

/// The panel's files, embedded at build time (edit `server/admin/`, then rebuild).
const ASSETS: &[(&str, &str)] = assets![
    "app.js",
    "api.js",
    "ui.js",
    "login.js",
    "dashboard.js",
    "events.js",
    "accounts.js",
    "games.js",
    "messages.js",
    "packs.js",
    "style.css",
    "vendor/preact.module.js",
    "vendor/hooks.module.js",
    "vendor/htm.module.js",
];

const INDEX: &str = include_str!("../admin/index.html");

/// The CSP: scripts from /admin/static plus the page's inline scripts (the import map and
/// the theme picker) by their hashes; nothing else from anywhere.
fn csp() -> &'static str {
    static CSP: OnceLock<String> = OnceLock::new();
    CSP.get_or_init(|| {
        let mut hashes = String::new();
        let mut rest = INDEX;
        while let Some(i) = rest.find("<script") {
            let tag_end = i + rest[i..].find('>').unwrap_or(0) + 1;
            let end = tag_end + rest[tag_end..].find("</script>").unwrap_or(0);
            if !rest[i..tag_end].contains("src=") {
                hashes += &format!(" 'sha256-{}'", STANDARD.encode(Sha256::digest(&rest.as_bytes()[tag_end..end])));
            }
            rest = &rest[end..];
        }
        format!(
            "default-src 'none'; script-src 'self'{hashes}; style-src 'self'; img-src 'self' data:; connect-src 'self'; \
             base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        )
    })
}

async fn security_headers(mut res: Response) -> Response {
    let h = res.headers_mut();
    h.insert(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    h.insert(header::REFERRER_POLICY, HeaderValue::from_static("no-referrer"));
    h.insert(header::X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
    h.entry(header::CACHE_CONTROL).or_insert(HeaderValue::from_static("no-store"));
    res
}

async fn index() -> Response {
    (
        [(header::CONTENT_TYPE, "text/html; charset=utf-8"), (header::CONTENT_SECURITY_POLICY, csp()), (header::CACHE_CONTROL, "no-cache")],
        INDEX,
    )
        .into_response()
}

async fn asset(Path(path): Path<String>) -> Response {
    let Some((_, body)) = ASSETS.iter().find(|(p, _)| *p == path) else { return StatusCode::NOT_FOUND.into_response() };
    let mime = match path.rsplit('.').next() {
        Some("js") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        _ => "text/plain; charset=utf-8",
    };
    ([(header::CONTENT_TYPE, mime), (header::CACHE_CONTROL, "no-cache")], *body).into_response()
}

// --- auth ------------------------------------------------------------------------

fn random() -> String {
    let mut b = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut b);
    URL_SAFE_NO_PAD.encode(b)
}

fn cookie(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|h| h.to_str().ok())
        .flat_map(|h| h.split(';'))
        .find_map(|kv| kv.trim().strip_prefix(name)?.strip_prefix('=').map(String::from))
}

/// Secure cookies when a TLS proxy says the request came over https.
fn set_cookie(headers: &HeaderMap, value: &str, max_age: i64) -> String {
    let secure = headers.get("x-forwarded-proto").is_some_and(|v| v.as_bytes() == b"https");
    format!("{COOKIE}={value}; Path=/admin; HttpOnly; SameSite=Strict; Max-Age={max_age}{}", if secure { "; Secure" } else { "" })
}

/// A request a browser sends from another site carries its Origin: refuse it (cross-site
/// WebSocket hijacking, CSRF). Requests without Origin (same-origin GETs, tools) pass.
fn origin_ok(app: &App, h: &HeaderMap) -> bool {
    let Some(origin) = h.get(header::ORIGIN).and_then(|o| o.to_str().ok()) else { return true };
    let fwd = if app.trust_proxy { h.get("x-forwarded-host") } else { None };
    let host = fwd.or(h.get(header::HOST)).and_then(|v| v.to_str().ok());
    host.is_some() && origin.split_once("://").map(|(_, rest)| rest) == host
}

fn err(status: StatusCode, text: &str) -> Response {
    (status, Json(json!({"error": text}))).into_response()
}

/// The admin making a request (put there by `guard`).
#[derive(Clone)]
pub struct Admin {
    me: Account,
    csrf: String,
    token: String,
}

impl Admin {
    fn ev(&self, text: String) -> Event {
        Event::new("admin", text).user(self.me.id, &self.me.name)
    }
}

async fn admin_of(app: &App, token: &str) -> Option<(Account, session::Model)> {
    let (me, s) = db::session(&app.db, token, "admin").await.ok()??;
    matches!(me.role.as_str(), "admin" | "super").then_some((me, s))
}

/// Every /admin/api call (but login) and /admin/ws: a live admin session, the same Origin,
/// and on anything but GET the CSRF token in the X-CSRF-Token header. Renews the session.
async fn guard(State(app): State<AppRef>, mut req: Request, next: Next) -> Response {
    if !origin_ok(&app, req.headers()) {
        return err(StatusCode::FORBIDDEN, "Cross-site request refused");
    }
    let Some(token) = cookie(req.headers(), COOKIE) else { return err(StatusCode::UNAUTHORIZED, "Log in") };
    let Some((me, s)) = admin_of(&app, &token).await else { return err(StatusCode::UNAUTHORIZED, "Log in") };
    if req.method() != Method::GET {
        let sent = req.headers().get("x-csrf-token").map(|v| v.as_bytes()).unwrap_or_default();
        if !auth::ct_eq(sent, s.csrf.as_bytes()) {
            return err(StatusCode::FORBIDDEN, "Bad CSRF token: reload the page");
        }
    }
    let renew = s.expires - ranked::now() < SESSION_SECS - 3600 && !req.uri().path().ends_with("/logout");
    if renew {
        let _ = db::renew_session(&app.db, s.hash.clone(), SESSION_SECS).await;
    }
    let headers = req.headers().clone();
    req.extensions_mut().insert(Admin { me, csrf: s.csrf, token: token.clone() });
    let mut res = next.run(req).await;
    if renew {
        if let Ok(v) = HeaderValue::from_str(&set_cookie(&headers, &token, SESSION_SECS)) {
            res.headers_mut().append(header::SET_COOKIE, v);
        }
    }
    res
}

#[derive(Deserialize)]
struct LoginIn {
    user: String,
    password: String,
}

/// JSON only (a cross-site form cannot send it), same Origin, rate-limited.
async fn login(State(app): State<AppRef>, ConnectInfo(addr): ConnectInfo<SocketAddr>, headers: HeaderMap, Json(f): Json<LoginIn>) -> Response {
    if !origin_ok(&app, &headers) {
        return err(StatusCode::FORBIDDEN, "Cross-site request refused");
    }
    let ip = crate::client_ip(&app, &headers, addr);
    let user: String = f.user.chars().take(40).collect();
    let failed = |why: &str| {
        app.event(
            Event::new("login_failed", format!("Failed admin login as {user}: {why}"))
                .other(&user)
                .data(json!({"ip": ip.to_string(), "reason": why, "admin": true})),
        );
    };
    if !app.login_allowed(&format!("admin:{ip}")) || !app.login_allowed(&format!("user:{}", user.to_lowercase())) {
        failed("rate limited");
        return err(StatusCode::TOO_MANY_REQUESTS, "Too many attempts: wait a minute");
    }
    if !auth::valid_user(&user) || f.password.len() > 1024 {
        failed("bad name");
        return err(StatusCode::UNAUTHORIZED, "Wrong name or password");
    }
    let found = db::account_by_name(&app.db, &user).await.ok().flatten();
    let password = f.password;
    let ok = tokio::task::spawn_blocking(move || {
        let stored = found.as_ref().map_or(auth::dummy_hash(), |a| a.pass.as_str());
        let ok = auth::verify_password(&password, stored);
        found.filter(|a| ok && !a.suspended && matches!(a.role.as_str(), "admin" | "super"))
    })
    .await
    .ok()
    .flatten();
    let Some(a) = ok else {
        failed("wrong password or not an admin");
        return err(StatusCode::UNAUTHORIZED, "Wrong name or password");
    };
    let csrf = random();
    let Ok(token) = db::new_session(&app.db, a.id, "admin", SESSION_SECS, &csrf).await else {
        return err(StatusCode::INTERNAL_SERVER_ERROR, "Server error");
    };
    app.event(Event::new("admin_login", format!("{} opened the admin panel", a.name)).user(a.id, &a.name).data(json!({"ip": ip.to_string()})));
    (
        [(header::SET_COOKIE, set_cookie(&headers, &token, SESSION_SECS))],
        Json(json!({"id": a.id, "user": a.name, "role": a.role, "csrf": csrf})),
    )
        .into_response()
}

async fn me(Extension(a): Extension<Admin>) -> Json<Value> {
    Json(json!({"id": a.me.id, "user": a.me.name, "role": a.me.role, "csrf": a.csrf}))
}

async fn logout(State(app): State<AppRef>, Extension(a): Extension<Admin>, headers: HeaderMap) -> Response {
    let _ = db::drop_session(&app.db, &a.token).await;
    app.event(Event::new("admin_logout", format!("{} left the admin panel", a.me.name)).user(a.me.id, &a.me.name));
    ([(header::SET_COOKIE, set_cookie(&headers, "", 0))], Json(json!({"ok": true}))).into_response()
}

// --- the live feed ------------------------------------------------------------------

/// /admin/ws: `hello {live}`, then `event {e}` for every logged event, `live {live}` when the
/// online list, queues or games change, `resync {}` when this panel fell behind. The session
/// is checked again every 30 s.
async fn feed(State(app): State<AppRef>, Extension(a): Extension<Admin>, ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(move |s| run_feed(app, a, s))
}

async fn run_feed(app: AppRef, a: Admin, mut socket: WebSocket) {
    let mut rx = app.log.feed.subscribe();
    let hello = json!({"t": "hello", "live": app.hub().live_json()}).to_string();
    if socket.send(Message::Text(hello.into())).await.is_err() {
        return;
    }
    let mut check = tokio::time::interval(Duration::from_secs(30));
    check.tick().await;
    loop {
        let out: String = tokio::select! {
            m = rx.recv() => match m {
                Ok(t) => t.to_string(),
                Err(RecvError::Lagged(_)) => r#"{"t":"resync"}"#.into(),
                Err(RecvError::Closed) => break,
            },
            m = socket.recv() => match m {
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                _ => continue,
            },
            _ = check.tick() => {
                if admin_of(&app, &a.token).await.is_none() {
                    break;
                }
                continue;
            }
        };
        if socket.send(Message::Text(out.into())).await.is_err() {
            break;
        }
    }
    let _ = socket.send(Message::Close(None)).await;
}

async fn live(State(app): State<AppRef>) -> Json<Value> {
    Json(app.hub().live_json())
}

// --- dashboard -------------------------------------------------------------------------

#[derive(Deserialize)]
struct DashQ {
    /// The admin's local midnight (unix ms): "today" starts there.
    day: Option<i64>,
}

/// Kinds counted per hour on the dashboard chart.
const CHART_KINDS: [&str; 5] = ["login", "register", "match", "msg", "game_action"];

async fn dashboard(State(app): State<AppRef>, Query(q): Query<DashQ>) -> Response {
    match dashboard_json(&app, q).await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

fn db_err(e: sea_orm::DbErr) -> Response {
    tracing::error!("admin: {e}");
    err(StatusCode::INTERNAL_SERVER_ERROR, "Database error")
}

async fn dashboard_json(app: &AppRef, q: DashQ) -> Result<Value, sea_orm::DbErr> {
    let db = &app.db;
    let now = now_ms();
    let day = q.day.filter(|d| (now - 2 * 86_400_000..=now).contains(d)).unwrap_or(now - now % 86_400_000);
    let today: HashMap<String, i64> = event::Entity::find()
        .select_only()
        .column(event::Column::Kind)
        .column_as(event::Column::Id.count(), "n")
        .filter(event::Column::At.gte(day))
        .group_by(event::Column::Kind)
        .into_tuple::<(String, i64)>()
        .all(db)
        .await?
        .into_iter()
        .collect();
    use sea_orm::sea_query::ExprTrait;
    let start = (now / 3_600_000 - 23) * 3_600_000;
    let hour = Expr::col(event::Column::At).sub(start).div(3_600_000);
    let rows: Vec<(i64, String, i64)> = event::Entity::find()
        .select_only()
        .column_as(hour.clone(), "h")
        .column(event::Column::Kind)
        .column_as(event::Column::Id.count(), "n")
        .filter(event::Column::At.gte(start))
        .filter(event::Column::Kind.is_in(CHART_KINDS))
        .group_by(hour)
        .group_by(event::Column::Kind)
        .into_tuple()
        .all(db)
        .await?;
    let mut series: HashMap<&str, Vec<i64>> = CHART_KINDS.iter().map(|k| (*k, vec![0; 24])).collect();
    for (h, kind, n) in rows {
        if let (Some(s), Ok(h)) = (series.get_mut(kind.as_str()), usize::try_from(h)) {
            if h < 24 {
                s[h] = n;
            }
        }
    }
    let accounts = account::Entity::find().count(db).await?;
    let suspended = account::Entity::find().filter(account::Column::Suspended.eq(true)).count(db).await?;
    let games = played::Entity::find().count(db).await?;
    let recent: Vec<Value> = event::Entity::find()
        .filter(event::Column::Kind.ne("game_action"))
        .order_by_desc(event::Column::Id)
        .limit(40)
        .all(db)
        .await?
        .iter()
        .map(event_json)
        .collect();
    Ok(json!({"now": now, "day": day, "today": today, "totals": {"accounts": accounts, "suspended": suspended, "games": games},
              "chart": {"start": start, "series": series}, "recent": recent, "live": app.hub().live_json()}))
}

// --- accounts ---------------------------------------------------------------------------

fn account_json(a: &Account, status: &str) -> Value {
    json!({"id": a.id, "user": a.name, "tag": a.tag, "role": a.role, "created": a.created, "last_seen": a.last_seen,
           "suspended": a.suspended, "rank": a.rank, "stars": a.stars, "streak": a.streak, "level": a.rank().level(),
           "casual_mmr": a.casual_mmr.round(), "ranked_mmr": a.ranked_mmr.round(), "season": ranked::season_name(a.season),
           "status": status})
}

#[derive(Deserialize)]
struct ListQ {
    q: Option<String>,
    sort: Option<String>,
    dir: Option<String>,
    page: Option<u64>,
    size: Option<u64>,
    /// online | offline | in_game | searching | suspended
    status: Option<String>,
    role: Option<String>,
}

impl ListQ {
    fn order(&self) -> Order {
        if self.dir.as_deref() == Some("asc") { Order::Asc } else { Order::Desc }
    }

    fn page(&self) -> (u64, u64) {
        (self.page.unwrap_or(0).min(1_000_000), self.size.unwrap_or(50).clamp(1, 500))
    }
}

/// Paged: {list, total, page, size}.
async fn page_of<E: EntityTrait>(sel: Select<E>, page: u64, size: u64, db: &crate::db::Db) -> Result<(Vec<E::Model>, u64), sea_orm::DbErr>
where
    E::Model: Sync,
{
    let p = sel.paginate(db, size);
    let total = p.num_items().await?;
    Ok((p.fetch_page(page).await?, total))
}

async fn accounts(State(app): State<AppRef>, Query(q): Query<ListQ>) -> Response {
    let mut sel = account::Entity::find();
    let search: String = q.q.clone().unwrap_or_default().trim().chars().take(40).collect();
    if !search.is_empty() {
        sel = sel.filter(Condition::any().add(account::Column::Name.contains(&search)).add(account::Column::Tag.contains(&search)));
    }
    if let Some(r) = q.role.as_deref().filter(|r| !r.is_empty()) {
        sel = sel.filter(account::Column::Role.eq(r));
    }
    match q.status.as_deref().unwrap_or("") {
        "suspended" => sel = sel.filter(account::Column::Suspended.eq(true)),
        "" => {}
        st => {
            let hub = app.hub();
            let ids: Vec<i64> = hub.conns.keys().copied().filter(|id| st == "online" || st == "offline" || hub.status(*id) == st).collect();
            drop(hub);
            sel = if st == "offline" { sel.filter(account::Column::Id.is_not_in(ids)) } else { sel.filter(account::Column::Id.is_in(ids)) };
        }
    }
    let o = q.order();
    let rev = if o == Order::Asc { Order::Desc } else { Order::Asc };
    sel = match q.sort.as_deref().unwrap_or("id") {
        "user" => sel.order_by(account::Column::Name, o),
        "created" => sel.order_by(account::Column::Created, o),
        "last_seen" => sel.order_by(account::Column::LastSeen, o),
        // the best first when descending: Legend (rank 0), then rank 1 with the most stars…
        "rank" => sel.order_by(account::Column::Rank, rev).order_by(account::Column::Stars, o),
        "ranked_mmr" => sel.order_by(account::Column::RankedMmr, o),
        "casual_mmr" => sel.order_by(account::Column::CasualMmr, o),
        _ => sel.order_by(account::Column::Id, o),
    }
    .order_by_desc(account::Column::Id);
    let (page, size) = q.page();
    let (rows, total) = match page_of(sel, page, size, &app.db).await {
        Ok(r) => r,
        Err(e) => return db_err(e),
    };
    let hub = app.hub();
    let list: Vec<Value> = rows.iter().map(|a| account_json(a, hub.status(a.id))).collect();
    Json(json!({"list": list, "total": total, "page": page, "size": size})).into_response()
}

/// May this admin change that account? Superusers are changed from the command line only.
fn may_manage(a: &Admin, t: &Account) -> bool {
    t.role != "super" && t.id != a.me.id && (a.me.role == "super" || t.role == "user")
}

async fn account_page(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    match account_page_json(&app, &a, id).await {
        Ok(Some(v)) => Json(v).into_response(),
        Ok(None) => err(StatusCode::NOT_FOUND, "No such account"),
        Err(e) => db_err(e),
    }
}

async fn account_page_json(app: &AppRef, admin: &Admin, id: i64) -> Result<Option<Value>, sea_orm::DbErr> {
    let db = &app.db;
    let Some(t) = db::account_by_id(db, id).await? else { return Ok(None) };
    let friends = friends_of(db, id).await?;
    let ins: Vec<i64> = request::Entity::find().filter(request::Column::Dst.eq(id)).all(db).await?.iter().map(|r| r.src).collect();
    let outs: Vec<i64> = request::Entity::find().filter(request::Column::Src.eq(id)).all(db).await?.iter().map(|r| r.dst).collect();
    let blocked: Vec<i64> = block::Entity::find().filter(block::Column::Who.eq(id)).all(db).await?.iter().map(|b| b.whom).collect();
    let games = played::Entity::find()
        .filter(Condition::any().add(played::Column::P0.eq(id)).add(played::Column::P1.eq(id)))
        .order_by_desc(played::Column::Ended)
        .limit(20)
        .all(db)
        .await?;
    let msgs = message::Entity::find()
        .filter(Condition::any().add(message::Column::Lo.eq(id)).add(message::Column::Hi.eq(id)))
        .order_by_desc(message::Column::Id)
        .limit(30)
        .all(db)
        .await?;
    let mut others: Vec<i64> = ins.iter().chain(&outs).chain(&blocked).copied().collect();
    others.extend(games.iter().flat_map(|g| [g.p0, g.p1]).flatten());
    others.extend(msgs.iter().flat_map(|m| [m.lo, m.hi]));
    others.sort_unstable();
    others.dedup();
    let names: HashMap<i64, String> = accounts_in_order(db, &others).await?.into_iter().map(|a| (a.id, a.name)).collect();
    let name = |i: i64| names.get(&i).cloned().unwrap_or_else(|| "(deleted)".into());
    let person = |i: &i64| json!({"id": i, "user": name(*i)});
    let sessions: Vec<Value> = session::Entity::find()
        .filter(session::Column::Account.eq(id))
        .filter(session::Column::Expires.gt(ranked::now()))
        .order_by_desc(session::Column::LastUsed)
        .all(db)
        .await?
        .iter()
        .map(|s| json!({"kind": s.kind, "created": s.created, "last_used": s.last_used, "expires": s.expires}))
        .collect();
    let run = arena::Entity::find_by_id(id).one(db).await?;
    let recent: Vec<Value> = event::Entity::find()
        .filter(Condition::any().add(event::Column::Account.eq(id)).add(event::Column::Other.eq(&t.name)))
        .filter(event::Column::Kind.ne("game_action"))
        .order_by_desc(event::Column::Id)
        .limit(40)
        .all(db)
        .await?
        .iter()
        .map(event_json)
        .collect();
    let legend = db::legend_number(db, &t).await?;
    let hub = app.hub();
    let friends: Vec<Value> = friends.iter().map(|f| json!({"id": f.id, "user": f.name, "tag": f.tag, "status": hub.status(f.id)})).collect();
    let mut acc = account_json(&t, hub.status(t.id));
    drop(hub);
    acc["legend"] = json!(legend);
    let games: Vec<Value> = games
        .iter()
        .map(|g| {
            let p = if g.p0 == Some(id) { 0 } else { 1 };
            let opp = if p == 0 { g.p1 } else { g.p0 };
            let result = if g.winner < 0 { "draw" } else if g.winner == p { "win" } else { "loss" };
            json!({"id": g.id, "mode": g.mode, "opponent": opp.map(|o| person(&o)), "result": result, "reason": g.reason,
                   "started": g.started, "ended": g.ended})
        })
        .collect();
    let messages: Vec<Value> = msgs
        .iter()
        .map(|m| {
            let with = if m.lo == id { m.hi } else { m.lo };
            json!({"id": m.id, "with": person(&with), "out": m.src == id, "text": m.text, "at": m.at, "seen": m.seen})
        })
        .collect();
    Ok(Some(json!({
        "account": acc,
        "may_manage": may_manage(admin, &t),
        "can_role": admin.me.role == "super" && may_manage(admin, &t),
        "friends": friends,
        "requests_in": ins.iter().map(person).collect::<Vec<_>>(),
        "requests_out": outs.iter().map(person).collect::<Vec<_>>(),
        "blocked": blocked.iter().map(person).collect::<Vec<_>>(),
        "games": games,
        "messages": messages,
        "sessions": sessions,
        "arena": run.map(|r| json!({"wins": r.wins, "losses": r.losses, "hero": r.hero,
                                    "picks": serde_json::from_str::<Value>(&r.picks).ok().and_then(|p| p.as_array().map(|a| a.len()))})),
        "events": recent,
    })))
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct ActionIn {
    password: String,
    role: String,
    confirm: String,
}

async fn account_action(
    State(app): State<AppRef>,
    Extension(a): Extension<Admin>,
    Path((id, action)): Path<(i64, String)>,
    Json(f): Json<ActionIn>,
) -> Response {
    let db = &app.db;
    let t = match db::account_by_id(db, id).await {
        Ok(Some(t)) => t,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such account"),
        Err(e) => return db_err(e),
    };
    if !may_manage(&a, &t) {
        return err(StatusCode::FORBIDDEN, "You may not change this account");
    }
    let kick = || async {
        app.hub().detach(id, None);
        presence(&app, id).await;
    };
    let (text, r) = match action.as_str() {
        "suspend" | "unsuspend" => {
            let s = action == "suspend";
            let r = async {
                account::ActiveModel { id: Unchanged(id), suspended: Set(s), ..Default::default() }.update(db).await?;
                if s {
                    db::drop_sessions(db, id, None).await?;
                }
                Ok(())
            }
            .await;
            if s {
                kick().await;
            }
            (format!("{} {action}ed {}", a.me.name, t.name), r)
        }
        "password" => {
            if !auth::valid_password(&f.password) {
                return err(StatusCode::BAD_REQUEST, "A password is 8 to 128 characters");
            }
            let pw = f.password;
            let hash = tokio::task::spawn_blocking(move || auth::hash_password(&pw)).await.unwrap_or_default();
            let r = db::set_password(db, id, &hash).await;
            kick().await;
            (format!("{} reset the password of {}", a.me.name, t.name), r)
        }
        "role" => {
            if a.me.role != "super" {
                return err(StatusCode::FORBIDDEN, "Only the superuser makes admins");
            }
            let role = if f.role == "admin" { "admin" } else { "user" };
            let r = async {
                account::ActiveModel { id: Unchanged(id), role: Set(role.into()), ..Default::default() }.update(db).await?;
                db::drop_sessions(db, id, Some("admin")).await
            }
            .await;
            (format!("{} made {} {role}", a.me.name, t.name), r)
        }
        "delete" => {
            if f.confirm != t.name {
                return err(StatusCode::BAD_REQUEST, "Type the account's name to confirm");
            }
            let hashes: Vec<String> =
                pack::Entity::find().filter(pack::Column::Owner.eq(id)).all(db).await.unwrap_or_default().into_iter().map(|p| p.content_hash).collect();
            let r = account::Entity::delete_by_id(id).exec(db).await.map(|_| ());
            for h in hashes {
                packs::gc(&app, &h).await;
            }
            kick().await;
            (format!("{} deleted the account {}", a.me.name, t.name), r)
        }
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    };
    if let Err(e) = r {
        return db_err(e);
    }
    tracing::info!("admin: {text}");
    app.event(a.ev(text.clone()).other(&t.name).data(json!({"action": action, "target": id})));
    Json(json!({"ok": true, "text": text})).into_response()
}

#[derive(Deserialize)]
struct CreateIn {
    user: String,
    password: String,
    #[serde(default)]
    role: String,
}

async fn create(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<CreateIn>) -> Response {
    if !auth::valid_user(&f.user) {
        return err(StatusCode::BAD_REQUEST, "A name is 3 to 20 letters, digits or _");
    }
    if !auth::valid_password(&f.password) {
        return err(StatusCode::BAD_REQUEST, "A password is 8 to 128 characters");
    }
    let role = if a.me.role == "super" && f.role == "admin" { "admin" } else { "user" };
    let pw = f.password;
    let hash = tokio::task::spawn_blocking(move || auth::hash_password(&pw)).await.unwrap_or_default();
    match db::create_account(&app.db, &f.user, &hash, role).await {
        Ok(Some(id)) => {
            app.event(a.ev(format!("{} created the account {} ({role})", a.me.name, f.user)).other(&f.user).data(json!({"action": "create", "target": id})));
            Json(json!({"id": id})).into_response()
        }
        Ok(None) => err(StatusCode::CONFLICT, "This name is taken"),
        Err(e) => db_err(e),
    }
}

// --- the event log -----------------------------------------------------------------------

#[derive(Deserialize)]
struct EventsQ {
    /// Kinds, comma-separated.
    kind: Option<String>,
    /// Either side (user or other), ignoring case.
    user: Option<String>,
    game: Option<String>,
    /// Unix ms, inclusive.
    from: Option<i64>,
    to: Option<i64>,
    /// In the text or the data.
    q: Option<String>,
    sort: Option<String>,
    dir: Option<String>,
    page: Option<u64>,
    size: Option<u64>,
}

async fn events(State(app): State<AppRef>, Query(q): Query<EventsQ>) -> Response {
    let mut sel = event::Entity::find();
    let kinds: Vec<&str> = q.kind.as_deref().unwrap_or("").split(',').map(str::trim).filter(|k| !k.is_empty()).collect();
    if !kinds.is_empty() {
        sel = sel.filter(event::Column::Kind.is_in(kinds));
    }
    if let Some(u) = q.user.as_deref().map(str::trim).filter(|u| !u.is_empty()) {
        sel = sel.filter(Condition::any().add(event::Column::User.eq(u)).add(event::Column::Other.eq(u)));
    }
    if let Some(g) = q.game.as_deref().map(str::trim).filter(|g| !g.is_empty()) {
        sel = sel.filter(event::Column::Game.eq(g));
    }
    if let Some(f) = q.from {
        sel = sel.filter(event::Column::At.gte(f));
    }
    if let Some(t) = q.to {
        sel = sel.filter(event::Column::At.lte(t));
    }
    let text: String = q.q.as_deref().unwrap_or("").trim().chars().take(100).collect();
    if !text.is_empty() {
        sel = sel.filter(Condition::any().add(event::Column::Text.contains(&text)).add(event::Column::Data.contains(&text)));
    }
    let o = if q.dir.as_deref() == Some("asc") { Order::Asc } else { Order::Desc };
    sel = match q.sort.as_deref().unwrap_or("") {
        "kind" => sel.order_by(event::Column::Kind, o.clone()),
        "user" => sel.order_by(event::Column::User, o.clone()),
        _ => sel,
    }
    .order_by(event::Column::Id, o);
    let (page, size) = (q.page.unwrap_or(0).min(1_000_000), q.size.unwrap_or(100).clamp(1, 1000));
    // ponytail: COUNT(*) per page; a "more" flag instead if the log reaches tens of millions.
    match page_of(sel, page, size, &app.db).await {
        Ok((rows, total)) => Json(json!({"list": rows.iter().map(event_json).collect::<Vec<_>>(), "total": total, "page": page, "size": size})).into_response(),
        Err(e) => db_err(e),
    }
}

// --- messages ------------------------------------------------------------------------------

#[derive(Deserialize)]
struct ConvQ {
    user: Option<String>,
    page: Option<u64>,
}

/// Conversations, the latest first: {list: [{a, b, count, unread, last}], more}.
async fn conversations(State(app): State<AppRef>, Query(q): Query<ConvQ>) -> Response {
    let page = Ord::min(q.page.unwrap_or(0), 100_000);
    use sea_orm::sea_query::ExprTrait;
    let db = &app.db;
    let r = async {
        let mut sel = message::Entity::find()
            .select_only()
            .column(message::Column::Lo)
            .column(message::Column::Hi)
            .column_as(message::Column::Id.max(), "last")
            .column_as(message::Column::Id.count(), "n")
            .column_as(Expr::expr(Func::sum(Expr::col(message::Column::Seen).eq(false))), "unread")
            .group_by(message::Column::Lo)
            .group_by(message::Column::Hi)
            .order_by_desc(message::Column::Id.max());
        if let Some(u) = q.user.as_deref().map(str::trim).filter(|u| !u.is_empty()) {
            let id = db::id_by_name(db, u).await?.unwrap_or(-1);
            sel = sel.filter(Condition::any().add(message::Column::Lo.eq(id)).add(message::Column::Hi.eq(id)));
        }
        let rows: Vec<(i64, i64, i64, i64, i64)> = sel.offset(page * 50).limit(51).into_tuple().all(db).await?;
        let more = rows.len() > 50;
        let rows = &rows[..rows.len().min(50)];
        let lasts: HashMap<i64, message::Model> =
            message::Entity::find().filter(message::Column::Id.is_in(rows.iter().map(|r| r.2))).all(db).await?.into_iter().map(|m| (m.id, m)).collect();
        let mut ids: Vec<i64> = rows.iter().flat_map(|r| [r.0, r.1]).collect();
        ids.sort_unstable();
        ids.dedup();
        let names: HashMap<i64, String> = accounts_in_order(db, &ids).await?.into_iter().map(|a| (a.id, a.name)).collect();
        let person = |i: i64| json!({"id": i, "user": names.get(&i)});
        let list: Vec<Value> = rows
            .iter()
            .map(|&(lo, hi, last, n, unread)| {
                let l = lasts.get(&last);
                json!({"a": person(lo), "b": person(hi), "count": n, "unread": unread,
                       "last": l.map(|m| json!({"from": m.src, "text": m.text, "at": m.at}))})
            })
            .collect();
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "more": more, "page": page}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

async fn conversation(State(app): State<AppRef>, Path((a, b)): Path<(i64, i64)>) -> Response {
    let db = &app.db;
    let r = async {
        let list: Vec<Value> = message::Entity::find()
            .filter(message::Column::Lo.eq(a.min(b)))
            .filter(message::Column::Hi.eq(a.max(b)))
            .order_by_asc(message::Column::Id)
            .all(db)
            .await?
            .iter()
            .map(|m| json!({"id": m.id, "from": m.src, "text": m.text, "at": m.at, "seen": m.seen}))
            .collect();
        let who = accounts_in_order(db, &[a.min(b), a.max(b)]).await?;
        let people: Vec<Value> = who.iter().map(|x| json!({"id": x.id, "user": x.name, "tag": x.tag})).collect();
        Ok::<_, sea_orm::DbErr>(json!({"people": people, "list": list}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

// --- games ---------------------------------------------------------------------------------

#[derive(Deserialize)]
struct GamesQ {
    user: Option<String>,
    mode: Option<String>,
    reason: Option<String>,
    page: Option<u64>,
    size: Option<u64>,
}

async fn games(State(app): State<AppRef>, Query(q): Query<GamesQ>) -> Response {
    let db = &app.db;
    let r = async {
        let mut sel = played::Entity::find().order_by_desc(played::Column::Ended);
        if let Some(u) = q.user.as_deref().map(str::trim).filter(|u| !u.is_empty()) {
            let id = db::id_by_name(db, u).await?.unwrap_or(-1);
            sel = sel.filter(Condition::any().add(played::Column::P0.eq(id)).add(played::Column::P1.eq(id)));
        }
        if let Some(m) = q.mode.as_deref().filter(|m| !m.is_empty()) {
            sel = sel.filter(played::Column::Mode.eq(m));
        }
        if let Some(m) = q.reason.as_deref().filter(|m| !m.is_empty()) {
            sel = sel.filter(played::Column::Reason.eq(m));
        }
        let (page, size) = (q.page.unwrap_or(0).min(1_000_000), q.size.unwrap_or(50).clamp(1, 500));
        let (rows, total) = page_of(sel, page, size, db).await?;
        let mut ids: Vec<i64> = rows.iter().flat_map(|g| [g.p0, g.p1]).flatten().collect();
        ids.sort_unstable();
        ids.dedup();
        let names: HashMap<i64, String> = accounts_in_order(db, &ids).await?.into_iter().map(|a| (a.id, a.name)).collect();
        let person = |i: Option<i64>| json!({"id": i, "user": i.and_then(|i| names.get(&i))});
        let list: Vec<Value> = rows
            .iter()
            .map(|g| json!({"id": g.id, "mode": g.mode, "players": [person(g.p0), person(g.p1)], "started": g.started, "ended": g.ended,
                            "winner": g.winner, "reason": g.reason}))
            .collect();
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "total": total, "page": page, "size": size}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// One game: its summary (live or finished) and its whole timeline from the event log.
async fn game_page(State(app): State<AppRef>, Path(id): Path<String>) -> Response {
    let db = &app.db;
    let r = async {
        let timeline: Vec<event::Model> =
            event::Entity::find().filter(event::Column::Game.eq(&id)).order_by_asc(event::Column::Id).limit(20_000).all(db).await?;
        let live = app.hub().live_json()["games"].as_array().and_then(|g| g.iter().find(|g| g["id"] == id.as_str()).cloned());
        let done = played::Entity::find_by_id(&id).one(db).await?;
        if live.is_none() && done.is_none() && timeline.is_empty() {
            return Ok(None);
        }
        let matched = timeline.iter().find(|e| e.kind == "match").and_then(|e| e.data.as_deref()).and_then(|d| serde_json::from_str::<Value>(d).ok());
        let summary = match (&live, &done) {
            (Some(g), _) => {
                let mut g = g.clone();
                g["live"] = json!(true);
                g
            }
            (None, Some(g)) => {
                let names = matched.as_ref().map(|m| m["players"].clone()).unwrap_or(json!([null, null]));
                json!({"id": g.id, "mode": g.mode, "live": false, "started": g.started, "ended": g.ended, "winner": g.winner, "reason": g.reason,
                       "players": [{"id": g.p0, "user": names[0]}, {"id": g.p1, "user": names[1]}]})
            }
            (None, None) => json!({"id": id, "live": false, "players": matched.as_ref().map(|m| m["players"].clone())}),
        };
        Ok::<_, sea_orm::DbErr>(Some(json!({"game": summary, "match": matched, "events": timeline.iter().map(event_json).collect::<Vec<_>>()})))
    };
    match r.await {
        Ok(Some(v)) => Json(v).into_response(),
        Ok(None) => err(StatusCode::NOT_FOUND, "No such game"),
        Err(e) => db_err(e),
    }
}

// --- game packs ------------------------------------------------------------------------------

/// `{server: [pack], players: [pack], stats}`; a pack is `packs::admin_json`.
async fn packs_list(State(app): State<AppRef>) -> Response {
    let db = &app.db;
    let r = async {
        let all = pack::Entity::find().order_by_desc(pack::Column::Id).all(db).await?;
        let mut owners: Vec<i64> = all.iter().filter_map(|p| p.owner).collect();
        owners.sort_unstable();
        owners.dedup();
        let names: HashMap<i64, String> = accounts_in_order(db, &owners).await?.into_iter().map(|a| (a.id, a.name)).collect();
        let (server, players): (Vec<&pack::Model>, Vec<&pack::Model>) = all.iter().partition(|p| p.owner.is_none());
        let mut hashes: Vec<(&str, i64)> = all.iter().map(|p| (p.content_hash.as_str(), p.size)).collect();
        hashes.sort_unstable();
        hashes.dedup();
        let stats = json!({
            "server": server.len(), "enabled": server.iter().filter(|p| p.enabled).count(), "players": players.len(),
            "uploaders": owners.len(), "files": hashes.len(), "bytes": hashes.iter().map(|h| h.1).sum::<i64>(),
            "downloads": all.iter().map(|p| p.downloads).sum::<i64>(), "storage": app.store.what,
            "limits": {"player": packs::MAX_PLAYER_PACK, "server": packs::MAX_SERVER_PACK, "per_player": packs::MAX_PER_PLAYER},
        });
        let list = |v: &[&pack::Model]| v.iter().map(|p| packs::admin_json(p, &names)).collect::<Vec<_>>();
        Ok::<_, sea_orm::DbErr>(json!({"server": list(&server), "players": list(&players), "stats": stats}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// The zip as the body: a new server pack (enabled).
async fn packs_upload(State(app): State<AppRef>, Extension(a): Extension<Admin>, headers: HeaderMap, body: Body) -> Response {
    let up = match packs::receive(&headers, body, packs::MAX_SERVER_PACK).await {
        Ok(u) => u,
        Err(e) => return e.into_response(),
    };
    match packs::add(&app, &up.path, &up.hash, up.size, None).await {
        Ok(p) => {
            let text = format!("{} uploaded the server pack {}", a.me.name, packs::label(&p));
            let mut data = packs::event_data(&p);
            data["admin"] = json!(true);
            app.event(Event::new("pack_upload", text).user(a.me.id, &a.me.name).data(data));
            Json(json!({"pack": packs::admin_json(&p, &HashMap::new())})).into_response()
        }
        Err(e) => {
            if e.1 == "invalid" {
                app.event(Event::new("pack_rejected", format!("{} uploaded a pack that was refused: {}", a.me.name, e.2))
                    .user(a.me.id, &a.me.name)
                    .data(json!({"reason": e.2, "content_hash": up.hash, "size": up.size, "admin": true})));
            }
            e.into_response()
        }
    }
}

/// enable | disable | delete (any pack, a player's too).
async fn pack_action(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path((id, action)): Path<(i64, String)>) -> Response {
    let db = &app.db;
    let p = match pack::Entity::find_by_id(id).one(db).await {
        Ok(Some(p)) => p,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such pack"),
        Err(e) => return db_err(e),
    };
    let owner = match p.owner {
        Some(o) => Some(db::name_of(db, o).await.unwrap_or_default()),
        None => None,
    };
    let whose = owner.as_ref().map_or("the server pack".to_string(), |o| format!("{o}'s pack"));
    let (kind, text, r) = match action.as_str() {
        "enable" | "disable" => {
            let on = action == "enable";
            let r = pack::ActiveModel { id: Unchanged(id), enabled: Set(on), ..Default::default() }.update(db).await.map(|_| ());
            (if on { "pack_enable" } else { "pack_disable" }, format!("{} {action}d {whose} {}", a.me.name, packs::label(&p)), r)
        }
        "delete" => {
            let r = pack::Entity::delete_by_id(id).exec(db).await.map(|_| ());
            if r.is_ok() {
                packs::gc(&app, &p.content_hash).await;
            }
            ("pack_delete", format!("{} deleted {whose} {}", a.me.name, packs::label(&p)), r)
        }
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    };
    if let Err(e) = r {
        return db_err(e);
    }
    let mut data = packs::event_data(&p);
    data["admin"] = json!(true);
    let mut ev = Event::new(kind, text.clone()).user(a.me.id, &a.me.name).data(data);
    if let Some(o) = &owner {
        ev = ev.other(o);
    }
    app.event(ev);
    if let Some(o) = p.owner {
        if let Ok(m) = packs::packs_msg(db, o).await {
            app.hub().send(o, &m);
        }
    }
    Json(json!({"ok": true, "text": text})).into_response()
}
