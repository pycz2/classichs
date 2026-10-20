//! Load generator: simulated players over the real WebSocket protocol (docs/server-profiling.md).
//!
//! ```sh
//! cargo build --release --example loadgen && L=target/release/examples/loadgen
//! # the server under test: its own port, database and store; --trust-proxy, because every
//! # simulated client sends its own X-Forwarded-For (the login limits are per address)
//! target/release/classichs-server --listen 127.0.0.1:7400 --db /tmp/p/lg.db --store-dir /tmp/p/store --trust-proxy &
//! $L setup --url ws://127.0.0.1:7400 --n 1000 --out /tmp/p/acc.json --db /tmp/p/lg.db --friends 10
//! $L idle  --url ws://127.0.0.1:7400 --acc /tmp/p/acc.json --n 1000 --secs 60 --churn 5 --pid $PID
//! $L play  --url ws://127.0.0.1:7400 --acc /tmp/p/acc.json --n 400 --secs 180 --think 500-2000 --pid $PID
//! $L burst --url ws://127.0.0.1:7400 --acc /tmp/p/acc.json --n 200 --conc 50 --pid $PID   # password logins (argon2)
//! $L mkadmin --db /tmp/p/lg.db --user root --pass password123     # before the server starts
//! ```
//!
//! `play`: every client resumes its session, queues casual in the default game (Neonfall) or,
//! with probability `--classic` (0.5), in Classic, and plays: it rebuilds a playable game from
//! its own view (`view::from_snapshot_in`, as the Godot client does with `new {state}`) and
//! moves with the engine's bot (or a random legal move with probability `--random`), after a
//! think delay drawn from `--think` (ms, `0` = no delay: the stress mode). It requeues after each
//! game and concedes at the end. Measured from `--warm` seconds to `--secs`: `act` → next
//! `state` latency (client side, so an upper bound of the server's), message sizes, actions
//! and games; with `--pid`, the server's RSS and CPU (`ps`). `--admin user:pass` also keeps an
//! admin live feed (/admin/ws) open. One JSON line of results goes to stdout.

use classichs_engine::ruleset::Ruleset;
use classichs_engine::{bot, deck, view, Engine, Game};
use futures_util::{SinkExt, StreamExt};
use rand::{Rng, SeedableRng};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{Notify, Semaphore};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
const PASSWORD: &str = "password123";
/// The shortest gap between a client's actions (the server's limit: 300 messages per 10 s).
const MIN_GAP: Duration = Duration::from_millis(40);

struct Args(HashMap<String, String>);

impl Args {
    fn get(&self, k: &str, d: &str) -> String {
        self.0.get(k).cloned().unwrap_or_else(|| d.to_string())
    }
    fn num(&self, k: &str, d: f64) -> f64 {
        self.0.get(k).map_or(d, |v| v.parse().unwrap_or_else(|_| panic!("--{k}: a number")))
    }
}

#[derive(Default)]
struct Stats {
    lat_us: Mutex<Vec<u32>>,
    state_bytes: Mutex<Vec<u32>>,
    frames_in: AtomicU64,
    bytes_in: AtomicU64,
    frames_out: AtomicU64,
    bytes_out: AtomicU64,
    presence: AtomicU64,
    matches: AtomicU64,
    games_over: AtomicU64,
    acts: AtomicU64,
    act_errors: AtomicU64,
    errors: AtomicU64,
    admin_frames: AtomicU64,
    admin_bytes: AtomicU64,
    admin_resyncs: AtomicU64,
    samples: Mutex<Vec<String>>,
}

impl Stats {
    fn sample(&self, s: String) {
        let mut v = self.samples.lock().unwrap();
        if v.len() < 8 {
            v.push(s);
        }
    }
}

/// The measuring window: counted only between `from` and `to`.
#[derive(Clone, Copy)]
struct Window {
    from: Instant,
    to: Instant,
}

impl Window {
    fn on(&self) -> bool {
        let n = Instant::now();
        n >= self.from && n < self.to
    }
}

fn xff(i: usize) -> String {
    let i = i + 1;
    format!("10.{}.{}.{}", (i >> 16) & 255, (i >> 8) & 255, i & 255)
}

async fn connect(url: &str, i: usize) -> Result<Ws, String> {
    let mut req = url.into_client_request().map_err(|e| e.to_string())?;
    req.headers_mut().insert("x-forwarded-for", xff(i).parse().unwrap());
    tokio_tungstenite::connect_async(req).await.map(|w| w.0).map_err(|e| e.to_string())
}

