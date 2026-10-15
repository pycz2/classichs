//! One WebSocket client: strict JSON messages {"t": …}, auth, social, queues, Arena, games.

use crate::auth::{self, RateLimit};
use crate::db::{self, Account, DbError, DbResult};
use crate::entity::{account, arena, block, friend, message, request};
use crate::events::Event;
use crate::game::{self, rank_json};
use crate::ranked::{self, Key, Mode};
use crate::{presence, AppRef, Out, Seeker};
use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use rand::Rng;
use sea_orm::sea_query::Expr;
use sea_orm::{
    ActiveModelTrait, ColumnTrait, Condition, ConnectionTrait, DatabaseTransaction, EntityTrait, PaginatorTrait, QueryFilter,
    QueryOrder, QuerySelect, Set, TransactionTrait, Unchanged,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::IpAddr;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::{self, UnboundedSender};

/// Malformed messages before the connection is closed.
const MAX_ERRORS: u32 = 20;
const MAX_FRIENDS: u64 = 200;
const HISTORY: u64 = 200;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeckIn {
    hero: String,
    cards: Vec<String>,
    #[serde(default)]
    #[allow(dead_code)]
    name: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    arena: Option<bool>,
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum QMode {
    Casual,
    Ranked,
}

#[derive(Deserialize)]
#[serde(tag = "t", rename_all = "snake_case", deny_unknown_fields)]
enum In {
    Register { user: String, password: String },
    Login { user: String, password: String },
    Resume { token: String },
    Logout {},
    Ping {},
    Me {},
    SetTag { tag: String },
    Friends {},
    FriendAdd { tag: String },
    FriendAccept { user: String },
    FriendDecline { user: String },
    FriendRemove { user: String },
    Block { user: String },
    Unblock { user: String },
    Msg { to: String, text: String },
    History { with: String },
    Chats {},
    Read { with: String },
    Invite { to: String, deck: DeckIn },
    InviteAccept { from: String, deck: DeckIn },
    InviteDecline { from: String },
    Queue { mode: QMode, deck: DeckIn },
    Unqueue {},
    ArenaStart {},
    ArenaHero { i: f64 },
    ArenaPick { i: f64 },
    ArenaQueue {},
    ArenaRetire {},
    Act {
        action: Value,
        #[serde(default)]
        game: Option<String>,
    },
    Emote {
        id: String,
        #[serde(default)]
        game: Option<String>,
    },
    Intent {
        i: Value,
        #[serde(default)]
        game: Option<String>,
    },
}

/// An error reply: code and text (and, for server errors, what went wrong, for the event log).
pub struct E(&'static str, String, Option<String>);

impl From<DbError> for E {
    fn from(err: DbError) -> E {
        tracing::error!("db: {err}");
        E("server", "Server error".into(), Some(format!("database: {err}")))
    }
}

fn e(code: &'static str, text: &str) -> E {
    E(code, text.into(), None)
}

type R = Result<(), E>;

struct Session {
    app: AppRef,
    tx: UnboundedSender<Out>,
    ip: IpAddr,
    me: Option<(i64, String)>,
    token: String,
    conn: u64,
    errors: u32,
    chat: RateLimit,
}

pub async fn run(app: AppRef, socket: WebSocket, ip: IpAddr) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Out>();
    // ponytail: unbounded outbox; inbound rate limits bound what peers can push. Bound it if memory ever matters.
    let mut writer = tokio::spawn(async move {
        while let Some(o) = rx.recv().await {
            match o {
                Out::Text(t) => {
                    if sink.send(Message::Text(t.into())).await.is_err() {
                        break;
                    }
                }
                Out::Close => {
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                }
            }
        }
    });
    let mut s = Session {
        app,
        tx,
        ip,
        me: None,
        token: String::new(),
        conn: 0,
        errors: 0,
        chat: RateLimit::new(10, Duration::from_secs(10)),
    };
    let mut general = RateLimit::new(300, Duration::from_secs(10));
    let mut writer_done = false;
    loop {
        let msg = tokio::select! {
            m = stream.next() => m,
            _ = &mut writer => { writer_done = true; break }
        };
        match msg {
            Some(Ok(Message::Text(t))) => {
                if !general.allow("", Instant::now()) {
                    s.reply("", Err(e("rate_limited", "Too many messages")));
                    if let Some((id, name)) = &s.me {
                        s.app.event(Event::new("error", format!("{name} sent too many messages: disconnected")).user(*id, name));
                    }
                    break;
                }
                s.handle(t.as_str()).await;
                if s.errors >= MAX_ERRORS {
                    break;
                }
            }
            Some(Ok(Message::Binary(_))) => {
                s.errors += 1;
                s.reply("", Err(e("bad_request", "Text frames only")));
            }
            Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
            Some(Ok(_)) => {}
        }
    }
    if let Some((id, name)) = s.me.take() {
        let ours = s.app.hub().conns.get(&id).is_some_and(|c| c.id == s.conn);
        s.app.hub().detach(id, Some(s.conn));
        let _ = db::touch(&s.app.db, id).await;
        if ours {
            s.app.event(Event::new("disconnect", format!("{name} went offline")).user(id, &name));
        }
        presence(&s.app, id).await;
    }
    let _ = s.tx.send(Out::Close);
    drop(s);
    if !writer_done {
        let _ = tokio::time::timeout(Duration::from_secs(5), writer).await;
    }
}

fn not_found(what: &str) -> DbError {
    DbError::RecordNotFound(what.into())
}

async fn are_friends(c: &impl ConnectionTrait, a: i64, b: i64) -> DbResult<bool> {
    Ok(friend::Entity::find_by_id((a, b)).one(c).await?.is_some())
}

async fn blocked(c: &impl ConnectionTrait, who: i64, whom: i64) -> DbResult<bool> {
    Ok(block::Entity::find_by_id((who, whom)).one(c).await?.is_some())
}

async fn friend_count(c: &impl ConnectionTrait, a: i64) -> DbResult<u64> {
    friend::Entity::find().filter(friend::Column::A.eq(a)).count(c).await
}

pub async fn friend_ids(c: &impl ConnectionTrait, me: i64) -> DbResult<Vec<i64>> {
    friend::Entity::find().select_only().column(friend::Column::B).filter(friend::Column::A.eq(me)).into_tuple().all(c).await
}

/// Accounts by id, in the order given.
pub async fn accounts_in_order(c: &impl ConnectionTrait, ids: &[i64]) -> DbResult<Vec<Account>> {
    let found = account::Entity::find().filter(account::Column::Id.is_in(ids.iter().copied())).all(c).await?;
    let mut by_id: HashMap<i64, Account> = found.into_iter().map(|a| (a.id, a)).collect();
    Ok(ids.iter().filter_map(|i| by_id.remove(i)).collect())
}

async fn make_friends(c: &impl ConnectionTrait, a: i64, b: i64) -> DbResult<()> {
    let pair = |a, b| friend::ActiveModel { a: Set(a), b: Set(b) };
    friend::Entity::insert_many([pair(a, b), pair(b, a)]).on_conflict_do_nothing().exec(c).await?;
    Ok(())
}

async fn unfriend(c: &impl ConnectionTrait, a: i64, b: i64) -> DbResult<()> {
    let pair = |a: i64, b: i64| Condition::all().add(friend::Column::A.eq(a)).add(friend::Column::B.eq(b));
    friend::Entity::delete_many().filter(Condition::any().add(pair(a, b)).add(pair(b, a))).exec(c).await?;
    Ok(())
}

/// The friend list, sorted by name.
pub async fn friends_of(c: &impl ConnectionTrait, me: i64) -> DbResult<Vec<Account>> {
    let mut v = accounts_in_order(c, &friend_ids(c, me).await?).await?;
    v.sort_by_key(|a| a.name.to_lowercase());
    Ok(v)
}

async fn arena_json(c: &impl ConnectionTrait, me: i64) -> DbResult<Value> {
    Ok(match arena::Entity::find_by_id(me).one(c).await? {
        None => Value::Null,
        Some(a) => {
            let mut v: Value = serde_json::from_str(&a.draft).unwrap_or_else(|_| json!({}));
            if let Some(o) = v.as_object_mut() {
                o.remove("ok");
            }
            v["wins"] = json!(a.wins);
            v["losses"] = json!(a.losses);
            v
        }
    })
}

async fn me_json(c: &impl ConnectionTrait, me: i64) -> DbResult<Value> {
    let mut a = db::account_by_id(c, me).await?.ok_or_else(|| not_found("account"))?;
    db::refresh_season(c, &mut a).await?;
    Ok(json!({"user": a.name, "tag": a.tag, "rank": rank_json(c, &a).await?, "arena": arena_json(c, me).await?,
              "season": ranked::season_name(a.season)}))
}

/// The friends message for an account (online status from the hub).
async fn friends_json(app: &AppRef, me: i64) -> Result<Value, E> {
    let c = &app.db;
    let friends = friends_of(c, me).await?;
    let reqs = |col: request::Column, val: i64| request::Entity::find().filter(col.eq(val)).order_by_asc(request::Column::At).all(c);
    let ins: Vec<i64> = reqs(request::Column::Dst, me).await?.iter().map(|r| r.src).collect();
    let outs: Vec<i64> = reqs(request::Column::Src, me).await?.iter().map(|r| r.dst).collect();
    let blocks: Vec<i64> = block::Entity::find().filter(block::Column::Who.eq(me)).all(c).await?.iter().map(|b| b.whom).collect();
    let (ins, outs) = (accounts_in_order(c, &ins).await?, accounts_in_order(c, &outs).await?);
    let mut blocks = accounts_in_order(c, &blocks).await?;
    blocks.sort_by_key(|a| a.name.to_lowercase());
    let hub = app.hub();
    let plain = |l: &[Account]| l.iter().map(|a| json!({"user": a.name, "tag": a.tag})).collect::<Vec<_>>();
    let list: Vec<Value> = friends
        .iter()
        .map(|a| json!({"user": a.name, "tag": a.tag, "online": hub.conns.contains_key(&a.id), "status": hub.status(a.id)}))
        .collect();
    Ok(json!({"t": "friends", "list": list, "requests_in": plain(&ins), "requests_out": plain(&outs), "blocked": plain(&blocks)}))
}

/// All friends with the latest message of each conversation and the unread count, the
/// latest conversations first.
async fn chats_json(app: &AppRef, me: i64) -> Result<Value, E> {
    let c = &app.db;
    let friends = friends_of(c, me).await?;
    let mine = Condition::any().add(message::Column::Lo.eq(me)).add(message::Column::Hi.eq(me));
    let unread: HashMap<i64, i64> = message::Entity::find()
        .select_only()
        .column(message::Column::Src)
        .column_as(message::Column::Id.count(), "n")
        .filter(mine.clone())
        .filter(message::Column::Src.ne(me))
        .filter(message::Column::Seen.eq(false))
        .group_by(message::Column::Src)
        .into_tuple::<(i64, i64)>()
        .all(c)
        .await?
        .into_iter()
        .collect();
    let last_ids: Vec<i64> = message::Entity::find()
        .select_only()
        .column_as(message::Column::Id.max(), "id")
        .filter(mine)
        .group_by(message::Column::Lo)
        .group_by(message::Column::Hi)
        .into_tuple()
        .all(c)
        .await?;
    let last: HashMap<i64, message::Model> = message::Entity::find()
        .filter(message::Column::Id.is_in(last_ids))
        .all(c)
        .await?
        .into_iter()
        .map(|m| (if m.lo == me { m.hi } else { m.lo }, m))
        .collect();
    let my_name = db::name_of(c, me).await?;
    let hub = app.hub();
    let mut list: Vec<(i64, Value)> = friends
        .iter()
        .map(|a| {
            let l = last.get(&a.id);
            let lj = l.map(|m| json!({"from": if m.src == me { &my_name } else { &a.name }, "text": m.text, "at": m.at}));
            (l.map_or(-1, |m| m.id), json!({"with": a.name, "tag": a.tag, "online": hub.conns.contains_key(&a.id),
                   "status": hub.status(a.id), "last": lj, "unread": unread.get(&a.id).copied().unwrap_or(0)}))
        })
        .collect();
    drop(hub);
    list.sort_by_key(|(id, _)| std::cmp::Reverse(*id)); // stable: friends without messages stay by name
    Ok(json!({"t": "chats", "list": list.into_iter().map(|(_, v)| v).collect::<Vec<_>>()}))
}

async fn push_friends(app: &AppRef, who: i64) {
    if app.hub().conns.contains_key(&who) {
        if let Ok(v) = friends_json(app, who).await {
            app.hub().send(who, &v);
        }
    }
}

fn deck_value(d: &DeckIn, arena: bool) -> Result<Value, E> {
    if d.cards.len() != 30 || d.hero.len() > 32 || d.cards.iter().any(|c| c.len() > 64) {
        return Err(e("deck", "A deck needs exactly 30 cards"));
    }
    Ok(json!({"hero": d.hero, "cards": d.cards, "arena": arena}))
}

fn index(i: f64, n: usize) -> Result<usize, E> {
    if i.fract() == 0.0 && i >= 0.0 && (i as usize) < n {
        Ok(i as usize)
    } else {
        Err(e("bad_request", "No such choice"))
    }
}

/// friend_add inside a transaction: (the other account, true = they had asked me: now friends).
async fn friend_add(c: &DatabaseTransaction, me: i64, key: &str) -> Result<(Account, bool), E> {
    let other = account::Entity::find().filter(account::Column::TagKey.eq(key)).one(c).await?;
    let Some(o) = other.filter(|o| o.id != me) else { return Err(e("not_found", "No player with this tag")) };
    if blocked(c, o.id, me).await? {
        return Err(e("not_found", "No player with this tag"));
    }
    if blocked(c, me, o.id).await? {
        return Err(e("blocked", "You blocked this player"));
    }
    if are_friends(c, me, o.id).await? {
        return Err(e("already", "Already friends"));
    }
    if friend_count(c, me).await? >= MAX_FRIENDS {
        return Err(e("friends_full", "You have 200 friends"));
    }
    let theirs = request::Entity::delete_by_id((o.id, me)).exec(c).await?.rows_affected == 1;
    if theirs {
        if friend_count(c, o.id).await? >= MAX_FRIENDS {
            return Err(e("friends_full", "The player has 200 friends"));
        }
        make_friends(c, me, o.id).await?;
    } else {
        let r = request::ActiveModel { src: Set(me), dst: Set(o.id), at: Set(ranked::now()) };
        request::Entity::insert(r).on_conflict_do_nothing().exec(c).await?;
    }
    Ok((o, theirs))
}

#[derive(Clone, Copy)]
enum PairOp {
    Accept,
    Decline,
    Remove,
    Block,
    Unblock,
}

impl PairOp {
    fn kind(self) -> &'static str {
        match self {
            PairOp::Accept => "friend_accept",
            PairOp::Decline => "friend_decline",
            PairOp::Remove => "friend_remove",
            PairOp::Block => "block",
            PairOp::Unblock => "unblock",
        }
    }

    fn verb(self) -> &'static str {
        match self {
            PairOp::Accept => "accepted the friend request of",
            PairOp::Decline => "declined the friend request of",
            PairOp::Remove => "removed the friend",
            PairOp::Block => "blocked",
            PairOp::Unblock => "unblocked",
        }
    }

    /// Applies the change between me and o inside a transaction.
    async fn apply(self, c: &DatabaseTransaction, me: i64, o: i64) -> Result<(), E> {
        let req = |src: i64, dst: i64| request::Entity::delete_by_id((src, dst)).exec(c);
        match self {
            PairOp::Accept => {
                if request::Entity::find_by_id((o, me)).one(c).await?.is_none() {
                    return Err(e("not_found", "No such request"));
                }
                if friend_count(c, me).await? >= MAX_FRIENDS || friend_count(c, o).await? >= MAX_FRIENDS {
                    return Err(e("friends_full", "200 friends at most"));
                }
                req(o, me).await?;
                req(me, o).await?;
                make_friends(c, me, o).await?;
            }
            PairOp::Decline => {
                req(o, me).await?;
            }
            PairOp::Remove => {
                unfriend(c, me, o).await?;
                req(me, o).await?;
            }
            PairOp::Block => {
                block::Entity::insert(block::ActiveModel { who: Set(me), whom: Set(o) }).on_conflict_do_nothing().exec(c).await?;
                unfriend(c, me, o).await?;
                req(me, o).await?;
                req(o, me).await?;
            }
            PairOp::Unblock => {
                block::Entity::delete_by_id((me, o)).exec(c).await?;
            }
        }
        Ok(())
    }
}

