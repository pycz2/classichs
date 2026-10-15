//! The admin panel at /admin: server-rendered HTML, its own login (superuser and admins),
//! an HttpOnly SameSite=Strict session cookie and a CSRF token on every form.

use crate::auth;
use crate::db::{self, Account};
use crate::ranked;
use crate::AppRef;
use axum::extract::{ConnectInfo, Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Form, Router};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use rusqlite::params;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::Instant;

const COOKIE: &str = "chs_admin";
const PRE_COOKIE: &str = "chs_pre";
const SESSION_SECS: i64 = 12 * 3600;
const PAGE: i64 = 50;

type F = Form<HashMap<String, String>>;

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin", get(|| async { Redirect::to("/admin/accounts") }))
        .route("/admin/login", get(login_page).post(login))
        .route("/admin/logout", post(logout))
        .route("/admin/accounts", get(accounts))
        .route("/admin/accounts/{id}", get(account))
        .route("/admin/accounts/{id}/delete", get(delete_page))
        .route("/admin/accounts/{id}/{action}", post(account_action))
        .route("/admin/create", get(create_page).post(create))
        .route("/admin/games", get(games))
}

pub fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            '\'' => o.push_str("&#39;"),
            _ => o.push(c),
        }
    }
    o
}

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
fn set_cookie(headers: &HeaderMap, name: &str, value: &str, max_age: i64) -> String {
    let secure = headers.get("x-forwarded-proto").is_some_and(|v| v.as_bytes() == b"https");
    format!(
        "{name}={value}; Path=/admin; HttpOnly; SameSite=Strict; Max-Age={max_age}{}",
        if secure { "; Secure" } else { "" }
    )
}

struct Admin {
    me: Account,
    csrf: String,
}

async fn admin(app: &AppRef, headers: &HeaderMap) -> Option<Admin> {
    let token = cookie(headers, COOKIE)?;
    let (me, csrf) = app.db.run(move |c| db::session(c, &token, "admin")).await.ok()??;
    matches!(me.role.as_str(), "admin" | "super").then_some(Admin { me, csrf })
}

fn csrf_ok(a: &Admin, f: &HashMap<String, String>) -> bool {
    f.get("csrf").is_some_and(|t| auth::ct_eq(t.as_bytes(), a.csrf.as_bytes()))
}

fn forbidden(text: &str) -> Response {
    (StatusCode::FORBIDDEN, Html(page("Forbidden", None, &format!("<p class=err>{}</p>", esc(text))))).into_response()
}

