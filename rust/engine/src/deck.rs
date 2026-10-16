//! Decks and deck-building rules (game/deck.gd, game/decks.gd), by a ruleset's
//! `rules.json` (deck size, copies, the constructed sets and class rule).
//! The free functions use the built-in Classic ruleset.

use crate::ruleset::{self, Ruleset};
use serde_json::Value;

/// Classic's deck size (a ruleset has its own: `Ruleset::deck_size`).
pub const SIZE: usize = 30;

/// The champion of a class (Classic).
pub fn hero(card_class: &str) -> Option<&'static str> {
    ruleset::classic().champion(card_class)
}

/// The class of a champion (Classic).
pub fn card_class(hero_id: &str) -> Option<&'static str> {
    ruleset::classic().class_of_champion(hero_id)
}

/// A starter deck (Classic): two of every Basic card of the class, then the starter core.
pub fn basic(card_class: &str) -> Vec<String> {
    basic_in(ruleset::classic(), card_class)
}

/// Two copies of every Basic (`FREE`) card of the class, then the ruleset's starter core up to the deck size.
pub fn basic_in(rs: &Ruleset, card_class: &str) -> Vec<String> {
    let mut deck = vec![];
    for id in &rs.collectible {
        let c = rs.card(id);
        if c.card_class == card_class && c.rarity == "FREE" {
            deck.push(id.clone());
            deck.push(id.clone());
        }
    }
    for id in &rs.starter_core {
        for _ in 0..2 {
            if deck.len() < rs.deck_size {
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
    max_copies_in(ruleset::classic(), id)
}

pub fn max_copies_in(rs: &Ruleset, id: &str) -> usize {
    rs.copies_by_rarity.get(&rs.card(id).rarity).copied().unwrap_or(rs.copies)
}

impl Deck {
    /// A deck from saved data (Classic). Card ids that no longer exist are dropped; a bad
    /// structure or an unknown hero gives None.
    pub fn from_value(d: &Value) -> Option<Deck> {
        Deck::from_value_in(ruleset::classic(), d)
    }

    pub fn from_value_in(rs: &Ruleset, d: &Value) -> Option<Deck> {
        let hero = d.get("hero")?.as_str()?;
        let cards = d.get("cards")?.as_array()?;
        rs.class_of_champion(hero)?;
        let mut deck = Deck { hero: hero.to_string(), cards: vec![], arena: d.get("arena") == Some(&Value::Bool(true)) };
        for id in cards {
            let id = id.as_str()?;
            if rs.has(id) {
                deck.cards.push(id.to_string());
            }
        }
        Some(deck)
    }

    /// Why id can't be added ("" = it can), Classic.
    pub fn can_add(&self, id: &str) -> String {
        self.can_add_in(ruleset::classic(), id)
    }

    pub fn can_add_in(&self, rs: &Ruleset, id: &str) -> String {
        if !rs.has(id) || rs.collectible.binary_search(&id.to_string()).is_err() {
            return "This card can't be put in a deck".into();
        }
        let cls = &rs.card(id).card_class;
        if rs.own_and_neutral && !rs.is_neutral(cls) && Some(cls.as_str()) != rs.class_of_champion(&self.hero) {
            return "This card belongs to another class".into();
        }
        if self.cards.len() >= rs.deck_size {
            return format!("The deck already has {} cards", rs.deck_size);
        }
        if !self.arena && self.cards.iter().filter(|c| *c == id).count() >= max_copies_in(rs, id) {
            return "No more copies of this card are allowed".into();
        }
        String::new()
    }

    /// Why the deck can't be played ("" = it is complete and legal), Classic.
    pub fn validate(&self) -> String {
        self.validate_in(ruleset::classic())
    }

    pub fn validate_in(&self, rs: &Ruleset) -> String {
        if rs.class_of_champion(&self.hero).is_none() {
            return "Unknown hero".into();
        }
        let mut copy = Deck { hero: self.hero.clone(), cards: vec![], arena: self.arena };
        for id in &self.cards {
            let why = copy.can_add_in(rs, id);
            if !why.is_empty() {
                return why;
            }
            copy.cards.push(id.clone());
        }
        if self.cards.len() != rs.deck_size {
            return format!("A deck needs exactly {} cards. Cards now: {}", rs.deck_size, self.cards.len());
        }
        String::new()
    }
}