impl Session {
    fn send(&self, v: Value) {
        let _ = self.tx.send(Out::Text(v.to_string()));
    }

    fn ok(&self, v: Value) -> R {
        self.send(v);
        Ok(())
    }

    fn name(&self) -> String {
        self.me.as_ref().map(|m| m.1.clone()).unwrap_or_default()
    }

    /// An event by this player.
    fn ev(&self, kind: &'static str, text: impl Into<String>) -> Event {
        let e = Event::new(kind, text);
        match &self.me {
            Some((id, name)) => e.user(*id, name),
            None => e,
        }
    }

    fn reply(&self, t: &str, r: R) {
        if let Err(E(code, text, detail)) = r {
            if code == "server" {
                let what = detail.unwrap_or_else(|| text.clone());
                self.app.event(self.ev("error", format!("{t}: {what}")).data(json!({"code": code, "message": t})));
            }
            self.send(json!({"t": "error", "code": code, "text": text}));
        }
    }

    async fn handle(&mut self, text: &str) {
        let parsed = serde_json::from_str::<Value>(text).and_then(|v| {
            let t = v["t"].as_str().unwrap_or("").chars().take(32).collect::<String>();
            Ok((t, serde_json::from_value::<In>(v)?))
        });
        let (t, msg) = match parsed {
            Ok(m) => m,
            Err(err) => {
                self.errors += 1;
                let mut t = err.to_string();
                t.truncate(200);
                return self.reply("", Err(E("bad_request", t, None)));
            }
        };
        let r = self.dispatch(msg).await;
        self.reply(&t, r);
    }

