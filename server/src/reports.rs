//! Problem reports from the game (0.74; docs/superpowers/specs/2026-11-26-roles-subservers-design.md
//! §3 and the owner's later requests): a player sends a text with the screen's picture and a voice
//! message (`POST /reports` with the game session token, as the packs' uploads). A report is a thread:
//! the admins answer in it, the player too; its state is open, resolved or rejected (the player sees
//! open or closed). The admin panel lists them, shows one with its thread, answers, merges
//! duplicates, deletes, purges the old ones and exports them (a zip or plain JSON; one report also as
//! Markdown for an AI agent). server/README.md, "Problem reports".

use crate::admin::{db_err, err, page_of, Admin};
use crate::db::Account;
use crate::entity::{account, replay, report, report_message as msg};
use crate::events::Event;
use crate::packs::{self, PackErr, TokenQ};
use crate::ranked::now;
use crate::ws::accounts_in_order;
use crate::AppRef;
use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use sea_orm::sea_query::Expr;
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Select, Set};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fmt::Write as _;
use std::io::{Seek, Write};

/// A report's or a message's text, in characters.
pub const MAX_TEXT: usize = 4000;
/// The picture (PNG) and the stored voice message (Ogg Opus), in bytes; the voice's length.
pub const MAX_SCREEN: usize = 10 << 20;
pub const MAX_VOICE: usize = 1 << 20;
pub const MAX_VOICE_SECS: usize = 60;
/// Reports, and answers in their threads, a player may send in an hour.
pub const PER_HOUR: u64 = 5;
pub const REPLIES_PER_HOUR: u64 = 20;
/// The request: the picture and a 60 s WAV (16 kHz mono, what the game records) in base64, and the text.
const MAX_BODY: usize = 20 << 20;
pub const STATES: [&str; 3] = ["open", "resolved", "rejected"];
/// Finished games of the player kept with a report (and the current one).
const LAST_GAMES: u64 = 5;

/// The one permission check of the reports (`reports.view`, `reports.manage`, `reports.export` in
/// a sub-server).
async fn may(app: &AppRef, account: i64, perm: &str, subserver: i64) -> bool {
    crate::perm::has(app, account, perm, subserver).await
}

/// The sub-server whose reports an admin's request is about: his panel's, or (the super admin's filter,
/// `subservers.view`) the one asked for.
fn sub_of(me: &Admin, asked: Option<i64>) -> i64 {
    asked.filter(|_| me.can("subservers.view")).unwrap_or(me.scope.id)
}

/// The file of a report in the store.
fn path(id: i64, file: &str) -> String {
    format!("reports/{id}/{file}")
}

/// What the player sees of a state.
fn player_state(s: &str) -> &'static str {
    if s == "open" { "open" } else { "closed" }
}

// --- the players' side ---------------------------------------------------------------------------

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/reports", get(mine).post(send).options(packs::preflight))
        .route("/reports/{id}", get(thread).post(reply).options(packs::preflight))
        .layer(DefaultBodyLimit::max(MAX_BODY))
        .layer(axum::middleware::map_response(packs::cors))
}

#[derive(Deserialize)]
struct SendIn {
    #[serde(default)]
    text: String,
    /// Unix seconds on the player's device.
    #[serde(default)]
    written_at: i64,
    #[serde(default)]
    context: Value,
    /// base64: a PNG; a WAV (16-bit mono PCM at 8, 12, 16, 24 or 48 kHz) or an Ogg Opus file.
    #[serde(default)]
    screen: String,
    #[serde(default)]
    voice: String,
}

fn refuse(status: StatusCode, code: &'static str, text: impl Into<String>) -> PackErr {
    PackErr::new(status, code, text)
}

fn bad(code: &'static str, text: impl Into<String>) -> PackErr {
    refuse(StatusCode::BAD_REQUEST, code, text)
}

fn store_err(e: impl std::fmt::Display) -> PackErr {
    tracing::error!("reports: storage: {e}");
    refuse(StatusCode::INTERNAL_SERVER_ERROR, "storage", "The report storage failed")
}

/// A WAV's 16-bit mono PCM samples and rate.
fn wav(b: &[u8]) -> Result<(Vec<i16>, u32), String> {
    if b.len() < 12 || &b[..4] != b"RIFF" || &b[8..12] != b"WAVE" {
        return Err("not a WAV".into());
    }
    let (mut at, mut fmt) = (12, None);
    while at + 8 <= b.len() {
        let id = &b[at..at + 4];
        let n = u32::from_le_bytes(b[at + 4..at + 8].try_into().unwrap()) as usize;
        let body = &b[at + 8..(at + 8).saturating_add(n).min(b.len())];
        if id == b"fmt " && body.len() >= 16 {
            let u16_at = |i: usize| u16::from_le_bytes([body[i], body[i + 1]]);
            fmt = Some((u16_at(0), u16_at(2), u32::from_le_bytes(body[4..8].try_into().unwrap()), u16_at(14)));
        } else if id == b"data" {
            return match fmt {
                Some((1, 1, rate, 16)) => Ok((body.chunks_exact(2).map(|s| i16::from_le_bytes([s[0], s[1]])).collect(), rate)),
                Some((f, ch, rate, bits)) => Err(format!("a WAV of format {f}, {ch} channels, {rate} Hz, {bits} bits: 16-bit mono PCM only")),
                None => Err("a WAV without its format".into()),
            };
        }
        at = at.saturating_add(8 + n + n % 2);
    }
    Err("a WAV without its data".into())
}

/// The voice message as Ogg Opus: an Ogg Opus file as it is, a WAV encoded; at most
/// MAX_VOICE_SECS (and a bit) and MAX_VOICE bytes.
pub fn voice_ogg(b: Vec<u8>) -> Result<Vec<u8>, PackErr> {
    let too_long = || bad("bad_voice", format!("A voice message is {MAX_VOICE_SECS} s at most"));
    let ogg = if b.starts_with(b"OggS") {
        b
    } else {
        let (pcm, rate) = wav(&b).map_err(|e| bad("bad_voice", e))?;
        if pcm.len() > (MAX_VOICE_SECS + 1) * rate as usize {
            return Err(too_long());
        }
        classichs_opus::encode(&pcm, rate).map_err(|e| bad("bad_voice", e))?
    };
    if ogg.len() > MAX_VOICE {
        return Err(refuse(StatusCode::PAYLOAD_TOO_LARGE, "too_large", format!("A voice message is {} MB at most", MAX_VOICE >> 20)));
    }
    let pcm = classichs_opus::decode(&ogg).map_err(|e| bad("bad_voice", format!("Not a voice message: {e}")))?;
    if pcm.samples.len() / pcm.channels as usize > (MAX_VOICE_SECS + 1) * 48000 {
        return Err(too_long());
    }
    Ok(ogg)
}

