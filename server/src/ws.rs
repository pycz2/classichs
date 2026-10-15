//! One WebSocket client: strict JSON messages {"t": …}, auth, social, queues, Arena, game relay.

use crate::auth::{self, RateLimit};
use crate::db::{self, DbError};
use crate::game::{self, rank_json};
use crate::ranked::{self, Key, Mode};
use crate::{AppRef, Out, Seeker};
use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use rand::Rng;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};
use std::net::IpAddr;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::{self, UnboundedSender};

/// Malformed messages before the connection is closed.
const MAX_ERRORS: u32 = 20;
const MAX_FRIENDS: i64 = 200;
const HISTORY: i64 = 200;

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
    Game {
        m: Value,
        #[serde(default)]
        game: Option<String>,
    },
}

/// An error reply: code and text.
pub struct E(&'static str, String);

impl From<DbError> for E {
    fn from(e: DbError) -> E {
        tracing::error!("db: {e}");
        E("server", "Server error".into())
    }
}

fn e(code: &'static str, text: &str) -> E {
    E(code, text.into())
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
                    s.reply(Err(e("rate_limited", "Too many messages")));
                    break;
                }
                s.handle(t.as_str()).await;
                if s.errors >= MAX_ERRORS {
                    break;
                }
            }
            Some(Ok(Message::Binary(_))) => {
                s.errors += 1;
                s.reply(Err(e("bad_request", "Text frames only")));
            }
            Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
            Some(Ok(_)) => {}
        }
    }
    if let Some((id, _)) = s.me.take() {
        s.app.hub().detach(id, Some(s.conn));
        let _ = s.app.db.run(move |c| c.execute("UPDATE accounts SET last_seen = ?1 WHERE id = ?2", params![ranked::now(), id])).await;
    }
    let _ = s.tx.send(Out::Close);
    drop(s);
    if !writer_done {
        let _ = tokio::time::timeout(Duration::from_secs(5), writer).await;
    }
}

fn id_by_name(c: &Connection, name: &str) -> rusqlite::Result<Option<i64>> {
    c.query_row("SELECT id FROM accounts WHERE name = ?1", [name], |r| r.get(0)).optional()
}

fn are_friends(c: &Connection, a: i64, b: i64) -> rusqlite::Result<bool> {
    c.query_row("SELECT 1 FROM friends WHERE a = ?1 AND b = ?2", [a, b], |_| Ok(())).optional().map(|x| x.is_some())
}