    async fn dispatch(&mut self, msg: In) -> R {
        let Some((me, my_name)) = self.me.clone() else {
            return match msg {
                In::Register { user, password } => self.register(user, password).await,
                In::Login { user, password } => self.login(user, password).await,
                In::Resume { token } => self.resume(token).await,
                In::Ping {} => self.ok(json!({"t": "pong"})),
                _ => Err(e("auth_required", "Log in first")),
            };
        };
        let app = self.app.clone();
        let db = &app.db;
        match msg {
            In::Register { .. } | In::Login { .. } | In::Resume { .. } => Err(e("bad_request", "Already logged in")),
            In::Ping {} => self.ok(json!({"t": "pong"})),
            In::Logout {} => {
                let t = std::mem::take(&mut self.token);
                db::drop_session(db, &t).await?;
                app.hub().detach(me, Some(self.conn));
                app.event(self.ev("logout", format!("{my_name} logged out")));
                self.me = None;
                presence(&app, me).await;
                self.ok(json!({"t": "logged_out"}))
            }
            In::Me {} => self.send_me(me).await,
            In::SetTag { tag } => {
                if !auth::valid_tag(&tag) {
                    return Err(e("bad_tag", "A tag is 3 to 16 letters or digits"));
                }
                let key = tag.to_lowercase();
                let tx = db.begin().await?;
                let taken = account::Entity::find()
                    .filter(account::Column::TagKey.eq(&key))
                    .filter(account::Column::Id.ne(me))
                    .one(&tx)
                    .await?
                    .is_some();
                if taken {
                    return Err(e("tag_taken", "This tag is taken"));
                }
                account::ActiveModel { id: Unchanged(me), tag: Set(Some(tag.clone())), tag_key: Set(Some(key)), ..Default::default() }
                    .update(&tx)
                    .await?;
                tx.commit().await?;
                app.event(self.ev("tag", format!("{my_name} took the tag {tag}")).data(json!({"tag": tag})));
                self.send_me(me).await
            }
            In::Friends {} => self.ok(friends_json(&app, me).await?),
            In::FriendAdd { tag } => {
                let tx = db.begin().await?;
                let (o, now_friends) = friend_add(&tx, me, &tag.to_lowercase()).await?;
                tx.commit().await?;
                let ev = if now_friends {
                    self.ev("friend_accept", format!("{my_name} and {} are friends now", o.name))
                } else {
                    self.ev("friend_request", format!("{my_name} asked {} to be friends", o.name))
                };
                app.event(ev.other(&o.name).data(json!({"tag": tag})));
                self.friends_changed(o.id).await?;
                if now_friends {
                    self.presence_pair(o.id).await;
                }
                Ok(())
            }
            In::FriendAccept { user } => self.pair_op(user, PairOp::Accept).await,
            In::FriendDecline { user } => self.pair_op(user, PairOp::Decline).await,
            In::FriendRemove { user } => self.pair_op(user, PairOp::Remove).await,
            In::Block { user } => self.pair_op(user, PairOp::Block).await,
            In::Unblock { user } => self.pair_op(user, PairOp::Unblock).await,
            In::Msg { to, text } => {
                let n = text.chars().count();
                if n == 0 || n > 500 || text.trim().is_empty() {
                    return Err(e("bad_text", "A message is 1 to 500 characters"));
                }
                if !self.chat.allow("", Instant::now()) {
                    return Err(e("rate_limited", "Too many messages: wait a little"));
                }
                let tx = db.begin().await?;
                let o = match db::account_by_name(&tx, &to).await? {
                    Some(o) if are_friends(&tx, me, o.id).await? => o,
                    Some(_) => return Err(e("not_friends", "Messages go to friends only")),
                    None => return Err(e("not_found", "No such player")),
                };
                let (lo, hi, at) = (me.min(o.id), me.max(o.id), ranked::now());
                let m = message::ActiveModel { lo: Set(lo), hi: Set(hi), src: Set(me), text: Set(text.clone()), at: Set(at), seen: Set(false), ..Default::default() };
                message::Entity::insert(m).exec_without_returning(&tx).await?;
                let pair = Condition::all().add(message::Column::Lo.eq(lo)).add(message::Column::Hi.eq(hi));
                let oldest_kept: Option<i64> = message::Entity::find()
                    .select_only()
                    .column(message::Column::Id)
                    .filter(pair.clone())
                    .order_by_desc(message::Column::Id)
                    .offset(HISTORY - 1)
                    .limit(1)
                    .into_tuple()
                    .one(&tx)
                    .await?;
                if let Some(id) = oldest_kept {
                    message::Entity::delete_many().filter(pair).filter(message::Column::Id.lt(id)).exec(&tx).await?;
                }
                tx.commit().await?;
                app.event(
                    self.ev("msg", format!("{my_name} → {}: {text}", o.name))
                        .other(&o.name)
                        .data(json!({"text": text, "from": me, "to": o.id})),
                );
                app.hub().send(o.id, &json!({"t": "msg", "from": my_name, "text": text, "at": at}));
                self.ok(json!({"t": "msg_sent", "to": o.name, "at": at}))
            }
            In::History { with } => {
                let o = db::account_by_name(db, &with).await?.ok_or_else(|| e("not_found", "No such player"))?;
                let mut list: Vec<Value> = message::Entity::find()
                    .filter(message::Column::Lo.eq(me.min(o.id)))
                    .filter(message::Column::Hi.eq(me.max(o.id)))
                    .order_by_desc(message::Column::Id)
                    .limit(HISTORY)
                    .all(db)
                    .await?
                    .into_iter()
                    .map(|m| json!({"from": if m.src == me { &my_name } else { &o.name }, "text": m.text, "at": m.at}))
                    .collect();
                list.reverse();
                self.ok(json!({"t": "history", "with": with, "list": list}))
            }
            In::Chats {} => self.ok(chats_json(&app, me).await?),
            In::Read { with } => {
                let o = db::id_by_name(db, &with).await?.ok_or_else(|| e("not_found", "No such player"))?;
                message::Entity::update_many()
                    .col_expr(message::Column::Seen, Expr::value(true))
                    .filter(message::Column::Lo.eq(me.min(o)))
                    .filter(message::Column::Hi.eq(me.max(o)))
                    .filter(message::Column::Src.eq(o))
                    .filter(message::Column::Seen.eq(false))
                    .exec(db)
                    .await?;
                self.ok(json!({"t": "read_ok", "with": with}))
            }
            In::Invite { to, deck } => {
                let deck = deck_value(&deck, false)?;
                let o = match db::account_by_name(db, &to).await? {
                    Some(o) if are_friends(db, me, o.id).await? => o,
                    _ => return Err(e("not_friends", "Invites go to friends only")),
                };
                self.validate(&deck).await?;
                {
                    let mut hub = app.hub();
                    if hub.in_game.contains_key(&me) {
                        return Err(e("in_game", "You are in a game"));
                    }
                    if !matches!(hub.status(o.id), "online" | "searching") {
                        return Err(e("busy", "The friend is not available"));
                    }
                    hub.invites.insert((me, o.id), deck);
                    hub.send(o.id, &json!({"t": "invite", "from": my_name}));
                }
                app.event(self.ev("invite", format!("{my_name} invited {} to a friendly game", o.name)).other(&o.name));
                self.ok(json!({"t": "invited", "to": to}))
            }
            In::InviteAccept { from, deck } => {
                let deck = deck_value(&deck, false)?;
                let o = db::account_by_name(db, &from).await?.ok_or_else(|| e("not_found", "No such invite"))?;
                if !app.hub().invites.contains_key(&(o.id, me)) {
                    return Err(e("not_found", "No such invite"));
                }
                self.validate(&deck).await?;
                let Some(theirs) = app.hub().invites.remove(&(o.id, me)) else { return Err(e("not_found", "No such invite")) };
                app.event(self.ev("invite_accept", format!("{my_name} accepted the invite of {}", o.name)).other(&o.name));
                tokio::spawn(game::start(app.clone(), Mode::Friendly, [(o.id, theirs), (me, deck)]));
                Ok(())
            }
            In::InviteDecline { from } => {
                let o = db::account_by_name(db, &from).await?.ok_or_else(|| e("not_found", "No such invite"))?;
                let had = {
                    let mut hub = app.hub();
                    let had = hub.invites.remove(&(o.id, me)).is_some();
                    if had {
                        hub.send(o.id, &json!({"t": "invite_declined", "by": my_name}));
                    }
                    had
                };
                if had {
                    app.event(self.ev("invite_decline", format!("{my_name} declined the invite of {}", o.name)).other(&o.name));
                }
                Ok(())
            }
            In::Queue { mode, deck } => {
                let deck = deck_value(&deck, false)?;
                self.validate(&deck).await?;
                let mut a = db::account_by_id(db, me).await?.ok_or_else(|| e("server", "No account"))?;
                let mode = match mode {
                    QMode::Casual => Mode::Casual,
                    QMode::Ranked => Mode::Ranked,
                };
                if mode == Mode::Ranked {
                    db::refresh_season(db, &mut a).await?;
                }
                let key = match mode {
                    Mode::Casual => Key { mmr: a.casual_mmr, level: 0, legend: false },
                    _ => Key { mmr: a.ranked_mmr, level: a.rank().level(), legend: a.rank().legend() },
                };
                self.enqueue(me, mode, deck, key).await
            }
            In::Unqueue {} => {
                let was = app.hub().queue.remove(&me);
                if let Some(s) = was {
                    app.event(self.ev("unqueue", format!("{my_name} stopped searching ({})", s.mode.as_str())).data(json!({"mode": s.mode})));
                    presence(&app, me).await;
                }
                self.ok(json!({"t": "unqueued"}))
            }
            In::ArenaStart {} => {
                if arena::Entity::find_by_id(me).one(db).await?.is_some() {
                    return Err(e("arena_active", "An Arena run is already going"));
                }
                let seed: u32 = rand::thread_rng().gen();
                let d = self.draft(seed as i64, -1, &[]).await?;
                let run = arena::ActiveModel {
                    account: Set(me),
                    seed: Set(seed as i64),
                    draft: Set(d.to_string()),
                    ..Default::default()
                };
                arena::Entity::insert(run).exec_without_returning(db).await?;
                app.event(self.ev("arena", format!("{my_name} started an Arena run")));
                self.send_arena(me).await
            }
            In::ArenaHero { i } => {
                let (seed, hero, _, d) = self.run_of(me).await?;
                let heroes = d["heroes"].as_array().map_or(0, |h| h.len());
                if hero >= 0 {
                    return Err(e("bad_request", "The hero is already chosen"));
                }
                let i = index(i, heroes)? as i64;
                let d = self.draft(seed, i, &[]).await?;
                arena::ActiveModel { account: Unchanged(me), hero: Set(i), draft: Set(d.to_string()), ..Default::default() }.update(db).await?;
                self.send_arena(me).await
            }
            In::ArenaPick { i } => {
                let (seed, hero, mut picks, d) = self.run_of(me).await?;
                if hero < 0 || d["done"] == true {
                    return Err(e("bad_request", "Nothing to pick"));
                }
                picks.push(index(i, d["offer"].as_array().map_or(0, |o| o.len()))? as i64);
                let d = self.draft(seed, hero, &picks).await?;
                arena::ActiveModel { account: Unchanged(me), picks: Set(json!(picks).to_string()), draft: Set(d.to_string()), ..Default::default() }
                    .update(db)
                    .await?;
                self.send_arena(me).await
            }
            In::ArenaQueue {} => {
                let (_, _, _, d) = self.run_of(me).await?;
                if d["done"] != true {
                    return Err(e("not_ready", "The deck is not drafted yet"));
                }
                let deck = json!({"hero": d["hero"], "cards": d["cards"], "arena": true});
                let run = arena::Entity::find_by_id(me).one(db).await?.ok_or_else(|| e("no_arena", "No Arena run: start one"))?;
                self.enqueue(me, Mode::Arena, deck, Key { mmr: 0.0, level: run.wins - run.losses, legend: false }).await
            }
            In::ArenaRetire {} => {
                arena::Entity::delete_by_id(me).exec(db).await?;
                let left_queue = {
                    let mut hub = app.hub();
                    let q = hub.queue.get(&me).is_some_and(|s| s.mode == Mode::Arena);
                    if q {
                        hub.queue.remove(&me);
                    }
                    q
                };
                app.event(self.ev("arena", format!("{my_name} retired from the Arena")));
                if left_queue {
                    presence(&app, me).await;
                }
                self.send_arena(me).await
            }
            In::Act { action, game } => self.to_game(me, game, |p| game::Ev::Act(p, action)),
            In::Emote { id, game } => self.to_game(me, game, |p| game::Ev::Emote(p, id)),
            In::Intent { i, game } => self.to_game(me, game, |p| game::Ev::Intent(p, i)),
        }
    }

