//! Arena drafting: the hero by the class's Arena strength, each card by its draft score
//! (bots/arena_tiers.json, per class) corrected for the mana curve.

use crate::bots::cards::{class_of, Library};

/// Classic Arena classes, strongest first (the 2014 class tier lists).
pub const CLASS_ORDER: [&str; 9] = ["MAGE", "PALADIN", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "SHAMAN", "WARRIOR", "PRIEST"];

/// Cards wanted per cost (1, 2, 3, 4, 5, 6+) in a 30-card deck (3 more go anywhere).
const CURVE: [i64; 6] = [2, 7, 6, 5, 4, 3];

pub fn pick_hero(lib: &Library, heroes: &[String]) -> usize {
    let rank = |h: &String| CLASS_ORDER.iter().position(|c| *c == class_of(lib.rs, h)).unwrap_or(9);
    (0..heroes.len()).min_by_key(|&i| rank(&heroes[i])).unwrap_or(0)
}

fn bucket(cost: i64) -> usize {
    (cost.clamp(1, 6) - 1) as usize
}

/// The score of taking `card` now: its draft score, less when that cost is already full, more when
/// the deck still lacks cards of that cost.
pub fn pick_score(lib: &Library, class: &str, picked: &[String], card: &str) -> f64 {
    let cost = if lib.rs.has(card) { lib.rs.card(card).cost } else { 3 };
    let b = bucket(cost);
    let have = picked.iter().filter(|c| lib.rs.has(c) && bucket(lib.rs.card(c).cost) == b).count() as i64;
    let mut s = lib.tier(card, class);
    if have >= CURVE[b] {
        s -= 8.0 * (have - CURVE[b] + 1) as f64;
    } else {
        let expected = CURVE[b] as f64 * (picked.len() + 1) as f64 / 30.0;
        if (have as f64) < expected - 1.0 {
            s += 4.0;
        }
    }
    s
}

pub fn pick_card(lib: &Library, class: &str, picked: &[String], offer: &[String]) -> usize {
    (0..offer.len())
        .max_by(|&a, &b| pick_score(lib, class, picked, &offer[a]).total_cmp(&pick_score(lib, class, picked, &offer[b])))
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn lib() -> &'static Library {
        Library::get()
    }

    #[test]
    fn takes_the_strong_class_and_the_strong_card() {
        let lib = lib();
        let heroes = vec!["HERO_09".to_string(), "HERO_08".to_string(), "HERO_01".to_string()];
        assert_eq!(pick_hero(lib, &heroes), 1, "Mage over Priest and Warrior");
        // Fireball over Wisp and Magma Rager
        let offer = vec!["VAN_CS2_231".to_string(), "VAN_CS2_029".to_string(), "VAN_CS2_118".to_string()];
        assert_eq!(pick_card(lib, "MAGE", &[], &offer), 1);
    }

    #[test]
    fn a_full_cost_counts_against_a_card() {
        let lib = lib();
        let yeti = "VAN_CS2_182".to_string();
        let fours: Vec<String> = vec![yeti.clone(); 6];
        assert!(pick_score(lib, "MAGE", &fours, &yeti) < pick_score(lib, "MAGE", &[], &yeti) - 10.0);
    }
}
