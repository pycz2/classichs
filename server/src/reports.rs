//! Problem reports from the game (0.74; docs/superpowers/specs/2026-11-26-roles-subservers-design.md
//! §3): a player sends a text with the screen's picture and a voice message (`POST /reports` with
//! the game session token, as the packs' uploads); the admin panel lists them, shows one, changes
//! its state and note, answers with a private message and exports them (a zip or plain JSON).
//! server/README.md, "Problem reports".

use crate::admin::{db_err, err, page_of, Admin};
use crate::db::{self, Account};
use crate::entity::{account, message, replay, report};
use crate::events::Event;
use crate::packs::{self, PackErr, TokenQ};
use crate::ranked::now;
use crate::ws::{accounts_in_order, store_msg};
use crate::AppRef;
use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Select, Set};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{Seek, Write};

/// A report's text, in characters.
pub const MAX_TEXT: usize = 4000;
/// The picture (PNG) and the stored voice message (Ogg Opus), in bytes; the voice's length.
pub const MAX_SCREEN: usize = 4 << 20;
pub const MAX_VOICE: usize = 1 << 20;
pub const MAX_VOICE_SECS: usize = 60;
/// Reports a player may send in an hour.
pub const PER_HOUR: u64 = 5;
/// The request: the picture and a 60 s WAV (16 kHz mono, what the game records) in base64, and the text.
const MAX_BODY: usize = 10 << 20;
pub const STATES: [&str; 3] = ["new", "seen", "done"];
/// Finished games of the player kept with a report (and the current one).
const LAST_GAMES: u64 = 5;

/// The one permission check of the reports (`reports.view`, `reports.manage`, `reports.export` in
/// a sub-server): today every admin (the panel's guard lets admins only in) may all of them.
// ponytail: today's admin role; the roles' perm::has(app, account, perm, subserver) replaces it.
async fn may(app: &AppRef, account: i64, perm: &str, subserver: i64) -> bool {
    let _ = (perm, subserver);
    matches!(db::account_by_id(&app.db, account).await, Ok(Some(a)) if matches!(a.role.as_str(), "admin" | "super"))
}

/// The file of a report in the store.
fn path(id: i64, file: &str) -> String {
    format!("reports/{id}/{file}")
}

// --- the players' side ---------------------------------------------------------------------------

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/reports", post(send).options(packs::preflight))
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

async fn send(State(app): State<AppRef>, Query(q): Query<TokenQ>, headers: HeaderMap, body: Bytes) -> Result<Response, PackErr> {
    let a = packs::player(&app, &headers, &q).await?;
    let f: SendIn = serde_json::from_slice(&body).map_err(|e| bad("bad_body", format!("Not a report: {e}")))?;
    let text = f.text.trim().to_string();
    if text.is_empty() || text.chars().count() > MAX_TEXT {
        return Err(bad("bad_text", format!("A report is 1 to {MAX_TEXT} characters")));
    }
    let screen = attachment(&f.screen, MAX_SCREEN, "bad_screen", "picture")?;
    if !screen.is_empty() && !screen.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err(bad("bad_screen", "The picture is not a PNG"));
    }
    // a 60 s WAV at 16 kHz is about 1.9 MB: the stored Ogg is checked against MAX_VOICE
    let voice = attachment(&f.voice, 3 * MAX_VOICE, "bad_voice", "voice message")?;
    let voice = if voice.is_empty() { None } else { Some(tokio::task::spawn_blocking(move || voice_ogg(voice)).await.map_err(store_err)??) };
    let context = if f.context.is_object() { f.context } else { json!({}) };
    let context_text = context.to_string();
    if context_text.len() > 4000 {
        return Err(bad("bad_context", "The report's context is too long"));
    }
    let received = now();
    let (subserver, db) = (0, &app.db);
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
        text: Set(text.clone()),
        version: Set(version),
        context: Set(context_text),
        games: Set(json!(games).to_string()),
        screen: Set(!screen.is_empty()),
        voice: Set(voice.is_some()),
        state: Set("new".into()),
        note: Set(String::new()),
        answer_message: Set(None),
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

/// A report gone with its files.
async fn remove(app: &AppRef, id: i64) {
    for f in ["screen.png", "voice.ogg"] {
        if let Err(e) = app.store.delete_path(&path(id, f)).await {
            tracing::error!("reports: deleting {}: {e}", path(id, f));
        }
    }
    if let Err(e) = report::Entity::delete_by_id(id).exec(&app.db).await {
        tracing::error!("reports: deleting {id}: {e}");
    }
}

