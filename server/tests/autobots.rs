//! Auto-bots: a player who waits alone gets a bot of a fitting level for one game.

use classichs_server::bots::auto::{self, level_for_mmr, level_for_wins};
use classichs_server::bots::brain::Level;
use classichs_server::storage::Storage;
use classichs_server::{db, router, spawn_background, App, AppRef};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn server() -> (SocketAddr, AppRef) {
    auto::WAIT_MS.store(1000, Ordering::Relaxed);
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-auto-{}", rand::random::<u64>()))).unwrap();
    let app = App::new(db::open(":memory:").await.unwrap(), false, None, store);
    spawn_background(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    (addr, app)
}

struct C(Ws);

impl C {
    async fn register(addr: SocketAddr, name: &str) -> C {
        let (ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
        let mut c = C(ws);
        c.send(json!({"t": "register", "user": name, "password": "password123"})).await;
        c.want("auth", 10).await;
        c
    }

    async fn send(&mut self, v: Value) {
        self.0.send(Message::text(v.to_string())).await.unwrap();
    }

    async fn want(&mut self, t: &str, secs: u64) -> Value {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(secs);
        loop {
            let m = tokio::time::timeout_at(deadline, self.0.next()).await.unwrap_or_else(|_| panic!("timed out waiting for {t}")).unwrap().unwrap();
            if let Message::Text(s) = m {
                let v: Value = serde_json::from_str(s.as_str()).unwrap();
                if v["t"] == t {
                    return v;
                }
                assert!(v["t"] != "error", "unexpected error while waiting for {t}: {v}");
            }
        }
    }
}

fn deck(class: &str) -> Value {
    json!({"name": "Test", "hero": classichs_engine::deck::hero(class).unwrap(), "cards": classichs_engine::deck::basic(class)})
}

#[test]
fn the_level_follows_the_player() {
    assert_eq!(level_for_mmr(1200.0), Level::Easy);
    assert_eq!(level_for_mmr(1500.0), Level::Medium, "a new player");
    assert_eq!(level_for_mmr(1800.0), Level::Hard);
    assert_eq!(level_for_wins(0), Level::Easy);
    assert_eq!(level_for_wins(4), Level::Medium);
    assert_eq!(level_for_wins(9), Level::Hard);
}

/// Alone in the casual queue: an auto-bot of the player's level comes, plays the game and goes.
#[tokio::test]
async fn a_lonely_player_gets_an_auto_bot() {
    let (addr, app) = server().await;
    let mut c = C::register(addr, "lonely").await;
    c.send(json!({"t": "queue", "mode": "casual", "deck": deck("MAGE")})).await;
    c.want("queued", 10).await;
    let m = c.want("match", 30).await;
    assert_eq!(m["opponent"]["user"], "AutoBot_Medium_1", "{m}");
    let game = m["game"].as_str().unwrap().to_string();
    // the bot plays at once (no human-pace pauses): its mulligan comes while we think
    c.send(json!({"t": "act", "game": game, "action": {"type": "concede", "player": m["you"]}})).await;
    let over = c.want("game_over", 30).await;
    assert_eq!(over["result"], "loss");
    // it goes: offline and free again
    for _ in 0..50 {
        if app.hub().auto_for.is_empty() && !app.hub().conns.keys().any(|&id| id != 1) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(app.hub().auto_for.is_empty(), "the auto-bot is free");
    assert_eq!(app.hub().conns.len(), 1, "the auto-bot logged out");
}

/// Two players find each other first: no auto-bot.
#[tokio::test]
async fn players_pair_with_players_first() {
    let (addr, _app) = server().await;
    let mut a = C::register(addr, "ann").await;
    let mut b = C::register(addr, "bob").await;
    a.send(json!({"t": "queue", "mode": "casual", "deck": deck("MAGE")})).await;
    b.send(json!({"t": "queue", "mode": "casual", "deck": deck("WARRIOR")})).await;
    assert_eq!(a.want("match", 10).await["opponent"]["user"], "bob");
}

/// The Arena: the auto-bot drafts a fresh deck for the game.
#[tokio::test]
async fn an_arena_player_gets_an_auto_bot_with_a_fresh_draft() {
    let (addr, _app) = server().await;
    let mut c = C::register(addr, "drafter").await;
    c.send(json!({"t": "arena_start"})).await;
    c.want("arena", 10).await;
    c.send(json!({"t": "arena_hero", "i": 0})).await;
    c.want("arena", 10).await;
    for _ in 0..30 {
        c.send(json!({"t": "arena_pick", "i": 0})).await;
        c.want("arena", 10).await;
    }
    c.send(json!({"t": "arena_queue"})).await;
    c.want("queued", 10).await;
    let m = c.want("match", 40).await;
    assert_eq!(m["opponent"]["user"], "AutoBot_Arena_1", "{m}");
    assert_eq!(m["mode"], "arena");
}