const CSS: &str = "body{font:15px/1.45 system-ui,sans-serif;margin:0;background:#f6f5f2;color:#222}
header{background:#2b2622;color:#f3e6c8;padding:10px 20px;display:flex;gap:18px;align-items:center;flex-wrap:wrap}
header a{color:#f3e6c8}header form{margin-left:auto}main{padding:20px;max-width:1100px}
table{border-collapse:collapse;width:100%;background:#fff}td,th{border:1px solid #ddd;padding:6px 8px;text-align:left}
th{background:#eee}form.inline{display:inline}input,select,button{font:inherit;padding:4px 8px;margin:2px}
.err{color:#a00}.ok{color:#070}.box{background:#fff;border:1px solid #ddd;padding:12px 16px;margin:12px 0}
button.danger{background:#a00;color:#fff;border:1px solid #700}";

fn page(title: &str, a: Option<&Admin>, body: &str) -> String {
    let nav = match a {
        Some(a) => format!(
            "<a href=/admin/accounts>Accounts</a><a href=/admin/create>Create account</a><a href=/admin/games>Live games</a>\
             <form method=post action=/admin/logout class=inline>{} <input type=hidden name=csrf value=\"{}\"><button>Log out</button></form>",
            esc(&a.me.name),
            esc(&a.csrf)
        ),
        None => String::new(),
    };
    format!(
        "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">\
         <title>{} · Classic HS admin</title><style>{CSS}</style></head><body><header><b>Classic HS admin</b>{nav}</header>\
         <main><h1>{}</h1>{body}</main></body></html>",
        esc(title),
        esc(title)
    )
}

fn hidden(a: &Admin) -> String {
    format!("<input type=hidden name=csrf value=\"{}\">", esc(&a.csrf))
}

fn rank_text(a: &Account) -> String {
    if a.rank.legend() {
        "Legend".into()
    } else {
        format!("{} ({}★)", a.rank.rank, a.rank.stars)
    }
}

async fn login_page(headers: HeaderMap) -> Response {
    let pre = random();
    let body = format!(
        "<form method=post action=/admin/login class=box><input type=hidden name=csrf value=\"{pre}\">\
         <p><label>Name <input name=user required maxlength=20 autocomplete=username></label></p>\
         <p><label>Password <input name=password type=password required maxlength=128 autocomplete=current-password></label></p>\
         <button>Log in</button></form>"
    );
    ([(header::SET_COOKIE, set_cookie(&headers, PRE_COOKIE, &pre, 3600))], Html(page("Log in", None, &body))).into_response()
}

async fn login(State(app): State<AppRef>, ConnectInfo(addr): ConnectInfo<SocketAddr>, headers: HeaderMap, Form(f): F) -> Response {
    let pre = cookie(&headers, PRE_COOKIE).unwrap_or_default();
    if pre.is_empty() || !f.get("csrf").is_some_and(|t| auth::ct_eq(t.as_bytes(), pre.as_bytes())) {
        return forbidden("The form expired: open the login page again.");
    }
    let ip = crate::client_ip(&app, &headers, addr);
    let user = f.get("user").cloned().unwrap_or_default();
    let password = f.get("password").cloned().unwrap_or_default();
    let fail = |text: &str| {
        Html(page("Log in", None, &format!("<p class=err>{}</p><p><a href=/admin/login>Try again</a></p>", esc(text)))).into_response()
    };
    if !app.login_allowed(&format!("admin:{ip}")) || !app.login_allowed(&format!("user:{}", user.to_lowercase())) {
        return fail("Too many attempts: wait a minute.");
    }
    if !auth::valid_user(&user) || password.len() > 1024 {
        return fail("Wrong name or password.");
    }
    let found = app.db.run(move |c| db::account_by_name(c, &user)).await.ok().flatten();
    let ok = tokio::task::spawn_blocking(move || {
        let stored = found.as_ref().map_or(auth::dummy_hash(), |(_, h)| h.as_str());
        let ok = auth::verify_password(&password, stored);
        found.filter(|(a, _)| ok && !a.suspended && matches!(a.role.as_str(), "admin" | "super")).map(|(a, _)| a)
    })
    .await
    .ok()
    .flatten();
    let Some(a) = ok else { return fail("Wrong name or password.") };
    let csrf = random();
    let Ok(token) = app.db.run(move |c| db::new_session(c, a.id, "admin", SESSION_SECS, &csrf)).await else {
        return fail("Server error.");
    };
    (
        [(header::SET_COOKIE, set_cookie(&headers, COOKIE, &token, SESSION_SECS))],
        Redirect::to("/admin/accounts"),
    )
        .into_response()
}

async fn logout(State(app): State<AppRef>, headers: HeaderMap, Form(f): F) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    if !csrf_ok(&a, &f) {
        return forbidden("Bad CSRF token.");
    }
    if let Some(t) = cookie(&headers, COOKIE) {
        let _ = app.db.run(move |c| db::drop_session(c, &t)).await;
    }
    ([(header::SET_COOKIE, set_cookie(&headers, COOKIE, "", 0))], Redirect::to("/admin/login")).into_response()
}

async fn accounts(State(app): State<AppRef>, headers: HeaderMap, Query(q): Query<HashMap<String, String>>) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    let search = q.get("q").cloned().unwrap_or_default().chars().take(40).collect::<String>();
    let pg: i64 = q.get("page").and_then(|p| p.parse().ok()).unwrap_or(0).clamp(0, 1_000_000);
    let s = search.clone();
    let rows = app
        .db
        .run(move |c| {
            let mut st = c.prepare(&format!(
                "SELECT {} FROM accounts WHERE ?1 = '' OR instr(lower(name), lower(?1)) > 0 OR instr(lower(coalesce(tag, '')), lower(?1)) > 0
                 ORDER BY id DESC LIMIT ?2 OFFSET ?3",
                db::ACCOUNT_COLS
            ))?;
            let rows = st.query_map(params![s, PAGE + 1, pg * PAGE], db::account_row)?;
            rows.collect::<rusqlite::Result<Vec<_>>>()
        })
        .await
        .unwrap_or_default();
    let more = rows.len() as i64 > PAGE;
    let hub = app.hub();
    let mut body = format!(
        "<form method=get class=box><input name=q value=\"{}\" placeholder=\"Name or tag\"><button>Search</button></form>\
         <table><tr><th>User</th><th>Tag</th><th>Role</th><th>Created</th><th>Last seen</th><th>Rank</th><th>Status</th></tr>",
        esc(&search)
    );
    for r in rows.iter().take(PAGE as usize) {
        body += &format!(
            "<tr><td><a href=/admin/accounts/{}>{}</a></td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
            r.id,
            esc(&r.name),
            esc(r.tag.as_deref().unwrap_or("")),
            esc(&r.role),
            ranked::date(r.created),
            ranked::date(r.last_seen),
            rank_text(r),
            if r.suspended { "<b class=err>suspended</b>" } else { hub.status(r.id) }
        );
    }
    drop(hub);
    body += "</table><p>";
    let qs = |p: i64| format!("/admin/accounts?q={}&page={p}", url_encode(&search));
    if pg > 0 {
        body += &format!("<a href=\"{}\">← Previous</a> ", esc(&qs(pg - 1)));
    }
    if more {
        body += &format!("<a href=\"{}\">Next →</a>", esc(&qs(pg + 1)));
    }
    body += "</p>";
    Html(page("Accounts", Some(&a), &body)).into_response()
}

fn url_encode(s: &str) -> String {
    s.bytes()
        .map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") })
        .collect()
}

/// May this admin change that account? Superusers are changed from the command line only.
fn may_manage(a: &Admin, t: &Account) -> bool {
    t.role != "super" && t.id != a.me.id && (a.me.role == "super" || t.role == "user")
}

async fn load(app: &AppRef, id: i64) -> Option<Account> {
    app.db.run(move |c| db::account_by_id(c, id)).await.ok().flatten()
}

async fn account(State(app): State<AppRef>, headers: HeaderMap, Path(id): Path<i64>, Query(q): Query<HashMap<String, String>>) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    let Some(t) = load(&app, id).await else { return (StatusCode::NOT_FOUND, Html(page("No such account", Some(&a), ""))).into_response() };
    let status = app.hub().status(t.id);
    let mut body = String::new();
    if let Some(m) = q.get("done") {
        body += &format!("<p class=ok>{}</p>", esc(m));
    }
    body += &format!(
        "<div class=box><p>Name: <b>{}</b> · tag: {} · role: {}</p><p>Created {} · last seen {} · now {}</p>\
         <p>Rank {} (streak {}) · season {} · ranked MMR {:.0} · casual MMR {:.0}</p><p>{}</p></div>",
        esc(&t.name),
        esc(t.tag.as_deref().unwrap_or("—")),
        esc(&t.role),
        ranked::date(t.created),
        ranked::date(t.last_seen),
        status,
        rank_text(&t),
        t.rank.streak,
        ranked::season_name(t.season),
        t.ranked_mmr,
        t.casual_mmr,
        if t.suspended { "<b class=err>Suspended</b>" } else { "Active" }
    );
    if may_manage(&a, &t) {
        let h = hidden(&a);
        let act = |action: &str, label: &str| {
            format!("<form method=post action=/admin/accounts/{}/{action} class=inline>{h}<button>{label}</button></form>", t.id)
        };
        body += "<div class=box>";
        body += &if t.suspended { act("unsuspend", "Unsuspend") } else { act("suspend", "Suspend") };
        body += &format!(" <a href=/admin/accounts/{}/delete>Delete…</a></div>", t.id);
        body += &format!(
            "<form method=post action=/admin/accounts/{}/password class=box>{h}<label>New password \
             <input name=password type=password minlength=8 maxlength=128 required autocomplete=new-password></label>\
             <button>Reset password</button></form>",
            t.id
        );
        if a.me.role == "super" {
            let other = if t.role == "admin" { "user" } else { "admin" };
            body += &format!(
                "<form method=post action=/admin/accounts/{}/role class=box>{h}<input type=hidden name=role value={other}>\
                 <button>Make {other}</button></form>",
                t.id
            );
        }
    }
    Html(page(&format!("Account {}", t.name), Some(&a), &body)).into_response()
}

async fn delete_page(State(app): State<AppRef>, headers: HeaderMap, Path(id): Path<i64>) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    let Some(t) = load(&app, id).await else { return (StatusCode::NOT_FOUND, Html(page("No such account", Some(&a), ""))).into_response() };
    if !may_manage(&a, &t) {
        return forbidden("You may not change this account.");
    }
    let body = format!(
        "<form method=post action=/admin/accounts/{}/delete class=box>{}<p>Delete <b>{}</b> with friends, messages and the Arena run? \
         This cannot be undone.</p><p><label>Type the name to confirm <input name=confirm required></label></p>\
         <button class=danger>Delete</button> <a href=/admin/accounts/{}>Cancel</a></form>",
        t.id,
        hidden(&a),
        esc(&t.name),
        t.id
    );
    Html(page("Delete account", Some(&a), &body)).into_response()
}

async fn account_action(
    State(app): State<AppRef>,
    headers: HeaderMap,
    Path((id, action)): Path<(i64, String)>,
    Form(f): F,
) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    if !csrf_ok(&a, &f) {
        return forbidden("Bad CSRF token.");
    }
    let Some(t) = load(&app, id).await else { return (StatusCode::NOT_FOUND, Html(page("No such account", Some(&a), ""))).into_response() };
    if !may_manage(&a, &t) {
        return forbidden("You may not change this account.");
    }
    let back = |msg: &str| Redirect::to(&format!("/admin/accounts/{id}?done={}", url_encode(msg))).into_response();
    let kick = |app: &AppRef| app.hub().detach(id, None);
    match action.as_str() {
        "suspend" | "unsuspend" => {
            let s = action == "suspend";
            let r = app
                .db
                .run(move |c| {
                    c.execute("UPDATE accounts SET suspended = ?1 WHERE id = ?2", params![s, id])?;
                    if s {
                        c.execute("DELETE FROM sessions WHERE account = ?1", [id])?;
                    }
                    Ok(())
                })
                .await;
            if s {
                kick(&app);
            }
            tracing::info!("admin {}: {action} {}", a.me.name, t.name);
            if r.is_ok() { back(if s { "Suspended" } else { "Unsuspended" }) } else { forbidden("Server error.") }
        }
        "password" => {
            let pw = f.get("password").cloned().unwrap_or_default();
            if !auth::valid_password(&pw) {
                return back("A password is 8 to 128 characters: not changed");
            }
            let hash = tokio::task::spawn_blocking(move || auth::hash_password(&pw)).await.unwrap_or_default();
            let _ = app.db.run(move |c| db::set_password(c, id, &hash)).await;
            kick(&app);
            tracing::info!("admin {}: reset the password of {}", a.me.name, t.name);
            back("Password reset; the account was logged out")
        }
        "role" if a.me.role == "super" => {
            let role = if f.get("role").map(String::as_str) == Some("admin") { "admin" } else { "user" };
            let _ = app
                .db
                .run(move |c| {
                    c.execute("UPDATE accounts SET role = ?1 WHERE id = ?2", params![role, id])?;
                    c.execute("DELETE FROM sessions WHERE account = ?1 AND kind = 'admin'", [id])
                })
                .await;
            tracing::info!("admin {}: {} is now {role}", a.me.name, t.name);
            back(&format!("Role: {role}"))
        }
        "delete" => {
            if f.get("confirm") != Some(&t.name) {
                return Redirect::to(&format!("/admin/accounts/{id}/delete")).into_response();
            }
            let _ = app.db.run(move |c| c.execute("DELETE FROM accounts WHERE id = ?1", [id])).await;
            kick(&app);
            tracing::info!("admin {}: deleted {}", a.me.name, t.name);
            Redirect::to("/admin/accounts").into_response()
        }
        _ => (StatusCode::NOT_FOUND, "no such action").into_response(),
    }
}

async fn create_page(State(app): State<AppRef>, headers: HeaderMap) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    Html(page("Create account", Some(&a), &create_form(&a, ""))).into_response()
}

