//! classichs-server: accounts, social, matchmaking and authoritative games for Classic HS
//! (the rules engine `classichs-engine` runs every game).
//! Protocol: docs/superpowers/specs/2026-10-15-server-design.md.

pub mod admin;
pub mod auth;
pub mod db;
pub mod entity;
pub mod events;
pub mod game;
pub mod migration;
pub mod packs;
pub mod ranked;
pub mod storage;
pub mod ws;

use auth::RateLimit;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{ConnectInfo, State};
use axum::http::HeaderMap;
use axum::response::Response;
use axum::routing::get;
use axum::Router;
use db::Db;
use entity::friend;
use events::{Event, Log};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, QuerySelect};
use packs::GameRules;
use ranked::{Key, Mode};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::mpsc::UnboundedSender;

pub const MAX_FRAME: usize = 64 * 1024;

pub type AppRef = Arc<App>;

pub struct App {
    pub db: Db,
    pub hub: Mutex<Hub>,
    /// Login and register attempts, keyed "ip:…" and "user:…": 10 a minute.
    pub logins: Mutex<RateLimit>,
    /// Use the last X-Forwarded-For address (behind a reverse proxy).
    pub trust_proxy: bool,
    /// The game clocks for every game (tests); None = each pack's (rules.json `timers`).
    pub timers: Option<Timers>,
    /// The event log and the admin panels' live feed.
    pub log: Log,
    /// Where pack files live (S3 or a directory).
    pub store: storage::Storage,
    /// The rules of the packs games were played in, by rules_hash (`packs::rules_for`).
    pub rules: Mutex<HashMap<String, Arc<GameRules>>>,
    /// One pack load or trial game at a time.
    pub loading: tokio::sync::Mutex<()>,
}

/// The game clocks (a pack's: rules.json `timers`, docs/packs/rules.md).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Timers {
    /// How long a player who dropped out of a game has to come back.
    pub away: Duration,
    pub turn: Duration,
    pub mulligan: Duration,
    /// After the deadline the players see, before the server plays the timeout moves.
    pub slack: Duration,
}

impl Default for Timers {
    fn default() -> Timers {
        let s = Duration::from_secs;
        Timers { away: s(30), turn: s(75), mulligan: s(45), slack: s(5) }
    }
}

impl App {
    /// Needs a tokio runtime (it starts the event log's writer).
    pub fn new(db: Db, trust_proxy: bool, timers: Option<Timers>, store: storage::Storage) -> AppRef {
        let db_clone = db.clone();
        Arc::new(App {
            db,
            hub: Mutex::new(Hub::default()),
            logins: Mutex::new(RateLimit::new(10, Duration::from_secs(60))),
            trust_proxy,
            timers,
            log: Log::start(db_clone),
            store,
            rules: Mutex::default(),
            loading: tokio::sync::Mutex::new(()),
        })
    }

    pub fn event(&self, e: Event) {
        self.log.add(e);
    }

    pub fn hub(&self) -> std::sync::MutexGuard<'_, Hub> {
        self.hub.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn login_allowed(&self, key: &str) -> bool {
        self.logins.lock().unwrap_or_else(|e| e.into_inner()).allow(key, Instant::now())
    }
}

pub enum Out {
    Text(String),
    Close,
    /// Close with a code and a reason (a second login: 4001 "another_login").
    CloseWith(u16, &'static str),
}

/// The close code of a connection another login took over.
pub const KICKED_CODE: u16 = 4001;

pub struct Conn {
    pub id: u64,
    pub name: String,
    pub tx: UnboundedSender<Out>,
}

pub struct Seeker {
    pub name: String,
    pub mode: Mode,
    /// The pack the game is played in: queues are per (mode, pack).
    pub rules: Arc<GameRules>,
    pub deck: Value,
    pub key: Key,
    pub since: Instant,
}

/// Two seekers paired: the mode, the pack, [(account, deck)].
pub type Pairing = (Mode, Arc<GameRules>, [(i64, Value); 2]);

pub struct LiveGame {
    pub tx: UnboundedSender<game::Ev>,
    pub mode: Mode,
    /// The pack's rules_hash and "Name version".
    pub pack: String,
    pub pack_name: String,
    pub ids: [i64; 2],
    pub names: [String; 2],
    pub started: i64,
    pub turn: i64,
    pub current: i64,
    /// Actions applied so far.
    pub actions: u64,
}

#[derive(Default)]
pub struct Hub {
    next_conn: u64,
    pub conns: HashMap<i64, Conn>,
    pub queue: HashMap<i64, Seeker>,
    pub games: HashMap<String, LiveGame>,
    /// Account → (game id, player number).
    pub in_game: HashMap<i64, (String, usize)>,
    /// (from, to) → the inviter's deck and the game's rules.
    pub invites: HashMap<(i64, i64), (Value, Arc<GameRules>)>,
    /// The last presence status sent to each account's friends (absent = offline).
    shown: HashMap<i64, &'static str>,
}

impl Hub {
    pub fn send(&self, account: i64, v: &Value) {
        if let Some(c) = self.conns.get(&account) {
            let _ = c.tx.send(Out::Text(v.to_string()));
        }
    }

