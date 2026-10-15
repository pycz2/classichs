//! The event log: `app.event(…)` never waits; a writer task saves events in batches and
//! then pushes them to the admin panels (the admin WebSocket) with their ids.

use crate::db::Db;
use crate::entity::event;
use sea_orm::{EntityTrait, Set};
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc};

/// Events older than this are deleted (checked hourly).
pub const KEEP_DAYS: i64 = 90;

pub fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// An event to log: `Event::new("login", "alice logged in").user(id, "alice")`.
#[derive(Clone, Debug, Default)]
pub struct Event {
    pub kind: &'static str,
    pub account: Option<i64>,
    pub user: Option<String>,
    pub other: Option<String>,
    pub game: Option<String>,
    pub text: String,
    pub data: Option<Value>,
}

impl Event {
    pub fn new(kind: &'static str, text: impl Into<String>) -> Event {
        Event { kind, text: text.into(), ..Default::default() }
    }

    pub fn user(mut self, id: i64, name: &str) -> Event {
        self.account = Some(id);
        self.user = Some(name.into());
        self
    }

    pub fn other(mut self, name: &str) -> Event {
        self.other = Some(name.into());
        self
    }

    pub fn game(mut self, id: &str) -> Event {
        self.game = Some(id.into());
        self
    }

    pub fn data(mut self, v: Value) -> Event {
        self.data = Some(v);
        self
    }
}

pub fn event_json(e: &event::Model) -> Value {
    json!({"id": e.id, "at": e.at, "kind": e.kind, "account": e.account, "user": e.user, "other": e.other,
           "game": e.game, "text": e.text,
           "data": e.data.as_deref().and_then(|d| serde_json::from_str::<Value>(d).ok())})
}

/// The log's two ends: `tx` takes events, `feed` carries saved ones (and live snapshots)
/// to the admin panels as ready JSON text.
pub struct Log {
    tx: mpsc::UnboundedSender<(i64, Event)>,
    pub feed: broadcast::Sender<Arc<str>>,
}

impl Log {
    pub fn start(db: Db) -> Log {
        let (tx, rx) = mpsc::unbounded_channel();
        let (feed, _) = broadcast::channel(4096);
        tokio::spawn(writer(db, rx, feed.clone()));
        Log { tx, feed }
    }

    pub fn add(&self, e: Event) {
        let _ = self.tx.send((now_ms(), e));
    }

    pub fn push(&self, v: &Value) {
        let _ = self.feed.send(v.to_string().into());
    }
}

async fn writer(db: Db, mut rx: mpsc::UnboundedReceiver<(i64, Event)>, feed: broadcast::Sender<Arc<str>>) {
    while let Some(first) = rx.recv().await {
        let mut batch = vec![first];
        while batch.len() < 500 {
            match rx.try_recv() {
                Ok(e) => batch.push(e),
                Err(_) => break,
            }
        }
        let rows: Vec<event::ActiveModel> = batch
            .into_iter()
            .map(|(at, e)| event::ActiveModel {
                at: Set(at),
                kind: Set(e.kind.into()),
                account: Set(e.account),
                user: Set(e.user),
                other: Set(e.other),
                game: Set(e.game),
                text: Set(e.text),
                data: Set(e.data.map(|d| d.to_string())),
                ..Default::default()
            })
            .collect();
        match event::Entity::insert_many(rows).exec_with_returning(&db).await {
            Ok(saved) => {
                for e in &saved {
                    let _ = feed.send(json!({"t": "event", "e": event_json(e)}).to_string().into());
                }
            }
            Err(e) => tracing::error!("event log: {e}"),
        }
    }
}