/// The new reports (the dashboard's count).
pub async fn new_count(app: &AppRef) -> Result<u64, sea_orm::DbErr> {
    report::Entity::find().filter(report::Column::State.eq("new")).filter(report::Column::Subserver.eq(0)).count(&app.db).await
}

// --- the admin panel ------------------------------------------------------------------------------

pub fn admin_routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/reports", get(list))
        .route("/admin/api/reports/export", get(export))
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

/// The reports the filters (or the ticked ids) pick, newest first.
async fn select(app: &AppRef, q: &ListQ) -> Result<Select<report::Entity>, sea_orm::DbErr> {
    let mut sel = report::Entity::find().filter(report::Column::Subserver.eq(q.subserver.unwrap_or(0))).order_by_desc(report::Column::Id);
    if let Some(ids) = q.ids.as_deref().filter(|s| !s.is_empty()) {
        let ids: Vec<i64> = ids.split(',').filter_map(|s| s.trim().parse().ok()).collect();
        return Ok(sel.filter(report::Column::Id.is_in(ids)));
    }
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
           "written_at": r.written_at, "received_at": r.received_at, "text": r.text, "version": r.version,
           "context": parse(&r.context), "games": parse(&r.games), "screen": r.screen, "voice": r.voice,
           "state": r.state, "note": r.note, "answer_message": r.answer_message})
}

async fn with_accounts(app: &AppRef, rows: &[report::Model]) -> Result<Vec<Value>, sea_orm::DbErr> {
    let mut ids: Vec<i64> = rows.iter().map(|r| r.account).collect();
    ids.sort_unstable();
    ids.dedup();
    let who: HashMap<i64, Account> = accounts_in_order(&app.db, &ids).await?.into_iter().map(|a| (a.id, a)).collect();
    Ok(rows.iter().map(|r| report_json(r, who.get(&r.account))).collect())
}