fn create_form(a: &Admin, msg: &str) -> String {
    let role = if a.me.role == "super" {
        "<p><label>Role <select name=role><option>user</option><option>admin</option></select></label></p>"
    } else {
        ""
    };
    format!(
        "{msg}<form method=post action=/admin/create class=box>{}\
         <p><label>Name <input name=user required minlength=3 maxlength=20 pattern=\"[A-Za-z0-9_]+\"></label></p>\
         <p><label>Password <input name=password type=password required minlength=8 maxlength=128 autocomplete=new-password></label></p>\
         {role}<button>Create</button></form>",
        hidden(a)
    )
}

async fn create(State(app): State<AppRef>, headers: HeaderMap, Form(f): F) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    if !csrf_ok(&a, &f) {
        return forbidden("Bad CSRF token.");
    }
    let user = f.get("user").cloned().unwrap_or_default();
    let pw = f.get("password").cloned().unwrap_or_default();
    let err = |m: &str| Html(page("Create account", Some(&a), &create_form(&a, &format!("<p class=err>{}</p>", esc(m))))).into_response();
    if !auth::valid_user(&user) {
        return err("A name is 3 to 20 letters, digits or _.");
    }
    if !auth::valid_password(&pw) {
        return err("A password is 8 to 128 characters.");
    }
    let role = if a.me.role == "super" && f.get("role").map(String::as_str) == Some("admin") { "admin" } else { "user" };
    let hash = tokio::task::spawn_blocking(move || auth::hash_password(&pw)).await.unwrap_or_default();
    let u = user.clone();
    match app.db.run(move |c| db::create_account(c, &u, &hash, role)).await {
        Ok(Some(id)) => {
            tracing::info!("admin {}: created {user} ({role})", a.me.name);
            Redirect::to(&format!("/admin/accounts/{id}")).into_response()
        }
        Ok(None) => err("This name is taken."),
        Err(_) => err("Server error."),
    }
}