    /// Passes a message to the player's game. One for a game that is over (or another game)
    /// is dropped silently.
    fn to_game(&self, me: i64, game: Option<String>, ev: impl FnOnce(usize) -> game::Ev) -> R {
        let hub = self.app.hub();
        let found = hub.in_game.get(&me).filter(|(g, _)| game.as_ref().is_none_or(|x| x == g));
        if let Some((lg, p)) = found.and_then(|(g, p)| Some((hub.games.get(g)?, *p))) {
            let _ = lg.tx.send(ev(p));
        }
        Ok(())
    }

    async fn register(&mut self, user: String, password: String) -> R {
        if !self.app.login_allowed(&format!("ip:{}", self.ip)) {
            return Err(e("rate_limited", "Too many attempts: wait a minute"));
        }
        if !auth::valid_user(&user) {
            return Err(e("bad_user", "A name is 3 to 20 letters, digits or _"));
        }
        if !auth::valid_password(&password) {
            return Err(e("bad_password", "A password is 8 to 128 characters"));
        }
        let hash = tokio::task::spawn_blocking(move || auth::hash_password(&password)).await.map_err(|_| e("server", "Server error"))?;
        let id = db::create_account(&self.app.db, &user, &hash, "user").await?;
        let id = id.ok_or_else(|| e("taken", "This name is taken"))?;
        self.app.event(Event::new("register", format!("{user} registered")).user(id, &user).data(json!({"ip": self.ip.to_string()})));
        self.logged_in(id, None, "register").await
    }