/// `{list, total, page, size, new, versions}`.
async fn list(State(app): State<AppRef>, Extension(me): Extension<Admin>, Query(q): Query<ListQ>) -> Response {
    let sub = q.subserver.unwrap_or(0);
    if !may(&app, me.me.id, "reports.view", sub).await {
        return err(StatusCode::FORBIDDEN, "You may not see the reports");
    }
    let r = async {
        let (page, size) = (q.page.unwrap_or(0).min(1_000_000), q.size.unwrap_or(50).clamp(1, 500));
        let (rows, total) = page_of(select(&app, &q).await?, page, size, &app.db).await?;
        let new = report::Entity::find().filter(report::Column::Subserver.eq(sub)).filter(report::Column::State.eq("new")).count(&app.db).await?;
        let versions: Vec<String> = report::Entity::find()
            .select_only()
            .column(report::Column::Version)
            .filter(report::Column::Subserver.eq(sub))
            .distinct()
            .order_by_desc(report::Column::Version)
            .into_tuple()
            .all(&app.db)
            .await?;
        let list = with_accounts(&app, &rows).await?;
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "total": total, "page": page, "size": size, "new": new, "versions": versions}))
    };
    match r.await {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// A report: its fields, the games (`{game, replay, mode, players, ended}`), the answer (`{id, text, at}`).
/// Opening a new one makes it seen.
async fn one(State(app): State<AppRef>, Extension(me): Extension<Admin>, Path(id): Path<i64>) -> Response {
    let r = async {
        let Some(mut r) = report::Entity::find_by_id(id).one(&app.db).await? else { return Ok(None) };
        if !may(&app, me.me.id, "reports.view", r.subserver).await {
            return Ok(Some(Err(())));
        }
        if r.state == "new" && may(&app, me.me.id, "reports.manage", r.subserver).await {
            let mut m: report::ActiveModel = r.clone().into();
            m.state = Set("seen".into());
            r = m.update(&app.db).await?;
        }
        let mut v = with_accounts(&app, std::slice::from_ref(&r)).await?.remove(0);
        let mut games = vec![];
        for g in v["games"].as_array().cloned().unwrap_or_default() {
            let g = g.as_str().unwrap_or_default().to_string();
            let d = crate::replays::data(&app.db, &g).await?;
            let ended = replay::Entity::find_by_id(&g).select_only().column(replay::Column::Ended).into_tuple::<i64>().one(&app.db).await?;
            games.push(match d {
                Some(d) => json!({"game": g, "replay": true, "mode": d["mode"], "pack_name": d["pack_name"], "ended": ended,
                                  "players": [d["players"][0]["name"], d["players"][1]["name"]], "winner": d["result"]["winner"]}),
                None => json!({"game": g, "replay": false}),
            });
        }
        v["games"] = json!(games);
        if let Some(m) = r.answer_message {
            v["answer"] = match message::Entity::find_by_id(m).one(&app.db).await? {
                Some(m) => json!({"id": m.id, "text": m.text, "at": m.at}),
                None => json!({"id": m}),
            };
        }
        Ok::<_, sea_orm::DbErr>(Some(Ok(v)))
    };
    match r.await {
        Ok(Some(Ok(v))) => Json(v).into_response(),
        Ok(Some(Err(()))) => err(StatusCode::FORBIDDEN, "You may not see this report"),
        Ok(None) => err(StatusCode::NOT_FOUND, "No such report"),
        Err(e) => db_err(e),
    }
}

/// `screen.png` or `voice.ogg` of a report.
async fn file(State(app): State<AppRef>, Extension(me): Extension<Admin>, Path((id, what)): Path<(i64, String)>) -> Response {
    let mime = match what.as_str() {
        "screen.png" => "image/png",
        "voice.ogg" => "audio/ogg",
        _ => return err(StatusCode::NOT_FOUND, "No such file"),
    };
    let r = match report::Entity::find_by_id(id).one(&app.db).await {
        Ok(Some(r)) => r,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such report"),
        Err(e) => return db_err(e),
    };
    if !may(&app, me.me.id, "reports.view", r.subserver).await {
        return err(StatusCode::FORBIDDEN, "You may not see this report");
    }
    match app.store.read_path(&path(id, &what), (MAX_SCREEN + MAX_VOICE) as u64).await {
        Ok(b) => ([(header::CONTENT_TYPE, mime), (header::CACHE_CONTROL, "private, max-age=86400")], b).into_response(),
        Err(e) => {
            tracing::warn!("reports: {}: {e}", path(id, &what));
            err(StatusCode::NOT_FOUND, "The file is not in the store")
        }
    }
}

/// `state {state}`, `note {note}`, `answer {text}` (a private message to the player), `delete`.
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
    let mut m: report::ActiveModel = r.clone().into();
    let text = |k: &str| body[k].as_str().unwrap_or_default().trim().to_string();
    let log = |what: String, data: Value| app.event(me.ev(format!("{} {what} (report {id})", me.me.name)).data(json!({"action": "report", "report": id, "change": data})));
    match what.as_str() {
        "state" => {
            let s = text("state");
            if !STATES.contains(&s.as_str()) {
                return err(StatusCode::BAD_REQUEST, "The state is new, seen or done");
            }
            log(format!("marked a problem report {s}"), json!({"state": s}));
            m.state = Set(s);
        }
        "note" => {
            let n = text("note");
            if n.chars().count() > MAX_TEXT {
                return err(StatusCode::BAD_REQUEST, "A note is 4000 characters at most");
            }
            log("wrote a note on a problem report".into(), json!({"note": n}));
            m.note = Set(n);
        }
        "answer" => {
            let t = text("text");
            if t.is_empty() || t.chars().count() > 500 {
                return err(StatusCode::BAD_REQUEST, "A message is 1 to 500 characters");
            }
            if r.account == me.me.id {
                return err(StatusCode::BAD_REQUEST, "This is your own report");
            }
            let (msg, at) = match store_msg(&app.db, me.me.id, r.account, &t).await {
                Ok(x) => x,
                Err(e) => return db_err(e),
            };
            app.hub().send(r.account, &json!({"t": "msg", "from": me.me.name, "text": t, "at": at}));
            log("answered a problem report".into(), json!({"text": t, "message": msg}));
            m.answer_message = Set(Some(msg));
        }
        "delete" => {
            remove(&app, id).await;
            log("deleted a problem report".into(), json!({"deleted": true}));
            return Json(json!({"ok": true})).into_response();
        }
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    }
    match m.update(&app.db).await {
        Ok(r) => Json(report_json(&r, None)).into_response(),
        Err(e) => db_err(e),
    }
}

