//! Tournament chats (0.74): the tournaments list's common chat (channel `tournaments`) and each
//! tournament's own (`t:<tournament id>`), live over the websocket to the players subscribed to a
//! channel (`chat_sub` while the list or a tournament's page is open). Marks: "admin" (may moderate)
//! in every chat, "creator" in its tournament's. A moderator deletes a message: the row stays and
//! everyone sees "deleted by <moderator>". A tournament's chat opens at its creation and closes 10
//! minutes after its end (read-only then). The cleanup removes chat and private messages older
//! than the keeping time (`settings::CHAT_KEEP_DAYS`). Protocol: server/README.md, "Chats".

use crate::admin::{db_err, err, Admin};
use crate::entity::{account, chat_message as cm, message, tournament as tour};
use crate::events::{now_ms, Event};
use crate::tournament::TErr;
use crate::{ranked, settings, App, AppRef};
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, QueryFilter, QueryOrder, QuerySelect, Set};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

/// The messages a subscriber gets first (`chat_history`).
pub const HISTORY: u64 = 100;
/// A tournament's chat closes this long after the tournament's end.
pub const CLOSE_AFTER_MS: i64 = 10 * 60_000;
const MAX_TEXT: usize = 500;
/// The channel name of the tournaments list's chat.
pub const LIST: &str = "tournaments";

type Res<T> = Result<T, TErr>;

fn no(code: &'static str, text: &str) -> TErr {
    TErr(code, text.into())
}

/// The one permission check of the chats: `chats.moderate`, `chats.write_as_admin`, `settings.retention`.
// The roles (0.74, `perm::has(app, account, perm, subserver)`) replace this; until then an admin has them all.
pub async fn may(app: &App, account: i64, _perm: &str) -> bool {
    matches!(account::Entity::find_by_id(account).one(&app.db).await, Ok(Some(a)) if matches!(a.role.as_str(), "admin" | "super"))
}

/// A channel's tournament (None: the list's chat), or why the channel is not one.
async fn tournament_of(app: &App, channel: &str) -> Res<Option<tour::Model>> {
    if channel == LIST {
        return Ok(None);
    }
    let id = channel.strip_prefix("t:").and_then(|s| s.parse::<i64>().ok()).ok_or_else(|| no("bad_request", "channel: tournaments or t:<id>"))?;
    tour::Entity::find_by_id(id).one(&app.db).await?.map(Some).ok_or_else(|| no("not_found", "No such tournament"))
}

/// When the chat closes (unix ms; 0: the list's chat, or a tournament not over yet).
fn closes_ms(t: &Option<tour::Model>) -> i64 {
    t.as_ref().filter(|t| t.ended > 0).map_or(0, |t| t.ended + CLOSE_AFTER_MS)
}

fn is_open(t: &Option<tour::Model>, now_ms: i64) -> bool {
    let c = closes_ms(t);
    c == 0 || now_ms < c
}

/// Messages as players see them: the sender's mark, and "deleted by" instead of a deleted one's
/// text (`with_deleted`: the admin panel also gets that text as `deleted_text`).
async fn to_json(app: &App, t: &Option<tour::Model>, rows: &[cm::Model], with_deleted: bool) -> Res<Vec<Value>> {
    let ids: HashSet<i64> = rows.iter().flat_map(|m| [Some(m.account), m.deleted_by]).flatten().collect();
    let names: HashMap<i64, String> =
        account::Entity::find().filter(account::Column::Id.is_in(ids)).all(&app.db).await?.into_iter().map(|a| (a.id, a.name)).collect();
    let mut admin = HashMap::new();
    for m in rows {
        if !admin.contains_key(&m.account) {
            admin.insert(m.account, may(app, m.account, "chats.moderate").await);
        }
    }
    let name = |id: i64| names.get(&id).cloned().unwrap_or_else(|| "?".into());
    Ok(rows
        .iter()
        .map(|m| {
            let mark = if admin[&m.account] {
                "admin"
            } else if t.as_ref().is_some_and(|t| t.creator == m.account) {
                "creator"
            } else {
                ""
            };
            let by = m.deleted_by.map(name).unwrap_or_default();
            let mut v = json!({"id": m.id, "from": name(m.account), "text": if by.is_empty() { &m.text } else { "" }, "at": m.at,
                               "mark": mark, "deleted_by": by});
            if with_deleted && m.deleted_by.is_some() {
                v["deleted_text"] = json!(m.text);
            }
            v
        })
        .collect())
}

/// The last `n` messages of a channel, oldest first.
async fn last(app: &App, channel: &str, n: u64) -> Res<Vec<cm::Model>> {
    let mut rows = cm::Entity::find()
        .filter(cm::Column::Subserver.eq(0))
        .filter(cm::Column::Channel.eq(channel))
        .order_by_desc(cm::Column::Id)
        .limit(n)
        .all(&app.db)
        .await?;
    rows.reverse();
    Ok(rows)
}