    /// "offline" | "in_game" | "searching" | "online".
    pub fn status(&self, account: i64) -> &'static str {
        if !self.conns.contains_key(&account) {
            "offline"
        } else if self.in_game.contains_key(&account) {
            "in_game"
        } else if self.queue.contains_key(&account) {
            "searching"
        } else {
            "online"
        }
    }

    /// What the admin panel shows live: who is online, the queues, the games.
    pub fn live_json(&self) -> Value {
        let now = Instant::now();
        let mut online: Vec<Value> =
            self.conns.iter().map(|(id, c)| json!({"id": id, "user": c.name, "status": self.status(*id)})).collect();
        online.sort_by(|a, b| a["user"].as_str().cmp(&b["user"].as_str()));
        let mut queue: Vec<Value> = self
            .queue
            .iter()
            .map(|(id, s)| {
                let w = now.duration_since(s.since).as_secs();
                json!({"id": id, "user": s.name, "mode": s.mode, "waited": w, "window": ranked::shown_window(s.mode, &s.key, w),
                       "mmr": s.key.mmr.round(), "level": s.key.level, "pack": s.rules.rules_hash, "pack_name": packs::short_name(&s.rules)})
            })
            .collect();
        queue.sort_by_key(|q| std::cmp::Reverse(q["waited"].as_u64()));
        let mut games: Vec<Value> = self
            .games
            .iter()
            .map(|(id, g)| {
                let players: Vec<Value> = (0..2)
                    .map(|p| json!({"id": g.ids[p], "user": g.names[p], "online": self.conns.contains_key(&g.ids[p])}))
                    .collect();
                json!({"id": id, "mode": g.mode, "players": players, "started": g.started, "turn": g.turn,
                       "current": g.current, "actions": g.actions, "pack": g.pack, "pack_name": g.pack_name})
            })
            .collect();
        games.sort_by_key(|g| g["started"].as_i64());
        json!({"online": online, "queue": queue, "games": games})
    }

    /// The account's new connection. One login per account: an older connection gets
    /// `kicked {reason: "another_login"}` and is closed. Returns (connection id, kicked one).
    pub fn attach(&mut self, account: i64, name: &str, tx: UnboundedSender<Out>) -> (u64, bool) {
        self.next_conn += 1;
        let old = self.conns.insert(account, Conn { id: self.next_conn, name: name.into(), tx });
        if let Some(old) = &old {
            // The message first, then the close frame tells it again (a client may lose a
            // message that arrives right before the close).
            let _ = old.tx.send(Out::Text(json!({"t": "kicked", "reason": "another_login"}).to_string()));
            let _ = old.tx.send(Out::CloseWith(KICKED_CODE, "another_login"));
        }
        if let Some((g, p)) = self.in_game.get(&account) {
            if let Some(lg) = self.games.get(g) {
                let _ = lg.tx.send(game::Ev::Back(*p));
            }
        }
        (self.next_conn, old.is_some())
    }

    /// The account went away (this connection, or any with `conn` None: a kick).
    pub fn detach(&mut self, account: i64, conn: Option<u64>) {
        match self.conns.get(&account) {
            Some(c) if conn.is_none_or(|id| id == c.id) => {
                if conn.is_none() {
                    let _ = c.tx.send(Out::Close);
                }
            }
            _ => return,
        }
        self.conns.remove(&account);
        self.queue.remove(&account);
        self.invites.retain(|(a, b), _| *a != account && *b != account);
        if let Some((g, p)) = self.in_game.get(&account) {
            if let Some(lg) = self.games.get(g) {
                let _ = lg.tx.send(game::Ev::Gone(*p));
            }
        }
    }

    /// Pairs the queued players whose gaps fit both windows (the longest waiting first).
    // ponytail: O(n²) scan per tick; bucket by mode and key if queues reach thousands.
    pub fn pair(&mut self, now: Instant) -> Vec<Pairing> {
        let waited = |s: &Seeker| now.duration_since(s.since).as_secs();
        let mut order: Vec<i64> = self.queue.keys().copied().collect();
        order.sort_by_key(|id| (self.queue[id].since, *id));
        let mut taken = std::collections::HashSet::new();
        let mut pairs = vec![];
        for &a in &order {
            if taken.contains(&a) {
                continue;
            }
            let sa = &self.queue[&a];
            let best = order
                .iter()
                .filter(|&&b| b != a && !taken.contains(&b) && self.queue[&b].mode == sa.mode && self.queue[&b].rules.rules_hash == sa.rules.rules_hash)
                .filter_map(|&b| {
                    let sb = &self.queue[&b];
                    ranked::fits(sa.mode, &sa.key, waited(sa), &sb.key, waited(sb)).map(|g| (g, b))
                })
                .min_by(|x, y| x.0.total_cmp(&y.0));
            if let Some((_, b)) = best {
                taken.insert(a);
                taken.insert(b);
                pairs.push((a, b));
            }
        }
        for (&a, s) in self.queue.iter().filter(|(a, _)| !taken.contains(*a)) {
            let w = waited(s);
            self.send(a, &json!({"t": "queue_status", "mode": s.mode, "waited": w,
                "window": ranked::shown_window(s.mode, &s.key, w)}));
        }
        pairs
            .into_iter()
            .map(|(a, b)| {
                let (sa, sb) = (self.queue.remove(&a).unwrap(), self.queue.remove(&b).unwrap());
                (sa.mode, sa.rules, [(a, sa.deck), (b, sb.deck)])
            })
            .collect()
    }
}

