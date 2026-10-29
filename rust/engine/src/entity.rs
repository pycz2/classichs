//! One card in the match (engine/entity.gd).

use crate::card_db::Card;
use serde_json::{json, Map, Value};
use std::borrow::Cow;

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

/// A string of the engine's data: a mechanic name, card id or field name is not copied.
pub type Str = Cow<'static, str>;

/// Field names the engine writes (other keys are copied).
pub const KEYS: [&str; 22] = ["atk", "hp", "eot", "src", "set_atk", "set_hp", "cost", "hooks", "player", "turn", "kind", "set",
    "delta", "until", "type", "entity", "target", "card", "amount", "source", "by", "by_id"];

fn key(s: &str) -> Str {
    KEYS.iter().find(|k| **k == s).map_or_else(|| Cow::Owned(s.to_string()), |k| Cow::Borrowed(*k))
}

/// A value of the engine's data: ints, bools and strings typed, anything else as JSON.
#[derive(Clone, Debug, PartialEq)]
pub enum V {
    Bool(bool),
    Int(i64),
    Str(Str),
    Json(Value),
}

impl V {
    /// From JSON (`intern`: how strings are kept).
    pub fn of(v: &Value, intern: &dyn Fn(&str) -> Str) -> V {
        match v {
            Value::Bool(b) => V::Bool(*b),
            Value::Number(n) if n.as_i64().is_some() => V::Int(n.as_i64().unwrap()),
            Value::String(s) => V::Str(intern(s)),
            _ => V::Json(v.clone()),
        }
    }
    pub fn to_value(&self) -> Value {
        match self {
            V::Bool(b) => Value::Bool(*b),
            V::Int(i) => Value::from(*i),
            V::Str(s) => Value::String(s.to_string()),
            V::Json(v) => v.clone(),
        }
    }
    /// GDScript truthiness (`truthy`).
    pub fn truthy(&self) -> bool {
        match self {
            V::Bool(b) => *b,
            V::Int(i) => *i != 0,
            V::Str(s) => !s.is_empty(),
            V::Json(v) => truthy(Some(v)),
        }
    }
    /// GDScript int() (`int`).
    pub fn int(&self) -> i64 {
        match self {
            V::Bool(b) => *b as i64,
            V::Int(i) => *i,
            V::Str(_) => 0,
            V::Json(v) => int(Some(v)),
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            V::Str(s) => Some(s),
            _ => None,
        }
    }
    /// == the JSON value v (as serde_json compares values).
    pub fn same(&self, v: &Value) -> bool {
        match (self, v) {
            (V::Bool(a), Value::Bool(b)) => a == b,
            (V::Int(a), Value::Number(_)) => Value::from(*a) == *v,
            (V::Str(a), Value::String(b)) => a == b,
            (V::Json(a), _) => a == v,
            _ => false,
        }
    }
    pub fn is_null(&self) -> bool {
        matches!(self, V::Json(Value::Null))
    }
}

/// An `Obj` from JSON-like pairs: `obj!{"type": "damage", "target": t}`.
macro_rules! obj {
    ($($k:literal: $v:expr),* $(,)?) => {{
        let mut o = $crate::entity::Obj::new();
        $(o.insert($k, $crate::entity::V::from($v));)*
        o
    }};
}
pub(crate) use obj;

impl From<i64> for V {
    fn from(v: i64) -> V {
        V::Int(v)
    }
}
impl From<bool> for V {
    fn from(v: bool) -> V {
        V::Bool(v)
    }
}
impl From<&'static str> for V {
    fn from(v: &'static str) -> V {
        V::Str(Cow::Borrowed(v))
    }
}
impl From<i32> for V {
    fn from(v: i32) -> V {
        V::Int(v as i64)
    }
}
impl From<usize> for V {
    fn from(v: usize) -> V {
        V::Int(v as i64)
    }
}
impl From<String> for V {
    fn from(v: String) -> V {
        V::Str(Cow::Owned(v))
    }
}
impl From<Vec<Id>> for V {
    fn from(v: Vec<Id>) -> V {
        V::Json(json!(v))
    }
}
impl From<Value> for V {
    fn from(v: Value) -> V {
        V::of(&v, &key)
    }
}

pub fn vtruthy(v: Option<&V>) -> bool {
    v.is_some_and(V::truthy)
}

pub fn vint(v: Option<&V>) -> i64 {
    v.map_or(0, V::int)
}

/// A small JSON object (tags, an enchantment, a cost change): keys sorted as in
/// serde_json's Map, cheap to clone.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Obj(Vec<(Str, V)>);