fn broadcast(app: &App, channel: &str, v: &Value) {
    let hub = app.hub();
    for a in hub.chats.get(channel).into_iter().flatten() {
        hub.send(*a, v);
    }
}

/// `chat_sub`: the player gets the channel's live messages from now on; the answer is its history.
pub async fn subscribe(app: &App, me: i64, channel: &str) -> Res<Value> {
    let t = tournament_of(app, channel).await?;
    let list = to_json(app, &t, &last(app, channel, HISTORY).await?, false).await?;
    app.hub().chats.entry(channel.to_string()).or_default().insert(me);
    Ok(json!({"t": "chat_history", "channel": channel, "list": list, "open": is_open(&t, now_ms()),
              "closes": (closes_ms(&t) + 999) / 1000, "moderator": may(app, me, "chats.moderate").await}))
}

/// `chat_unsub`.
pub fn unsubscribe(app: &App, me: i64, channel: &str) {
    let mut hub = app.hub();
    if let Some(subs) = hub.chats.get_mut(channel) {
        subs.remove(&me);
        if subs.is_empty() {
            hub.chats.remove(channel);
        }
    }
}

/// A message to a channel (a player's `chat_send`, or the admin panel's): every subscriber gets it.
pub async fn send(app: &App, me: i64, channel: &str, text: &str) -> Res<Value> {
    let n = text.chars().count();
    if n == 0 || n > MAX_TEXT || text.trim().is_empty() {
        return Err(no("bad_text", "A message is 1 to 500 characters"));
    }
    let t = tournament_of(app, channel).await?;
    if !is_open(&t, now_ms()) {
        return Err(no("chat_closed", "This chat is closed"));
    }
    let row = cm::ActiveModel { subserver: Set(0), channel: Set(channel.into()), account: Set(me), text: Set(text.into()), at: Set(ranked::now()), ..Default::default() }
        .insert(&app.db)
        .await?;
    let msg = to_json(app, &t, &[row], false).await?.remove(0);
    app.event(Event::new("chat", format!("{} in {channel}: {text}", msg["from"].as_str().unwrap_or("?"))).user(me, msg["from"].as_str().unwrap_or("?")).data(json!({"channel": channel, "id": msg["id"]})));
    broadcast(app, channel, &json!({"t": "chat_msg", "channel": channel, "msg": msg}));
    Ok(msg)
}

/// A moderator deletes a message (`chat_delete`, or the admin panel): the row stays, its text hidden.
pub async fn delete(app: &App, me: i64, id: i64) -> Res<()> {
    if !may(app, me, "chats.moderate").await {
        return Err(no("forbidden", "Only moderators delete messages"));
    }
    let m = cm::Entity::find_by_id(id).filter(cm::Column::Subserver.eq(0)).one(&app.db).await?.ok_or_else(|| no("not_found", "No such message"))?;
    if m.deleted_by.is_some() {
        return Ok(());
    }
    let by = crate::db::name_of(&app.db, me).await?;
    let channel = m.channel.clone();
    let mut a: cm::ActiveModel = m.into();
    a.deleted_by = Set(Some(me));
    a.deleted_at = Set(Some(ranked::now()));
    a.update(&app.db).await?;
    app.event(Event::new("chat", format!("{by} deleted a message in {channel}")).user(me, &by).data(json!({"channel": channel, "id": id})));
    broadcast(app, &channel, &json!({"t": "chat_deleted", "channel": channel, "id": id, "by": by}));
    Ok(())
}

/// The tournament chats that closed in (from, to] (unix ms) tell their subscribers (`chat_closed`).
pub async fn announce_closed(app: &App, from: i64, to: i64) {
    let ids: Vec<i64> = app.hub().chats.keys().filter_map(|c| c.strip_prefix("t:")?.parse().ok()).collect();
    if ids.is_empty() {
        return;
    }
    let closing = tour::Entity::find()
        .filter(tour::Column::Id.is_in(ids))
        .filter(tour::Column::Ended.gt(0))
        .filter(tour::Column::Ended.gt(from - CLOSE_AFTER_MS))
        .filter(tour::Column::Ended.lte(to - CLOSE_AFTER_MS))
        .all(&app.db)
        .await;
    match closing {
        Ok(rows) => {
            for t in rows {
                let channel = format!("t:{}", t.id);
                broadcast(app, &channel, &json!({"t": "chat_closed", "channel": channel}));
            }
        }
        Err(e) => tracing::error!("chat: closing: {e}"),
    }
}