async fn send(ws: &mut Ws, st: &Stats, v: Value) -> Result<(), String> {
    let s = v.to_string();
    st.frames_out.fetch_add(1, Relaxed);
    st.bytes_out.fetch_add(s.len() as u64, Relaxed);
    ws.send(Message::text(s)).await.map_err(|e| e.to_string())
}

/// The next text frame as JSON, with its size; None = closed.
async fn recv(ws: &mut Ws, st: &Stats) -> Option<(Value, usize)> {
    loop {
        match ws.next().await? {
            Ok(Message::Text(t)) => {
                st.frames_in.fetch_add(1, Relaxed);
                st.bytes_in.fetch_add(t.len() as u64, Relaxed);
                return serde_json::from_str(t.as_str()).ok().map(|v| (v, t.len()));
            }
            Ok(Message::Close(_)) | Err(_) => return None,
            Ok(_) => {}
        }
    }
}

/// Reads until a message of type `t` (or an error message) arrives.
async fn want(ws: &mut Ws, st: &Stats, t: &str) -> Result<Value, String> {
    loop {
        let (v, _) = tokio::time::timeout(Duration::from_secs(60), recv(ws, st))
            .await
            .map_err(|_| format!("timed out waiting for {t}"))?
            .ok_or_else(|| format!("closed waiting for {t}"))?;
        if v["t"] == t {
            return Ok(v);
        }
        if v["t"] == "error" {
            return Err(v.to_string());
        }
    }
}

async fn resume(url: &str, i: usize, token: &str, st: &Stats) -> Result<Ws, String> {
    let mut ws = connect(url, i).await?;
    send(&mut ws, st, json!({"t": "resume", "token": token})).await?;
    want(&mut ws, st, "auth").await?;
    Ok(ws)
}

// --- the server's process: RSS and CPU time by `ps` ------------------------------------------

#[derive(Default)]
struct Sampler {
    /// (seconds since start, RSS KB, CPU seconds).
    rows: Mutex<Vec<(f64, u64, f64)>>,
}

fn cpu_secs(s: &str) -> f64 {
    // [[D-]H:]M:S(.ss) (macOS and Linux `ps -o time`)
    let (days, rest) = s.split_once('-').map_or((0.0, s), |(d, r)| (d.parse().unwrap_or(0.0), r));
    days * 86400.0 + rest.split(':').fold(0.0, |acc, p| acc * 60.0 + p.parse::<f64>().unwrap_or(0.0))
}

fn ps(pid: &str) -> Option<(u64, f64)> {
    let out = std::process::Command::new("ps").args(["-o", "rss=,time=", "-p", pid]).output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    let mut it = s.split_whitespace();
    Some((it.next()?.parse().ok()?, cpu_secs(it.next()?)))
}

impl Sampler {
    fn start(pid: Option<String>, t0: Instant) -> Arc<Sampler> {
        let s = Arc::new(Sampler::default());
        if let Some(pid) = pid {
            let s2 = s.clone();
            tokio::spawn(async move {
                let mut tick = tokio::time::interval(Duration::from_millis(500));
                loop {
                    tick.tick().await;
                    let p = pid.clone();
                    let Ok(Some((rss, cpu))) = tokio::task::spawn_blocking(move || ps(&p)).await else { break };
                    s2.rows.lock().unwrap().push((t0.elapsed().as_secs_f64(), rss, cpu));
                }
            });
        }
        s
    }

    /// RSS (MB) at the window's start and end and its peak, the CPU (cores) used in it.
    fn summary(&self, from: f64, to: f64) -> Value {
        let rows = self.rows.lock().unwrap();
        let w: Vec<&(f64, u64, f64)> = rows.iter().filter(|r| r.0 >= from && r.0 <= to).collect();
        let (Some(a), Some(b)) = (w.first(), w.last()) else { return Value::Null };
        let all_peak = rows.iter().map(|r| r.1).max().unwrap_or(0);
        let mb = |k: u64| (k as f64 / 1024.0 * 10.0).round() / 10.0;
        json!({"rss_mb_start": mb(a.1), "rss_mb_end": mb(b.1), "rss_mb_peak": mb(w.iter().map(|r| r.1).max().unwrap_or(0)),
               "rss_mb_peak_run": mb(all_peak), "cpu_s": ((b.2 - a.2) * 1000.0).round() / 1000.0,
               "cpu_cores": if b.0 > a.0 { ((b.2 - a.2) / (b.0 - a.0) * 1000.0).round() / 1000.0 } else { 0.0 }})
    }
}

