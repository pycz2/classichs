//! The Witchwood: the Paladin, Priest and Rogue cards (packs/gil/scripts/gil_ppr.lua).

use super::*;

const RAIDER: &str = "VAN_CS2_168"; // Murloc Raider (1)
const HOARDER: &str = "VAN_EX1_096"; // Loot Hoarder: Deathrattle
const WATER_ELEMENTAL: &str = "VAN_CS2_033";
const AXE: &str = "VAN_CS2_106"; // Fiery War Axe
const WHELP: &str = "GIL_190t";

fn secrets(t: &T, p: usize) -> Vec<String> {
    t.g.players[p].secrets.iter().map(|&e| card_of(t, e)).collect()
}

fn weapon(t: &T, p: usize) -> Id {
    t.g.players[p].weapon.expect("a weapon")
}

fn deck_of(t: &T, p: usize, card: &str) -> Vec<Id> {
    t.g.players[p].deck.iter().copied().filter(|&e| t.g.e(e).card_id == card).collect()
}

// --- Paladin ---

#[test]
fn hidden_wisdom_draws_two_after_the_third_card() {
    let mut t = scene!({"secrets": ["GIL_903"]}, {"hand": [WISP, WISP, WISP]});
    t.end_turn();
    t.play(WISP, NONE).play(WISP, NONE);
    assert_eq!(t.g.players[0].hand.len(), 0, "two cards: not yet");
    assert_eq!(secrets(&t, 0), vec!["GIL_903"]);
    t.play(WISP, NONE);
    assert_eq!(t.g.players[0].hand.len(), 2, "the third: draw 2");
    assert!(secrets(&t, 0).is_empty());
}

#[test]
fn cathedral_gargoyle_needs_a_dragon_in_hand() {
    let mut t = scene!({"hand": ["GIL_635", WHELP, "GIL_635"]}, {});
    t.play("GIL_635", NONE);
    let a = t.nth(0, 0);
    assert!(t.g.e(a).has("TAUNT") && t.g.e(a).has("DIVINE_SHIELD"));
    t.play(WHELP, NONE).play("GIL_635", NONE);
    let b = t.nth(0, 2);
    assert!(!t.g.e(b).has("TAUNT") && !t.g.e(b).has("DIVINE_SHIELD"), "no Dragon left in the hand");
}

#[test]
fn rebuke_makes_enemy_spells_cost_five_more_next_turn() {
    let mut t = scene!({"hand": ["GIL_203"]}, {"hand": [FIREBALL]});
    t.play("GIL_203", NONE).end_turn();
    assert_eq!(t.cost(FIREBALL), 9);
    t.end_turn().end_turn();
    assert_eq!(t.cost(FIREBALL), 4, "only that turn");
}

#[test]
fn sound_the_bells_buffs_and_echoes() {
    let mut t = scene!({"hand": ["GIL_145"], "board": [YETI]}, {});
    let y = t.nth(0, 0);
    t.play("GIL_145", y);
    assert_eq!(t.stats(y), (5, 7));
    assert_eq!(t.hand(0), vec!["GIL_145"], "the Echo copy");
}

#[test]
fn paragon_of_light_has_taunt_and_lifesteal_from_three_attack() {
    let mut t = scene!({"hand": ["GIL_145"], "board": ["GIL_685"], "hero_state": {"damage": 10}}, {});
    let m = t.nth(0, 0);
    assert!(!t.g.e(m).has("TAUNT") && !t.g.e(m).has("LIFESTEAL"));
    t.play("GIL_145", m);
    assert!(t.g.e(m).has("TAUNT") && t.g.e(m).has("LIFESTEAL"), "3 Attack");
    let hp = t.hp(0);
    let foe = t.hero(1);
    t.attack(m, foe);
    assert_eq!(t.hp(0), hp + 3, "Lifesteal");
}

#[test]
fn bellringer_sentry_puts_secrets_from_the_deck_on_play_and_death() {
    let mut t = scene!({"hand": ["GIL_634", FIREBALL], "deck": ["GIL_903", "LOOT_204", "GIL_903"]}, {});
    t.play("GIL_634", NONE);
    assert_eq!(secrets(&t, 0).len(), 1);
    let s = t.nth(0, 0);
    t.play(FIREBALL, s);
    let mut got = secrets(&t, 0);
    got.sort();
    assert_eq!(got, vec!["GIL_903", "LOOT_204"], "the Deathrattle: another one (not the same Secret twice)");
    assert_eq!(t.g.players[0].deck.len(), 1);
}

