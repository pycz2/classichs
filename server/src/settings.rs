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
pub struct Cache(Mutex<HashMap<String, String>>);

impl Cache {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, String>> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }
}

pub async fn get(app: &App, key: &str) -> DbResult<String> {
    if let Some(v) = app.settings.lock().get(key) {
        return Ok(v.clone());
    }
    let v = server_setting::Entity::find_by_id(key).one(&app.db).await?.map_or_else(|| default(key).to_string(), |r| r.value);
    app.settings.lock().insert(key.to_string(), v.clone());
    Ok(v)
}

/// Saves a setting (the caller checked the value) and applies it.
pub async fn set(app: &App, key: &str, value: &str) -> DbResult<()> {
    let row = server_setting::ActiveModel { key: Set(key.to_string()), value: Set(value.to_string()) };
    server_setting::Entity::insert(row)
        .on_conflict(OnConflict::column(server_setting::Column::Key).update_column(server_setting::Column::Value).to_owned())
        .exec_without_returning(&app.db)
        .await?;
    app.settings.lock().insert(key.to_string(), value.to_string());
    apply(key, value);
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
    apply(AUTOBOT_WAIT_MS, &get(app, AUTOBOT_WAIT_MS).await?);
    Ok(())
}

pub async fn autobot_wait_ms(app: &App) -> DbResult<u64> {
    Ok(get(app, AUTOBOT_WAIT_MS).await?.parse().unwrap_or(30_000))
}

pub async fn invite_only(app: &App) -> DbResult<bool> {
    Ok(get(app, INVITE_ONLY).await? == "1")
}