async fn games(State(app): State<AppRef>, headers: HeaderMap) -> Response {
    let Some(a) = admin(&app, &headers).await else { return Redirect::to("/admin/login").into_response() };
    let hub = app.hub();
    let mut body = String::from("<h2>Games</h2><table><tr><th>Game</th><th>Mode</th><th>Players (host first)</th><th>Turn</th><th>Current</th><th>Started</th></tr>");
    let mut games: Vec<_> = hub.games.iter().collect();
    games.sort_by_key(|(_, g)| g.started);
    for (id, g) in games {
        body += &format!(
            "<tr><td>{}</td><td>{}</td><td><a href=/admin/accounts/{}>{}</a> vs <a href=/admin/accounts/{}>{}</a></td><td>{}</td><td>{}</td><td>{}</td></tr>",
            esc(id),
            g.mode.as_str(),
            g.ids[0],
            esc(&g.names[0]),
            g.ids[1],
            esc(&g.names[1]),
            g.turn,
            esc(g.names.get(g.current as usize).map_or("", |s| s.as_str())),
            ranked::date(g.started)
        );
    }
    body += "</table><h2>Queues</h2><table><tr><th>Player</th><th>Mode</th><th>Waited</th><th>Window</th></tr>";
    let now = Instant::now();
    for (id, s) in &hub.queue {
        let w = now.duration_since(s.since).as_secs();
        body += &format!(
            "<tr><td><a href=/admin/accounts/{id}>{}</a></td><td>{}</td><td>{w} s</td><td>{}</td></tr>",
            esc(&s.name),
            s.mode.as_str(),
            ranked::shown_window(s.mode, &s.key, w)
        );
    }
    body += &format!("</table><p>{} players online.</p>", hub.conns.len());
    drop(hub);
    Html(page("Live games", Some(&a), &body)).into_response()
}
