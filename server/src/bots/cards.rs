//! What the bots know before a game: card names (data/cards.json), the deck library (decks.json),
//! the Arena draft scores (arena_tiers.json) and, per class, the cards an opponent of that
//! class probably holds (weights for guessing hidden cards).

use classichs_engine::ruleset::{self, Ruleset};
use rand::Rng;
use serde_json::Value;
use std::collections::HashMap;

#[derive(Clone, Debug)]
pub struct Deck {
    pub name: String,
    pub hero: String,
    pub cards: Vec<String>,
}

/// Cards with weights: what a hidden card of one class probably is.
#[derive(Clone, Debug, Default)]
pub struct Pool {
    pub cards: Vec<(String, f64)>,
    total: f64,
}

impl Pool {
    pub fn add(&mut self, id: &str, w: f64) {
        if w > 0.0 {
            self.cards.push((id.to_string(), w));
            self.total += w;
        }
    }

    /// A card by weight, skipping the ones `full` says have no copies left.
    pub fn sample(&self, rng: &mut impl Rng, full: impl Fn(&str) -> bool) -> Option<String> {
        for _ in 0..40 {
            let mut x = rng.gen::<f64>() * self.total;
            for (id, w) in &self.cards {
                x -= w;
                if x <= 0.0 {
                    if !full(id) {
                        return Some(id.clone());
                    }
                    break;
                }
            }
        }
        self.cards.iter().find(|(id, _)| !full(id)).map(|(id, _)| id.clone())
    }
}

pub struct Library {
    pub rs: &'static Ruleset,
    pub names: HashMap<String, String>,
    pub decks: Vec<Deck>,
    /// draft scores: the card's, and per class where the tier list differs
    pub tiers: HashMap<String, (f64, HashMap<String, f64>)>,
    /// class → cards weighted by the deck library (constructed opponents)
    pub ladder_pools: HashMap<String, Pool>,
    /// class → cards weighted by the draft scores (Arena opponents)
    pub arena_pools: HashMap<String, Pool>,
}

pub fn class_of(rs: &Ruleset, hero: &str) -> String {
    if rs.has(hero) { rs.card(hero).card_class.clone() } else { String::new() }
}