#[test]
fn glass_knight_regains_divine_shield_when_you_restore_health() {
    let mut t = scene!({"hand": ["GIL_506", "GIL_835"], "board": ["GIL_817"], "hero_state": {"damage": 5}}, {"hand": ["GIL_835"]});
    let k = t.nth(0, 0);
    assert!(t.g.e(k).has("DIVINE_SHIELD"));
    t.play("GIL_506", k);
    assert!(!t.g.e(k).has("DIVINE_SHIELD"));
    let me = t.hero(0);
    t.play("GIL_835", me);
    assert!(t.g.e(k).has("DIVINE_SHIELD"), "your heal");
    t.play("GIL_506", k); // the Echo copy breaks it again
    assert!(!t.g.e(k).has("DIVINE_SHIELD"));
    t.end_turn();
    let foe_hero = t.hero(0);
    t.play("GIL_835", foe_hero);
    assert!(!t.g.e(k).has("DIVINE_SHIELD"), "the opponent's heal does not count");
}

#[test]
fn prince_liam_turns_one_cost_cards_of_the_deck_into_legendaries() {
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hand": ["GIL_694"], "deck": [WISP, RAIDER, RAIDER, YETI, "GIL_903"]}, {});
    t.play("GIL_694", NONE);
    let deck: Vec<String> = t.g.players[0].deck.iter().map(|&e| card_of(&t, e)).collect();
    assert_eq!(deck[0], WISP);
    assert_eq!(deck[3], YETI);
    for i in [1, 2, 4] {
        let c = rs.card(&deck[i]);
        assert!(c.rarity == "LEGENDARY" && c.kind == "MINION" && c.collectible, "{} became {}", i, deck[i]);
    }
}

#[test]
fn silver_sword_buffs_your_minions_after_your_hero_attacks() {
    let mut t = scene!({"weapon": "GIL_596", "board": [WISP, YETI]}, {});
    let (a, b) = (t.nth(0, 0), t.nth(0, 1));
    let (h, foe) = (t.hero(0), t.hero(1));
    t.attack(h, foe);
    assert_eq!((t.stats(a), t.stats(b)), ((2, 2), (5, 6)));
    assert_eq!(t.hp(1), 30 - 3);
}

#[test]
fn ghostly_charger_has_rush_and_divine_shield() {
    let mut t = scene!({"hand": ["GIL_545"]}, {"board": [WISP]});
    t.play("GIL_545", NONE);
    let c = t.on_board(0, "GIL_545");
    assert!(t.g.e(c).has("DIVINE_SHIELD"));
    let w = t.nth(1, 0);
    t.attack(c, w);
    assert!(t.g.players[1].board.is_empty(), "Rush: a minion the turn it comes");
}

// --- Priest ---

#[test]
fn chameleos_becomes_a_card_of_the_enemy_hand_each_turn() {
    // the opponent's deck: a Yeti on top, then a Fireball
    let mut t = scene!({"hand": [{"card": "GIL_142", "enchantments": [{"atk": 2, "hp": 2}]}]}, {"hand": [FIREBALL], "deck": [FIREBALL, YETI]});
    t.end_turn(); // the opponent draws the Yeti
    let me = t.hero(0);
    t.play(FIREBALL, me).end_turn();
    // turn 3: the enemy hand is [Yeti]
    assert_eq!(t.hand(0)[0], YETI, "a copy of the only enemy card (before the draw)");
    let e = t.g.players[0].hand[0];
    assert_eq!(t.stats(e), (6, 7), "its buff kept (before patch 12.0)");
    assert_eq!(t.g.e(e).enchantments.len(), 2, "the buff and Shifting");
    t.end_turn();
    t.play(YETI, NONE).end_turn(); // the opponent drew the Fireball and played the Yeti
    assert_eq!(t.hand(0)[0], FIREBALL, "it keeps shifting");
    assert_eq!(t.g.e(t.g.players[0].hand[0]).enchantments.len(), 2, "one Shifting");
    t.end_turn();
    t.play(FIREBALL, me).end_turn(); // the enemy hand is empty now
    assert_eq!(t.hand(0)[0], FIREBALL, "an empty enemy hand: no change");
    assert!(t.events().iter().all(|e| e["type"] != "game_over"));
}

#[test]
fn divine_hymn_restores_six_to_all_friendly_characters() {
    let mut t = scene!({"hand": ["GIL_661"], "board": [{"card": YETI, "damage": 4}], "hero_state": {"damage": 10}}, {"board": [{"card": YETI, "damage": 4}]});
    t.play("GIL_661", NONE);
    let y = t.nth(0, 0);
    assert_eq!(t.stats(y), (4, 5));
    assert_eq!(t.hp(0), 26);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 1), "not the enemy's");
}

#[test]
fn squashling_restores_two_and_echoes() {
    let mut t = scene!({"hand": ["GIL_835"], "hero_state": {"damage": 5}}, {});
    let me = t.hero(0);
    t.play("GIL_835", me);
    assert_eq!(t.hp(0), 27);
    assert_eq!(t.hand(0), vec!["GIL_835"]);
}