/// A base64 attachment ("" = none), at most `limit` bytes.
fn attachment(b64: &str, limit: usize, code: &'static str, what: &str) -> Result<Vec<u8>, PackErr> {
    if b64.len() > limit / 3 * 4 + 8 {
        return Err(refuse(StatusCode::PAYLOAD_TOO_LARGE, "too_large", format!("The {what} is {} MB at most", limit >> 20)));
    }
    STANDARD.decode(b64.trim()).map_err(|_| bad(code, format!("The {what} is not base64")))
}

/// A PNG attachment ("" = none).
fn picture(b64: &str) -> Result<Vec<u8>, PackErr> {
    let screen = attachment(b64, MAX_SCREEN, "bad_screen", "picture")?;
    if !screen.is_empty() && !screen.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err(bad("bad_screen", "The picture is not a PNG"));
    }
    Ok(screen)
}

fn text_of(t: &str) -> Result<String, PackErr> {
    let t = t.trim();
    if t.is_empty() || t.chars().count() > MAX_TEXT {
        return Err(bad("bad_text", format!("A report is 1 to {MAX_TEXT} characters")));
    }
    Ok(t.to_string())
}

async fn send(State(app): State<AppRef>, scope: crate::scope::Scope, Query(q): Query<TokenQ>, headers: HeaderMap, body: Bytes) -> Result<Response, PackErr> {
    let a = packs::player(&app, &headers, &q).await?;
    let f: SendIn = serde_json::from_slice(&body).map_err(|e| bad("bad_body", format!("Not a report: {e}")))?;
    let text = text_of(&f.text)?;
    let screen = picture(&f.screen)?;
    // a 60 s WAV at 16 kHz is about 1.9 MB: the stored Ogg is checked against MAX_VOICE
    let voice = attachment(&f.voice, 3 * MAX_VOICE, "bad_voice", "voice message")?;
    let voice = if voice.is_empty() { None } else { Some(tokio::task::spawn_blocking(move || voice_ogg(voice)).await.map_err(store_err)??) };
    let context = if f.context.is_object() { f.context } else { json!({}) };
    let context_text = context.to_string();
    if context_text.len() > 4000 {
        return Err(bad("bad_context", "The report's context is too long"));
    }
    let received = now();
    let (subserver, db) = (scope.id, &app.db);
    let recent = report::Entity::find()
        .filter(report::Column::Account.eq(a.id))
        .filter(report::Column::ReceivedAt.gt(received - 3600))
        .count(db)
        .await?;
    if recent >= PER_HOUR {
        return Err(refuse(StatusCode::TOO_MANY_REQUESTS, "too_many", format!("{PER_HOUR} reports an hour at most: try later")));
    }
    // the game it was sent from (the server's own, else the one the game says), then the last finished ones
    let live = app.hub().in_game.get(&a.id).map(|(g, _)| g.clone());
    let current = live.or_else(|| context["game"].as_str().filter(|g| !g.is_empty() && g.len() <= 64).map(String::from));
    let last: Vec<String> = replay::Entity::find()
        .select_only()
        .column(replay::Column::Game)
        .filter(Condition::any().add(replay::Column::P0.eq(a.id)).add(replay::Column::P1.eq(a.id)))
        .filter(replay::Column::Game.ne(current.clone().unwrap_or_default()))
        .order_by_desc(replay::Column::Ended)
        .limit(LAST_GAMES)
        .into_tuple()
        .all(db)
        .await?;
    let games: Vec<String> = current.into_iter().chain(last).collect();
    let version: String = context["version"].as_str().unwrap_or_default().chars().take(40).collect();
    let row = report::ActiveModel {
        subserver: Set(subserver),
        account: Set(a.id),
        written_at: Set(if f.written_at > 0 { f.written_at } else { received }),
        received_at: Set(received),
        last_at: Set(received),
        text: Set(text.clone()),
        version: Set(version),
        context: Set(context_text),
        games: Set(json!(games).to_string()),
        screen: Set(!screen.is_empty()),
        voice: Set(voice.is_some()),
        state: Set("open".into()),
        note: Set(String::new()),
        merged_into: Set(None),
        admin_opened: Set(false),
        admin_unread: Set(true),
        player_unread: Set(false),
        ..Default::default()
    };
    let id = report::Entity::insert(row).exec(db).await?.last_insert_id;
    let stored = async {
        if !screen.is_empty() {
            app.store.put_path(&path(id, "screen.png"), screen).await?;
        }
        if let Some(v) = voice {
            app.store.put_path(&path(id, "voice.ogg"), v).await?;
        }
        Ok::<_, crate::storage::Error>(())
    }
    .await;
    if let Err(e) = stored {
        remove(&app, id).await;
        return Err(store_err(e));
    }
    let short: String = text.chars().take(120).collect();
    app.event(Event::new("report", format!("{} sent a problem report: {short}", a.name)).user(a.id, &a.name).data(json!({"report": id})));
    Ok((StatusCode::CREATED, Json(json!({"report": {"id": id}}))).into_response())
}

/// The player's threads with something new for him (answers, state changes).
async fn unread_of(app: &AppRef, account: i64) -> Result<u64, sea_orm::DbErr> {
    report::Entity::find().filter(report::Column::Account.eq(account)).filter(report::Column::PlayerUnread.eq(true)).count(&app.db).await
}

/// `reports_unread {n}` to the player's game, when online.
async fn push_unread(app: &AppRef, account: i64) {
    if let Ok(n) = unread_of(app, account).await {
        app.hub().send(account, &json!({"t": "reports_unread", "n": n}));
    }
}

/// `{list: [{id, text, state, received_at, last_at, unread, messages}], unread}`: the player's reports,
/// the latest activity first.
async fn mine(State(app): State<AppRef>, scope: crate::scope::Scope, Query(q): Query<TokenQ>, headers: HeaderMap) -> Result<Response, PackErr> {
    let a = packs::player(&app, &headers, &q).await?;
    let rows = report::Entity::find().filter(report::Column::Subserver.eq(scope.id)).filter(report::Column::Account.eq(a.id)).order_by_desc(report::Column::LastAt).limit(200).all(&app.db).await?;
    let ids: Vec<i64> = rows.iter().map(|r| r.id).collect();
    let counts: HashMap<i64, i64> = msg::Entity::find()
        .select_only()
        .column(msg::Column::Report)
        .column_as(msg::Column::Id.count(), "n")
        .filter(msg::Column::Report.is_in(ids))
        .group_by(msg::Column::Report)
        .into_tuple()
        .all(&app.db)
        .await?
        .into_iter()
        .collect();
    let list: Vec<Value> = rows
        .iter()
        .map(|r| json!({"id": r.id, "text": r.text, "state": player_state(&r.state), "received_at": r.received_at, "last_at": r.last_at,
                        "unread": r.player_unread, "messages": 1 + counts.get(&r.id).copied().unwrap_or(0)}))
        .collect();
    let unread = rows.iter().filter(|r| r.player_unread).count();
    Ok(Json(json!({"list": list, "unread": unread})).into_response())
}

