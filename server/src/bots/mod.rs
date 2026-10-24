//! The server's bots: accounts that play Classic on this server to give it life, managed on the
//! admin's Bots page (how many, how strong, which games, when). A bot is a client like any player —
//! it speaks the same protocol through an adapter (`transport`: in this process, or over the network)
//! and sees only its own player's view; how it thinks: `brain`.

pub mod arena;
pub mod brain;
pub mod cards;
pub mod runtime;
pub mod status;
pub mod transport;

use crate::db::{self, DbResult};
use crate::entity::bot;
use crate::AppRef;
use runtime::{Auth, ConnectFn, Ctx, LoadFn};
use sea_orm::{ActiveModelTrait, EntityTrait, Set};
use status::Statuses;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::Semaphore;
use transport::Transport;

pub const LEVELS: [&str; 3] = ["easy", "medium", "hard"];
pub const MODES: [&str; 4] = ["ladder", "ranked", "casual", "arena"];

/// A bot's settings (the `bots` row and its account's name).
#[derive(Clone, Debug)]
pub struct BotConfig {
    pub id: i64,
    pub account: i64,
    pub name: String,
    pub level: String,
    pub modes: String,
    pub enabled: bool,
    pub from_min: i64,
    pub to_min: i64,
    pub pause_min: i64,
    pub pause_max: i64,
}

/// The running bots of this process and what they are doing.
pub struct Manager {
    running: Mutex<HashMap<i64, tokio::task::AbortHandle>>,
    pub status: Statuses,
    /// bots thinking at once: one less than the CPUs (at least one); the players come first
    think: Arc<Semaphore>,
}

impl Default for Manager {
    fn default() -> Manager {
        let cpus = std::thread::available_parallelism().map_or(1, |n| n.get());
        Manager { running: Mutex::default(), status: Statuses::default(), think: Arc::new(Semaphore::new(cpus.saturating_sub(1).max(1))) }
    }
}

impl Manager {
    pub fn is_running(&self, id: i64) -> bool {
        self.running.lock().unwrap_or_else(|e| e.into_inner()).get(&id).is_some_and(|h| !h.is_finished())
    }
}

fn config_of(b: bot::Model, name: String) -> BotConfig {
    BotConfig {
        id: b.id,
        account: b.account,
        name,
        level: b.level,
        modes: b.modes,
        enabled: b.enabled,
        from_min: b.from_min,
        to_min: b.to_min,
        pause_min: b.pause_min,
        pause_max: b.pause_max,
    }
}

pub async fn config(app: &AppRef, id: i64) -> Option<BotConfig> {
    let b = bot::Entity::find_by_id(id).one(&app.db).await.ok()??;
    let name = db::name_of(&app.db, b.account).await.unwrap_or_default();
    Some(config_of(b, name))
}

pub async fn all(app: &AppRef) -> DbResult<Vec<BotConfig>> {
    let rows = bot::Entity::find().all(&app.db).await?;
    let mut out = vec![];
    for b in rows {
        let name = db::name_of(&app.db, b.account).await?;
        out.push(config_of(b, name));
    }
    out.sort_by_key(|b| b.id);
    Ok(out)
}

/// Runs the enabled bots and stops the others (after a change on the Bots page, and at start).
pub async fn sync(app: &AppRef) -> DbResult<()> {
    let bots = all(app).await?;
    let want: HashMap<i64, &BotConfig> = bots.iter().filter(|b| b.enabled).map(|b| (b.id, b)).collect();
    let mut start = vec![];
    {
        let mut running = app.bots.running.lock().unwrap_or_else(|e| e.into_inner());
        running.retain(|id, h| {
            let keep = want.contains_key(id) && !h.is_finished();
            if !keep {
                h.abort(); // (its connection closes: a game it was in is lost after the server's `away`)
            }
            keep
        });
        for (id, b) in &want {
            if !running.contains_key(id) {
                start.push((*b).clone());
            }
        }
    }
    for b in bots.iter().filter(|b| !b.enabled) {
        app.bots.status.update(b.id, |s| {
            s.online = false;
            s.game.clear();
            s.opponent.clear();
        });
        app.bots.status.set_state(b.id, "stopped");
    }
    for (k, b) in start.into_iter().enumerate() {
        let h = spawn(app, b, k as u64);
        app.bots.running.lock().unwrap_or_else(|e| e.into_inner()).insert(h.0, h.1);
    }
    Ok(())
}

/// A bot of this process: a session token of its own, the local adapter, its settings from the database.
fn spawn(app: &AppRef, b: BotConfig, k: u64) -> (i64, tokio::task::AbortHandle) {
    let (id, account, name) = (b.id, b.account, b.name.clone());
    let app2 = app.clone();
    let task = tokio::spawn(async move {
        // (several bots start a moment apart)
        tokio::time::sleep(std::time::Duration::from_millis(400 * k)).await;
        let app = app2;
        let token = match db::new_session(&app.db, account, "game", crate::auth::TOKEN_DAYS * 86400, "").await {
            Ok(t) => t,
            Err(e) => {
                app.bots.status.error(id, format!("no session: {e}"));
                return;
            }
        };
        let ctx = Ctx { id, name, status: app.bots.status.clone(), think: app.bots.think.clone(), app: Some(app.clone()) };
        let a1 = app.clone();
        let connect: ConnectFn = Arc::new(move || {
            let a = a1.clone();
            Box::pin(async move { Ok(Transport::local(&a)) })
        });
        let a2 = app.clone();
        let load: LoadFn = Arc::new(move || {
            let a = a2.clone();
            Box::pin(async move { config(&a, id).await })
        });
        runtime::run(ctx, connect, Auth::Token(token), load).await;
    });
    (id, task.abort_handle())
}

/// New bots: an account each ("Bot_<Level>_<n>", a password nobody knows) and its settings.
pub async fn create(app: &AppRef, count: usize, level: &str, modes: &str, window: (i64, i64), pause: (i64, i64)) -> DbResult<Vec<String>> {
    let mut made = vec![];
    let cap = |s: &str| s[..1].to_uppercase() + &s[1..];
    let mut n = 1;
    while made.len() < count && n < 10000 {
        let name = format!("Bot_{}_{n}", cap(level));
        n += 1;
        if db::id_by_name(&app.db, &name).await?.is_some() {
            continue;
        }
        let pw: String = {
            use rand::Rng;
            let mut r = rand::thread_rng();
            (0..40).map(|_| r.sample(rand::distributions::Alphanumeric) as char).collect()
        };
        let hash = tokio::task::spawn_blocking(move || crate::auth::hash_password(&pw)).await.unwrap_or_default();
        let Some(acc) = db::create_account(&app.db, &name, &hash, "user").await? else { continue };
        bot::ActiveModel {
            account: Set(acc),
            level: Set(level.into()),
            modes: Set(modes.into()),
            enabled: Set(true),
            from_min: Set(window.0),
            to_min: Set(window.1),
            pause_min: Set(pause.0),
            pause_max: Set(pause.1),
            created: Set(crate::ranked::now()),
            ..Default::default()
        }
        .insert(&app.db)
        .await?;
        made.push(name);
    }
    Ok(made)
}

/// Is this account one of the server's bots?
pub async fn is_bot(app: &AppRef, account_id: i64) -> bool {
    use sea_orm::{ColumnTrait, QueryFilter};
    bot::Entity::find().filter(bot::Column::Account.eq(account_id)).one(&app.db).await.ok().flatten().is_some()
}
