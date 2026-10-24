//! What every bot is doing now, for the admin's Bots page: kept in memory (the last 300 log lines a
//! bot); errors also go to the server's event log.

use crate::bots::cards::Library;
use classichs_engine::state::Game;
use classichs_engine::view;
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};

pub fn now() -> i64 {
    crate::ranked::now()
}

#[derive(Clone, Default)]
pub struct BotStatus {
    pub state: String,
    pub since: i64,
    pub online: bool,
    pub mode: String,
    pub deck: String,
    pub opponent: String,
    pub game: String,
    pub turn: i64,
    pub my_turn: bool,
    pub board: Value,
    pub decision: Value,
    pub games: u64,
    pub wins: u64,
    pub losses: u64,
    pub draws: u64,
    pub ranked: u64,
    pub casual: u64,
    pub arena_runs: u64,
    pub arena_best: i64,
    pub arena_now: Value,
    pub rank: Value,
    pub errors: u64,
    pub last_error: String,
    pub decisions: u64,
    pub think_ms: u64,
    /// (unix seconds, text), oldest first
    pub log: VecDeque<(i64, String)>,
}

#[derive(Clone, Default)]
pub struct Statuses(Arc<Mutex<HashMap<i64, BotStatus>>>);

impl Statuses {
    pub fn update(&self, id: i64, f: impl FnOnce(&mut BotStatus)) {
        let mut all = self.0.lock().unwrap_or_else(|e| e.into_inner());
        f(all.entry(id).or_default());
    }

    pub fn get(&self, id: i64) -> Option<BotStatus> {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).get(&id).cloned()
    }

    pub fn remove(&self, id: i64) {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).remove(&id);
    }

    pub fn set_state(&self, id: i64, state: &str) {
        self.update(id, |b| {
            if b.state != state {
                b.state = state.to_string();
                b.since = now();
            }
        });
    }

    pub fn log(&self, id: i64, msg: impl AsRef<str>) {
        self.update(id, |b| {
            b.log.push_back((now(), msg.as_ref().to_string()));
            while b.log.len() > 300 {
                b.log.pop_front();
            }
        });
    }

    pub fn error(&self, id: i64, msg: impl AsRef<str>) {
        let m = msg.as_ref().to_string();
        self.update(id, |b| {
            b.errors += 1;
            b.last_error = m.clone();
        });
        self.log(id, format!("ERROR: {m}"));
    }
}

impl BotStatus {
    /// For the admin page; `log` = how many of the newest log lines.
    pub fn json(&self, log: usize) -> Value {
        json!({
            "state": self.state, "since": self.since, "online": self.online,
            "mode": self.mode, "deck": self.deck, "opponent": self.opponent, "game": self.game, "turn": self.turn,
            "my_turn": self.my_turn, "board": self.board, "decision": self.decision,
            "games": self.games, "wins": self.wins, "losses": self.losses, "draws": self.draws,
            "ranked": self.ranked, "casual": self.casual,
            "arena_runs": self.arena_runs, "arena_best": self.arena_best, "arena_now": self.arena_now,
            "rank": self.rank, "errors": self.errors, "last_error": self.last_error,
            "decisions": self.decisions, "think_ms_avg": if self.decisions > 0 { self.think_ms / self.decisions } else { 0 },
            "log": self.log.iter().rev().take(log).map(|(t, s)| json!({"at": t, "text": s})).collect::<Vec<_>>(),
        })
    }
}

/// The table as this bot sees it: its own cards in full, the opponent's hidden ones as counts.
pub fn board(lib: &Library, v: &Value, seat: usize) -> Value {
    let Ok(g) = view::from_snapshot_in(lib.rs, v) else { return Value::Null };
    let side = |g: &Game, p: usize| {
        let n = g.n();
        let pl = &g.players[p];
        let hero = g.e(pl.hero);
        let minion = |&id: &i64| {
            let e = g.e(id);
            let mut tags = vec![];
            for (t, label) in [(n.guard, "taunt"), (n.barrier, "shield"), (n.double_attack, "windfury"), (n.stealth, "stealth"), (n.frozen, "frozen")] {
                if e.has(t) {
                    tags.push(label);
                }
            }
            json!({"name": lib.name(&e.card_id), "atk": e.atk(), "hp": e.health(), "tags": tags})
        };
        let own = p == seat;
        json!({
            "hero": lib.name(&hero.card_id), "hp": hero.health(), "armor": hero.tag(n.armor),
            "mana": pl.mana, "max_mana": pl.max_mana,
            "weapon": pl.weapon.map(|w| { let w = g.e(w); json!({"name": lib.name(&w.card_id), "atk": w.atk(), "dur": w.tag(n.durability)}) }),
            "board": pl.board.iter().map(minion).collect::<Vec<_>>(),
            "hand": if own { json!(pl.hand.iter().map(|&h| json!({"name": lib.name(&g.e(h).card_id), "cost": g.cost(h)})).collect::<Vec<_>>()) } else { json!(pl.hand.len()) },
            "secrets": pl.secrets.len(), "deck": v["players"][p]["deck_count"].as_i64().unwrap_or(pl.deck.len() as i64),
        })
    };
    json!({"me": side(&g, seat), "opp": side(&g, 1 - seat), "turn": g.turn, "current": g.current == seat})
}