    fn failed(&self, user: &str, why: &str) {
        let user: String = user.chars().take(40).collect();
        self.app.event(
            Event::new("login_failed", format!("Failed login as {user}: {why}"))
                .other(&user)
                .data(json!({"ip": self.ip.to_string(), "reason": why})),
        );
    }

    async fn login(&mut self, user: String, password: String) -> R {
        let ip_ok = self.app.login_allowed(&format!("ip:{}", self.ip));
        let user_ok = self.app.login_allowed(&format!("user:{}", user.to_lowercase()));
        if !ip_ok || !user_ok {
            self.failed(&user, "rate limited");
            return Err(e("rate_limited", "Too many attempts: wait a minute"));
        }
        if !auth::valid_user(&user) || password.len() > 1024 {
            self.failed(&user, "bad name");
            return Err(e("bad_login", "Wrong name or password"));
        }
        let found = db::account_by_name(&self.app.db, &user).await?;
        let (ok, found) = tokio::task::spawn_blocking(move || {
            let stored = found.as_ref().map_or(auth::dummy_hash(), |a| a.pass.as_str());
            (auth::verify_password(&password, stored) && found.is_some(), found)
        })
        .await
        .map_err(|_| e("server", "Server error"))?;
        match found {
            Some(a) if ok => {
                if a.suspended {
                    self.failed(&user, "suspended");
                    return Err(e("suspended", "This account is suspended"));
                }
                self.logged_in(a.id, None, "password").await
            }
            Some(_) => {
                self.failed(&user, "wrong password");
                Err(e("bad_login", "Wrong name or password"))
            }
            None => {
                self.failed(&user, "no such account");
                Err(e("bad_login", "Wrong name or password"))
            }
        }
    }