/// Unix seconds now minus the time since `t0`: when `t0` was (to line up `docker stats` samples).
fn unix_at(t0: Instant) -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64() - t0.elapsed().as_secs_f64()
}

fn pct(v: &mut [u32], p: f64) -> f64 {
    if v.is_empty() {
        return 0.0;
    }
    v.sort_unstable();
    v[((v.len() - 1) as f64 * p).round() as usize] as f64
}

// --- setup: accounts, friends, the superuser ---------------------------------------------------

async fn setup(a: &Args) {
    let url = a.get("url", "ws://127.0.0.1:7400");
    let n = a.num("n", 100.0) as usize;
    let prefix = a.get("prefix", "lg");
    let st = Arc::new(Stats::default());
    let sem = Arc::new(Semaphore::new(a.num("conc", 8.0) as usize));
    let t0 = Instant::now();
    let jobs: Vec<_> = (0..n)
        .map(|i| {
            let (url, st, sem, user) = (url.clone(), st.clone(), sem.clone(), format!("{prefix}{i}"));
            tokio::spawn(async move {
                let _p = sem.acquire().await.unwrap();
                let mut ws = connect(&url, i).await?;
                send(&mut ws, &st, json!({"t": "register", "user": user, "password": PASSWORD})).await?;
                let auth = match want(&mut ws, &st, "auth").await {
                    Ok(v) => v,
                    Err(e) if e.contains("taken") => {
                        send(&mut ws, &st, json!({"t": "login", "user": user, "password": PASSWORD})).await?;
                        want(&mut ws, &st, "auth").await?
                    }
                    Err(e) => return Err(e),
                };
                let _ = ws.close(None).await;
                Ok::<_, String>(json!({"user": user, "token": auth["token"]}))
            })
        })
        .collect();
    let mut out = vec![];
    for j in jobs {
        match j.await.unwrap() {
            Ok(v) => out.push(v),
            Err(e) => panic!("setup: {e}"),
        }
    }
    let took = t0.elapsed().as_secs_f64();
    std::fs::write(a.get("out", "accounts.json"), serde_json::to_string(&out).unwrap()).unwrap();
    let k = a.num("friends", 0.0) as i64;
    if k > 0 {
        // Each account befriends its k nearest ids (a ring), both ways, straight in the database.
        let db = classichs_server::db::open(&a.get("db", "classichs.db")).await.unwrap();
        let sql = format!(
            "INSERT OR IGNORE INTO friends (a, b) SELECT x.id, y.id FROM accounts x JOIN accounts y \
             ON y.id != x.id AND abs(y.id - x.id) <= {} WHERE x.name LIKE '{prefix}%' AND y.name LIKE '{prefix}%'",
            k / 2
        );
        use sea_orm::ConnectionTrait;
        db.execute_unprepared(&sql).await.unwrap();
    }
    println!("{}", json!({"cmd": "setup", "accounts": out.len(), "secs": took, "per_s": out.len() as f64 / took}));
}

async fn mkadmin(a: &Args) {
    let db = classichs_server::db::open(&a.get("db", "classichs.db")).await.unwrap();
    let hash = classichs_server::auth::hash_password(&a.get("pass", PASSWORD));
    classichs_server::db::make_superuser(&db, &a.get("user", "root"), &hash).await.unwrap();
}

fn accounts(a: &Args) -> Vec<(String, String)> {
    let v: Vec<Value> = serde_json::from_str(&std::fs::read_to_string(a.get("acc", "accounts.json")).unwrap()).unwrap();
    let n = (a.num("n", v.len() as f64) as usize).min(v.len());
    v[..n].iter().map(|x| (x["user"].as_str().unwrap().into(), x["token"].as_str().unwrap().into())).collect()
}

// --- the admin panel's live feed -----------------------------------------------------------------