/// Classic cards a deck of `class` may hold (the class's and neutral collectible ones).
fn collectible(rs: &'static Ruleset, class: &str) -> Vec<&'static str> {
    let mut v: Vec<&'static str> = rs
        .cards
        .values()
        .filter(|c| c.collectible && c.id.starts_with("VAN_") && c.kind != "HERO" && c.kind != "HERO_POWER")
        .filter(|c| c.card_class == class || c.card_class == "NEUTRAL")
        .map(|c| c.id.as_str())
        .collect();
    v.sort();
    v
}

impl Library {
    /// The library built into the server: card names (data/cards.json), decks (decks.json),
    /// draft scores (arena_tiers.json). Built once.
    pub fn get() -> &'static Library {
        static LIB: std::sync::OnceLock<Library> = std::sync::OnceLock::new();
        LIB.get_or_init(|| {
            Library::from_json(include_str!("../../../data/cards.json"), include_str!("decks.json"), include_str!("arena_tiers.json"))
                .expect("the built-in bot library")
        })
    }

    pub fn from_json(cards_json: &str, decks_json: &str, tiers_json: &str) -> Result<Library, String> {
        let rs = ruleset::classic();
        let mut names = HashMap::new();
        let data: Value = serde_json::from_str(cards_json).map_err(|e| format!("cards.json: {e}"))?;
        let list: Vec<&Value> = match &data {
            Value::Array(a) => a.iter().collect(),
            Value::Object(o) => o.values().collect(),
            _ => vec![],
        };
        for c in list {
            let id = c["id"].as_str().unwrap_or_default();
            let n = c["name"]["enUS"].as_str().or(c["name"]["ruRU"].as_str()).unwrap_or(id);
            names.insert(id.to_string(), n.to_string());
            // the game's own ids: the vanilla copies are "VAN_" + the original id
            names.entry(format!("VAN_{id}")).or_insert_with(|| n.to_string());
        }
        let mut decks = vec![];
        let dv: Value = serde_json::from_str(decks_json).map_err(|e| format!("decks.json: {e}"))?;
        for v in dv.as_array().into_iter().flatten() {
            let hero = v["hero"].as_str().unwrap_or_default().to_string();
            let cards: Vec<String> = v["cards"].as_array().map_or(vec![], |a| a.iter().filter_map(|c| c.as_str().map(String::from)).collect());
            if cards.len() != 30 || !rs.has(&hero) || !cards.iter().all(|c| rs.has(c)) {
                return Err(format!("decks.json: {} is not a 30-card Classic deck", v["name"]));
            }
            decks.push(Deck { name: v["name"].as_str().unwrap_or("?").to_string(), hero, cards });
        }
        if decks.is_empty() {
            return Err("decks.json: no decks".into());
        }
        let mut tiers = HashMap::new();
        let v: Value = serde_json::from_str(tiers_json).map_err(|e| format!("arena_tiers.json: {e}"))?;
        if let Some(m) = v["cards"].as_object() {
            for (id, c) in m {
                let by: HashMap<String, f64> = c["by_class"].as_object().map_or(HashMap::new(), |m| {
                    m.iter().filter_map(|(k, v)| v.as_f64().map(|x| (k.clone(), x))).collect()
                });
                tiers.insert(id.clone(), (c["score"].as_f64().unwrap_or(50.0), by));
            }
        }
        let classes = ["WARRIOR", "SHAMAN", "ROGUE", "PALADIN", "HUNTER", "DRUID", "WARLOCK", "MAGE", "PRIEST"];
        let mut ladder_pools = HashMap::new();
        let mut arena_pools = HashMap::new();
        for class in classes {
            let all = collectible(rs, class);
            let mut counts: HashMap<&str, f64> = HashMap::new();
            for d in decks.iter().filter(|d| class_of(rs, &d.hero) == class) {
                for c in &d.cards {
                    *counts.entry(c.as_str()).or_default() += 1.0;
                }
            }
            let (mut lp, mut ap) = (Pool::default(), Pool::default());
            for id in &all {
                // decks of the library first, every other card of the class a little
                lp.add(id, counts.get(id).copied().unwrap_or(0.0) + 0.05);
                let s = tiers.get(*id).map_or_else(|| heuristic_score(rs, id), |(s, by): &(f64, HashMap<String, f64>)| by.get(class).copied().unwrap_or(*s));
                ap.add(id, (s / 100.0).powi(2));
            }
            ladder_pools.insert(class.to_string(), lp);
            arena_pools.insert(class.to_string(), ap);
        }
        Ok(Library { rs, names, decks, tiers, ladder_pools, arena_pools })
    }

    pub fn name(&self, id: &str) -> String {
        self.names.get(id).cloned().unwrap_or_else(|| id.to_string())
    }

    pub fn decks_of(&self, class: &str) -> Vec<&Deck> {
        self.decks.iter().filter(|d| class_of(self.rs, &d.hero) == class).collect()
    }

    /// The draft score of a card for a class (bots/arena_tiers.json, else a guess from its numbers).
    pub fn tier(&self, id: &str, class: &str) -> f64 {
        self.tiers.get(id).map_or_else(|| heuristic_score(self.rs, id), |(s, by)| by.get(class).copied().unwrap_or(*s))
    }
}

/// A rough 0-100 draft score from cost and stats, for cards the tier list misses.
pub fn heuristic_score(rs: &Ruleset, id: &str) -> f64 {
    if !rs.has(id) {
        return 40.0;
    }
    let c = rs.card(id);
    match c.kind.as_str() {
        "MINION" => {
            let stats = c.attack as f64 + c.health as f64;
            let par = 2.0 * c.cost as f64 + 1.0;
            (55.0 + 8.0 * (stats - par) + 4.0 * c.keywords.len() as f64).clamp(10.0, 85.0)
        }
        "WEAPON" => (50.0 + 5.0 * (c.attack * c.durability) as f64 - 4.0 * c.cost as f64).clamp(20.0, 85.0),
        _ => 50.0,
    }
}