/// A message as the player sees it (the admins' names are theirs: the player knows who answered).
fn player_msg(m: &msg::Model) -> Value {
    json!({"id": m.id, "from": if m.admin { "admin" } else { "you" }, "name": m.name, "text": m.text, "at": m.at, "screen": m.screen})
}

/// The player's own report (else 404).
async fn own(app: &AppRef, account: i64, id: i64) -> Result<report::Model, PackErr> {
    match report::Entity::find_by_id(id).one(&app.db).await? {
        Some(r) if r.account == account => Ok(r),
        _ => Err(refuse(StatusCode::NOT_FOUND, "not_found", "No such report")),
    }
}

/// One of the player's threads; opening it clears its mark.
async fn thread(State(app): State<AppRef>, Path(id): Path<i64>, Query(q): Query<TokenQ>, headers: HeaderMap) -> Result<Response, PackErr> {
    let a = packs::player(&app, &headers, &q).await?;
    let r = own(&app, a.id, id).await?;
    let msgs = msg::Entity::find().filter(msg::Column::Report.eq(id)).order_by_asc(msg::Column::Id).all(&app.db).await?;
    if r.player_unread {
        report::Entity::update_many().col_expr(report::Column::PlayerUnread, Expr::value(false)).filter(report::Column::Id.eq(id)).exec(&app.db).await?;
        push_unread(&app, a.id).await;
    }
    let first = json!({"id": 0, "from": "you", "name": a.name, "text": r.text, "at": r.received_at, "screen": r.screen});
    let messages: Vec<Value> = std::iter::once(first).chain(msgs.iter().map(player_msg)).collect();
    Ok(Json(json!({"id": r.id, "state": player_state(&r.state), "text": r.text, "received_at": r.received_at, "last_at": r.last_at, "messages": messages}))
        .into_response())
}

/// Adds a message to a report's thread (its picture into the store), marks it for the other side.
async fn add_message(app: &AppRef, r: &report::Model, who: &Account, admin: bool, text: &str, screen: Vec<u8>) -> Result<msg::Model, PackErr> {
    let at = now();
    let m = msg::ActiveModel {
        report: Set(r.id),
        account: Set(Some(who.id)),
        name: Set(who.name.clone()),
        admin: Set(admin),
        text: Set(text.into()),
        at: Set(at),
        screen: Set(!screen.is_empty()),
        ..Default::default()
    }
    .insert(&app.db)
    .await?;
    if !screen.is_empty() {
        if let Err(e) = app.store.put_path(&path(r.id, &format!("m{}.png", m.id)), screen).await {
            let _ = msg::Entity::delete_by_id(m.id).exec(&app.db).await;
            return Err(store_err(e));
        }
    }
    let mut u = report::Entity::update_many().col_expr(report::Column::LastAt, Expr::value(at)).filter(report::Column::Id.eq(r.id));
    u = if admin { u.col_expr(report::Column::PlayerUnread, Expr::value(true)) } else { u.col_expr(report::Column::AdminUnread, Expr::value(true)) };
    u.exec(&app.db).await?;
    Ok(m)
}

#[derive(Deserialize)]
struct ReplyIn {
    #[serde(default)]
    text: String,
    #[serde(default)]
    screen: String,
}

/// The player answers in his thread (a closed one too: the admins see it).
async fn reply(State(app): State<AppRef>, Path(id): Path<i64>, Query(q): Query<TokenQ>, headers: HeaderMap, body: Bytes) -> Result<Response, PackErr> {
    let a = packs::player(&app, &headers, &q).await?;
    let r = own(&app, a.id, id).await?;
    let f: ReplyIn = serde_json::from_slice(&body).map_err(|e| bad("bad_body", format!("Not a message: {e}")))?;
    let text = text_of(&f.text)?;
    let screen = picture(&f.screen)?;
    let mine: Vec<i64> = report::Entity::find().select_only().column(report::Column::Id).filter(report::Column::Account.eq(a.id)).into_tuple().all(&app.db).await?;
    let recent = msg::Entity::find()
        .filter(msg::Column::Report.is_in(mine))
        .filter(msg::Column::Account.eq(a.id))
        .filter(msg::Column::At.gt(now() - 3600))
        .count(&app.db)
        .await?;
    if recent >= REPLIES_PER_HOUR {
        return Err(refuse(StatusCode::TOO_MANY_REQUESTS, "too_many", format!("{REPLIES_PER_HOUR} answers an hour at most: try later")));
    }
    let m = add_message(&app, &r, &a, false, &text, screen).await?;
    let short: String = text.chars().take(120).collect();
    app.event(Event::new("report", format!("{} answered in the problem report {id}: {short}", a.name)).user(a.id, &a.name).data(json!({"report": id, "reply": m.id})));
    Ok((StatusCode::CREATED, Json(json!({"message": player_msg(&m)}))).into_response())
}

/// A report gone with its files (its messages' pictures too); the reports merged into it stand alone again.
async fn remove(app: &AppRef, id: i64) {
    let shots: Vec<i64> = msg::Entity::find()
        .select_only()
        .column(msg::Column::Id)
        .filter(msg::Column::Report.eq(id))
        .filter(msg::Column::Screen.eq(true))
        .into_tuple()
        .all(&app.db)
        .await
        .unwrap_or_default();
    let files = ["screen.png".to_string(), "voice.ogg".to_string()].into_iter().chain(shots.iter().map(|m| format!("m{m}.png")));
    for f in files {
        if let Err(e) = app.store.delete_path(&path(id, &f)).await {
            tracing::error!("reports: deleting {}: {e}", path(id, &f));
        }
    }
    let r = report::Entity::update_many()
        .col_expr(report::Column::MergedInto, Expr::value(Option::<i64>::None))
        .filter(report::Column::MergedInto.eq(id))
        .exec(&app.db)
        .await;
    if let Err(e) = r.and(report::Entity::delete_by_id(id).exec(&app.db).await.map(|_| ())) {
        tracing::error!("reports: deleting {id}: {e}");
    }
}

/// Removes the reports (with their files) that match: an account's when it is deleted, those
/// without activity since a time (`prune`) → how many.
async fn remove_where(app: &AppRef, cond: Condition) -> Result<usize, sea_orm::DbErr> {
    let ids: Vec<i64> = report::Entity::find().select_only().column(report::Column::Id).filter(cond).into_tuple().all(&app.db).await?;
    for &id in &ids {
        remove(app, id).await;
    }
    Ok(ids.len())
}