    /// The normal way back in: the token from `auth`, valid 30 days and renewed on every use.
    async fn resume(&mut self, token: String) -> R {
        if !self.app.login_allowed(&format!("ip:{}", self.ip)) {
            return Err(e("rate_limited", "Too many attempts: wait a minute"));
        }
        let Some((a, s)) = db::session(&self.app.db, &token, "game").await? else {
            self.failed("(token)", "expired or unknown token");
            return Err(e("bad_token", "The session expired: log in again"));
        };
        db::renew_session(&self.app.db, s.hash, auth::TOKEN_DAYS * 86400).await?;
        self.logged_in(a.id, Some(token), "token").await
    }

    async fn logged_in(&mut self, id: i64, token: Option<String>, via: &str) -> R {
        let db = &self.app.db;
        let token = match token {
            Some(t) => t,
            None => db::new_session(db, id, "game", auth::TOKEN_DAYS * 86400, "").await?,
        };
        db::touch(db, id).await?;
        let name = db::name_of(db, id).await?;
        let me = me_json(db, id).await?;
        // auth first: attaching may bring the player back into a game (match, state).
        self.send(json!({"t": "auth", "ok": true, "token": token.clone(), "me": me}));
        self.conn = self.app.hub().attach(id, &name, self.tx.clone());
        self.me = Some((id, name.clone()));
        self.token = token;
        if via != "register" {
            self.app.event(self.ev("login", format!("{name} logged in")).data(json!({"ip": self.ip.to_string(), "via": via})));
        }
        presence(&self.app, id).await;
        Ok(())
    }

