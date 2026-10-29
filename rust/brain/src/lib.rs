//! How the bots of Classic HS think, from what their player sees (rust/brain/src/brain.rs), what they
//! know before a game (cards.rs) and how they draft an Arena deck (arena.rs). Used by the game server
//! and, through `think`, by the game itself (GDExtension, WASM) for its offline bot.

pub mod arena;
pub mod brain;
pub mod cards;
pub mod clock;

use serde_json::{json, Value};
use std::time::Duration;

/// The game's bot move as JSON: {view (the bot player's snapshot), seat, deck (its 30 card ids),
/// level ("easy" | "medium" | "hard"), budget_ms?, seed?} → {ok, action (null: nothing to do), label, ms}.
pub fn think(req: &Value) -> Value {
    let level = brain::Level::parse(req["level"].as_str().unwrap_or("medium")).unwrap_or(brain::Level::Medium);
    let budget = req["budget_ms"].as_u64().map(Duration::from_millis).unwrap_or(match level {
        brain::Level::Easy => Duration::ZERO,
        brain::Level::Medium => Duration::from_millis(300),
        brain::Level::Hard => Duration::from_millis(1000),
    });
    let my_deck: Vec<String> = req["deck"].as_array().map_or(vec![], |a| a.iter().filter_map(|c| c.as_str().map(String::from)).collect());
    let k = brain::Knowledge {
        lib: cards::Library::get(),
        seat: req["seat"].as_u64().unwrap_or(1) as usize,
        my_deck,
        arena: req["arena"] == true,
        seed: req["seed"].as_u64().unwrap_or(1),
    };
    match brain::decide(&req["view"], &k, level, budget) {
        Ok(Some(d)) => json!({"ok": true, "action": d.action, "label": d.label, "ms": d.ms as u64, "worlds": d.worlds}),
        Ok(None) => json!({"ok": true, "action": null}),
        Err(e) => json!({"ok": false, "error": e}),
    }
}
