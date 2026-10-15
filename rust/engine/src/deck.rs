//! Decks and deck-building rules (game/deck.gd, game/decks.gd).

use crate::card_db;
use serde_json::Value;

pub const SIZE: usize = 30;

pub const HEROES: [(&str, &str); 9] = [("WARRIOR", "HERO_01"), ("SHAMAN", "HERO_02"), ("ROGUE", "HERO_03"),
    ("PALADIN", "HERO_04"), ("HUNTER", "HERO_05"), ("DRUID", "HERO_06"), ("WARLOCK", "HERO_07"), ("MAGE", "HERO_08"),
    ("PRIEST", "HERO_09")];
/// Neutral Basic cards that fill a class deck, in priority order.
pub const NEUTRAL_CORE: [&str; 10] = ["VAN_EX1_066", "VAN_CS2_172", "VAN_EX1_019", "VAN_CS2_182", "VAN_CS2_147",
    "VAN_CS2_179", "VAN_CS2_200", "VAN_CS2_120", "VAN_EX1_015", "VAN_CS2_189"];

pub fn hero(card_class: &str) -> Option<&'static str> {
    HEROES.iter().find(|(c, _)| *c == card_class).map(|(_, h)| *h)
}

pub fn card_class(hero_id: &str) -> Option<&'static str> {
    HEROES.iter().find(|(_, h)| *h == hero_id).map(|(c, _)| *c)
}

/// Two copies of every Basic card of the class, then neutral core cards up to 30.
pub fn basic(card_class: &str) -> Vec<String> {
    let mut deck = vec![];
    for id in card_db::collectible() {
        let c = card_db::card(id);
        if c.card_class == card_class && c.rarity == "FREE" {
            deck.push(id.clone());
            deck.push(id.clone());
        }
    }
    for id in NEUTRAL_CORE {
        for _ in 0..2 {
            if deck.len() < SIZE {
                deck.push(id.to_string());
            }
        }
    }
    deck
}

#[derive(Clone, Debug, Default)]
pub struct Deck {
    pub hero: String,
    pub cards: Vec<String>,
    /// An Arena deck: drafted, so any number of copies of a card.
    pub arena: bool,
}

pub fn max_copies(id: &str) -> usize {
    if card_db::card(id).rarity == "LEGENDARY" { 1 } else { 2 }
}

impl Deck {
    /// A deck from saved data. Card ids that no longer exist are dropped; a bad
    /// structure or an unknown hero gives None.
    pub fn from_value(d: &Value) -> Option<Deck> {
        let hero = d.get("hero")?.as_str()?;
        let cards = d.get("cards")?.as_array()?;
        card_class(hero)?;
        let mut deck = Deck { hero: hero.to_string(), cards: vec![], arena: d.get("arena") == Some(&Value::Bool(true)) };
        for id in cards {
            let id = id.as_str()?;
            if card_db::has(id) {
                deck.cards.push(id.to_string());
            }
        }
        Some(deck)
    }

    /// Why id can't be added ("" = it can).
    pub fn can_add(&self, id: &str) -> &'static str {
        if !card_db::has(id) || card_db::collectible().binary_search(&id.to_string()).is_err() {
            return "This card can't be put in a deck";
        }
        let cls = &card_db::card(id).card_class;
        if cls != "NEUTRAL" && Some(cls.as_str()) != card_class(&self.hero) {
            return "This card belongs to another class";
        }
        if self.cards.len() >= SIZE {
            return "The deck already has 30 cards";
        }
        if !self.arena && self.cards.iter().filter(|c| *c == id).count() >= max_copies(id) {
            return "No more copies of this card are allowed";
        }
        ""
    }

    /// Why the deck can't be played ("" = it is complete and legal).
    pub fn validate(&self) -> String {
        if card_class(&self.hero).is_none() {
            return "Unknown hero".into();
        }
        let mut copy = Deck { hero: self.hero.clone(), cards: vec![], arena: self.arena };
        for id in &self.cards {
            let why = copy.can_add(id);
            if !why.is_empty() {
                return why.into();
            }
            copy.cards.push(id.clone());
        }
        if self.cards.len() != SIZE {
            return format!("A deck needs exactly 30 cards. Cards now: {}", self.cards.len());
        }
        String::new()
    }
}
