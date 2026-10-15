//! Card data: data/cards.json (HearthstoneJSON, VANILLA set), embedded.

use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::OnceLock;

pub const CARDS_JSON: &str = include_str!("../../../data/cards.json");

#[derive(Deserialize, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct Card {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub cost: i64,
    #[serde(default)]
    pub attack: i64,
    #[serde(default)]
    pub health: i64,
    #[serde(default)]
    pub durability: i64,
    #[serde(default)]
    pub overload: i64,
    pub spell_damage: Option<i64>,
    #[serde(default)]
    pub race: String,
    #[serde(default)]
    pub mechanics: Vec<String>,
    #[serde(default)]
    pub rarity: String,
    #[serde(default)]
    pub card_class: String,
    #[serde(default)]
    pub collectible: bool,
    #[serde(default)]
    pub set: String,
}

impl Card {
    pub fn has_mechanic(&self, m: &str) -> bool {
        self.mechanics.iter().any(|x| x == m)
    }
    pub fn is_secret(&self) -> bool {
        self.kind == "SPELL" && self.has_mechanic("SECRET")
    }
}

struct Db {
    cards: HashMap<String, Card>,
    collectible: Vec<String>,
    hash: String,
}

fn db() -> &'static Db {
    static DB: OnceLock<Db> = OnceLock::new();
    DB.get_or_init(|| {
        let list: Vec<Card> = serde_json::from_str(CARDS_JSON).expect("data/cards.json");
        let mut collectible: Vec<String> =
            list.iter().filter(|c| c.collectible && c.set == "VANILLA").map(|c| c.id.clone()).collect();
        collectible.sort();
        let cards = list.into_iter().map(|c| (c.id.clone(), c)).collect();
        let hash = Sha256::digest(CARDS_JSON.as_bytes()).iter().map(|b| format!("{:02x}", b)).collect();
        Db { cards, collectible, hash }
    })
}

/// The card; panics on an unknown id (GDScript asserts). Check `has` at trust boundaries.
pub fn card(id: &str) -> &'static Card {
    db().cards.get(id).unwrap_or_else(|| panic!("unknown card {id}"))
}

pub fn has(id: &str) -> bool {
    db().cards.contains_key(id)
}

/// Collectible VANILLA cards, sorted by id.
pub fn collectible() -> &'static [String] {
    &db().collectible
}

/// SHA-256 of cards.json: both sides of a game must have the same card data.
pub fn data_hash() -> &'static str {
    &db().hash
}
