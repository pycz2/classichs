//! packs/eras, the cards that came after Rise of Shadows' release: SN1P-SN4P (31268), the ten Classic and Basic cards
//! of 14.6 and Pilfer's rework (31761), as the engine plays them in those versions (Zayle, Shadow Cloak of 30795 is
//! left out: its EVIL Decks need a `deck_recipes` entry a version patch cannot give). Needs python3 (skipped without
//! it).

#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

const MECH: &str = "BOT_309"; // Upgradeable Framebot, a 1/5 Mech
const NEW: [&str; 10] = ["EX1_183", "EX1_184", "EX1_185", "EX1_186", "EX1_187", "EX1_188", "EX1_189", "EX1_190", "EX1_191", "EX1_192"];

fn has_card(vid: &str, id: &str) -> bool {
    version(vid).unwrap().cards.contains_key(id)
}

fn pos_play(t: &mut T, card: &str, pos: i64) {
    let e = t.hand_id(card);
    t.act(&format!("play {card} at {pos}"), |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("pos")) == pos);
}

#[test]
fn the_new_cards_come_in_their_versions_and_zayle_in_none() {
    let Some(_) = eras() else { return };
    for id in NEW {
        assert!(!has_card("31268", id), "{id} before 14.6");
        let c = version("31761").unwrap().card(id);
        assert!(c.collectible && c.set == "VANILLA", "{id} in 14.6, Classic and Basic are VANILLA");
    }
    assert!(!has_card("31022", "BOT_700"));
    assert!(has_card("31268", "BOT_700") && has_card("31761", "BOT_700"));
    for v in ["30795", "31022", "31268", "31761"] {
        assert!(!has_card(v, "DAL_800") && !has_card(v, "DAL_800h"), "{v}: no Zayle");
    }
    assert_eq!(stats("31761", "EX1_185"), Some((7, 5, 8)));
    assert_eq!(stats("31761", "EX1_192").map(|s| s.0), Some(1));
}

#[test]
fn sn1p_sn4p_echoes_and_leaves_two_microbots_alone_or_magnetized() {
    for v in ["31268", "31761"] {
        // a minion: an Echo copy in the hand; it dies: two Microbots
        let mut t = scene!(v, {"hand": ["BOT_700", FIREBALL]}, {});
        t.play("BOT_700", NONE);
        assert_eq!(t.hand(0).iter().filter(|c| *c == "BOT_700").count(), 1, "{v}: Echo");
        let m = t.on_board(0, "BOT_700");
        t.play(FIREBALL, m);
        assert_eq!(t.cards(0), vec!["BOT_312t", "BOT_312t"], "{v}");
        // Magnetic onto a Mech: its stats and Deathrattle come along
        let mut t = scene!(v, {"hand": ["BOT_700", FIREBALL], "board": [{"card": MECH, "damage": 4}]}, {});
        pos_play(&mut t, "BOT_700", 0);
        let m = t.on_board(0, MECH);
        assert_eq!(t.stats(m), (1 + 2, 5 + 3 - 4), "{v}");
        t.play(FIREBALL, m);
        assert_eq!(t.cards(0), vec!["BOT_312t", "BOT_312t"], "{v}");
    }
}

#[test]
fn pilfer_gives_a_card_of_another_class_from_14_6() {
    let mut classes = BTreeSet::new();
    for seed in 1..=8 {
        // 14.4: the opponent's class (a Warrior)
        let mut t = scene!("31268", {"hand": ["EX1_182"]}, {});
        t.g.rng = classichs_engine::rng::Rng::new(seed);
        t.play("EX1_182", NONE);
        let got = t.hand(0)[0].clone();
        assert_eq!(version("31268").unwrap().card(&got).card_class, "WARRIOR", "{got}");
        // 14.6: any class but the Mage's own, never neutral
        let mut t = scene!("31761", {"hand": ["EX1_182"]}, {});
        t.g.rng = classichs_engine::rng::Rng::new(seed);
        t.play("EX1_182", NONE);
        let got = t.hand(0)[0].clone();
        let class = &version("31761").unwrap().card(&got).card_class;
        assert!(class != "MAGE" && class != "NEUTRAL", "{got}: {class}");
        classes.insert(class.clone());
    }
    assert!(classes.len() > 1, "not only the opponent's class: {classes:?}");
}

#[test]
fn gift_of_the_wild_and_righteousness_buff_every_friendly_minion() {
    let mut t = scene!("31761", {"hand": ["EX1_183", "EX1_184"], "board": [WISP, RAPTOR]}, {"board": [YETI]});
    t.play("EX1_183", NONE);
    let (w, r, y) = (t.on_board(0, WISP), t.on_board(0, RAPTOR), t.on_board(1, YETI));
    assert_eq!((t.stats(w), t.stats(r)), ((3, 3), (5, 4)));
    assert!(t.g.e(w).has("TAUNT") && t.g.e(r).has("TAUNT") && !t.g.e(y).has("TAUNT"));
    t.end_turn().end_turn();
    t.play("EX1_184", NONE);
    assert!(t.g.e(w).has("DIVINE_SHIELD") && t.g.e(r).has("DIVINE_SHIELD") && !t.g.e(y).has("DIVINE_SHIELD"));
}

