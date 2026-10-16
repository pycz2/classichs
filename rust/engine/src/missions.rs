//! Tutorial missions (a pack's missions/<n>.json, docs/packs/format.md §8):
//! the rules part only (decks, locked powers, the champion's safety net, the
//! guarded boss, turn-end blocks). Hints, boss lines and rewards are the client's.

use crate::ruleset::{self, Ruleset};
use crate::state::Game;
use serde_json::{json, Value};

#[derive(Debug, Clone, Default)]
pub struct Mission {
    pub id: usize,
    pub champion: String,
    pub boss: String,
    pub boss_power: String,
    pub locked: bool,
    pub unlosable: bool,
    pub guarded: bool,
    pub block_mana: bool,
    pub block_attack: bool,
    pub mana: i64,
    pub player_hand: Vec<String>,
    /// Top card first.
    pub player_deck: Vec<String>,
    pub boss_deck: Vec<String>,
}

impl Mission {
    pub fn from_json(v: &Value) -> Result<Mission, String> {
        let s = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let b = |x: &Value, k: &str| x.get(k) == Some(&json!(true));
        let l = |x: &Value, k: &str| -> Vec<String> {
            x.get(k).and_then(Value::as_array).map_or(vec![], |a| a.iter().filter_map(|c| c.as_str().map(String::from)).collect())
        };
        let id = v.get("id").and_then(Value::as_i64).filter(|&n| n >= 1).ok_or("no id")? as usize;
        let block = &v["end_turn_block"];
        let player = &v["player"];
        Ok(Mission {
            id,
            champion: s("champion"),
            boss: s("boss"),
            boss_power: s("boss_power"),
            locked: b(v, "powers_locked"),
            unlosable: b(v, "unlosable"),
            guarded: b(v, "boss_guarded"),
            block_mana: b(block, "while_can_play"),
            block_attack: b(block, "while_can_attack"),
            mana: player.get("mana").and_then(Value::as_i64).unwrap_or(1),
            player_hand: l(player, "hand"),
            player_deck: l(player, "deck"),
            boss_deck: l(v, "boss_deck"),
        })
    }
}

/// Mission n (1-based) of the built-in Classic pack.
pub fn get(n: usize) -> Option<&'static Mission> {
    ruleset::classic().mission(n)
}

/// The scenario of a mission: scripted hands and deck order, the player first, no mulligan.
pub fn scenario(m: &Mission) -> Value {
    let rev = |v: &[String]| v.iter().rev().cloned().collect::<Vec<_>>(); // Scenario: the last card is the top
    json!({"current": 0, "players": [
        {"hero": m.champion, "mana": m.mana, "max_mana": m.mana, "hand": m.player_hand, "deck": rev(&m.player_deck),
            "hero_power_locked": m.locked},
        {"hero": m.boss, "hero_power": m.boss_power, "hand": [], "deck": rev(&m.boss_deck), "hero_power_locked": m.locked},
    ]})
}

/// Tutorial.start: mission n of the built-in Classic pack.
pub fn start(n: usize) -> Result<Game, String> {
    start_in(ruleset::classic(), n)
}

/// The mission's game with the champion's safety net and the guarded boss.
pub fn start_in(rs: &'static Ruleset, n: usize) -> Result<Game, String> {
    let m = rs.mission(n).ok_or_else(|| format!("no mission {n}"))?;
    let mut g = crate::scenario::build_in(rs, &scenario(m))?;
    if m.unlosable {
        let h = g.hero(0);
        g.em(h).add_enchant(json!({"hooks": "ench:tutorial_guard"}));
    }
    if m.guarded {
        let (h, t) = (g.hero(1), rs.names.guarded);
        g.em(h).give_tag(t, false);
    }
    Ok(g)
}

/// Why player p can't end the turn yet: (reason key, the English text), ("", "") if they can.
/// The key is what a client translates (`while_can_play`, `while_can_attack`, as the mission's
/// `end_turn_block` fields); the English text is kept for old clients.
pub fn end_turn_block(m: &Mission, g: &Game, p: usize) -> (&'static str, &'static str) {
    if g.current != p || g.game_over {
        return ("", "");
    }
    let legal = g.legal_actions();
    let any = |ty: &str| legal.iter().any(|a| a["player"] == p && a["type"] == ty);
    if m.block_mana && any("play") {
        return ("while_can_play", "Not yet! You have more cards to play!");
    }
    if m.block_attack && any("attack") {
        return ("while_can_attack", "Not yet! You can still attack.");
    }
    ("", "")
}