/// Removes the chat and private messages older than the keeping time (none when it is 0, unlimited).
/// `now`: unix seconds. Returns how many of each were removed.
pub async fn cleanup(app: &App, now: i64) -> Result<(u64, u64), sea_orm::DbErr> {
    let days = settings::chat_keep_days(app).await?;
    if days <= 0 {
        return Ok((0, 0));
    }
    let before = now - days * 86_400;
    let chats = cm::Entity::delete_many().filter(cm::Column::At.lt(before)).exec(&app.db).await?.rows_affected;
    let privates = message::Entity::delete_many().filter(message::Column::At.lt(before)).exec(&app.db).await?.rows_affected;
    Ok((chats, privates))
}

// --- the admin panel's Chats page ----------------------------------------------------------------

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/chats", get(admin_list))
        .route("/admin/api/chats/{channel}", get(admin_get).post(admin_send))
        .route("/admin/api/chat_messages/{id}/delete", post(admin_delete))
}

fn refused(e: TErr) -> Response {
    match e.0 {
        "server" => err(StatusCode::INTERNAL_SERVER_ERROR, &e.1),
        "forbidden" => err(StatusCode::FORBIDDEN, &e.1),
        "not_found" => err(StatusCode::NOT_FOUND, &e.1),
        _ => err(StatusCode::BAD_REQUEST, &e.1),
    }
}

/// `{chats: [{channel, title, status, count, last, open}]}`: the list's chat first, then the
/// tournaments' chats that have messages or are still open, the latest active first.
async fn admin_list(State(app): State<AppRef>) -> Response {
    let r = async {
        let counts: Vec<(String, i64, i64)> = cm::Entity::find()
            .select_only()
            .column(cm::Column::Channel)
            .column_as(cm::Column::Id.count(), "n")
            .column_as(cm::Column::At.max(), "last")
            .filter(cm::Column::Subserver.eq(0))
            .group_by(cm::Column::Channel)
            .into_tuple()
            .all(&app.db)
            .await?;
        let counts: HashMap<String, (i64, i64)> = counts.into_iter().map(|(c, n, l)| (c, (n, l))).collect();
        let now = now_ms();
        let with_msgs: Vec<i64> = counts.keys().filter_map(|c| c.strip_prefix("t:")?.parse().ok()).collect();
        let open = sea_orm::Condition::any().add(tour::Column::Ended.eq(0)).add(tour::Column::Ended.gt(now - CLOSE_AFTER_MS));
        let ts = tour::Entity::find().filter(sea_orm::Condition::any().add(tour::Column::Id.is_in(with_msgs)).add(open)).all(&app.db).await?;
        let (n, l) = counts.get(LIST).copied().unwrap_or_default();
        let mut list = vec![json!({"channel": LIST, "title": "", "status": "", "count": n, "last": l, "open": true})];
        let mut rest: Vec<Value> = ts
            .into_iter()
            .map(|t| {
                let channel = format!("t:{}", t.id);
                let (n, l) = counts.get(&channel).copied().unwrap_or_default();
                let open = is_open(&Some(t.clone()), now);
                json!({"channel": channel, "title": t.name, "status": t.status, "count": n, "last": l.max(t.created / 1000), "open": open})
            })
            .collect();
        rest.sort_by_key(|v| std::cmp::Reverse(v["last"].as_i64()));
        list.extend(rest);
        Ok::<_, sea_orm::DbErr>(json!({"chats": list}))
    }
    .await;
    match r {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// `{channel, title, open, closes, list}`: the last 500 messages, deleted ones with their text.
async fn admin_get(State(app): State<AppRef>, Path(channel): Path<String>) -> Response {
    let r = async {
        let t = tournament_of(&app, &channel).await?;
        let list = to_json(&app, &t, &last(&app, &channel, 500).await?, true).await?;
        Ok::<_, TErr>(json!({"channel": channel, "title": t.as_ref().map_or("", |t| &t.name), "open": is_open(&t, now_ms()),
                              "closes": (closes_ms(&t) + 999) / 1000, "list": list}))
    }
    .await;
    match r {
        Ok(v) => Json(v).into_response(),
        Err(e) => refused(e),
    }
}

#[derive(Deserialize)]
struct SendIn {
    text: String,
}

/// The admin writes in a chat as themselves (marked "admin").
async fn admin_send(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(channel): Path<String>, Json(f): Json<SendIn>) -> Response {
    if !may(&app, a.me.id, "chats.write_as_admin").await {
        return err(StatusCode::FORBIDDEN, "Not allowed");
    }
    match send(&app, a.me.id, &channel, &f.text).await {
        Ok(msg) => Json(json!({"ok": true, "msg": msg})).into_response(),
        Err(e) => refused(e),
    }
}

async fn admin_delete(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    match delete(&app, a.me.id, id).await {
        Ok(()) => Json(json!({"ok": true})).into_response(),
        Err(e) => refused(e),
    }
}
