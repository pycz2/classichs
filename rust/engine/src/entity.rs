//! One card in the match (engine/entity.gd).

use crate::card_db::Card;
use serde_json::{json, Map, Value};

pub type Id = i64;
/// "No entity" (GDScript null; actions use -1 for "no target").
pub const NONE: Id = -1;

/// GDScript truthiness of a Variant.
pub fn truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0) != 0.0,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
    }
}

/// GDScript int(v) with a default for a missing key.
pub fn int(v: Option<&Value>) -> i64 {
    match v {
        Some(Value::Number(n)) => n.as_i64().unwrap_or_else(|| n.as_f64().unwrap_or(0.0) as i64),
        Some(Value::Bool(b)) => *b as i64,
        _ => 0,
    }
}

/// Aura contributions, recomputed by update_auras (not part of the state hash).
#[derive(Clone, Debug, Default)]
pub struct Aura {
    pub atk: i64,
    pub hp: i64,
    pub tags: Map<String, Value>,
    /// card id -> [atk, hp] it adds (display only).
    pub src: Map<String, Value>,
}

#[derive(Clone, Debug)]
pub struct Entity {
    pub id: Id,
    pub card_id: &'static str,
    pub card: &'static Card,
    pub controller: usize,
    pub zone: &'static str,
    pub play_order: i64,
    pub damage: i64,
    pub tags: Map<String, Value>,
    pub enchantments: Vec<Map<String, Value>>,
    pub eot_tags: Vec<String>,
    pub aura: Aura,
    pub silenced: bool,
}

impl Entity {
    /// A new entity of a card: the card's start tags (its keywords, spell power,
    /// a weapon's durability, a champion's armor), out of play.
    pub fn new(id: Id, card: &'static Card, controller: usize) -> Entity {
        Entity { id, card_id: &card.id, card, controller, zone: "SETASIDE", play_order: 0, damage: 0,
            tags: card.start_tags.clone(), enchantments: vec![], eot_tags: vec![], aura: Aura::default(), silenced: false }
    }

    pub fn kind(&self) -> &'static str {
        self.card.kind.as_str()
    }
    pub fn is_minion(&self) -> bool {
        self.kind() == "MINION"
    }
    pub fn is_champion(&self) -> bool {
        self.kind() == "CHAMPION"
    }
    pub fn is_weapon(&self) -> bool {
        self.kind() == "WEAPON"
    }
    pub fn race(&self) -> &'static str {
        self.card.race.as_str()
    }

    pub fn atk(&self) -> i64 {
        let mut v = self.card.attack;
        for e in &self.enchantments {
            if e.contains_key("set_atk") {
                v = int(e.get("set_atk"));
            }
            v += int(e.get("atk"));
        }
        (v + self.aura.atk).max(0)
    }

    pub fn max_health(&self) -> i64 {
        let mut v = self.card.health;
        for e in &self.enchantments {
            if e.contains_key("set_hp") {
                v = int(e.get("set_hp"));
            }
            v += int(e.get("hp"));
        }
        v + self.aura.hp
    }

    pub fn health(&self) -> i64 {
        self.max_health() - self.damage
    }

    pub fn has(&self, tag: &str) -> bool {
        truthy(self.tags.get(tag)) || truthy(self.aura.tags.get(tag))
    }

    /// int(tags.get(tag, 0)).
    pub fn tag(&self, tag: &str) -> i64 {
        int(self.tags.get(tag))
    }

    pub fn set_tag(&mut self, tag: &str, v: Value) {
        self.tags.insert(tag.to_string(), v);
    }

    pub fn erase_tag(&mut self, tag: &str) {
        self.tags.remove(tag);
    }

    /// Its spell power (`name`: the SPELL_POWER tag name).
    pub fn spell_power(&self, name: &str) -> i64 {
        self.tag(name) + int(self.aura.tags.get(name))
    }

    pub fn give_tag(&mut self, tag: &str, eot: bool) {
        self.tags.insert(tag.to_string(), Value::Bool(true));
        if eot && !self.eot_tags.iter().any(|t| t == tag) {
            self.eot_tags.push(tag.to_string());
        }
    }

    pub fn add_enchant(&mut self, ench: Value) {
        match ench {
            Value::Object(m) => self.enchantments.push(m),
            _ => panic!("enchantment must be an object"),
        }
    }

    /// The enchantments with these hooks (their "player" fields).
    pub fn ench_players(&self, hooks: &str) -> Vec<usize> {
        self.enchantments
            .iter()
            .filter(|e| e.get("hooks").and_then(Value::as_str) == Some(hooks))
            .map(|e| int(e.get("player")) as usize)
            .collect()
    }

    /// Removes "this turn" enchantments and tags. A lost Health bonus never kills.
    pub fn remove_eot(&mut self) {
        let (old_max, old_hp) = (self.max_health(), self.health());
        self.enchantments.retain(|e| !truthy(e.get("eot")));
        for t in std::mem::take(&mut self.eot_tags) {
            self.tags.remove(&t);
        }
        self.fix_health(old_max, old_hp);
    }

    /// Silence: no enchantments, no "this turn" tags, none of `tags` (the ruleset's silenced tags).
    pub fn silence(&mut self, tags: &[&str]) {
        let (old_max, old_hp) = (self.max_health(), self.health());
        self.enchantments.clear();
        self.eot_tags.clear();
        for k in tags {
            self.tags.remove(*k);
        }
        self.silenced = true;
        self.fix_health(old_max, old_hp);
    }

    /// When max Health drops, current Health becomes min(old current, new max).
    pub fn fix_health(&mut self, old_max: i64, old_health: i64) {
        let new_max = self.max_health();
        if new_max < old_max {
            self.damage = 0.max(new_max - old_health.min(new_max));
        }
    }

    pub fn snapshot(&self) -> Value {
        json!({"card": self.card_id, "ctrl": self.controller, "zone": self.zone, "order": self.play_order,
            "dmg": self.damage, "tags": self.tags, "ench": self.enchantments, "eot": self.eot_tags,
            "sil": self.silenced})
    }
}