    async fn send_me(&self, me: i64) -> R {
        let v = me_json(&self.app.db, me).await?;
        self.ok(json!({"t": "me", "me": v}))
    }

    async fn send_arena(&self, me: i64) -> R {
        let v = arena_json(&self.app.db, me).await?;
        self.ok(json!({"t": "arena", "state": v}))
    }

    /// A change between me and the named player, then both friend lists are refreshed.
    async fn pair_op(&self, user: String, op: PairOp) -> R {
        let (me, my_name) = self.me.clone().unwrap_or_default();
        let tx = self.app.db.begin().await?;
        let o = db::account_by_name(&tx, &user).await?.ok_or_else(|| match op {
            PairOp::Accept => e("not_found", "No such request"),
            _ => e("not_found", "No such player"),
        })?;
        op.apply(&tx, me, o.id).await?;
        tx.commit().await?;
        self.app.event(self.ev(op.kind(), format!("{my_name} {} {}", op.verb(), o.name)).other(&o.name));
        self.friends_changed(o.id).await?;
        if matches!(op, PairOp::Accept) {
            self.presence_pair(o.id).await;
        }
        Ok(())
    }

    /// New friends see each other's status (the friends message carries it too).
    async fn presence_pair(&self, other: i64) {
        let me = self.me.as_ref().map_or(0, |m| m.0);
        let hub = self.app.hub();
        for (a, b) in [(me, other), (other, me)] {
            let st = hub.status(a);
            let name = hub.conns.get(&a).map(|c| c.name.clone());
            if let Some(name) = name {
                hub.send(b, &json!({"t": "presence", "user": name, "online": st != "offline", "status": st}));
            }
        }
    }