pub async fn remove_of(app: &AppRef, account: i64) -> Result<usize, sea_orm::DbErr> {
    remove_where(app, Condition::all().add(report::Column::Account.eq(account))).await
}

/// The reports without activity since `before` (unix seconds): the admin's purge, and the daily
/// cleanup of the chats' keeping time (`chat_keep_days`; the plan's §3) may call it.
pub async fn prune(app: &AppRef, before: i64) -> Result<usize, sea_orm::DbErr> {
    remove_where(app, Condition::all().add(report::Column::LastAt.lt(before))).await
}

/// `{new, answers}` for the admins: reports no admin opened yet; opened ones the player wrote in since.
pub async fn counts(app: &AppRef, subserver: i64) -> Result<Value, sea_orm::DbErr> {
    let base = || report::Entity::find().filter(report::Column::Subserver.eq(subserver)).filter(report::Column::AdminUnread.eq(true));
    let new = base().filter(report::Column::AdminOpened.eq(false)).count(&app.db).await?;
    let answers = base().filter(report::Column::AdminOpened.eq(true)).count(&app.db).await?;
    Ok(json!({"new": new, "answers": answers}))
}

// --- the admin panel ------------------------------------------------------------------------------

pub fn admin_routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/reports", get(list))
        .route("/admin/api/reports/counts", get(counts_api))
        .route("/admin/api/reports/export", get(export))
        .route("/admin/api/reports/purge", post(purge))
        .route("/admin/api/reports/{id}", get(one))
        .route("/admin/api/reports/{id}/{what}", get(file).post(action))
}

#[derive(Deserialize, Default)]
struct ListQ {
    state: Option<String>,
    /// A part of the player's name or tag.
    player: Option<String>,
    version: Option<String>,
    subserver: Option<i64>,
    /// The ticked ones (export): "3,5,8".
    ids: Option<String>,
    page: Option<u64>,
    size: Option<u64>,
    /// Export: "zip" (the default) or "json".
    format: Option<String>,
}

/// The reports the filters (or the ticked ids) pick, latest activity first; merged ones only by id.
async fn select(app: &AppRef, q: &ListQ) -> Result<Select<report::Entity>, sea_orm::DbErr> {
    let mut sel = report::Entity::find().filter(report::Column::Subserver.eq(q.subserver.unwrap_or(0))).order_by_desc(report::Column::LastAt);
    if let Some(ids) = q.ids.as_deref().filter(|s| !s.is_empty()) {
        let ids: Vec<i64> = ids.split(',').filter_map(|s| s.trim().parse().ok()).collect();
        return Ok(sel.filter(report::Column::Id.is_in(ids)));
    }
    sel = sel.filter(report::Column::MergedInto.is_null());
    if let Some(s) = q.state.as_deref().filter(|s| !s.is_empty()) {
        sel = sel.filter(report::Column::State.eq(s));
    }
    if let Some(v) = q.version.as_deref().filter(|s| !s.is_empty()) {
        sel = sel.filter(report::Column::Version.eq(v));
    }
    if let Some(p) = q.player.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        let who: Vec<i64> = account::Entity::find()
            .select_only()
            .column(account::Column::Id)
            .filter(Condition::any().add(account::Column::Name.contains(p)).add(account::Column::Tag.contains(p)))
            .into_tuple()
            .all(&app.db)
            .await?;
        sel = sel.filter(report::Column::Account.is_in(who));
    }
    Ok(sel)
}

fn report_json(r: &report::Model, a: Option<&Account>) -> Value {
    let parse = |s: &str| serde_json::from_str::<Value>(s).unwrap_or(Value::Null);
    json!({"id": r.id, "subserver": r.subserver,
           "account": {"id": r.account, "user": a.map(|a| a.name.as_str()), "tag": a.and_then(|a| a.tag.as_deref())},
           "written_at": r.written_at, "received_at": r.received_at, "last_at": r.last_at, "text": r.text, "version": r.version,
           "context": parse(&r.context), "games": parse(&r.games), "screen": r.screen, "voice": r.voice,
           "state": r.state, "note": r.note, "merged_into": r.merged_into, "unread": r.admin_unread, "opened": r.admin_opened})
}

async fn with_accounts(app: &AppRef, rows: &[report::Model]) -> Result<Vec<Value>, sea_orm::DbErr> {
    let mut ids: Vec<i64> = rows.iter().map(|r| r.account).collect();
    ids.sort_unstable();
    ids.dedup();
    let who: HashMap<i64, Account> = accounts_in_order(&app.db, &ids).await?.into_iter().map(|a| (a.id, a)).collect();
    Ok(rows.iter().map(|r| report_json(r, who.get(&r.account))).collect())
}

