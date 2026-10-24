//! What every bot is doing, for the admin page: kept in memory, shared by the bots and the page.

use crate::cards::Library;
use classichs_engine::state::Game;
use classichs_engine::view;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

/// The local time of day (the zone's offset read once from `date +%z`).
fn clock() -> String {
    static OFFSET: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    let off = *OFFSET.get_or_init(|| {
        let z = std::process::Command::new("date").arg("+%z").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
        let (sign, hm) = if let Some(r) = z.strip_prefix('-') { (-1, r) } else { (1, z.trim_start_matches('+')) };
        let n: i64 = hm.parse().unwrap_or(0);
        sign * ((n / 100) * 3600 + (n % 100) * 60)
    });
    let s = (now() as i64 + off).rem_euclid(86400);
    format!("{:02}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
}

#[derive(Clone, Default)]
pub struct BotStatus {
    pub name: String,
    pub kind: String,
    pub state: String,
    pub since: u64,
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
    pub log: VecDeque<String>,
}

#[derive(Clone)]
pub struct Shared {
    pub bots: Arc<Mutex<Vec<BotStatus>>>,
    pub started: u64,
    pub server: String,
}

impl Shared {
    pub fn update(&self, i: usize, f: impl FnOnce(&mut BotStatus)) {
        if let Ok(mut b) = self.bots.lock() {
            if let Some(s) = b.get_mut(i) {
                f(s);
            }
        }
    }

    pub fn set_state(&self, i: usize, state: &str) {
        self.update(i, |b| {
            if b.state != state {
                b.state = state.to_string();
                b.since = now();
            }
        });
    }

    pub fn log(&self, i: usize, msg: impl AsRef<str>) {
        let line = format!("{} {}", clock(), msg.as_ref());
        self.update(i, |b| {
            tracing::info!("{}: {}", b.name, msg.as_ref());
            b.log.push_back(line);
            while b.log.len() > 300 {
                b.log.pop_front();
            }
        });
    }

    pub fn error(&self, i: usize, msg: impl AsRef<str>) {
        let m = msg.as_ref().to_string();
        self.update(i, |b| {
            b.errors += 1;
            b.last_error = format!("{} {}", clock(), m);
        });
        self.log(i, format!("ОШИБКА: {m}"));
    }

    pub fn json(&self) -> Value {
        let bots = self.bots.lock().map(|b| b.clone()).unwrap_or_default();
        json!({
            "server": self.server,
            "started": self.started,
            "now": now(),
            "bots": bots.iter().map(|b| json!({
                "name": b.name, "kind": b.kind, "state": b.state, "since": b.since, "online": b.online,
                "mode": b.mode, "deck": b.deck, "opponent": b.opponent, "game": b.game, "turn": b.turn,
                "my_turn": b.my_turn, "board": b.board, "decision": b.decision,
                "games": b.games, "wins": b.wins, "losses": b.losses, "draws": b.draws,
                "ranked": b.ranked, "casual": b.casual,
                "arena_runs": b.arena_runs, "arena_best": b.arena_best, "arena_now": b.arena_now,
                "rank": b.rank, "errors": b.errors, "last_error": b.last_error,
                "decisions": b.decisions, "think_ms_avg": if b.decisions > 0 { b.think_ms / b.decisions } else { 0 },
                "log": b.log.iter().rev().take(80).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
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
            for (t, label) in [(n.guard, "провокация"), (n.barrier, "щит"), (n.double_attack, "неистовство"), (n.stealth, "маскировка"), (n.frozen, "заморожен")] {
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