#[test]
fn vivid_nightmare_copies_a_friendly_minion_with_one_health() {
    let mut t = scene!({"hand": ["GIL_813", "GIL_145"], "board": [YETI, WISP]}, {});
    let y = t.nth(0, 0);
    t.play("GIL_145", y); // 5/7
    t.play("GIL_813", y);
    assert_eq!(t.cards(0), vec![YETI, WISP, YETI], "at the right end");
    let c = t.nth(0, 2);
    assert_eq!(t.stats(c), (5, 1), "its enchantments, 1 Health left");
    assert_eq!(t.g.e(c).max_health(), 7);
}

#[test]
fn glitter_moth_doubles_health_with_an_odd_deck() {
    let mut t = scene!({"hand": ["GIL_837"], "board": [{"card": YETI, "damage": 1}], "deck": [RAIDER, RAIDER]}, {});
    t.play("GIL_837", NONE);
    let y = t.nth(0, 0);
    assert_eq!(t.stats(y), (4, 8));
    assert_eq!(t.stats(t.on_board(0, "GIL_837")), (4, 4), "not itself");
    let mut t = scene!({"hand": ["GIL_837"], "board": [YETI], "deck": [RAIDER, YETI]}, {});
    t.play("GIL_837", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 5), "an even card in the deck");
}

#[test]
fn holy_water_gives_a_copy_when_it_kills() {
    let mut t = scene!({"hand": ["GIL_134", "GIL_134"]}, {"board": [{"card": YETI, "damage": 1}, YETI]});
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play("GIL_134", a);
    assert_eq!(t.hand(0), vec!["GIL_134", YETI]);
    t.play("GIL_134", b);
    assert_eq!(t.hand(0), vec![YETI], "it lives: nothing");
}

#[test]
fn quartz_elemental_cant_attack_while_damaged() {
    let t = scene!({"board": [{"card": "GIL_156", "damage": 1}, "GIL_156"]}, {});
    let (a, b) = (t.nth(0, 0), t.nth(0, 1));
    let can = |m: Id| t.g.legal_actions().iter().any(|x| x["type"] == "attack" && int(x.get("attacker")) == m);
    assert!(!can(a) && can(b));
}

#[test]
fn coffin_crasher_summons_a_deathrattle_minion_from_hand() {
    let mut t = scene!({"hand": [FIREBALL, YETI, HOARDER], "board": [WISP, "GIL_805", WISP]}, {});
    let c = t.nth(0, 1);
    t.play(FIREBALL, c);
    assert_eq!(t.cards(0), vec![WISP, HOARDER, WISP], "where it died");
    assert_eq!(t.hand(0), vec![YETI]);
}

#[test]
fn lady_in_white_sets_attack_to_health_in_the_deck() {
    let mut t = scene!({"hand": ["GIL_840"], "deck": [YETI, FIREBALL, "GIL_190"]}, {});
    t.play("GIL_840", NONE);
    let y = deck_of(&t, 0, YETI)[0];
    let m = deck_of(&t, 0, "GIL_190")[0];
    assert_eq!((t.stats(y), t.stats(m)), ((5, 5), (9, 9)));
    assert_eq!(t.stats(t.on_board(0, "GIL_840")), (5, 5), "not itself");
}

#[test]
fn nightscale_matriarch_summons_a_whelp_when_a_friendly_minion_is_healed() {
    let mut t = scene!({"hand": ["GIL_835", "GIL_661"], "board": ["GIL_190", {"card": YETI, "damage": 2}, {"card": WISP}], "hero_state": {"damage": 5}}, {});
    let me = t.hero(0);
    t.play("GIL_835", me);
    assert_eq!(t.cards(0).len(), 4, "the hero: no Whelp (the Squashling only)");
    let y = t.nth(0, 1);
    t.play("GIL_835", y); // the Echo copy heals the Yeti
    assert_eq!(t.cards(0), vec!["GIL_190", WHELP, YETI, WISP, "GIL_835", "GIL_835"]);
    assert_eq!(t.stats(t.nth(0, 1)), (3, 3));
}

// --- Rogue ---

