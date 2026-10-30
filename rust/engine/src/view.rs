//! A playable Game rebuilt from a snapshot (`api::snapshot`), also from a player's
//! view: a client of an authoritative server finds its legal actions with it.
//! Cards it cannot see (the opponent's hand and Secrets, both decks) become a
//! filler card; RNG, history and start decks are not restored. Not for parity.

use crate::entity::{int, truthy, Entity, Id, Obj};
use crate::ruleset::{self, Ruleset};
use crate::scenario::ints;
use crate::state::{Game, Pending};
use serde_json::{Map, Value};
use std::sync::Arc;

/// A minion standing in for a hidden card: the pack's cheapest (collectible first) minion without
/// hooks or keywords (then the lowest id).
fn filler(rs: &Ruleset) -> &str {
    rs.cards
        .values()
        .filter(|c| c.kind == "MINION" && c.script.is_empty() && c.keywords.is_empty())
        .min_by_key(|c| (!c.collectible, c.cost, c.id.as_str()))
        .map_or("", |c| c.id.as_str())
}

fn zone(rs: &Ruleset, s: &str) -> &'static str {
    match s {
        "DECK" => "DECK",
        "HAND" => "HAND",
        "PLAY" => "PLAY",
        "GRAVEYARD" => "GRAVEYARD",
        _ if s == rs.names.trap => rs.names.trap,
        _ => "SETASIDE",
    }
}

fn ids(v: &Value) -> Vec<Id> {
    v.as_array().map_or(vec![], |a| a.iter().map(|x| int(Some(x))).collect())
}

/// A game of the built-in Classic ruleset from a snapshot.
pub fn from_snapshot(snap: &Value) -> Result<Game, String> {
    from_snapshot_in(ruleset::classic(), snap)
}

pub fn from_snapshot_in(rs: &'static Ruleset, snap: &Value) -> Result<Game, String> {
    let s = ints(snap);
    let filler = filler(rs);
    if filler.is_empty() {
        return Err("the pack has no minion to stand in for hidden cards".into());
    }
    let (Some(ents), Some(ps)) = (s["entities"].as_object(), s["players"].as_array()) else {
        return Err("not a snapshot".into());
    };
    if ps.len() != 2 {
        return Err("not a snapshot".into());
    }
    let mut g = Game::blank(rs, 0);
    let intern = |s: &str| rs.intern(s);
    let next_id = int(s.get("next_id")).max(1);
    let mut hidden: Vec<Id> = vec![];
    for id in 1..next_id {
        let Some(d) = ents.get(&id.to_string()) else {
            hidden.push(id);
            g.entities.push(Arc::new(Entity::new(id, rs.card(filler), 0)));
            continue;
        };
        let card = d["card"].as_str().filter(|c| rs.has(c)).unwrap_or(filler);
        let mut e = Entity::new(id, rs.card(card), int(d.get("ctrl")).clamp(0, 1) as usize);
        e.zone = zone(rs, d["zone"].as_str().unwrap_or(""));
        e.play_order = int(d.get("order"));
        if card != filler || d["card"] == filler {
            e.damage = int(d.get("dmg"));
            if let Some(t) = d["tags"].as_object() {
                e.tags = Obj::of(t, &intern);
            }
            e.enchantments = d["ench"].as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_object().map(|o| Obj::of(o, &intern))).collect());
            e.eot_tags = d["eot"].as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(intern)).collect());
            e.silenced = truthy(d.get("sil"));
        }
        g.entities.push(Arc::new(e));
    }
    for (i, p) in ps.iter().enumerate() {
        let mut pl = crate::player::Player::new(i);
        pl.hero = int(p.get("hero"));
        pl.hero_power = int(p.get("power"));
        pl.weapon = Some(int(p.get("weapon"))).filter(|&w| w > 0);
        pl.hand = ids(&p["hand"]);
        pl.deck = ids(&p["deck"]);
        pl.board = ids(&p["board"]);
        pl.secrets = ids(&p["secrets"]);
        pl.mana = int(p.get("mana"));
        pl.max_mana = int(p.get("max_mana"));
        pl.mana_lock_owed = int(p.get("ol_owed"));
        pl.mana_locked = int(p.get("ol_locked"));
        pl.fatigue = int(p.get("fatigue"));
        pl.cards_played_this_turn = int(p.get("played"));
        pl.minions_played_this_turn = int(p.get("minions_played"));
        pl.cost_mods = p["cost_mods"].as_array().map_or(vec![], |a| a.iter().filter_map(|x| x.as_object().map(|o| Obj::of(o, &intern))).collect());
        pl.mulliganed = truthy(p.get("mulliganed"));
        pl.mulligan_replace = ids(&p["mulligan_replace"]);
        // a view has no deck lists: its hidden ids stand in, so draws still draw
        let want = (int(p.get("deck_count")).max(0) as usize).saturating_sub(pl.deck.len());
        for _ in 0..want.min(hidden.len()) {
            let id = hidden.remove(0);
            let e = g.em(id);
            e.controller = i;
            e.zone = "DECK";
            pl.deck.push(id);
        }
        for &id in pl.hand.iter().chain(&pl.deck).chain(&pl.board).chain(&pl.secrets).chain([pl.hero, pl.hero_power].iter()) {
            if id < 1 || id >= next_id {
                return Err(format!("bad entity id {id}"));
            }
        }
        g.players.push(pl);
    }
    g.turn = int(s.get("turn"));
    g.current = int(s.get("current")).clamp(0, 1) as usize;
    g.phase = match s["phase"].as_str() {
        Some("MULLIGAN") => "MULLIGAN",
        Some("OVER") => "OVER",
        _ => "PLAY",
    };
    g.game_over = truthy(s.get("game_over"));
    g.winner = s.get("winner").map_or(-1, |w| int(Some(w)));
    g.next_id = next_id;
    g.next_order = int(s.get("next_order")).max(1);
    if let Some(p) = s["pending"].as_object().filter(|p| !p.is_empty()) {
        let options = ids(&p["options"]);
        let none = Map::new();
        let zones = p.get("zones").and_then(Value::as_object).unwrap_or(&none);
        g.pending = Some(Pending {
            player: int(p.get("player")).clamp(0, 1) as usize,
            source: int(p.get("source")),
            zones: options.iter().map(|o| zone(rs, zones.get(&o.to_string()).and_then(Value::as_str).unwrap_or(""))).collect(),
            options,
        });
    }
    g.update_auras();
    Ok(g)
}

#[cfg(test)]
mod tests {
    /// Classic keeps its stand-in: the vanilla Wisp.
    #[test]
    fn classic_filler_is_the_wisp() {
        assert_eq!(super::filler(crate::ruleset::classic()), "VAN_CS2_231");
    }
}
