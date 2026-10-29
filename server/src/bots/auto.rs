//! Auto-bots: a player waits in a queue (ranked, casual, Arena) of the Classic pack for WAIT_MS and
//! nobody comes: a bot of a fitting level joins that queue for this player (the matchmaking pairs
//! them whatever the window), plays the one game at once (no human-pace pauses) and goes. The
//! accounts are a pool: "AutoBot_<Level>_<n>" (POOL per level) and "AutoBot_Arena_<n>" (POOL; the
//! level per game), made when first needed. All busy: the player waits on.
//! The level: ranked and casual by the player's hidden MMR, the Arena by the run's wins.

use crate::bots::brain::Level;
use crate::bots::runtime::{self, Auth, Ctx};
use crate::bots::transport::Transport;
use crate::db;
use crate::events::Event;
use crate::ranked::Mode;
use crate::AppRef;
use sea_orm::EntityTrait;
use serde_json::json;
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// How long a player waits before an auto-bot comes (ms; tests make it short).
pub static WAIT_MS: AtomicU64 = AtomicU64::new(30_000);
/// Accounts per level (and for the Arena).
pub const POOL: usize = 3;
/// The pack the bots know.
pub const CLASSIC: &str = "classic-2014";

/// The auto-bot accounts playing now.
#[derive(Default)]
pub struct Auto {
    busy: Mutex<HashSet<i64>>,
}

/// The level for a player's hidden MMR (ranked, casual).
pub fn level_for_mmr(mmr: f64) -> Level {
    if mmr < 1350.0 {
        Level::Easy
    } else if mmr <= 1650.0 {
        Level::Medium
    } else {
        Level::Hard
    }
}

/// The level for an Arena run's wins.
pub fn level_for_wins(wins: i64) -> Level {
    match wins {
        ..=2 => Level::Easy,
        3..=5 => Level::Medium,
        _ => Level::Hard,
    }
}

/// An account of no player: the admin's bots and the auto-bots.
pub fn is_bot_name(name: &str) -> bool {
    name.starts_with("Bot_") || name.starts_with("AutoBot_")
}

/// Who waits for an auto-bot now (the matchmaking tick calls it every second).
pub async fn tick(app: &AppRef) {
    let want: Vec<(i64, Mode, f64, String)> = {
        let hub = app.hub();
        let now = std::time::Instant::now();
        let taken: HashSet<i64> = hub.auto_for.values().copied().collect();
        hub.queue
            .iter()
            .filter(|(id, s)| {
                now.duration_since(s.since) >= Duration::from_millis(WAIT_MS.load(Ordering::Relaxed))
                    && s.mode != Mode::Friendly
                    && s.rules.id == CLASSIC
                    && !taken.contains(id)
                    && !is_bot_name(&s.name)
            })
            .map(|(id, s)| (*id, s.mode, s.key.mmr, s.rules.rules_hash.clone()))
            .collect()
    };
    for (player, mode, mmr, pack) in want {
        let level = if mode == Mode::Arena {
            let wins = crate::entity::arena::Entity::find_by_id(player).one(&app.db).await.ok().flatten().map_or(0, |r| r.wins);
            level_for_wins(wins)
        } else {
            level_for_mmr(mmr)
        };
        let Some((account, name)) = take(app, mode, level).await else { continue };
        app.hub().auto_for.insert(account, player);
        let player_name = db::name_of(&app.db, player).await.unwrap_or_default();
        app.event(
            Event::new("auto_bot", format!("{name} ({}) joins the {} queue for {player_name}", level.name(), mode.as_str()))
                .other(&name)
                .data(json!({"bot": name, "level": level.name(), "mode": mode, "for": player_name})),
        );
        let app2 = app.clone();
        tokio::spawn(async move {
            let r = play_once(&app2, account, &name, mode, pack, level).await;
            if let Err(e) = r {
                app2.event(Event::new("auto_bot", format!("{name}: {e}")).other(&name).data(json!({"bot": name, "error": e})));
            }
            app2.hub().auto_for.remove(&account);
            app2.bots.auto.busy.lock().unwrap_or_else(|e| e.into_inner()).remove(&account);
        });
    }
}

/// A free account of the pool for this mode and level (made when missing), marked busy.
async fn take(app: &AppRef, mode: Mode, level: Level) -> Option<(i64, String)> {
    let kind = if mode == Mode::Arena { "Arena".to_string() } else { cap(level.name()) };
    for n in 1..=POOL {
        let name = format!("AutoBot_{kind}_{n}");
        let id = match db::id_by_name(&app.db, &name).await.ok()? {
            Some(id) => id,
            None => make(app, &name).await?,
        };
        if app.hub().conns.contains_key(&id) {
            continue; // (still online after its last game)
        }
        if app.bots.auto.busy.lock().unwrap_or_else(|e| e.into_inner()).insert(id) {
            return Some((id, name));
        }
    }
    None
}

fn cap(s: &str) -> String {
    s[..1].to_uppercase() + &s[1..]
}

/// A new pool account (a password nobody knows).
async fn make(app: &AppRef, name: &str) -> Option<i64> {
    let pw: String = {
        use rand::Rng;
        let mut r = rand::thread_rng();
        (0..40).map(|_| r.sample(rand::distributions::Alphanumeric) as char).collect()
    };
    let hash = tokio::task::spawn_blocking(move || crate::auth::hash_password(&pw)).await.ok()?;
    db::create_account(&app.db, name, &hash, "user").await.ok()?
}

/// The one game: log in through this process, queue (Arena: a fresh draft), play, go.
async fn play_once(app: &AppRef, account: i64, name: &str, mode: Mode, pack: String, level: Level) -> Result<(), String> {
    let token = db::new_session(&app.db, account, "game", 3600, "").await.map_err(|e| e.to_string())?;
    let ctx = Ctx { id: -account, name: name.to_string(), status: app.bots.status.clone(), think: app.bots.think.clone(), app: Some(app.clone()), pace: false };
    let app2 = app.clone();
    let connect: runtime::ConnectFn = Arc::new(move || {
        let a = app2.clone();
        Box::pin(async move { Ok(Transport::local(&a)) })
    });
    runtime::one_game(&ctx, &connect, &Auth::Token(token), mode.as_str(), Some(pack), level).await
}
