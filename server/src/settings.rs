//! The server's settings (the admin panel's Settings page): `server_settings` rows (key → text),
//! cached; a missing row is its default. A change takes effect at once.

use crate::db::DbResult;
use crate::entity::server_setting;
use crate::App;
use sea_orm::sea_query::OnConflict;
use sea_orm::{EntityTrait, Set};
use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::Mutex;

/// How long a player waits in a queue before an auto-bot comes (ms, 0..=600000).
pub const AUTOBOT_WAIT_MS: &str = "autobot_wait_ms";
/// "1": registering needs an invite key; "0": anyone registers.
pub const INVITE_ONLY: &str = "signup_invite_only";

fn default(key: &str) -> &'static str {
    match key {
        AUTOBOT_WAIT_MS => "30000",
        _ => "0",
    }
}

/// The values read or set so far.
#[derive(Default)]
pub struct Cache(Mutex<HashMap<(i64, String), String>>);

impl Cache {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<(i64, String), String>> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// A setting of a sub-server.
pub async fn get(app: &App, sub: i64, key: &str) -> DbResult<String> {
    if let Some(v) = app.settings.lock().get(&(sub, key.to_string())) {
        return Ok(v.clone());
    }
    let v = server_setting::Entity::find_by_id((sub, key.to_string())).one(&app.db).await?.map_or_else(|| default(key).to_string(), |r| r.value);
    app.settings.lock().insert((sub, key.to_string()), v.clone());
    Ok(v)
}

/// Saves a setting (the caller checked the value) and applies it.
pub async fn set(app: &App, sub: i64, key: &str, value: &str) -> DbResult<()> {
    let row = server_setting::ActiveModel { subserver: Set(sub), key: Set(key.to_string()), value: Set(value.to_string()) };
    server_setting::Entity::insert(row)
        .on_conflict(OnConflict::columns([server_setting::Column::Subserver, server_setting::Column::Key]).update_column(server_setting::Column::Value).to_owned())
        .exec_without_returning(&app.db)
        .await?;
    app.settings.lock().insert((sub, key.to_string()), value.to_string());
    if sub == 0 {
        apply(key, value);
    }
    Ok(())
}

fn apply(key: &str, value: &str) {
    if key == AUTOBOT_WAIT_MS {
        if let Ok(ms) = value.parse() {
            crate::bots::auto::WAIT_MS.store(ms, Ordering::Relaxed);
        }
    }
}

/// At start: the settings that live outside the cache (the auto-bots' wait).
pub async fn load(app: &App) -> DbResult<()> {
    apply(AUTOBOT_WAIT_MS, &get(app, 0, AUTOBOT_WAIT_MS).await?);
    Ok(())
}

pub async fn autobot_wait_ms(app: &App, sub: i64) -> DbResult<u64> {
    Ok(get(app, sub, AUTOBOT_WAIT_MS).await?.parse().unwrap_or(30_000))
}

pub async fn invite_only(app: &App, sub: i64) -> DbResult<bool> {
    Ok(get(app, sub, INVITE_ONLY).await? == "1")
}