#[test]
fn siegebreaker_gives_other_demons_one_attack() {
    let mut t = scene!("31761", {"hand": ["EX1_185"], "board": ["VAN_EX1_319", WISP]}, {"board": ["VAN_EX1_319"]});
    t.play("EX1_185", NONE);
    let s = t.on_board(0, "EX1_185");
    assert_eq!(t.stats(s), (5, 8));
    assert!(t.g.e(s).has("TAUNT"));
    assert_eq!(t.stats(t.on_board(0, "VAN_EX1_319")), (4, 2), "Flame Imp");
    assert_eq!(t.stats(t.on_board(0, WISP)), (1, 1), "not a Demon");
    assert_eq!(t.stats(t.on_board(1, "VAN_EX1_319")), (3, 2), "not the enemy's");
}

#[test]
fn si7_infiltrator_destroys_one_random_enemy_secret() {
    let mut t = scene!("31761", {"hand": ["EX1_186"]}, {"secrets": ["VAN_EX1_130", "VAN_EX1_136"]});
    t.play("EX1_186", NONE);
    assert_eq!(t.g.players[1].secrets.len(), 1);
    let mut t = scene!("31761", {"hand": ["EX1_186"]}, {});
    t.play("EX1_186", NONE);
    assert!(t.has(0, "EX1_186"), "no Secret: nothing happens");
}

#[test]
fn arcane_devourer_grows_with_each_spell_its_player_casts() {
    let mut t = scene!("31761", {"board": ["EX1_187"], "hand": [FROSTBOLT, FROSTBOLT]}, {"board": [YETI], "hand": [FROSTBOLT]});
    let (d, y) = (t.on_board(0, "EX1_187"), t.on_board(1, YETI));
    t.play(FROSTBOLT, y);
    assert_eq!(t.stats(d), (7, 7));
    t.play(FROSTBOLT, y);
    assert_eq!(t.stats(d), (9, 9));
    t.end_turn();
    t.play(FROSTBOLT, d);
    assert_eq!(t.stats(d), (9, 6), "not the opponent's spell");
}

#[test]
fn barrens_stablehand_summons_a_beast_and_brightwing_gives_a_legendary() {
    let mut t = scene!("31761", {"hand": ["EX1_188", "EX1_189"]}, {});
    t.play("EX1_188", NONE);
    let rs = version("31761").unwrap();
    let cards = t.cards(0);
    assert_eq!(cards.len(), 2, "{cards:?}");
    assert_eq!(rs.card(&cards[1]).race, "BEAST", "{cards:?}");
    t.play("EX1_189", NONE);
    let got = t.hand(0);
    assert_eq!(got.len(), 1);
    let c = rs.card(&got[0]);
    assert!(c.kind == "MINION" && c.rarity == "LEGENDARY", "{}", got[0]);
}

#[test]
fn whitemane_brings_back_the_friendly_minions_that_died_this_turn() {
    let mut t = scene!("31761", {"hand": ["EX1_190"], "board": [WISP, RAPTOR]}, {"board": [YETI, WISP]});
    let (w, r, y, ew) = (t.on_board(0, WISP), t.on_board(0, RAPTOR), t.on_board(1, YETI), t.on_board(1, WISP));
    t.attack(w, y).attack(r, ew);
    assert_eq!(t.cards(0), vec![RAPTOR]);
    t.play("EX1_190", NONE);
    assert_eq!(t.cards(0), vec![RAPTOR, "EX1_190", WISP], "the Wisp, not the enemy's");
    // a minion that died last turn stays dead
    let mut t = scene!("31761", {"hand": ["EX1_190"], "board": [WISP]}, {"board": [YETI]});
    let (w, y) = (t.on_board(0, WISP), t.on_board(1, YETI));
    t.attack(w, y).end_turn().end_turn();
    t.play("EX1_190", NONE);
    assert_eq!(t.cards(0), vec!["EX1_190"]);
}

#[test]
fn plaguebringer_gives_a_friendly_minion_poisonous_and_radiance_heals_the_hero() {
    let mut t = scene!("31761", {"hand": ["EX1_191", "EX1_192"], "board": [WISP], "damage": 10}, {"board": [YETI]});
    let w = t.on_board(0, WISP);
    t.play("EX1_191", w);
    assert!(t.g.e(w).has("POISONOUS"));
    let y = t.on_board(1, YETI);
    t.attack(w, y);
    assert!(t.cards(1).is_empty(), "the Yeti died of poison");
    t.play("EX1_192", NONE);
    assert_eq!(t.hp(0), 25);
}