fn arena_json(c: &Connection, me: i64) -> rusqlite::Result<Value> {
    let row: Option<(String, i64, i64)> = c
        .query_row("SELECT draft, wins, losses FROM arena WHERE account = ?1", [me], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .optional()?;
    Ok(match row {
        None => Value::Null,
        Some((d, w, l)) => {
            let mut v: Value = serde_json::from_str(&d).unwrap_or_else(|_| json!({}));
            if let Some(o) = v.as_object_mut() {
                o.remove("ok");
            }
            v["wins"] = json!(w);
            v["losses"] = json!(l);
            v
        }
    })
}

fn me_json(c: &Connection, me: i64) -> rusqlite::Result<Value> {
    let mut a = db::account_by_id(c, me)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
    db::refresh_season(c, &mut a)?;
    Ok(json!({"user": a.name, "tag": a.tag, "rank": rank_json(c, &a)?, "arena": arena_json(c, me)?,
              "season": ranked::season_name(a.season)}))
}

type People = Vec<(i64, String, Option<String>)>;

fn people(c: &Connection, sql: &str, me: i64) -> rusqlite::Result<People> {
    let mut st = c.prepare(sql)?;
    let rows = st.query_map([me], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?;
    rows.collect()
}

/// The friends message for an account (online status from the hub).
async fn friends_json(app: &AppRef, me: i64) -> Result<Value, E> {
    let lists = app
        .db
        .run(move |c| {
            Ok([
                people(c, "SELECT a.id, a.name, a.tag FROM friends f JOIN accounts a ON a.id = f.b WHERE f.a = ?1 ORDER BY a.name", me)?,
                people(c, "SELECT a.id, a.name, a.tag FROM requests r JOIN accounts a ON a.id = r.src WHERE r.dst = ?1 ORDER BY r.at", me)?,
                people(c, "SELECT a.id, a.name, a.tag FROM requests r JOIN accounts a ON a.id = r.dst WHERE r.src = ?1 ORDER BY r.at", me)?,
                people(c, "SELECT a.id, a.name, a.tag FROM blocks b JOIN accounts a ON a.id = b.whom WHERE b.who = ?1 ORDER BY a.name", me)?,
            ])
        })
        .await?;
    let hub = app.hub();
    let plain = |l: &People| l.iter().map(|(_, n, t)| json!({"user": n, "tag": t})).collect::<Vec<_>>();
    let list: Vec<Value> = lists[0]
        .iter()
        .map(|(id, n, t)| json!({"user": n, "tag": t, "online": hub.conns.contains_key(id), "status": hub.status(*id)}))
        .collect();
    Ok(json!({"t": "friends", "list": list, "requests_in": plain(&lists[1]), "requests_out": plain(&lists[2]), "blocked": plain(&lists[3])}))
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

impl Session {
    fn send(&self, v: Value) {
        let _ = self.tx.send(Out::Text(v.to_string()));
    }

    fn ok(&self, v: Value) -> R {
        self.send(v);
        Ok(())
    }

    fn reply(&self, r: R) {
        if let Err(E(code, text)) = r {
            self.send(json!({"t": "error", "code": code, "text": text}));
        }
    }

    async fn handle(&mut self, text: &str) {
        let msg: In = match serde_json::from_str(text) {
            Ok(m) => m,
            Err(err) => {
                self.errors += 1;
                let mut t = err.to_string();
                t.truncate(200);
                return self.reply(Err(E("bad_request", t)));
            }
        };
        let r = self.dispatch(msg).await;
        self.reply(r);
    }

    async fn dispatch(&mut self, msg: In) -> R {
        let Some((me, _name)) = self.me.clone() else {
            return match msg {
                In::Register { user, password } => self.register(user, password).await,
                In::Login { user, password } => self.login(user, password).await,
                In::Resume { token } => self.resume(token).await,
                In::Ping {} => self.ok(json!({"t": "pong"})),
                _ => Err(e("auth_required", "Log in first")),
            };
        };
        let app = self.app.clone();
        match msg {
            In::Register { .. } | In::Login { .. } | In::Resume { .. } => Err(e("bad_request", "Already logged in")),
            In::Ping {} => self.ok(json!({"t": "pong"})),
            In::Logout {} => {
                let t = std::mem::take(&mut self.token);
                app.db.run(move |c| db::drop_session(c, &t)).await?;
                app.hub().detach(me, Some(self.conn));
                self.me = None;
                self.ok(json!({"t": "logged_out"}))
            }
            In::Me {} => self.send_me(me).await,
            In::SetTag { tag } => {
                if !auth::valid_tag(&tag) {
                    return Err(e("bad_tag", "A tag is 3 to 16 letters or digits"));
                }
                let key = tag.to_lowercase();
                let n = app
                    .db
                    .run(move |c| {
                        c.execute("UPDATE accounts SET tag = ?1, tag_key = ?2 WHERE id = ?3 AND NOT EXISTS
                                   (SELECT 1 FROM accounts WHERE tag_key = ?2 AND id <> ?3)", params![tag, key, me])
                    })
                    .await?;
                if n == 0 {
                    return Err(e("tag_taken", "This tag is taken"));
                }
                self.send_me(me).await
            }
            In::Friends {} => self.ok(friends_json(&app, me).await?),
            In::FriendAdd { tag } => {
                let key = tag.to_lowercase();
                let other = app
                    .db
                    .run(move |c| -> rusqlite::Result<Result<(i64, bool), E>> {
                        let Some(o) = c.query_row("SELECT id FROM accounts WHERE tag_key = ?1", [&key], |r| r.get::<_, i64>(0)).optional()? else {
                            return Ok(Err(e("not_found", "No player with this tag")));
                        };
                        let blocked = |a: i64, b: i64| c.query_row("SELECT 1 FROM blocks WHERE who = ?1 AND whom = ?2", [a, b], |_| Ok(())).optional();
                        if o == me || blocked(o, me)?.is_some() {
                            return Ok(Err(e("not_found", "No player with this tag")));
                        }
                        if blocked(me, o)?.is_some() {
                            return Ok(Err(e("blocked", "You blocked this player")));
                        }
                        if are_friends(c, me, o)? {
                            return Ok(Err(e("already", "Already friends")));
                        }
                        let count = |a: i64| c.query_row("SELECT COUNT(*) FROM friends WHERE a = ?1", [a], |r| r.get::<_, i64>(0));
                        if count(me)? >= MAX_FRIENDS {
                            return Ok(Err(e("friends_full", "You have 200 friends")));
                        }
                        let theirs = c.execute("DELETE FROM requests WHERE src = ?1 AND dst = ?2", [o, me])? == 1;
                        if theirs {
                            if count(o)? >= MAX_FRIENDS {
                                return Ok(Err(e("friends_full", "The player has 200 friends")));
                            }
                            c.execute("INSERT OR IGNORE INTO friends (a, b) VALUES (?1, ?2), (?2, ?1)", [me, o])?;
                        } else {
                            c.execute("INSERT OR IGNORE INTO requests (src, dst, at) VALUES (?1, ?2, ?3)", params![me, o, ranked::now()])?;
                        }
                        Ok(Ok((o, theirs)))
                    })
                    .await??;
                self.friends_changed(other.0).await
            }
            In::FriendAccept { user } => {
                let o = app
                    .db
                    .run(move |c| -> rusqlite::Result<Result<i64, E>> {
                        let Some(o) = id_by_name(c, &user)? else { return Ok(Err(e("not_found", "No such request"))) };
                        let count = |a: i64| c.query_row("SELECT COUNT(*) FROM friends WHERE a = ?1", [a], |r| r.get::<_, i64>(0));
                        if c.query_row("SELECT 1 FROM requests WHERE src = ?1 AND dst = ?2", [o, me], |_| Ok(())).optional()?.is_none() {
                            return Ok(Err(e("not_found", "No such request")));
                        }
                        if count(me)? >= MAX_FRIENDS || count(o)? >= MAX_FRIENDS {
                            return Ok(Err(e("friends_full", "200 friends at most")));
                        }
                        c.execute("DELETE FROM requests WHERE (src = ?1 AND dst = ?2) OR (src = ?2 AND dst = ?1)", [o, me])?;
                        c.execute("INSERT OR IGNORE INTO friends (a, b) VALUES (?1, ?2), (?2, ?1)", [me, o])?;
                        Ok(Ok(o))
                    })
                    .await??;
                self.friends_changed(o).await
            }
            In::FriendDecline { user } => self.pair_op(user, "DELETE FROM requests WHERE src = ?2 AND dst = ?1").await,
            In::FriendRemove { user } => {
                self.pair_op(user, "DELETE FROM friends WHERE (a = ?1 AND b = ?2) OR (a = ?2 AND b = ?1);
                                    DELETE FROM requests WHERE src = ?1 AND dst = ?2").await
            }
            In::Block { user } => {
                self.pair_op(user, "INSERT OR IGNORE INTO blocks (who, whom) VALUES (?1, ?2);
                                    DELETE FROM friends WHERE (a = ?1 AND b = ?2) OR (a = ?2 AND b = ?1);
                                    DELETE FROM requests WHERE (src = ?1 AND dst = ?2) OR (src = ?2 AND dst = ?1)").await
            }
            In::Unblock { user } => self.pair_op(user, "DELETE FROM blocks WHERE who = ?1 AND whom = ?2").await,
            In::Msg { to, text } => {
                let n = text.chars().count();
                if n == 0 || n > 500 || text.trim().is_empty() {
                    return Err(e("bad_text", "A message is 1 to 500 characters"));
                }
                if !self.chat.allow("", Instant::now()) {
                    return Err(e("rate_limited", "Too many messages: wait a little"));
                }
                let t = text.clone();
                let (o, at) = app
                    .db
                    .run(move |c| -> rusqlite::Result<Result<(i64, i64), E>> {
                        let Some(o) = id_by_name(c, &to)? else { return Ok(Err(e("not_found", "No such player"))) };
                        if !are_friends(c, me, o)? {
                            return Ok(Err(e("not_friends", "Messages go to friends only")));
                        }
                        let (lo, hi, at) = (me.min(o), me.max(o), ranked::now());
                        c.execute("INSERT INTO messages (lo, hi, src, text, at) VALUES (?1, ?2, ?3, ?4, ?5)", params![lo, hi, me, t, at])?;
                        c.execute(
                            "DELETE FROM messages WHERE lo = ?1 AND hi = ?2 AND id NOT IN
                             (SELECT id FROM messages WHERE lo = ?1 AND hi = ?2 ORDER BY id DESC LIMIT ?3)",
                            params![lo, hi, HISTORY],
                        )?;
                        Ok(Ok((o, at)))
                    })
                    .await??;
                let name = self.me.as_ref().map(|m| m.1.clone()).unwrap_or_default();
                app.hub().send(o, &json!({"t": "msg", "from": name, "text": text, "at": at}));
                self.ok(json!({"t": "msg_sent", "to": name_of(&app, o).await, "at": at}))
            }
            In::History { with } => {
                let w = with.clone();
                let list = app
                    .db
                    .run(move |c| -> rusqlite::Result<Option<Vec<Value>>> {
                        let Some(o) = id_by_name(c, &w)? else { return Ok(None) };
                        let mut st = c.prepare(
                            "SELECT a.name, m.text, m.at FROM messages m JOIN accounts a ON a.id = m.src
                             WHERE m.lo = ?1 AND m.hi = ?2 ORDER BY m.id DESC LIMIT ?3",
                        )?;
                        let rows = st.query_map(params![me.min(o), me.max(o), HISTORY], |r| {
                            Ok(json!({"from": r.get::<_, String>(0)?, "text": r.get::<_, String>(1)?, "at": r.get::<_, i64>(2)?}))
                        })?;
                        let mut v = rows.collect::<rusqlite::Result<Vec<_>>>()?;
                        v.reverse();
                        Ok(Some(v))
                    })
                    .await?
                    .ok_or_else(|| e("not_found", "No such player"))?;
                self.ok(json!({"t": "history", "with": with, "list": list}))
            }
            In::Invite { to, deck } => {
                let deck = deck_value(&deck, false)?;
                let t = to.clone();
                let o = app
                    .db
                    .run(move |c| Ok(match id_by_name(c, &t)? { Some(o) if are_friends(c, me, o)? => Some(o), _ => None }))
                    .await?
                    .ok_or_else(|| e("not_friends", "Invites go to friends only"))?;
                self.validate(&deck).await?;
                let mut hub = app.hub();
                if hub.in_game.contains_key(&me) {
                    return Err(e("in_game", "You are in a game"));
                }
                if hub.status(o) != "online" && hub.status(o) != "queue" {
                    return Err(e("busy", "The friend is not available"));
                }
                hub.invites.insert((me, o), deck);
                let name = hub.conns.get(&me).map(|c| c.name.clone()).unwrap_or_default();
                hub.send(o, &json!({"t": "invite", "from": name}));
                drop(hub);
                self.ok(json!({"t": "invited", "to": to}))
            }
            In::InviteAccept { from, deck } => {
                let deck = deck_value(&deck, false)?;
                let o = app.db.run(move |c| id_by_name(c, &from)).await?.ok_or_else(|| e("not_found", "No such invite"))?;
                if !app.hub().invites.contains_key(&(o, me)) {
                    return Err(e("not_found", "No such invite"));
                }
                self.validate(&deck).await?;
                let Some(theirs) = app.hub().invites.remove(&(o, me)) else { return Err(e("not_found", "No such invite")) };
                tokio::spawn(game::start(app.clone(), Mode::Friendly, [(o, theirs), (me, deck)]));
                Ok(())
            }
            In::InviteDecline { from } => {
                let o = app.db.run(move |c| id_by_name(c, &from)).await?.ok_or_else(|| e("not_found", "No such invite"))?;
                let mut hub = app.hub();
                if hub.invites.remove(&(o, me)).is_some() {
                    let name = hub.conns.get(&me).map(|c| c.name.clone()).unwrap_or_default();
                    hub.send(o, &json!({"t": "invite_declined", "by": name}));
                }
                Ok(())
            }
            In::Queue { mode, deck } => {
                let deck = deck_value(&deck, false)?;
                self.validate(&deck).await?;
                let mut a = app.db.run(move |c| db::account_by_id(c, me)).await?.ok_or_else(|| e("server", "No account"))?;
                let mode = match mode {
                    QMode::Casual => Mode::Casual,
                    QMode::Ranked => Mode::Ranked,
                };
                if mode == Mode::Ranked {
                    let id = a.id;
                    a = app
                        .db
                        .run(move |c| {
                            let mut a = db::account_by_id(c, id)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
                            db::refresh_season(c, &mut a)?;
                            Ok(a)
                        })
                        .await?;
                }
                let key = match mode {
                    Mode::Casual => Key { mmr: a.casual_mmr, level: 0, legend: false },
                    _ => Key { mmr: a.ranked_mmr, level: a.rank.level(), legend: a.rank.legend() },
                };
                self.enqueue(me, mode, deck, key)
            }
            In::Unqueue {} => {
                app.hub().queue.remove(&me);
                self.ok(json!({"t": "unqueued"}))
            }
            In::ArenaStart {} => {
                let exists = app.db.run(move |c| c.query_row("SELECT 1 FROM arena WHERE account = ?1", [me], |_| Ok(())).optional()).await?;
                if exists.is_some() {
                    return Err(e("arena_active", "An Arena run is already going"));
                }
                let seed: u32 = rand::thread_rng().gen();
                let d = self.draft(seed as i64, -1, &[]).await?;
                app.db
                    .run(move |c| c.execute("INSERT INTO arena (account, seed, draft) VALUES (?1, ?2, ?3)", params![me, seed, d.to_string()]))
                    .await?;
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
                app.db
                    .run(move |c| c.execute("UPDATE arena SET hero = ?1, draft = ?2 WHERE account = ?3", params![i, d.to_string(), me]))
                    .await?;
                self.send_arena(me).await
            }
            In::ArenaPick { i } => {
                let (seed, hero, mut picks, d) = self.run_of(me).await?;
                if hero < 0 || d["done"] == true {
                    return Err(e("bad_request", "Nothing to pick"));
                }
                picks.push(index(i, d["offer"].as_array().map_or(0, |o| o.len()))? as i64);
                let d = self.draft(seed, hero, &picks).await?;
                let p = json!(picks).to_string();
                app.db
                    .run(move |c| c.execute("UPDATE arena SET picks = ?1, draft = ?2 WHERE account = ?3", params![p, d.to_string(), me]))
                    .await?;
                self.send_arena(me).await
            }
            In::ArenaQueue {} => {
                let (_, _, _, d) = self.run_of(me).await?;
                if d["done"] != true {
                    return Err(e("not_ready", "The deck is not drafted yet"));
                }
                let deck = json!({"hero": d["hero"], "cards": d["cards"], "arena": true});
                let rec = app.db.run(move |c| c.query_row("SELECT wins - losses FROM arena WHERE account = ?1", [me], |r| r.get(0))).await?;
                self.enqueue(me, Mode::Arena, deck, Key { mmr: 0.0, level: rec, legend: false })
            }
            In::ArenaRetire {} => {
                app.db.run(move |c| c.execute("DELETE FROM arena WHERE account = ?1", [me])).await?;
                {
                    let mut hub = app.hub();
                    if hub.queue.get(&me).is_some_and(|s| s.mode == Mode::Arena) {
                        hub.queue.remove(&me);
                    }
                }
                self.send_arena(me).await
            }
            In::Game { m, game } => {
                if !m.is_object() {
                    self.errors += 1;
                    return Err(e("bad_request", "A game message is an object"));
                }
                let hub = app.hub();
                let g = hub
                    .in_game
                    .get(&me)
                    .filter(|(g, _)| game.as_ref().is_none_or(|x| x == g))
                    .and_then(|(g, p)| hub.games.get(g).map(|lg| (lg.tx.clone(), *p)));
                drop(hub);
                // A message for a game that is over (e.g. a bye after game_over) is dropped silently.
                if let Some((tx, p)) = g {
                    let _ = tx.send(game::Ev::Msg(p, m));
                }
                Ok(())
            }
        }
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
        let id = self.app.db.run(move |c| db::create_account(c, &user, &hash, "user")).await?;
        let id = id.ok_or_else(|| e("taken", "This name is taken"))?;
        self.logged_in(id, None).await
    }

    async fn login(&mut self, user: String, password: String) -> R {
        let ip_ok = self.app.login_allowed(&format!("ip:{}", self.ip));
        let user_ok = self.app.login_allowed(&format!("user:{}", user.to_lowercase()));
        if !ip_ok || !user_ok {
            return Err(e("rate_limited", "Too many attempts: wait a minute"));
        }
        if !auth::valid_user(&user) || password.len() > 1024 {
            return Err(e("bad_login", "Wrong name or password"));
        }
        let found = self.app.db.run(move |c| db::account_by_name(c, &user)).await?;
        let (ok, found) = tokio::task::spawn_blocking(move || {
            let stored = found.as_ref().map_or(auth::dummy_hash(), |(_, h)| h.as_str());
            (auth::verify_password(&password, stored) && found.is_some(), found)
        })
        .await
        .map_err(|_| e("server", "Server error"))?;
        match found {
            Some((a, _)) if ok => {
                if a.suspended {
                    return Err(e("suspended", "This account is suspended"));
                }
                self.logged_in(a.id, None).await
            }
            _ => Err(e("bad_login", "Wrong name or password")),
        }
    }

    async fn resume(&mut self, token: String) -> R {
        if !self.app.login_allowed(&format!("ip:{}", self.ip)) {
            return Err(e("rate_limited", "Too many attempts: wait a minute"));
        }
        let t = token.clone();
        let a = self.app.db.run(move |c| db::session(c, &t, "game")).await?;
        let (a, _) = a.ok_or_else(|| e("bad_token", "The session expired: log in again"))?;
        self.logged_in(a.id, Some(token)).await
    }

    async fn logged_in(&mut self, id: i64, token: Option<String>) -> R {
        let (token, name, me) = self
            .app
            .db
            .run(move |c| {
                let token = match token {
                    Some(t) => t,
                    None => db::new_session(c, id, "game", auth::TOKEN_DAYS * 86400, "")?,
                };
                c.execute("UPDATE accounts SET last_seen = ?1 WHERE id = ?2", params![ranked::now(), id])?;
                let name: String = c.query_row("SELECT name FROM accounts WHERE id = ?1", [id], |r| r.get(0))?;
                Ok((token, name, me_json(c, id)?))
            })
            .await?;
        self.conn = self.app.hub().attach(id, &name, self.tx.clone());
        self.me = Some((id, name));
        self.token = token.clone();
        self.send(json!({"t": "auth", "ok": true, "token": token, "me": me}));
        Ok(())
    }

    async fn send_me(&self, me: i64) -> R {
        let v = self.app.db.run(move |c| me_json(c, me)).await?;
        self.ok(json!({"t": "me", "me": v}))
    }

    async fn send_arena(&self, me: i64) -> R {
        let v = self.app.db.run(move |c| arena_json(c, me)).await?;
        self.ok(json!({"t": "arena", "state": v}))
    }

    /// Runs a two-account statement (?1 = me, ?2 = the named player), then refreshes both friend lists.
    async fn pair_op(&self, user: String, sql: &'static str) -> R {
        let me = self.me.as_ref().map_or(0, |m| m.0);
        let o = self
            .app
            .db
            .run(move |c| {
                let Some(o) = id_by_name(c, &user)? else { return Ok(None) };
                let tx = c.transaction()?;
                for stmt in sql.split(';').filter(|s| !s.trim().is_empty()) {
                    tx.execute(stmt, [me, o])?;
                }
                tx.commit()?;
                Ok(Some(o))
            })
            .await?
            .ok_or_else(|| e("not_found", "No such player"))?;
        self.friends_changed(o).await
    }

    async fn friends_changed(&self, other: i64) -> R {
        let me = self.me.as_ref().map_or(0, |m| m.0);
        self.send(friends_json(&self.app, me).await?);
        push_friends(&self.app, other).await;
        Ok(())
    }

    async fn validate(&self, deck: &Value) -> R {
        match self.app.referee.call(json!({"op": "validate", "deck": deck})).await {
            Ok(r) if r["ok"] == true => Ok(()),
            Ok(r) => Err(E("deck", r["error"].as_str().unwrap_or("The deck is not valid").chars().take(200).collect())),
            Err(_) => Err(e("referee", "The referee is not available")),
        }
    }

    async fn draft(&self, seed: i64, hero: i64, picks: &[i64]) -> Result<Value, E> {
        match self.app.referee.call(json!({"op": "draft", "seed": seed, "hero": hero, "picks": picks})).await {
            Ok(r) if r["ok"] == true => Ok(r),
            _ => Err(e("referee", "The referee is not available")),
        }
    }

    /// The account's Arena run: (seed, hero, picks, last draft reply).
    async fn run_of(&self, me: i64) -> Result<(i64, i64, Vec<i64>, Value), E> {
        let row = self
            .app
            .db
            .run(move |c| {
                c.query_row("SELECT seed, hero, picks, draft FROM arena WHERE account = ?1", [me], |r| {
                    Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?))
                })
                .optional()
            })
            .await?
            .ok_or_else(|| e("no_arena", "No Arena run: start one"))?;
        let picks = serde_json::from_str(&row.2).unwrap_or_default();
        Ok((row.0, row.1, picks, serde_json::from_str(&row.3).unwrap_or(Value::Null)))
    }

    fn enqueue(&self, me: i64, mode: Mode, deck: Value, key: Key) -> R {
        let mut hub = self.app.hub();
        if hub.in_game.contains_key(&me) {
            return Err(e("queue", "You are in a game"));
        }
        let name = self.me.as_ref().map(|m| m.1.clone()).unwrap_or_default();
        hub.queue.insert(me, Seeker { name, mode, deck, key, since: Instant::now() });
        drop(hub);
        self.ok(json!({"t": "queued", "mode": mode}))
    }
}

async fn name_of(app: &AppRef, id: i64) -> String {
    app.db
        .run(move |c| c.query_row("SELECT name FROM accounts WHERE id = ?1", [id], |r| r.get(0)))
        .await
        .unwrap_or_default()
}