    async fn friends_changed(&self, other: i64) -> R {
        let me = self.me.as_ref().map_or(0, |m| m.0);
        self.send(friends_json(&self.app, me).await?);
        push_friends(&self.app, other).await;
        Ok(())
    }

    async fn validate(&self, deck: &Value) -> R {
        let r = classichs_engine::Engine::new().handle(&json!({"op": "validate", "deck": deck}));
        if r["ok"] == true {
            Ok(())
        } else {
            Err(E("deck", r["error"].as_str().unwrap_or("The deck is not valid").chars().take(200).collect(), None))
        }
    }

    async fn draft(&self, seed: i64, hero: i64, picks: &[i64]) -> Result<Value, E> {
        let r = classichs_engine::Engine::new().handle(&json!({"op": "draft", "seed": seed, "hero": hero, "picks": picks}));
        if r["ok"] == true {
            Ok(r)
        } else {
            Err(E("server", "Server error".into(), Some(format!("draft refused: {r}"))))
        }
    }

    /// The account's Arena run: (seed, hero, picks, last draft reply).
    async fn run_of(&self, me: i64) -> Result<(i64, i64, Vec<i64>, Value), E> {
        let run = arena::Entity::find_by_id(me).one(&self.app.db).await?.ok_or_else(|| e("no_arena", "No Arena run: start one"))?;
        let picks = serde_json::from_str(&run.picks).unwrap_or_default();
        Ok((run.seed, run.hero, picks, serde_json::from_str(&run.draft).unwrap_or(Value::Null)))
    }

    async fn enqueue(&self, me: i64, mode: Mode, deck: Value, key: Key) -> R {
        {
            let mut hub = self.app.hub();
            if hub.in_game.contains_key(&me) {
                return Err(e("queue", "You are in a game"));
            }
            hub.queue.insert(me, Seeker { name: self.name(), mode, deck: deck.clone(), key, since: Instant::now() });
        }
        let detail = match mode {
            Mode::Casual => format!("MMR {:.0}", key.mmr),
            Mode::Ranked if key.legend => format!("Legend, MMR {:.0}", key.mmr),
            Mode::Ranked => format!("level {}", key.level),
            _ => format!("record {:+}", key.level),
        };
        self.app.event(
            self.ev("queue", format!("{} is searching ({}, {detail})", self.name(), mode.as_str()))
                .data(json!({"mode": mode, "mmr": key.mmr.round(), "level": key.level, "hero": deck["hero"]})),
        );
        presence(&self.app, me).await;
        self.ok(json!({"t": "queued", "mode": mode}))
    }
}
