//! Arena drafting, by the bot's level: a random one of the three heroes (the bots play every class);
//! the cards: Easy takes any, Medium the best one 7 times in 10 (else any), Hard always the best —
//! the draft score (arena_tiers.json, per class) corrected for the mana curve.

use crate::brain::Level;
use crate::cards::{class_of, Library};
use rand::Rng;

/// Classic Arena classes, strongest first (the 2014 class tier lists).
pub const CLASS_ORDER: [&str; 9] = ["MAGE", "PALADIN", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "SHAMAN", "WARRIOR", "PRIEST"];

/// Cards wanted per cost (1, 2, 3, 4, 5, 6+) in a 30-card deck (3 more go anywhere).
const CURVE: [i64; 6] = [2, 7, 6, 5, 4, 3];

/// A random one of the offered heroes.
pub fn pick_hero(heroes: &[String], rng: &mut impl Rng) -> usize {
    rng.gen_range(0..heroes.len().max(1))
}

/// The strongest class among the heroes (CLASS_ORDER).
pub fn best_hero(lib: &Library, heroes: &[String]) -> usize {
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

/// The best card of the offer (draft score and mana curve).
pub fn best_card(lib: &Library, class: &str, picked: &[String], offer: &[String]) -> usize {
    (0..offer.len())
        .max_by(|&a, &b| pick_score(lib, class, picked, &offer[a]).total_cmp(&pick_score(lib, class, picked, &offer[b])))
        .unwrap_or(0)
}

/// The card a bot of this level takes.
pub fn pick_card(lib: &Library, class: &str, picked: &[String], offer: &[String], level: Level, rng: &mut impl Rng) -> usize {
    let any = rng.gen_range(0..offer.len().max(1));
    match level {
        Level::Easy => any,
        Level::Medium if rng.gen_bool(0.3) => any,
        _ => best_card(lib, class, picked, offer),
    }
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
        assert_eq!(best_hero(lib, &heroes), 1, "Mage over Priest and Warrior");
        // Fireball over Wisp and Magma Rager
        let offer = vec!["VAN_CS2_231".to_string(), "VAN_CS2_029".to_string(), "VAN_CS2_118".to_string()];
        assert_eq!(best_card(lib, "MAGE", &[], &offer), 1);
    }

    #[test]
    fn the_levels_draft_differently() {
        use rand::SeedableRng;
        let lib = lib();
        let mut rng = rand::rngs::StdRng::seed_from_u64(3);
        let heroes = vec!["HERO_09".to_string(), "HERO_08".to_string(), "HERO_01".to_string()];
        let mut seen = [0; 3];
        for _ in 0..300 {
            seen[pick_hero(&heroes, &mut rng)] += 1;
        }
        assert!(seen.iter().all(|&n| n > 60), "every hero now and then: {seen:?}");
        let offer = vec!["VAN_CS2_231".to_string(), "VAN_CS2_029".to_string(), "VAN_CS2_118".to_string()];
        let best = |level: Level, rng: &mut rand::rngs::StdRng| (0..1000).filter(|_| pick_card(lib, "MAGE", &[], &offer, level, rng) == 1).count();
        let (easy, medium, hard) = (best(Level::Easy, &mut rng), best(Level::Medium, &mut rng), best(Level::Hard, &mut rng));
        assert_eq!(hard, 1000, "Hard: always the best");
        assert!((750..850).contains(&medium), "Medium: 70 % + a third of 30 %: {medium}");
        assert!((280..390).contains(&easy), "Easy: any: {easy}");
    }

    #[test]
    fn a_full_cost_counts_against_a_card() {
        let lib = lib();
        let yeti = "VAN_CS2_182".to_string();
        let fours: Vec<String> = vec![yeti.clone(); 6];
        assert!(pick_score(lib, "MAGE", &fours, &yeti) < pick_score(lib, "MAGE", &[], &yeti) - 10.0);
    }
}
