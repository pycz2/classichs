//! One side of the match (engine/player.gd). Entities are referenced by id.

use crate::entity::{Id, Obj, NONE};
use serde_json::{json, Value};

#[derive(Clone, Debug, Default)]
pub struct Player {
    pub index: usize,
    pub hero: Id,
    pub hero_power: Id,
    pub weapon: Option<Id>,
    pub hand: Vec<Id>,
    /// The last element is the top card.
    pub deck: Vec<Id>,
    pub board: Vec<Id>,
    /// TRAP cards in play (the protocol's `secrets`, like `hero` and `hero_power`).
    pub secrets: Vec<Id>,
    pub mana: i64,
    pub max_mana: i64,
    /// MANA_LOCK for the next turn / locked this turn.
    pub mana_lock_owed: i64,
    pub mana_locked: i64,
    pub fatigue: i64,
    pub cards_played_this_turn: i64,
    pub minions_played_this_turn: i64,
    /// One-shot or timed cost changes: {"kind": "spell"|"secret"|"minion"|"any",
    /// "set": int or "delta": int, "until": "use"|"turn_end", "turn": int}
    pub cost_mods: Vec<Obj>,
    pub mulliganed: bool,
    pub mulligan_replace: Vec<Id>,
}

impl Player {
    pub fn new(index: usize) -> Player {
        Player { index, ..Default::default() }
    }

    pub fn snapshot(&self) -> Value {
        json!({"hero": self.hero, "power": self.hero_power, "weapon": self.weapon.unwrap_or(NONE),
            "hand": self.hand, "deck": self.deck, "board": self.board, "secrets": self.secrets,
            "mana": self.mana, "max_mana": self.max_mana, "ol_owed": self.mana_lock_owed,
            "ol_locked": self.mana_locked, "fatigue": self.fatigue, "played": self.cards_played_this_turn,
            "minions_played": self.minions_played_this_turn, "cost_mods": self.cost_mods.iter().map(Obj::to_value).collect::<Vec<_>>(),
            "mulliganed": self.mulliganed, "mulligan_replace": self.mulligan_replace})
    }
}