#[test]
fn cheap_shot_deals_two_and_echoes() {
    let mut t = scene!({"hand": ["GIL_506"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("GIL_506", y).play("GIL_506", y);
    assert_eq!(t.stats(y), (4, 1));
    assert_eq!(t.hand(0), vec!["GIL_506"]);
}

#[test]
fn pick_pocket_and_blink_fox_give_cards_of_the_opponents_class() {
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hand": ["GIL_696", "GIL_827"]}, {});
    t.play("GIL_696", NONE).play("GIL_827", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 3, "two cards and the Echo copy");
    let warrior: Vec<&String> = h.iter().filter(|c| *c != "GIL_696").collect();
    assert_eq!(warrior.len(), 2);
    for c in warrior {
        let x = rs.card(c);
        assert!(x.card_class == "WARRIOR" || x.classes.iter().any(|k| k == "WARRIOR"), "{c}");
    }
}

#[test]
fn cutthroat_buccaneer_combo_buffs_the_weapon() {
    let mut t = scene!({"weapon": AXE, "hand": ["GIL_902", WISP, "GIL_902"]}, {});
    t.play("GIL_902", NONE);
    let w = weapon(&t, 0);
    assert_eq!(t.g.e(w).atk(), 3, "no combo");
    t.play(WISP, NONE).play("GIL_902", NONE);
    assert_eq!(t.g.e(w).atk(), 4);
}

#[test]
fn face_collector_gives_a_legendary_minion() {
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hand": ["GIL_677"]}, {});
    t.play("GIL_677", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    assert_eq!(h[1], "GIL_677", "the Echo copy last");
    let c = rs.card(&h[0]);
    assert!(c.rarity == "LEGENDARY" && c.kind == "MINION" && c.collectible, "{}", h[0]);
}

#[test]
fn mistwraith_grows_when_you_play_echo_cards() {
    let mut t = scene!({"hand": ["GIL_506", WISP], "board": ["GIL_510"]}, {"board": [YETI]});
    let m = t.nth(0, 0);
    let y = t.nth(1, 0);
    t.play("GIL_506", y).play("GIL_506", y);
    assert_eq!(t.stats(m), (5, 7), "the card and its copy");
    t.play(WISP, NONE);
    assert_eq!(t.stats(m), (5, 7));
}

#[test]
fn spectral_cutlass_gains_durability_for_cards_of_another_class() {
    // a Mage plays a Rogue card (Cheap Shot): another class; a Mage card and a neutral one: not
    let mut t = scene!({"weapon": "GIL_672", "hand": [FIREBALL, WISP, "GIL_506"], "hero_state": {"damage": 10}}, {"board": [YETI]});
    let w = weapon(&t, 0);
    let foe = t.hero(1);
    t.play(FIREBALL, foe).play(WISP, NONE);
    assert_eq!(t.g.e(w).tag("DURABILITY"), 2);
    let y = t.nth(1, 0);
    t.play("GIL_506", y);
    assert_eq!(t.g.e(w).tag("DURABILITY"), 3);
    let h = t.hero(0);
    t.attack(h, foe);
    assert_eq!(t.hp(0), 20 + 2, "Lifesteal");
}

#[test]
fn wanted_gives_a_coin_when_it_kills() {
    let mut t = scene!({"hand": ["GIL_687", "GIL_687"]}, {"board": [{"card": YETI, "damage": 2}, YETI]});
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play("GIL_687", a);
    assert_eq!(t.hand(0), vec!["GIL_687", "GAME_005"]);
    t.play("GIL_687", b);
    assert_eq!(t.hand(0), vec!["GAME_005"]);
}

#[test]
fn cursed_castaway_draws_a_combo_card() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["GIL_557"], "deck": [YETI, "GIL_902", WISP]}, {});
    let c = t.nth(0, 0);
    t.play(FIREBALL, c);
    assert_eq!(t.hand(0), vec!["GIL_902"]);
}

#[test]
fn tess_replays_the_cards_of_other_classes() {
    let mut t = scene!({"hero": "HERO_03", "hand": [FIREBALL, WATER_ELEMENTAL, WISP, "GIL_506", AXE, "GIL_598"]}, {"board": [YETI]});
    let foe = t.hero(1);
    t.play(FIREBALL, foe).play(WATER_ELEMENTAL, NONE).play(WISP, NONE);
    t.end_turn().end_turn();
    let y = t.nth(1, 0);
    t.play(AXE, NONE).play("GIL_506", y);
    let axe = weapon(&t, 0);
    t.end_turn().end_turn();
    t.play("GIL_598", NONE);
    let summons = |c: &str| t.events().iter().filter(|e| e["type"] == "summon" && e["card"] == c).count();
    assert_eq!(summons(WISP), 1, "not the neutral one");
    assert_eq!(summons(WATER_ELEMENTAL), 2, "the Mage minion again (summoned)");
    let casts: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "cast").collect();
    assert_eq!(casts.len(), 1, "the Fireball once (not the Rogue spell)");
    assert_eq!(casts[0]["card"], FIREBALL);
    assert_eq!(card_of(&t, weapon(&t, 0)), AXE, "the Warrior weapon equipped again");
    assert_ne!(weapon(&t, 0), axe, "a new Axe");
}