/// The export: `format=json`: the reports as JSON; else a zip of `reports.json` and per report
/// `<id>/screen.png`, `<id>/voice.ogg`, `<id>/<game>.chsreplay` (the paths are in reports.json's
/// `files`). All, the filtered (the list's filters) or the ticked (`ids`).
async fn export(State(app): State<AppRef>, Extension(me): Extension<Admin>, Query(q): Query<ListQ>) -> Response {
    if !may(&app, me.me.id, "reports.export", q.subserver.unwrap_or(0)).await {
        return err(StatusCode::FORBIDDEN, "You may not export the reports");
    }
    // ponytail: at most 2000 reports in one export, the zip built in a temp file at once; stream it if that grows
    let rows = match select(&app, &q).await {
        Ok(sel) => sel.limit(2000).all(&app.db).await,
        Err(e) => Err(e),
    };
    let rows = match rows {
        Ok(r) => r,
        Err(e) => return db_err(e),
    };
    let mut list = match with_accounts(&app, &rows).await {
        Ok(l) => l,
        Err(e) => return db_err(e),
    };
    let stamp = now();
    if q.format.as_deref() == Some("json") {
        let disposition = format!("attachment; filename=\"reports-{stamp}.json\"");
        return ([(header::CONTENT_TYPE, "application/json".to_string()), (header::CONTENT_DISPOSITION, disposition)], json!(list).to_string()).into_response();
    }
    match zip(&app, &rows, &mut list).await {
        Ok((size, f)) => {
            let disposition = format!("attachment; filename=\"reports-{stamp}.zip\"");
            let body = Body::from_stream(tokio_util::io::ReaderStream::new(tokio::fs::File::from_std(f)));
            ([(header::CONTENT_TYPE, "application/zip".to_string()), (header::CONTENT_LENGTH, size.to_string()), (header::CONTENT_DISPOSITION, disposition)], body)
                .into_response()
        }
        Err(e) => {
            tracing::error!("reports: export: {e}");
            err(StatusCode::INTERNAL_SERVER_ERROR, "The export failed")
        }
    }
}

/// The zip of `export` in a temp file of its own (already unlinked) → (its size, the file at its start).
async fn zip(app: &AppRef, rows: &[report::Model], list: &mut [Value]) -> Result<(u64, std::fs::File), String> {
    use zip::write::SimpleFileOptions;
    let io = |e: std::io::Error| e.to_string();
    let tmp = std::env::temp_dir().join(format!("chs-reports-{}.zip", rand::random::<u64>()));
    let f = std::fs::File::options().read(true).write(true).create_new(true).open(&tmp).map_err(io)?;
    let _ = std::fs::remove_file(&tmp);
    let mut z = zip::ZipWriter::new(f);
    let stored = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    for (r, v) in rows.iter().zip(list.iter_mut()) {
        let mut files = json!({});
        for (has, name, key) in [(r.screen, "screen.png", "screen"), (r.voice, "voice.ogg", "voice")] {
            if !has {
                continue;
            }
            match app.store.read_path(&path(r.id, name), (MAX_SCREEN + MAX_VOICE) as u64).await {
                Ok(b) => {
                    let at = format!("{}/{name}", r.id);
                    z.start_file(at.as_str(), stored).map_err(|e| e.to_string())?;
                    z.write_all(&b).map_err(io)?;
                    files[key] = json!(at);
                }
                Err(e) => tracing::warn!("reports: export: {}: {e}", path(r.id, name)),
            }
        }
        let mut replays = vec![];
        for g in v["games"].as_array().cloned().unwrap_or_default() {
            let g = g.as_str().unwrap_or_default();
            if let Some(d) = crate::replays::data(&app.db, g).await.map_err(|e| e.to_string())? {
                let name: String = g.chars().filter(char::is_ascii_alphanumeric).collect();
                let at = format!("{}/{name}.chsreplay", r.id);
                z.start_file(at.as_str(), SimpleFileOptions::default()).map_err(|e| e.to_string())?;
                z.write_all(d.to_string().as_bytes()).map_err(io)?;
                replays.push(at);
            }
        }
        files["replays"] = json!(replays);
        v["files"] = files;
    }
    z.start_file("reports.json", SimpleFileOptions::default()).map_err(|e| e.to_string())?;
    z.write_all(serde_json::to_string_pretty(&json!(list)).unwrap_or_default().as_bytes()).map_err(io)?;
    let mut f = z.finish().map_err(|e| e.to_string())?;
    let size = f.stream_position().map_err(io)?;
    f.rewind().map_err(io)?;
    Ok((size, f))
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
}