impl Obj {
    pub fn new() -> Obj {
        Obj(vec![])
    }
    /// From a JSON object (`intern`: how strings are kept).
    pub fn of(m: &Map<String, Value>, intern: &dyn Fn(&str) -> Str) -> Obj {
        // a Map iterates sorted
        Obj(m.iter().map(|(k, v)| (intern(k), V::of(v, intern))).collect())
    }
    pub fn get(&self, k: &str) -> Option<&V> {
        self.0.iter().find(|(x, _)| x == k).map(|(_, v)| v)
    }
    pub fn contains_key(&self, k: &str) -> bool {
        self.get(k).is_some()
    }
    pub fn insert(&mut self, k: impl Into<Str>, v: impl Into<V>) {
        let k = k.into();
        match self.0.binary_search_by(|(x, _)| x.as_ref().cmp(k.as_ref())) {
            Ok(i) => self.0[i].1 = v.into(),
            Err(i) => self.0.insert(i, (k, v.into())),
        }
    }
    pub fn remove(&mut self, k: &str) -> Option<V> {
        let i = self.0.iter().position(|(x, _)| x == k)?;
        Some(self.0.remove(i).1)
    }
    pub fn iter(&self) -> impl Iterator<Item = (&str, &V)> {
        self.0.iter().map(|(k, v)| (k.as_ref(), v))
    }
    pub fn len(&self) -> usize {
        self.0.len()
    }
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    pub fn retain(&mut self, mut f: impl FnMut(&str, &V) -> bool) {
        self.0.retain(|(k, v)| f(k, v));
    }
    pub fn to_map(&self) -> Map<String, Value> {
        self.0.iter().map(|(k, v)| (k.to_string(), v.to_value())).collect()
    }
    pub fn to_value(&self) -> Value {
        Value::Object(self.to_map())
    }
}

impl From<&Map<String, Value>> for Obj {
    fn from(m: &Map<String, Value>) -> Obj {
        Obj::of(m, &key)
    }
}

impl serde::Serialize for Obj {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.to_value().serialize(s)
    }
}

/// Aura contributions, recomputed by update_auras (not part of the state hash).
#[derive(Clone, Debug, Default)]
pub struct Aura {
    pub atk: i64,
    pub hp: i64,
    pub tags: Obj,
    /// card id -> [atk, hp] it adds (display only), by card id.
    pub src: Vec<(&'static str, [i64; 2])>,
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
    pub tags: Obj,
    pub enchantments: Vec<Obj>,
    pub eot_tags: Vec<Str>,
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
            if let Some(x) = e.get("set_atk") {
                v = x.int();
            }
            v += vint(e.get("atk"));
        }
        (v + self.aura.atk).max(0)
    }

    pub fn max_health(&self) -> i64 {
        let mut v = self.card.health;
        for e in &self.enchantments {
            if let Some(x) = e.get("set_hp") {
                v = x.int();
            }
            v += vint(e.get("hp"));
        }
        v + self.aura.hp
    }

    pub fn health(&self) -> i64 {
        self.max_health() - self.damage
    }

    pub fn has(&self, tag: &str) -> bool {
        vtruthy(self.tags.get(tag)) || vtruthy(self.aura.tags.get(tag))
    }

    /// int(tags.get(tag, 0)).
    pub fn tag(&self, tag: &str) -> i64 {
        vint(self.tags.get(tag))
    }

    pub fn set_tag(&mut self, tag: impl Into<Str>, v: impl Into<V>) {
        self.tags.insert(tag, v);
    }

    pub fn erase_tag(&mut self, tag: &str) {
        self.tags.remove(tag);
    }

    /// Its spell power (`name`: the SPELL_POWER tag name).
    pub fn spell_power(&self, name: &str) -> i64 {
        self.tag(name) + vint(self.aura.tags.get(name))
    }

    pub fn give_tag(&mut self, tag: impl Into<Str>, eot: bool) {
        let tag = tag.into();
        if eot && !self.eot_tags.contains(&tag) {
            self.eot_tags.push(tag.clone());
        }
        self.tags.insert(tag, true);
    }

    pub fn add_enchant(&mut self, ench: Value) {
        match ench {
            Value::Object(m) => self.enchantments.push(Obj::from(&m)),
            _ => panic!("enchantment must be an object"),
        }
    }

    /// The enchantments with these hooks (their "player" fields).
    pub fn ench_players(&self, hooks: &str) -> Vec<usize> {
        self.enchantments
            .iter()
            .filter(|e| e.get("hooks").and_then(V::as_str) == Some(hooks))
            .map(|e| vint(e.get("player")) as usize)
            .collect()
    }

    /// Removes "this turn" enchantments and tags. A lost Health bonus never kills.
    pub fn remove_eot(&mut self) {
        let (old_max, old_hp) = (self.max_health(), self.health());
        self.enchantments.retain(|e| !vtruthy(e.get("eot")));
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
            "dmg": self.damage, "tags": self.tags.to_value(), "ench": self.enchantments.iter().map(Obj::to_value).collect::<Vec<_>>(),
            "eot": self.eot_tags,
            "sil": self.silenced})
    }
}