/// Tells the account's friends its status ("online" | "in_game" | "searching" | "offline")
/// when it changed since the last time: `presence {user, online, status}`.
pub async fn presence(app: &AppRef, account: i64) {
    let friends: Result<Vec<i64>, _> = friend::Entity::find()
        .select_only()
        .column(friend::Column::B)
        .filter(friend::Column::A.eq(account))
        .into_tuple()
        .all(&app.db)
        .await;
    let Ok(friends) = friends else { return };
    let online = app.hub().conns.get(&account).map(|c| c.name.clone());
    let name = match online {
        Some(n) => n,
        None => db::name_of(&app.db, account).await.unwrap_or_default(),
    };
    let mut hub = app.hub();
    let status = hub.status(account);
    if hub.shown.get(&account).copied().unwrap_or("offline") == status {
        return;
    }
    if status == "offline" {
        hub.shown.remove(&account);
    } else {
        hub.shown.insert(account, status);
    }
    let m = json!({"t": "presence", "user": name, "online": status != "offline", "status": status});
    for f in friends {
        hub.send(f, &m);
    }
}

/// The matchmaking tick (every second), the rate-limit sweep, the admin panels' live
/// snapshot (when it changed) and, hourly, the deletion of old events.
pub fn spawn_background(app: AppRef) {
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        let mut last_live = String::new();
        let mut n: u64 = 0;
        loop {
            tick.tick().await;
            let now = Instant::now();
            let pairs = app.hub().pair(now);
            for (mode, rules, players) in pairs {
                tokio::spawn(game::start(app.clone(), mode, rules, players));
            }
            app.logins.lock().unwrap_or_else(|e| e.into_inner()).sweep(now);
            let live = app.hub().live_json();
            let text = live.to_string();
            if text != last_live {
                app.log.push(&json!({"t": "live", "live": live}));
                last_live = text;
            }
            if n.is_multiple_of(3600) {
                let old = events::now_ms() - events::KEEP_DAYS * 86_400_000;
                if let Err(e) = entity::event::Entity::delete_many().filter(entity::event::Column::At.lt(old)).exec(&app.db).await {
                    tracing::error!("pruning events: {e}");
                }
            }
            n += 1;
        }
    });
}

pub fn router(app: AppRef) -> Router {
    Router::new().route("/", get(ws_upgrade)).merge(packs::routes()).merge(admin::routes(app.clone())).with_state(app)
}

pub fn client_ip(app: &App, headers: &HeaderMap, addr: SocketAddr) -> IpAddr {
    if app.trust_proxy {
        let last = headers
            .get("x-forwarded-for")
            .and_then(|h| h.to_str().ok())
            .and_then(|s| s.rsplit(',').next())
            .and_then(|s| s.trim().parse().ok());
        if let Some(ip) = last {
            return ip;
        }
    }
    addr.ip()
}

async fn ws_upgrade(
    State(app): State<AppRef>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    let ip = client_ip(&app, &headers, addr);
    ws.max_message_size(MAX_FRAME).max_frame_size(MAX_FRAME).on_upgrade(move |s| ws::run(app, s, ip))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairs_by_window() {
        let mut h = Hub::default();
        let t0 = Instant::now();
        let classic = GameRules::classic();
        let mut add = |id, mmr, rules: &Arc<GameRules>| {
            h.queue.insert(id, Seeker { name: format!("p{id}"), mode: Mode::Casual, rules: rules.clone(), deck: json!(id),
                key: Key { mmr, level: 0, legend: false }, since: t0 });
        };
        add(1, 1500.0, &classic);
        add(2, 1700.0, &classic);
        add(3, 1540.0, &classic);
        add(4, 1900.0, &classic);
        // Another pack's queue: never paired with the Classic seekers.
        let other = Arc::new(GameRules { rules_hash: "other".into(), ..GameRules::of(classic.rs, &classichs_engine::ruleset::classic_files()) });
        add(5, 1500.0, &other);
        let p = h.pair(t0);
        assert_eq!(p.len(), 1);
        assert_eq!([p[0].2[0].0, p[0].2[1].0], [1, 3]);
        assert!(h.pair(t0 + Duration::from_secs(5)).is_empty()); // 200 > 50 + 125
        assert_eq!(h.pair(t0 + Duration::from_secs(6)).len(), 1); // 200 ≤ 50 + 150
    }
}