/// `{list, total, page, size, counts: {new, answers}, versions}`; a report has `merged` (how many
/// duplicates were merged into it) and `messages` (its thread's, theirs too).
async fn list(State(app): State<AppRef>, Extension(me): Extension<Admin>, Query(q): Query<ListQ>) -> Response {
    let sub = sub_of(&me, q.subserver);
    let q = ListQ { subserver: Some(sub), ..q };
    if !may(&app, me.me.id, "reports.view", sub).await {
        return err(StatusCode::FORBIDDEN, "You may not see the reports");
    }
    let r = async {
        let (page, size) = (q.page.unwrap_or(0).min(1_000_000), q.size.unwrap_or(50).clamp(1, 500));
        let (rows, total) = page_of(select(&app, &q).await?, page, size, &app.db).await?;
        let versions: Vec<String> = report::Entity::find()
            .select_only()
            .column(report::Column::Version)
            .filter(report::Column::Subserver.eq(sub))
            .distinct()
            .order_by_desc(report::Column::Version)
            .into_tuple()
            .all(&app.db)
            .await?;
        let mut list = with_accounts(&app, &rows).await?;
        for v in &mut list {
            let id = v["id"].as_i64().unwrap_or_default();
            let group = group_ids(&app, id).await?;
            v["merged"] = json!(group.len() - 1);
            v["messages"] = json!(1 + msg::Entity::find().filter(msg::Column::Report.is_in(group)).count(&app.db).await?);
        }
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "total": total, "page": page, "size": size, "counts": counts(&app, sub).await?, "versions": versions}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

async fn counts_api(State(app): State<AppRef>, Extension(me): Extension<Admin>, Query(q): Query<ListQ>) -> Response {
    let sub = sub_of(&me, q.subserver);
    if !may(&app, me.me.id, "reports.view", sub).await {
        return err(StatusCode::FORBIDDEN, "You may not see the reports");
    }
    match counts(&app, sub).await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// A report and the ones merged into it (its own id first).
async fn group_ids(app: &AppRef, id: i64) -> Result<Vec<i64>, sea_orm::DbErr> {
    let merged: Vec<i64> = report::Entity::find().select_only().column(report::Column::Id).filter(report::Column::MergedInto.eq(id)).order_by_asc(report::Column::Id).into_tuple().all(&app.db).await?;
    Ok(std::iter::once(id).chain(merged).collect())
}

/// The whole of a report for the admins: its fields, `merged` (the reports merged into it, each
/// with its fields), `thread` (every message of them all, oldest first: `{id, report, from: player|admin,
/// name, text, at, screen: <file url> | null}`, the reports themselves included), `games` with their replays.
async fn full(app: &AppRef, r: &report::Model) -> Result<Value, sea_orm::DbErr> {
    let group = group_ids(app, r.id).await?;
    let rows = report::Entity::find().filter(report::Column::Id.is_in(group.clone())).order_by_asc(report::Column::Id).all(&app.db).await?;
    let all = with_accounts(app, &rows).await?;
    let mut v = all.iter().find(|x| x["id"] == r.id).cloned().unwrap_or_default();
    let mut thread = vec![];
    for x in &all {
        let id = x["id"].as_i64().unwrap_or_default();
        thread.push(json!({"id": 0, "report": id, "from": "player", "name": x["account"]["user"], "text": x["text"], "at": x["received_at"],
                           "screen": if x["screen"] == true { json!(format!("screen.png?of={id}")) } else { Value::Null }}));
    }
    for m in msg::Entity::find().filter(msg::Column::Report.is_in(group)).order_by_asc(msg::Column::Id).all(&app.db).await? {
        // an admin's answer is copied into every report of the group: show it once
        if m.admin && thread.iter().any(|t| t["from"] == "admin" && t["text"] == json!(m.text) && t["at"] == json!(m.at)) {
            continue;
        }
        thread.push(json!({"id": m.id, "report": m.report, "from": if m.admin { "admin" } else { "player" }, "name": m.name, "text": m.text, "at": m.at,
                           "screen": if m.screen { json!(format!("m{}.png?of={}", m.id, m.report)) } else { Value::Null }}));
    }
    thread.sort_by_key(|t| t["at"].as_i64().unwrap_or_default());
    let mut games = vec![];
    for g in v["games"].as_array().cloned().unwrap_or_default() {
        let g = g.as_str().unwrap_or_default().to_string();
        let d = crate::replays::data(&app.db, r.subserver, &g).await?;
        let ended = replay::Entity::find_by_id(&g).select_only().column(replay::Column::Ended).into_tuple::<i64>().one(&app.db).await?;
        games.push(match d {
            Some(d) => json!({"game": g, "replay": true, "mode": d["mode"], "pack_name": d["pack_name"], "ended": ended,
                              "players": [d["players"][0]["name"], d["players"][1]["name"]], "winner": d["result"]["winner"]}),
            None => json!({"game": g, "replay": false}),
        });
    }
    v["games"] = json!(games);
    v["thread"] = json!(thread);
    v["merged"] = json!(all.into_iter().filter(|x| x["id"] != r.id).collect::<Vec<_>>());
    Ok(v)
}

/// A report with its thread (`full`); opening it marks the group read for the admins.
async fn one(State(app): State<AppRef>, Extension(me): Extension<Admin>, Path(id): Path<i64>) -> Response {
    let r = async {
        let Some(r) = report::Entity::find_by_id(id).one(&app.db).await? else { return Ok(None) };
        if !may(&app, me.me.id, "reports.view", r.subserver).await {
            return Ok(Some(Err(())));
        }
        let group = group_ids(&app, id).await?;
        report::Entity::update_many()
            .col_expr(report::Column::AdminOpened, Expr::value(true))
            .col_expr(report::Column::AdminUnread, Expr::value(false))
            .filter(report::Column::Id.is_in(group))
            .exec(&app.db)
            .await?;
        Ok::<_, sea_orm::DbErr>(Some(Ok(full(&app, &r).await?)))
    };
    match r.await {
        Ok(Some(Ok(v))) => Json(v).into_response(),
        Ok(Some(Err(()))) => err(StatusCode::FORBIDDEN, "You may not see this report"),
        Ok(None) => err(StatusCode::NOT_FOUND, "No such report"),
        Err(e) => db_err(e),
    }
}

#[derive(Deserialize)]
struct FileQ {
    /// The report of the group the file is in (default: this one).
    of: Option<i64>,
}

/// `screen.png`, `voice.ogg`, `m<id>.png` (a message's picture) of a report (`?of=` one merged into
/// it); `export` (this report as a zip), `markdown` (as text for an AI agent).
async fn file(State(app): State<AppRef>, Extension(me): Extension<Admin>, Path((id, what)): Path<(i64, String)>, Query(fq): Query<FileQ>) -> Response {
    let r = match report::Entity::find_by_id(id).one(&app.db).await {
        Ok(Some(r)) => r,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such report"),
        Err(e) => return db_err(e),
    };
    if !may(&app, me.me.id, "reports.view", r.subserver).await {
        return err(StatusCode::FORBIDDEN, "You may not see this report");
    }
    if what == "export" || what == "markdown" {
        if !may(&app, me.me.id, "reports.export", r.subserver).await {
            return err(StatusCode::FORBIDDEN, "You may not export the reports");
        }
        let v = match full(&app, &r).await {
            Ok(v) => v,
            Err(e) => return db_err(e),
        };
        if what == "markdown" {
            return ([(header::CONTENT_TYPE, "text/markdown; charset=utf-8")], markdown(&v, &files_of(&app, &v).await)).into_response();
        }
        return match zip_one(&app, &v).await {
            Ok((size, f)) => zip_response(size, f, &format!("report-{id}.zip")),
            Err(e) => {
                tracing::error!("reports: export {id}: {e}");
                err(StatusCode::INTERNAL_SERVER_ERROR, "The export failed")
            }
        };
    }
    let mime = match what.as_str() {
        "voice.ogg" => "audio/ogg",
        w if w == "screen.png" || (w.starts_with('m') && w.ends_with(".png") && w[1..w.len() - 4].bytes().all(|b| b.is_ascii_digit())) => "image/png",
        _ => return err(StatusCode::NOT_FOUND, "No such file"),
    };
    let of = fq.of.unwrap_or(id);
    let in_group = match group_ids(&app, id).await {
        Ok(g) => g.contains(&of),
        Err(e) => return db_err(e),
    };
    if !in_group {
        return err(StatusCode::NOT_FOUND, "No such file");
    }
    match app.store.read_path(&path(of, &what), (MAX_SCREEN + MAX_VOICE) as u64).await {
        Ok(b) => ([(header::CONTENT_TYPE, mime), (header::CACHE_CONTROL, "private, max-age=86400")], b).into_response(),
        Err(e) => {
            tracing::warn!("reports: {}: {e}", path(of, &what));
            err(StatusCode::NOT_FOUND, "The file is not in the store")
        }
    }
}

/// `state {state}` (the group's), `note {note}`, `answer {text}` (in every thread of the group),
/// `merge {into}` (this report and its merged ones into another), `unmerge`, `delete`.
async fn action(State(app): State<AppRef>, Extension(me): Extension<Admin>, Path((id, what)): Path<(i64, String)>, body: Option<Json<Value>>) -> Response {
    let body = body.map(|Json(v)| v).unwrap_or_default();
    let r = match report::Entity::find_by_id(id).one(&app.db).await {
        Ok(Some(r)) => r,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such report"),
        Err(e) => return db_err(e),
    };
    if !may(&app, me.me.id, "reports.manage", r.subserver).await {
        return err(StatusCode::FORBIDDEN, "You may not change the reports");
    }
    let text = |k: &str| body[k].as_str().unwrap_or_default().trim().to_string();
    let log = |what: String, data: Value| app.event(me.ev(format!("{} {what} (report {id})", me.me.name)).data(json!({"action": "report", "report": id, "change": data})));
    let res: Result<Option<Response>, sea_orm::DbErr> = async {
        let group = group_ids(&app, id).await?;
        let players = || async {
            let mut who: Vec<i64> = report::Entity::find().select_only().column(report::Column::Account).filter(report::Column::Id.is_in(group.clone())).into_tuple().all(&app.db).await?;
            who.dedup();
            Ok::<_, sea_orm::DbErr>(who)
        };
        match what.as_str() {
            "state" => {
                let s = text("state");
                if !STATES.contains(&s.as_str()) {
                    return Ok(Some(err(StatusCode::BAD_REQUEST, "The state is open, resolved or rejected")));
                }
                report::Entity::update_many()
                    .col_expr(report::Column::State, Expr::value(s.clone()))
                    .col_expr(report::Column::PlayerUnread, Expr::value(true))
                    .col_expr(report::Column::LastAt, Expr::value(now()))
                    .filter(report::Column::Id.is_in(group.clone()))
                    .exec(&app.db)
                    .await?;
                for p in players().await? {
                    push_unread(&app, p).await;
                }
                log(format!("marked a problem report {s}"), json!({"state": s}));
            }
            "note" => {
                let n = text("note");
                if n.chars().count() > MAX_TEXT {
                    return Ok(Some(err(StatusCode::BAD_REQUEST, "A note is 4000 characters at most")));
                }
                let mut m: report::ActiveModel = r.clone().into();
                m.note = Set(n.clone());
                m.update(&app.db).await?;
                log("wrote a note on a problem report".into(), json!({"note": n}));
            }
            "answer" => {
                let t = text("text");
                if t.is_empty() || t.chars().count() > MAX_TEXT {
                    return Ok(Some(err(StatusCode::BAD_REQUEST, "An answer is 1 to 4000 characters")));
                }
                for g in report::Entity::find().filter(report::Column::Id.is_in(group.clone())).all(&app.db).await? {
                    if let Err(e) = add_message(&app, &g, &me.me, true, &t, vec![]).await {
                        return Ok(Some(e.into_response()));
                    }
                }
                for p in players().await? {
                    push_unread(&app, p).await;
                }
                log("answered a problem report".into(), json!({"text": t}));
            }
            "merge" => {
                let Some(into) = body["into"].as_i64() else { return Ok(Some(err(StatusCode::BAD_REQUEST, "Merge into which report?"))) };
                let target = match report::Entity::find_by_id(into).one(&app.db).await? {
                    Some(t) if t.subserver == r.subserver => t,
                    _ => return Ok(Some(err(StatusCode::NOT_FOUND, "No such report to merge into"))),
                };
                let target = target.merged_into.unwrap_or(target.id);
                if group.contains(&target) {
                    return Ok(Some(err(StatusCode::BAD_REQUEST, "That is this report")));
                }
                report::Entity::update_many()
                    .col_expr(report::Column::MergedInto, Expr::value(target))
                    .filter(report::Column::Id.is_in(group.clone()))
                    .exec(&app.db)
                    .await?;
                log(format!("merged a problem report into {target}"), json!({"into": target, "reports": group}));
            }
            "unmerge" => {
                let mut m: report::ActiveModel = r.clone().into();
                m.merged_into = Set(None);
                m.update(&app.db).await?;
                log("took a problem report out of its merge".into(), json!({"merged_into": r.merged_into}));
            }
            "delete" => {
                remove(&app, id).await;
                log("deleted a problem report".into(), json!({"deleted": true}));
                return Ok(Some(Json(json!({"ok": true})).into_response()));
            }
            _ => return Ok(Some(err(StatusCode::NOT_FOUND, "No such action"))),
        }
        Ok(None)
    }
    .await;
    match res {
        Ok(Some(resp)) => resp,
        Ok(None) => match report::Entity::find_by_id(id).one(&app.db).await {
            Ok(Some(r)) => match full(&app, &r).await {
                Ok(v) => Json(v).into_response(),
                Err(e) => db_err(e),
            },
            Ok(None) => Json(json!({"ok": true})).into_response(),
            Err(e) => db_err(e),
        },
        Err(e) => db_err(e),
    }
}

/// `purge {days}`: removes the request's sub-server's reports without activity in that many days (1 or more)
/// → `{removed}`.
async fn purge(State(app): State<AppRef>, Extension(me): Extension<Admin>, Json(body): Json<Value>) -> Response {
    let sub = me.scope.id;
    if !may(&app, me.me.id, "reports.manage", sub).await {
        return err(StatusCode::FORBIDDEN, "You may not change the reports");
    }
    let Some(days) = body["days"].as_i64().filter(|d| (1..=36500).contains(d)) else {
        return err(StatusCode::BAD_REQUEST, "Purge the reports older than 1 or more days");
    };
    let old = Condition::all().add(report::Column::LastAt.lt(now() - days * 86400)).add(report::Column::Subserver.eq(sub));
    match remove_where(&app, old).await {
        Ok(n) => {
            app.event(me.ev(format!("{} purged {n} problem reports older than {days} days", me.me.name)).data(json!({"action": "report_purge", "days": days, "removed": n})));
            Json(json!({"removed": n})).into_response()
        }
        Err(e) => db_err(e),
    }
}

// --- export ------------------------------------------------------------------------------------------

/// The export: `format=json`: the reports as JSON; else a zip of `reports.json` and per report
/// `<id>/screen.png`, `<id>/voice.ogg`, `<id>/m<msg>.png`, `<id>/<game>.chsreplay` (the paths are in
/// reports.json's `files`). All, the filtered (the list's filters) or the ticked (`ids`).
async fn export(State(app): State<AppRef>, Extension(me): Extension<Admin>, Query(q): Query<ListQ>) -> Response {
    let q = ListQ { subserver: Some(sub_of(&me, q.subserver)), ..q };
    if !may(&app, me.me.id, "reports.export", q.subserver.unwrap_or(0)).await {
        return err(StatusCode::FORBIDDEN, "You may not export the reports");
    }
    // ponytail: at most 2000 reports in one export, the zip built in a temp file at once; stream it if that grows
    let r = async {
        let rows = select(&app, &q).await?.limit(2000).all(&app.db).await?;
        let mut list = vec![];
        for r in &rows {
            list.push(full(&app, r).await?);
        }
        Ok::<_, sea_orm::DbErr>(list)
    };
    let mut list = match r.await {
        Ok(l) => l,
        Err(e) => return db_err(e),
    };
    let stamp = now();
    if q.format.as_deref() == Some("json") {
        let disposition = format!("attachment; filename=\"reports-{stamp}.json\"");
        return ([(header::CONTENT_TYPE, "application/json".to_string()), (header::CONTENT_DISPOSITION, disposition)], json!(list).to_string()).into_response();
    }
    let r = async {
        let mut z = temp_zip()?;
        for v in &mut list {
            let prefix = format!("{}/", v["id"]);
            let files = add_files(&app, &mut z, v, &prefix).await?;
            v["files"] = files;
        }
        z.start_file("reports.json", zip::write::SimpleFileOptions::default()).map_err(|e| e.to_string())?;
        z.write_all(serde_json::to_string_pretty(&json!(list)).unwrap_or_default().as_bytes()).map_err(|e| e.to_string())?;
        finish(z)
    };
    match r.await {
        Ok((size, f)) => zip_response(size, f, &format!("reports-{stamp}.zip")),
        Err(e) => {
            tracing::error!("reports: export: {e}");
            err(StatusCode::INTERNAL_SERVER_ERROR, "The export failed")
        }
    }
}

fn zip_response(size: u64, f: std::fs::File, name: &str) -> Response {
    let body = Body::from_stream(tokio_util::io::ReaderStream::new(tokio::fs::File::from_std(f)));
    ([(header::CONTENT_TYPE, "application/zip".to_string()), (header::CONTENT_LENGTH, size.to_string()), (header::CONTENT_DISPOSITION, format!("attachment; filename=\"{name}\""))], body)
        .into_response()
}

type Zip = zip::ZipWriter<std::fs::File>;

/// A zip in a temp file of its own (already unlinked).
fn temp_zip() -> Result<Zip, String> {
    let tmp = std::env::temp_dir().join(format!("chs-reports-{}.zip", rand::random::<u64>()));
    let f = std::fs::File::options().read(true).write(true).create_new(true).open(&tmp).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&tmp);
    Ok(zip::ZipWriter::new(f))
}

/// → (its size, the file at its start).
fn finish(z: Zip) -> Result<(u64, std::fs::File), String> {
    let mut f = z.finish().map_err(|e| e.to_string())?;
    let size = f.stream_position().map_err(|e| e.to_string())?;
    f.rewind().map_err(|e| e.to_string())?;
    Ok((size, f))
}

/// The files of a report (`full`) as they are named in its export: `[(name, store path)]` and the
/// replays' game ids.
async fn files_of(app: &AppRef, v: &Value) -> Vec<(String, String)> {
    let mut out = vec![];
    for x in std::iter::once(v).chain(v["merged"].as_array().into_iter().flatten()) {
        let id = x["id"].as_i64().unwrap_or_default();
        let own = id == v["id"].as_i64().unwrap_or_default();
        let name = |f: &str| if own { f.to_string() } else { format!("merged-{id}-{f}") };
        if x["screen"] == true {
            out.push((name("screen.png"), path(id, "screen.png")));
        }
        if x["voice"] == true {
            out.push((name("voice.ogg"), path(id, "voice.ogg")));
        }
    }
    for t in v["thread"].as_array().into_iter().flatten() {
        if t["id"].as_i64().unwrap_or(0) > 0 && t["screen"].is_string() {
            let f = format!("m{}.png", t["id"]);
            out.push((f.clone(), path(t["report"].as_i64().unwrap_or_default(), &f)));
        }
    }
    for g in v["games"].as_array().into_iter().flatten().filter(|g| g["replay"] == true) {
        let g = g["game"].as_str().unwrap_or_default();
        out.push((format!("{}.chsreplay", safe(g)), format!("replay:{g}")));
    }
    let _ = app;
    out
}

fn safe(g: &str) -> String {
    g.chars().filter(char::is_ascii_alphanumeric).collect()
}

/// Writes a report's files into the zip under `prefix` → `{screen, voice, pictures, replays}` (paths in the zip).
async fn add_files(app: &AppRef, z: &mut Zip, v: &Value, prefix: &str) -> Result<Value, String> {
    use zip::write::SimpleFileOptions;
    let stored = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    let mut files = json!({"pictures": [], "replays": []});
    for (name, from) in files_of(app, v).await {
        let at = format!("{prefix}{name}");
        let bytes = if let Some(g) = from.strip_prefix("replay:") {
            match crate::replays::data(&app.db, v["subserver"].as_i64().unwrap_or(0), g).await.map_err(|e| e.to_string())? {
                Some(d) => d.to_string().into_bytes(),
                None => continue,
            }
        } else {
            match app.store.read_path(&from, (MAX_SCREEN + MAX_VOICE) as u64).await {
                Ok(b) => b,
                Err(e) => {
                    tracing::warn!("reports: export: {from}: {e}");
                    continue;
                }
            }
        };
        let opts = if name.ends_with(".chsreplay") { SimpleFileOptions::default() } else { stored };
        z.start_file(at.as_str(), opts).map_err(|e| e.to_string())?;
        z.write_all(&bytes).map_err(|e| e.to_string())?;
        match name.as_str() {
            "screen.png" => files["screen"] = json!(at),
            "voice.ogg" => files["voice"] = json!(at),
            n if n.ends_with(".chsreplay") => files["replays"].as_array_mut().unwrap().push(json!(at)),
            _ => files["pictures"].as_array_mut().unwrap().push(json!(at)),
        }
    }
    Ok(files)
}

/// One report as a zip: `report.md`, `report.json` and its files.
async fn zip_one(app: &AppRef, v: &Value) -> Result<(u64, std::fs::File), String> {
    let mut z = temp_zip()?;
    let mut v = v.clone();
    v["files"] = add_files(app, &mut z, &v, "").await?;
    let opts = zip::write::SimpleFileOptions::default();
    z.start_file("report.md", opts).map_err(|e| e.to_string())?;
    z.write_all(markdown(&v, &files_of(app, &v).await).as_bytes()).map_err(|e| e.to_string())?;
    z.start_file("report.json", opts).map_err(|e| e.to_string())?;
    z.write_all(serde_json::to_string_pretty(&v).unwrap_or_default().as_bytes()).map_err(|e| e.to_string())?;
    finish(z)
}

/// Unix seconds as "2026-11-26 09:30 UTC".
fn utc(t: i64) -> String {
    let (days, secs) = (t.div_euclid(86400), t.rem_euclid(86400));
    // civil from days (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02} {:02}:{:02} UTC", secs / 3600, secs % 3600 / 60)
}

/// A report (`full`) as Markdown with what an AI agent needs to reproduce and fix the problem:
/// the player's words, the game's version and pack, the thread, the files of its export.
pub fn markdown(v: &Value, files: &[(String, String)]) -> String {
    let s = |x: &Value| x.as_str().map(String::from).unwrap_or_else(|| if x.is_null() { "—".into() } else { x.to_string() });
    let c = &v["context"];
    let mut o = String::new();
    let _ = writeln!(o, "# Problem report #{} (Classic HS)\n", v["id"]);
    let _ = writeln!(o, "- Player: {} (account {}{})", s(&v["account"]["user"]), v["account"]["id"], v["account"]["tag"].as_str().map(|t| format!(", tag {t}")).unwrap_or_default());
    let _ = writeln!(o, "- State: {}", s(&v["state"]));
    let _ = writeln!(o, "- Written: {} (the player's clock); received: {}", utc(v["written_at"].as_i64().unwrap_or_default()), utc(v["received_at"].as_i64().unwrap_or_default()));
    let _ = writeln!(o, "- Game version: {}; platform: {}; screen: {}; language: {}", s(&c["version"]), s(&c["platform"]), s(&c["screen"]), s(&c["language"]));
    let _ = writeln!(o, "- Game pack: {} {} (rules_hash {})", s(&c["pack"]["id"]), s(&c["pack"]["version"]), s(&c["pack"]["rules_hash"]));
    let from = c["game"].as_str().filter(|g| !g.is_empty()).map(|g| format!("the match {g}")).unwrap_or_else(|| "the menu".into());
    let _ = writeln!(o, "- Sent from: {from}");
    if !v["note"].as_str().unwrap_or_default().is_empty() {
        let _ = writeln!(o, "- Admin's note: {}", s(&v["note"]));
    }
    let _ = writeln!(o, "\n## What the player wrote\n");
    for l in s(&v["text"]).lines() {
        let _ = writeln!(o, "> {l}");
    }
    let _ = writeln!(o, "\n## Thread\n");
    for t in v["thread"].as_array().into_iter().flatten() {
        let who = if t["from"] == "admin" { format!("admin {}", s(&t["name"])) } else { format!("player {}", s(&t["name"])) };
        let pic = match (&t["screen"], t["id"].as_i64().unwrap_or(0)) {
            (Value::String(_), 0) if t["report"] == v["id"] => " [picture: screen.png]".to_string(),
            (Value::String(_), 0) => format!(" [picture: merged-{}-screen.png]", t["report"]),
            (Value::String(_), m) => format!(" [picture: m{m}.png]"),
            _ => String::new(),
        };
        let _ = writeln!(o, "- **{who}**, {} (report #{}){pic}: {}", utc(t["at"].as_i64().unwrap_or_default()), t["report"], s(&t["text"]).replace('\n', " / "));
    }
    let merged = v["merged"].as_array().cloned().unwrap_or_default();
    if !merged.is_empty() {
        let _ = writeln!(o, "\n## Duplicates merged into it\n");
        for m in &merged {
            let _ = writeln!(o, "- #{} by {}, version {}, platform {}", m["id"], s(&m["account"]["user"]), s(&m["context"]["version"]), s(&m["context"]["platform"]));
        }
    }
    let _ = writeln!(o, "\n## Files (in the report's zip)\n");
    for (name, _) in files {
        let what = match name.as_str() {
            n if n.ends_with("screen.png") => "the player's screen when he opened the report window",
            n if n.ends_with("voice.ogg") => "the player's voice message (Ogg Opus; listen to it, there is no transcript)",
            n if n.ends_with(".chsreplay") => "a replay of one of the player's games (the replay JSON: the setup with the decks and the seed, every action, the result and the final state hash; the game opens it: Replays, Import)",
            _ => "a picture the player added in the thread",
        };
        let _ = writeln!(o, "- `{name}`: {what}");
    }
    let _ = writeln!(o, "\n## To reproduce\n");
    let _ = writeln!(o, "Use the game version and the pack above (the pack's rules_hash names its rules exactly). A replay plays the whole game again in the rules engine: its actions applied in order must end in its final state hash. The first replay is the match the report was sent from, when there was one.");
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wav_of(samples: &[i16], rate: u32, channels: u16) -> Vec<u8> {
        let data: Vec<u8> = samples.iter().flat_map(|s| s.to_le_bytes()).collect();
        let mut b = b"RIFF".to_vec();
        b.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
        b.extend_from_slice(b"WAVEfmt ");
        b.extend_from_slice(&16u32.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&channels.to_le_bytes());
        b.extend_from_slice(&rate.to_le_bytes());
        b.extend_from_slice(&(rate * 2 * channels as u32).to_le_bytes());
        b.extend_from_slice(&(2 * channels).to_le_bytes());
        b.extend_from_slice(&16u16.to_le_bytes());
        b.extend_from_slice(b"data");
        b.extend_from_slice(&(data.len() as u32).to_le_bytes());
        b.extend_from_slice(&data);
        b
    }

    #[test]
    fn voice_from_wav() {
        let tone: Vec<i16> = (0..16000).map(|i| ((i as f64 * 0.17).sin() * 9000.0) as i16).collect();
        let ogg = voice_ogg(wav_of(&tone, 16000, 1)).unwrap();
        assert!(ogg.starts_with(b"OggS"));
        assert_eq!(classichs_opus::decode(&ogg).unwrap().samples.len(), 48000);
        assert_eq!(voice_ogg(ogg.clone()).unwrap(), ogg, "an Ogg Opus file is kept as it is");
        assert_eq!(voice_ogg(wav_of(&tone, 16000, 2)).unwrap_err().1, "bad_voice", "stereo");
        assert_eq!(voice_ogg(wav_of(&tone, 44100, 1)).unwrap_err().1, "bad_voice", "a rate Opus does not take");
        assert_eq!(voice_ogg(wav_of(&vec![0; 16000 * 62], 16000, 1)).unwrap_err().1, "bad_voice", "too long");
        assert_eq!(voice_ogg(b"garbage".to_vec()).unwrap_err().1, "bad_voice");
    }

    #[test]
    fn utc_dates() {
        assert_eq!(utc(0), "1970-01-01 00:00 UTC");
        assert_eq!(utc(1_764_149_400), "2025-11-26 09:30 UTC");
        assert_eq!(utc(951_782_400), "2000-02-29 00:00 UTC");
    }
}
