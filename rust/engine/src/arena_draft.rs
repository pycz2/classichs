//! The Arena draft (game/arena_draft.gd) by a ruleset's `modes.arena`
//! (docs/packs/rules.md): champions of different classes, then picks of cards
//! of one rarity tier. Classic: three heroes, 30 picks of three cards, 2014 odds.

use crate::rng::Rng;
use crate::ruleset::{self, Ruleset};

pub struct ArenaDraft {
    pub rs: &'static Ruleset,
    pub rng: Rng,
    /// The champions offered.
    pub heroes: Vec<String>,
    pub hero: String,
    pub cards: Vec<String>,
    /// The cards of the current pick.
    pub offer: Vec<String>,
}

/// The cards of a tier for a class with their weights (class : neutral = class_weight : neutral_weight).
pub fn pool(rs: &Ruleset, card_class: &str, t: &str) -> Vec<(String, f64)> {
    let cw = rs.arena.class_weight as f64 / rs.arena.neutral_weight.max(1) as f64;
    let mut out = vec![];
    for id in &rs.arena_pool {
        let c = rs.card(id);
        if c.kind == "CHAMPION" || rs.tier(id) != t {
            continue;
        }
        if c.card_class == card_class {
            out.push((id.clone(), cw));
        } else if rs.is_neutral(&c.card_class) {
            out.push((id.clone(), 1.0));
        }
    }
    out
}

impl ArenaDraft {
    /// A draft of the built-in Classic ruleset.
    pub fn new(seed: i64) -> ArenaDraft {
        ArenaDraft::new_in(ruleset::classic(), seed)
    }

    pub fn new_in(rs: &'static Ruleset, seed: i64) -> ArenaDraft {
        let mut d = ArenaDraft { rs, rng: Rng::new(seed as u64), heroes: vec![], hero: String::new(), cards: vec![], offer: vec![] };
        let mut classes: Vec<&str> = rs.arena.classes.iter().map(String::as_str).filter(|c| rs.champion(c).is_some()).collect();
        for _ in 0..rs.arena.champions_offered.min(classes.len()) {
            let i = d.rng.randi_range(0, classes.len() as i64 - 1) as usize;
            d.heroes.push(rs.champion(classes.remove(i)).unwrap().to_string());
        }
        d
    }

    pub fn choose_hero(&mut self, i: usize) {
        self.hero = self.heroes[i].clone();
        self.next();
    }

    /// Takes card i of the offer; the others are gone.
    pub fn pick(&mut self, i: usize) {
        if self.done() || i >= self.offer.len() {
            return;
        }
        self.cards.push(self.offer[i].clone());
        self.next();
    }

    pub fn done(&self) -> bool {
        self.cards.len() >= self.rs.arena.picks
    }

    fn next(&mut self) {
        self.offer.clear();
        if !self.done() {
            let t = self.roll_tier(self.rs.arena.special_picks.contains(&self.cards.len()));
            self.offer = self.roll_offer(t);
        }
    }

    pub fn roll_tier(&mut self, special: bool) -> &'static str {
        let a = &self.rs.arena;
        let odds = if special { &a.special_tier_weights } else { &a.tier_weights };
        let mut x = self.rng.randf();
        for (t, w) in odds {
            x -= *w as f64 / 1000.0;
            if x < 0.0 {
                return t;
            }
        }
        odds.last().map_or("common", |o| o.0)
    }

    /// `offer` different cards of tier t for the hero, drawn by weight.
    pub fn roll_offer(&mut self, t: &str) -> Vec<String> {
        let mut left = pool(self.rs, self.rs.class_of_champion(&self.hero).unwrap_or(""), t);
        let mut out = vec![];
        while out.len() < self.rs.arena.offer && !left.is_empty() {
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