async fn admin_feed(url: &str, cred: &str, st: Arc<Stats>, stop: Instant) -> Result<(), String> {
    let (user, pass) = cred.split_once(':').ok_or("--admin user:pass")?;
    let host = url.trim_start_matches("ws://").trim_end_matches('/');
    let body = json!({"user": user, "password": pass}).to_string();
    let mut s = tokio::net::TcpStream::connect(host).await.map_err(|e| e.to_string())?;
    let req = format!(
        "POST /admin/api/login HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    s.write_all(req.as_bytes()).await.map_err(|e| e.to_string())?;
    let mut res = String::new();
    s.read_to_string(&mut res).await.map_err(|e| e.to_string())?;
    let cookie = res
        .lines()
        .find_map(|l| l.to_ascii_lowercase().starts_with("set-cookie:").then(|| l[11..].trim().split(';').next().unwrap_or("").to_string()))
        .ok_or_else(|| format!("admin login failed: {}", res.lines().next().unwrap_or("")))?;
    let mut req = format!("ws://{host}/admin/ws").into_client_request().map_err(|e| e.to_string())?;
    req.headers_mut().insert("cookie", cookie.parse().unwrap());
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await.map_err(|e| e.to_string())?;
    while Instant::now() < stop {
        match tokio::time::timeout(Duration::from_secs(1), ws.next()).await {
            Ok(Some(Ok(Message::Text(t)))) => {
                st.admin_frames.fetch_add(1, Relaxed);
                st.admin_bytes.fetch_add(t.len() as u64, Relaxed);
                if t.as_str().starts_with(r#"{"t":"resync""#) {
                    st.admin_resyncs.fetch_add(1, Relaxed);
                }
            }
            Ok(None) | Ok(Some(Err(_))) => return Err("admin feed closed".into()),
            _ => {}
        }
    }
    Ok(())
}

// --- idle: logged-in clients that do nothing (presence only), with optional churn -----------------

async fn idle(a: &Args) {
    let url = a.get("url", "ws://127.0.0.1:7400");
    let acc = accounts(a);
    let n = acc.len();
    let secs = a.num("secs", 60.0);
    let churn = a.num("churn", 0.0);
    let t0 = Instant::now();
    let sampler = Sampler::start(a.0.get("pid").cloned(), t0);
    tokio::time::sleep(Duration::from_secs(2)).await; // the RSS before
    let before = t0.elapsed().as_secs_f64();
    let st = Arc::new(Stats::default());
    let sem = Arc::new(Semaphore::new(64));
    let kicks: Vec<Arc<Notify>> = (0..n).map(|_| Arc::new(Notify::new())).collect();
    let ready = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(Notify::new());
    let reconnects = Arc::new(AtomicU64::new(0));
    let mut jobs = vec![];
    for (i, (_, token)) in acc.iter().enumerate() {
        let (url, token, st, sem, kick, ready, stop, rc) =
            (url.clone(), token.clone(), st.clone(), sem.clone(), kicks[i].clone(), ready.clone(), stop.clone(), reconnects.clone());
        let me_pack = a.0.get("me-pack").cloned();
        jobs.push(tokio::spawn(async move {
            let mut first = true;
            loop {
                let ws = {
                    let _p = sem.acquire().await.unwrap();
                    resume(&url, i, &token, &st).await
                };
                let mut ws = match ws {
                    Ok(w) => w,
                    Err(e) => {
                        st.errors.fetch_add(1, Relaxed);
                        st.sample(e);
                        return;
                    }
                };
                if first {
                    if let (0, Some(h)) = (i, &me_pack) {
                        // loads that pack's rules in the server (the RSS of a ruleset)
                        let _ = send(&mut ws, &st, json!({"t": "me", "pack": h})).await;
                    }
                    ready.fetch_add(1, Relaxed);
                    first = false;
                } else {
                    rc.fetch_add(1, Relaxed);
                }
                loop {
                    tokio::select! {
                        m = recv(&mut ws, &st) => match m {
                            Some((v, _)) => if v["t"] == "presence" { st.presence.fetch_add(1, Relaxed); },
                            None => { st.errors.fetch_add(1, Relaxed); return; }
                        },
                        _ = kick.notified() => { let _ = ws.close(None).await; break; }
                        _ = stop.notified() => { let _ = ws.close(None).await; return; }
                    }
                }
            }
        }));
    }
    while (ready.load(Relaxed) as usize) < n && jobs.iter().any(|j| !j.is_finished()) {
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let connected_at = t0.elapsed().as_secs_f64();
    tokio::time::sleep(Duration::from_secs(3)).await; // settle
    let from = t0.elapsed().as_secs_f64();
    let (p0, f0) = (st.presence.load(Relaxed), st.frames_in.load(Relaxed));
    let admin = a.0.get("admin").cloned();
    if let Some(cred) = admin.clone() {
        let (url, st) = (url.clone(), st.clone());
        let stop_at = Instant::now() + Duration::from_secs_f64(secs);
        tokio::spawn(async move {
            if let Err(e) = admin_feed(&url, &cred, st.clone(), stop_at).await {
                st.sample(e);
            }
        });
    }
    let end = Instant::now() + Duration::from_secs_f64(secs);
    let mut rng = rand::rngs::StdRng::from_entropy();
    while Instant::now() < end {
        if churn > 0.0 {
            kicks[rng.gen_range(0..n)].notify_one();
            tokio::time::sleep(Duration::from_secs_f64(1.0 / churn)).await;
        } else {
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
    }
    let to = t0.elapsed().as_secs_f64();
    let report = json!({
        "cmd": "idle", "t0_unix": unix_at(t0), "win": [from, to], "before": before, "clients": n, "connected": ready.load(Relaxed), "connect_secs": connected_at - before,
        "window_s": to - from, "churn_per_s": churn, "reconnects": reconnects.load(Relaxed),
        "presence_per_s": (st.presence.load(Relaxed) - p0) as f64 / (to - from),
        "frames_in_per_s": (st.frames_in.load(Relaxed) - f0) as f64 / (to - from),
        "errors": st.errors.load(Relaxed), "samples": *st.samples.lock().unwrap(),
        "admin_frames": st.admin_frames.load(Relaxed), "admin_bytes": st.admin_bytes.load(Relaxed),
        "server_before": sampler.summary(0.0, before),
        "server_idle": sampler.summary(from, to),
    });
    let b = &report["server_before"]["rss_mb_end"];
    let i = &report["server_idle"]["rss_mb_end"];
    let per = match (b.as_f64(), i.as_f64()) {
        (Some(b), Some(i)) => json!(((i - b) * 1024.0 / n as f64 * 10.0).round() / 10.0),
        _ => Value::Null,
    };
    let mut report = report;
    report["rss_kb_per_conn"] = per;
    println!("{report}");
    for _ in 0..3 {
        stop.notify_waiters();
        tokio::time::sleep(Duration::from_millis(300)).await;
    }
}

// --- burst: password logins at once (argon2 on the blocking pool) ---------------------------------

async fn burst(a: &Args) {
    let url = a.get("url", "ws://127.0.0.1:7400");
    let acc = accounts(a);
    let t0 = Instant::now();
    let sampler = Sampler::start(a.0.get("pid").cloned(), t0);
    tokio::time::sleep(Duration::from_secs(2)).await;
    let from = t0.elapsed().as_secs_f64();
    let st = Arc::new(Stats::default());
    let sem = Arc::new(Semaphore::new(a.num("conc", 50.0) as usize));
    let lat = Arc::new(Mutex::new(vec![]));
    let jobs: Vec<_> = acc
        .iter()
        .enumerate()
        .map(|(i, (user, _))| {
            let (url, user, st, sem, lat) = (url.clone(), user.clone(), st.clone(), sem.clone(), lat.clone());
            tokio::spawn(async move {
                let _p = sem.acquire().await.unwrap();
                let Ok(mut ws) = connect(&url, i).await else { return };
                let t = Instant::now();
                let _ = send(&mut ws, &st, json!({"t": "login", "user": user, "password": PASSWORD})).await;
                if want(&mut ws, &st, "auth").await.is_ok() {
                    lat.lock().unwrap().push(t.elapsed().as_micros() as u32);
                } else {
                    st.errors.fetch_add(1, Relaxed);
                }
                let _ = ws.close(None).await;
            })
        })
        .collect();
    for j in jobs {
        let _ = j.await;
    }
    let to = t0.elapsed().as_secs_f64();
    tokio::time::sleep(Duration::from_secs(2)).await;
    let mut l = lat.lock().unwrap().clone();
    println!("{}", json!({"cmd": "burst", "t0_unix": unix_at(t0), "win": [from, to], "logins": l.len(), "errors": st.errors.load(Relaxed), "secs": to - from,
        "per_s": l.len() as f64 / (to - from), "lat_ms_p50": pct(&mut l, 0.5) / 1000.0, "lat_ms_p99": pct(&mut l, 0.99) / 1000.0,
        "server": sampler.summary(from, to)}));
}

// --- play: bot-vs-bot games through the protocol ------------------------------------------------------

struct Pack {
    /// None: the server's default game (no `pack` in `queue`).
    hash: Option<String>,
    decks: Vec<Value>,
}

/// The pack's ready decks (decks/*.json) and the starter decks that are legal in its rules.
fn decks_of(rs: &Ruleset, ready: &[Value]) -> Vec<Value> {
    let ready = ready.iter().filter_map(|d| deck::Deck::from_value_in(rs, &json!({"hero": d.get("champion").or(d.get("hero"))?, "cards": d.get("cards")?})));
    let starter = rs
        .classes
        .iter()
        .filter(|c| c.playable && !c.champion.is_empty())
        .map(|c| deck::Deck { hero: c.champion.clone(), cards: deck::basic_in(rs, &c.id), arena: false });
    ready.chain(starter).filter(|d| d.validate_in(rs).is_empty()).map(|d| json!({"hero": d.hero, "cards": d.cards})).collect()
}

struct Play {
    url: String,
    packs: Vec<Pack>,
    classic: f64,
    random: f64,
    think: (u64, u64),
    win: Window,
    stop: Instant,
    st: Stats,
}

/// Whose move: does player p have one now (per the view)?
fn my_move(g: &Game, p: usize, sent_mulligan: bool) -> bool {
    if g.game_over {
        false
    } else if g.phase == "MULLIGAN" {
        !g.players[p].mulliganed && !sent_mulligan
    } else if let Some(c) = &g.pending {
        c.player == p
    } else {
        g.current == p
    }
}

async fn player(i: usize, token: String, ctx: Arc<Play>) -> Result<(), String> {
    let st = &ctx.st;
    let mut ws = resume(&ctx.url, i, &token, st).await?;
    let mut rng = rand::rngs::StdRng::seed_from_u64(i as u64 * 7919 + 1);
    let mut last = Instant::now();
    while Instant::now() < ctx.stop {
        let pi = if rng.gen_bool(ctx.classic) { 1 } else { 0 };
        let pack = &ctx.packs[pi];
        let deck = pack.decks[rng.gen_range(0..pack.decks.len())].clone();
        let mut q = json!({"t": "queue", "mode": "casual", "deck": deck});
        if let Some(h) = &pack.hash {
            q["pack"] = json!(h);
        }
        send(&mut ws, st, q).await?;
        let mut game: Option<(String, usize, &'static Ruleset)> = None;
        let mut sent: Option<(Instant, bool)> = None;
        let mut sent_mulligan = false;
        let mut conceded = false;
        loop {
            let left = ctx.stop.saturating_duration_since(Instant::now());
            let m = if conceded || game.is_none() && left.is_zero() {
                tokio::time::timeout(Duration::from_secs(15), recv(&mut ws, st)).await.ok().flatten()
            } else {
                match tokio::time::timeout(left.max(Duration::from_millis(1)), recv(&mut ws, st)).await {
                    Ok(m) => m,
                    Err(_) => {
                        // the end of the run: concede the game (or leave the queue)
                        match &game {
                            Some((g, p, _)) => send(&mut ws, st, json!({"t": "act", "game": g, "action": {"type": "concede", "player": p}})).await?,
                            None => send(&mut ws, st, json!({"t": "unqueue"})).await?,
                        }
                        conceded = true;
                        continue;
                    }
                }
            };
            let Some((v, size)) = m else {
                if conceded || game.is_none() {
                    return Ok(());
                }
                return Err("connection closed".into());
            };
            let at = Instant::now();
            match v["t"].as_str().unwrap_or("") {
                "match" => {
                    let rs = classichs_engine::ruleset::get(v["pack"].as_str().unwrap_or("")).ok_or("a game in an unknown pack")?;
                    game = Some((v["game"].as_str().unwrap_or("").into(), v["you"].as_u64().unwrap_or(0) as usize, rs));
                    if ctx.win.on() {
                        st.matches.fetch_add(1, Relaxed);
                    }
                }
                "state" => {
                    let on = ctx.win.on();
                    if on {
                        st.state_bytes.lock().unwrap().push(size as u32);
                    }
                    if let Some((t, mull)) = sent.take() {
                        if on && !mull {
                            st.lat_us.lock().unwrap().push((at - t).as_micros() as u32);
                        }
                    }
                    let Some((gid, p, rs)) = game.clone() else { continue };
                    if v["result"]["over"] == true || conceded {
                        continue;
                    }
                    let g = match view::from_snapshot_in(rs, &v["view"]) {
                        Ok(g) => g,
                        Err(e) => {
                            st.errors.fetch_add(1, Relaxed);
                            st.sample(format!("view: {e}"));
                            continue;
                        }
                    };
                    if !my_move(&g, p, sent_mulligan) {
                        continue;
                    }
                    // At least MIN_GAP between a client's messages: the server allows 300 per 10 s.
                    let ms = if ctx.think.1 > 0 { rng.gen_range(ctx.think.0..=ctx.think.1) } else { 0 };
                    let wait = Duration::from_millis(ms).max(MIN_GAP.saturating_sub(last.elapsed()));
                    tokio::time::sleep(wait).await;
                    let action = if rng.gen_bool(ctx.random) {
                        let legal: Vec<_> = g
                            .legal_actions()
                            .into_iter()
                            .filter(|a| a["player"].as_u64() == Some(p as u64) && a["type"] != "concede")
                            .collect();
                        (!legal.is_empty()).then(|| Value::Object(legal[rng.gen_range(0..legal.len())].clone()))
                    } else {
                        bot::choose(&g, p).map(Value::Object)
                    };
                    let action = action.unwrap_or_else(|| {
                        if g.phase == "MULLIGAN" {
                            json!({"type": "mulligan", "player": p, "replace": []})
                        } else {
                            json!({"type": "end_turn", "player": p})
                        }
                    });
                    let mull = action["type"] == "mulligan";
                    sent_mulligan |= mull;
                    send(&mut ws, st, json!({"t": "act", "game": gid, "action": action})).await?;
                    last = Instant::now();
                    sent = Some((last, mull));
                    if ctx.win.on() {
                        st.acts.fetch_add(1, Relaxed);
                    }
                }
                "act_error" => {
                    st.act_errors.fetch_add(1, Relaxed);
                    st.sample(format!("act_error: {}", v["error"]));
                    sent = None;
                }
                "game_over" => {
                    if ctx.win.on() {
                        st.games_over.fetch_add(1, Relaxed);
                    }
                    break;
                }
                "unqueued" => return Ok(()),
                "error" => {
                    st.errors.fetch_add(1, Relaxed);
                    st.sample(v.to_string());
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    break;
                }
                _ => {}
            }
        }
    }
    let _ = ws.close(None).await;
    Ok(())
}

async fn play(a: &Args) {
    let url = a.get("url", "ws://127.0.0.1:7400");
    let acc = accounts(a);
    // The packs: the server's list (the default game and Classic), the files from --packs.
    let st0 = Stats::default();
    let mut ws = resume(&url, 0, &acc[0].1, &st0).await.unwrap();
    send(&mut ws, &st0, json!({"t": "packs"})).await.unwrap();
    let list = want(&mut ws, &st0, "packs").await.unwrap();
    let _ = ws.close(None).await;
    let server = list["server"].as_array().cloned().unwrap_or_default();
    let dir = a.get("packs", "../packs");
    let mut engine = Engine::new();
    let mut ready: HashMap<String, Vec<Value>> = HashMap::new();
    for f in std::fs::read_dir(&dir).unwrap().flatten().filter(|e| e.path().extension().is_some_and(|x| x == "cardpack")) {
        let bytes = std::fs::read(f.path()).unwrap();
        let rs = engine.load_pack_bytes(&bytes).unwrap();
        ready.insert(rs.rules_hash.clone(), classichs_server::packs::inspect(&bytes).map(|p| p.decks).unwrap_or_default());
    }
    let find = |pred: &dyn Fn(&Value) -> bool| -> Pack {
        let p = server.iter().find(|p| pred(p)).unwrap_or_else(|| panic!("no such pack on the server: {list}"));
        let h = p["rules_hash"].as_str().unwrap();
        let rs = classichs_engine::ruleset::get(h).unwrap_or_else(|| panic!("pack {h} is not in {dir}"));
        let decks = decks_of(rs, ready.get(h).map_or(&[][..], |v| &v[..]));
        assert!(!decks.is_empty(), "no legal deck for {h}");
        Pack { hash: (p["default"] != true).then(|| h.to_string()), decks }
    };
    let packs = vec![find(&|p| p["default"] == true), find(&|p| p["id"].as_str().is_some_and(|s| s.starts_with("classic")))];
    let think = a.get("think", "500-2000");
    let think = think.split_once('-').map_or_else(
        || (think.parse().unwrap(), think.parse().unwrap()),
        |(x, y)| (x.parse().unwrap(), y.parse().unwrap()),
    );
    let secs = a.num("secs", 120.0);
    let warm = a.num("warm", 15.0_f64.min(secs / 4.0));
    let t0 = Instant::now();
    let sampler = Sampler::start(a.0.get("pid").cloned(), t0);
    let win = Window { from: t0 + Duration::from_secs_f64(warm), to: t0 + Duration::from_secs_f64(secs) };
    let ctx = Arc::new(Play {
        url: url.clone(),
        packs,
        classic: a.num("classic", 0.5),
        random: a.num("random", 0.0),
        think,
        win,
        stop: win.to,
        st: Stats::default(),
    });
    if let Some(cred) = a.0.get("admin").cloned() {
        let (url, ctx) = (url.clone(), ctx.clone());
        tokio::spawn(async move {
            let st = Arc::new(Stats::default());
            let r = admin_feed(&url, &cred, st.clone(), ctx.stop).await;
            ctx.st.admin_frames.store(st.admin_frames.load(Relaxed), Relaxed);
            ctx.st.admin_bytes.store(st.admin_bytes.load(Relaxed), Relaxed);
            ctx.st.admin_resyncs.store(st.admin_resyncs.load(Relaxed), Relaxed);
            if let Err(e) = r {
                ctx.st.sample(e);
            }
        });
    }
    let ramp = a.num("ramp", 200.0); // connections a second
    let n = acc.len();
    let mut jobs = vec![];
    for (i, (_, token)) in acc.into_iter().enumerate() {
        let ctx = ctx.clone();
        jobs.push(tokio::spawn(async move {
            if let Err(e) = player(i, token, ctx.clone()).await {
                ctx.st.errors.fetch_add(1, Relaxed);
                ctx.st.sample(e);
            }
        }));
        tokio::time::sleep(Duration::from_secs_f64(1.0 / ramp)).await;
    }
    let hard_stop = tokio::time::Instant::from_std(ctx.stop + Duration::from_secs(60));
    for j in jobs {
        if tokio::time::timeout_at(hard_stop, j).await.is_err() {
            ctx.st.sample("a client did not finish within 60 s of the end".into());
        }
    }
    tokio::time::sleep(Duration::from_millis(1500)).await; // the admin feed's last numbers
    let st = &ctx.st;
    let w = (warm, secs);
    let span = w.1 - w.0;
    let mut lat = st.lat_us.lock().unwrap().clone();
    let mut sizes = st.state_bytes.lock().unwrap().clone();
    let acts = st.acts.load(Relaxed);
    let server = sampler.summary(w.0, w.1);
    let cpu_s = server["cpu_s"].as_f64().unwrap_or(0.0);
    let games = st.games_over.load(Relaxed) as f64 / 2.0;
    println!(
        "{}",
        json!({
            "cmd": "play", "t0_unix": unix_at(t0), "win": [w.0, w.1], "clients": n, "think_ms": [think.0, think.1], "window_s": span, "classic": ctx.classic, "random": ctx.random,
            "acts": acts, "acts_per_s": acts as f64 / span, "games": games, "games_per_min": games / span * 60.0,
            "lat_ms": {"n": lat.len(), "p50": pct(&mut lat, 0.5) / 1000.0, "p95": pct(&mut lat, 0.95) / 1000.0,
                       "p99": pct(&mut lat, 0.99) / 1000.0, "max": pct(&mut lat, 1.0) / 1000.0},
            "state_bytes": {"avg": if sizes.is_empty() { 0 } else { sizes.iter().map(|x| *x as u64).sum::<u64>() / sizes.len() as u64 },
                            "p99": pct(&mut sizes, 0.99), "max": pct(&mut sizes, 1.0)},
            "net": {"in_bytes": st.bytes_in.load(Relaxed), "out_bytes": st.bytes_out.load(Relaxed),
                    "frames_in": st.frames_in.load(Relaxed), "frames_out": st.frames_out.load(Relaxed)},
            "act_errors": st.act_errors.load(Relaxed), "errors": st.errors.load(Relaxed), "samples": *st.samples.lock().unwrap(),
            "admin": {"frames": st.admin_frames.load(Relaxed), "bytes": st.admin_bytes.load(Relaxed), "resyncs": st.admin_resyncs.load(Relaxed)},
            "server": server,
            "server_ms_per_act": if acts > 0 { cpu_s * 1000.0 / acts as f64 } else { 0.0 },
        })
    );
}

#[tokio::main]
async fn main() {
    let mut it = std::env::args().skip(1);
    let cmd = it.next().unwrap_or_default();
    let mut m = HashMap::new();
    while let Some(k) = it.next() {
        let k = k.trim_start_matches("--").to_string();
        m.insert(k, it.next().unwrap_or_default());
    }
    let a = Args(m);
    match cmd.as_str() {
        "setup" => setup(&a).await,
        "mkadmin" => mkadmin(&a).await,
        "idle" => idle(&a).await,
        "burst" => burst(&a).await,
        "play" => play(&a).await,
        _ => eprintln!("usage: loadgen setup|mkadmin|idle|burst|play [--options], see the top of examples/loadgen.rs"),
    }
}
