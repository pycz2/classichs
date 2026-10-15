//! classichs-server: accounts, social, matchmaking and refereed games for Classic HS.
//! Protocol: docs/superpowers/specs/2026-10-15-server-design.md.

pub mod admin;
pub mod auth;
pub mod db;
pub mod game;
pub mod ranked;
pub mod referee;
pub mod ws;

use auth::RateLimit;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{ConnectInfo, State};
use axum::http::HeaderMap;
use axum::response::Response;
use axum::routing::get;
use axum::Router;
use db::Db;
use ranked::{Key, Mode};
use referee::Referee;
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
    pub referee: Arc<dyn Referee>,
    pub hub: Mutex<Hub>,
    /// Login and register attempts, keyed "ip:…" and "user:…": 10 a minute.
    pub logins: Mutex<RateLimit>,
    /// Use the last X-Forwarded-For address (behind a reverse proxy).
    pub trust_proxy: bool,
    /// How long a player who dropped out of a game has to come back.
    pub grace: Duration,
}

impl App {
    pub fn new(db: Db, referee: Arc<dyn Referee>, trust_proxy: bool, grace: Duration) -> AppRef {
        Arc::new(App {
            db,
            referee,
            hub: Mutex::new(Hub::default()),
            logins: Mutex::new(RateLimit::new(10, Duration::from_secs(60))),
            trust_proxy,
            grace,
        })
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
}

pub struct Conn {
    pub id: u64,
    pub name: String,
    pub tx: UnboundedSender<Out>,
}

pub struct Seeker {
    pub name: String,
    pub mode: Mode,
    pub deck: Value,
    pub key: Key,
    pub since: Instant,
}

pub struct LiveGame {
    pub tx: UnboundedSender<game::Ev>,
    pub mode: Mode,
    pub ids: [i64; 2],
    pub names: [String; 2],
    pub started: i64,
    pub turn: i64,
    pub current: i64,
}

#[derive(Default)]
pub struct Hub {
    next_conn: u64,
    pub conns: HashMap<i64, Conn>,
    pub queue: HashMap<i64, Seeker>,
    pub games: HashMap<String, LiveGame>,
    /// Account → (game id, player number).
    pub in_game: HashMap<i64, (String, usize)>,
    /// (from, to) → the inviter's deck.
    pub invites: HashMap<(i64, i64), Value>,
}

impl Hub {
    pub fn send(&self, account: i64, v: &Value) {
        if let Some(c) = self.conns.get(&account) {
            let _ = c.tx.send(Out::Text(v.to_string()));
        }
    }

    pub fn status(&self, account: i64) -> &'static str {
        if !self.conns.contains_key(&account) {
            "offline"
        } else if self.in_game.contains_key(&account) {
            "game"
        } else if self.queue.contains_key(&account) {
            "queue"
        } else {
            "online"
        }
    }

    /// The account's new connection; an older one is closed. Returns the connection id.
    pub fn attach(&mut self, account: i64, name: &str, tx: UnboundedSender<Out>) -> u64 {
        self.next_conn += 1;
        let old = self.conns.insert(account, Conn { id: self.next_conn, name: name.into(), tx });
        if let Some(old) = old {
            let _ = old.tx.send(Out::Text(json!({"t": "error", "code": "replaced", "text": "Logged in elsewhere"}).to_string()));
            let _ = old.tx.send(Out::Close);
        }
        if let Some((g, p)) = self.in_game.get(&account) {
            if let Some(lg) = self.games.get(g) {
                let _ = lg.tx.send(game::Ev::Back(*p));
            }
        }
        self.next_conn
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
    pub fn pair(&mut self, now: Instant) -> Vec<(Mode, [(i64, Value); 2])> {
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
                .filter(|&&b| b != a && !taken.contains(&b) && self.queue[&b].mode == sa.mode)
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
                (sa.mode, [(a, sa.deck), (b, sb.deck)])
            })
            .collect()
    }
}

/// The matchmaking tick (every second) and the rate-limit sweep.
pub fn spawn_background(app: AppRef) {
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            tick.tick().await;
            let now = Instant::now();
            let pairs = app.hub().pair(now);
            for (mode, players) in pairs {
                tokio::spawn(game::start(app.clone(), mode, players));
            }
            app.logins.lock().unwrap_or_else(|e| e.into_inner()).sweep(now);
        }
    });
}

pub fn router(app: AppRef) -> Router {
    Router::new().route("/", get(ws_upgrade)).merge(admin::routes()).with_state(app)
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
        let mut add = |id, mmr| {
            h.queue.insert(id, Seeker { name: format!("p{id}"), mode: Mode::Casual, deck: json!(id),
                key: Key { mmr, level: 0, legend: false }, since: t0 });
        };
        add(1, 1500.0);
        add(2, 1700.0);
        add(3, 1540.0);
        add(4, 1900.0);
        let p = h.pair(t0);
        assert_eq!(p.len(), 1);
        assert_eq!([p[0].1[0].0, p[0].1[1].0], [1, 3]);
        assert!(h.pair(t0 + Duration::from_secs(5)).is_empty()); // 200 > 50 + 125
        assert_eq!(h.pair(t0 + Duration::from_secs(6)).len(), 1); // 200 ≤ 50 + 150
    }
}
