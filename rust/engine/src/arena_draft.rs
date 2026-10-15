//! The Arena draft as in Hearthstone in 2014 (game/arena_draft.gd): three heroes
//! of different classes, then 30 picks of three cards of one rarity tier.

use crate::card_db;
use crate::deck;
use crate::rng::Rng;

pub const PICKS: usize = 30;
/// Pick indexes that are Rare or better.
pub const SPECIAL: [usize; 4] = [0, 9, 19, 29];
pub const ODDS: [(&str, f64); 4] = [("common", 0.765), ("rare", 0.14), ("epic", 0.075), ("legendary", 0.02)];
pub const SPECIAL_ODDS: [(&str, f64); 3] = [("rare", 0.65), ("epic", 0.27), ("legendary", 0.08)];
pub const CLASS_WEIGHT: f64 = 1.5;
pub const CLASSES: [&str; 9] = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"];

pub struct ArenaDraft {
    pub rng: Rng,
    /// The three offered.
    pub heroes: Vec<String>,
    pub hero: String,
    pub cards: Vec<String>,
    /// The three cards of the current pick.
    pub offer: Vec<String>,
}

/// The rarity tier of a card: Basic counts as common.
pub fn tier(id: &str) -> String {
    let r = &card_db::card(id).rarity;
    if r.is_empty() || r == "FREE" || r == "COMMON" { "common".into() } else { r.to_lowercase() }
}

/// The cards of a tier for a class with their weights.
pub fn pool(card_class: &str, t: &str) -> Vec<(String, f64)> {
    let mut out = vec![];
    for id in card_db::collectible() {
        let c = card_db::card(id);
        if c.kind == "HERO" || tier(id) != t {
            continue;
        }
        if c.card_class == card_class {
            out.push((id.clone(), CLASS_WEIGHT));
        } else if c.card_class == "NEUTRAL" {
            out.push((id.clone(), 1.0));
        }
    }
    out
}

impl ArenaDraft {
    pub fn new(seed: i64) -> ArenaDraft {
        let mut d = ArenaDraft { rng: Rng::new(seed as u64), heroes: vec![], hero: String::new(), cards: vec![], offer: vec![] };
        let mut classes = CLASSES.to_vec();
        for _ in 0..3 {
            let i = d.rng.randi_range(0, classes.len() as i64 - 1) as usize;
            d.heroes.push(deck::hero(classes.remove(i)).unwrap().to_string());
        }
        d
    }

    pub fn choose_hero(&mut self, i: usize) {
        self.hero = self.heroes[i].clone();
        self.next();
    }

    /// Takes card i of the offer; the other two are gone.
    pub fn pick(&mut self, i: usize) {
        if self.done() || i >= self.offer.len() {
            return;
        }
        self.cards.push(self.offer[i].clone());
        self.next();
    }

    pub fn done(&self) -> bool {
        self.cards.len() >= PICKS
    }

    fn next(&mut self) {
        self.offer.clear();
        if !self.done() {
            let t = self.roll_tier(SPECIAL.contains(&self.cards.len()));
            self.offer = self.roll_offer(t);
        }
    }

    pub fn roll_tier(&mut self, special: bool) -> &'static str {
        let odds: &[(&'static str, f64)] = if special { &SPECIAL_ODDS } else { &ODDS };
        let mut x = self.rng.randf();
        for (t, p) in odds {
            x -= p;
            if x < 0.0 {
                return t;
            }
        }
        odds[odds.len() - 1].0
    }

    /// Three different cards of tier t for the hero, drawn by weight.
    pub fn roll_offer(&mut self, t: &str) -> Vec<String> {
        let mut left = pool(deck::card_class(&self.hero).unwrap_or(""), t);
        let mut out = vec![];
        while out.len() < 3 && !left.is_empty() {
            let mut total = 0.0;
            for it in &left {
                total += it.1;
            }
            let mut x = self.rng.randf() * total;
            let mut k = 0;
            while k < left.len() - 1 && x >= left[k].1 {
                x -= left[k].1;
                k += 1;
            }
            out.push(left.remove(k).0);
        }
        out
    }
}
