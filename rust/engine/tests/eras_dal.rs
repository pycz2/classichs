//! packs/eras, the versions of Rise of Shadows' time (29933, 30103, 30795, 31022, 31268, 31761): each version patch's
//! changes as the engine plays them, against the version before. Needs python3 (skipped without it).

#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

const KALECGOS: &str = "DAL_609";
const COUNTERSPELL: &str = "VAN_EX1_287";
const FORESTS_AID: &str = "DAL_256";
const PREPARATION: &str = "VAN_EX1_145";
const RECKLESS: &str = "BOT_566";
const LOOT_HOARDER: &str = "VAN_EX1_096"; // 2 mana, Deathrattle
const SYLVANAS: &str = "VAN_EX1_016"; // 6 mana, Deathrattle
const FULL: [&str; 7] = [WISP, WISP, WISP, WISP, WISP, WISP, WISP];

#[test]
fn patch_29933_and_30103_are_the_rise_of_shadows_pack() {
    let Some(_) = eras() else { return };
    for vid in ["29933", "30103"] {
        assert_eq!(stats(vid, "DAL_415").unwrap().2, 5, "{vid}: EVIL Miscreant before its nerf");
        assert_eq!(stats(vid, "BOT_433").unwrap().0, 8, "{vid}: Dr. Morrigan before Rise of the Mech");
    }
}

/// Frostbolt's cost after a Fireball countered with Kalecgos in play.
fn kalecgos_after_counter(vid: &str) -> Option<i64> {
    let mut t = game(vid, json!({"hand": [FIREBALL, FROSTBOLT], "board": [KALECGOS]}), json!({"secrets": [COUNTERSPELL]}))?;
    assert_eq!(t.cost(FIREBALL), 0, "{vid}: the first spell is free");
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.hp(1), 30, "{vid}: countered");
    Some(t.cost(FROSTBOLT))
}

#[test]
fn a_countered_spell_uses_kalecgos_up_from_30795() {
    let Some(before) = kalecgos_after_counter("30103") else { return };
    assert_eq!(before, 0, "30103: the next spell is still free");
    for vid in ["30795", "31022", "31268", "31761"] {
        assert_eq!(kalecgos_after_counter(vid), Some(2), "{vid}");
    }
}

#[test]
fn the_forests_aid_needs_a_free_slot_from_30795() {
    let t = scene!("30103", {"hand": [FORESTS_AID], "board": FULL}, {});
    assert!(t.can_play(FORESTS_AID));
    for vid in ["30795", "31761"] {
        let t = scene!(vid, {"hand": [FORESTS_AID], "board": FULL}, {});
        assert!(!t.can_play(FORESTS_AID), "{vid}");
        let mut t = scene!(vid, {"hand": [FORESTS_AID], "board": [WISP]}, {});
        t.play(FORESTS_AID, NONE);
        assert_eq!(t.cards(0).len(), 6, "{vid}: five Treants");
    }
}

fn fireball_after_preparation(vid: &str) -> Option<i64> {
    let mut t = game(vid, json!({"hand": [PREPARATION, FIREBALL]}), json!({}))?;
    t.play(PREPARATION, NONE);
    Some(t.cost(FIREBALL))
}

#[test]
fn patch_31022_nerfs_preparation_raiding_party_evil_miscreant_and_elysiana() {
    let Some(_) = eras() else { return };
    assert_eq!(fireball_after_preparation("30795"), Some(1));
    for vid in ["31022", "31268", "31761"] {
        assert_eq!(fireball_after_preparation(vid), Some(2), "{vid}");
        assert_eq!(stats(vid, "TRL_124").unwrap().0, 4, "{vid}: Raiding Party");
        assert_eq!(stats(vid, "DAL_415").unwrap().2, 4, "{vid}: EVIL Miscreant");
        assert_eq!(stats(vid, "DAL_736").unwrap().0, 9, "{vid}: Archivist Elysiana");
    }
    assert_eq!(stats("30795", "TRL_124").unwrap().0, 3);
    assert_eq!(stats("30795", "DAL_736").unwrap().0, 8);
}

#[test]
fn patch_31268_buffs_the_boomsday_cards() {
    let Some(_) = eras() else { return };
    // (card, which of cost/attack/health, before, after)
    let buffs = [
        ("BOT_039", 0, 5, 4),
        ("BOT_084", 0, 3, 2),
        ("BOT_218", 2, 5, 6),
        ("BOT_219", 0, 3, 2),
        ("BOT_219t", 0, 3, 2),
        ("BOT_222", 0, 2, 1),
        ("BOT_237", 1, 3, 4),
        ("BOT_245", 0, 7, 6),
        ("BOT_254", 0, 4, 3),
        ("BOT_257", 0, 7, 5),
        ("BOT_283", 0, 2, 1),
        ("BOT_407", 2, 5, 6),
        ("BOT_429", 0, 8, 7),
        ("BOT_433", 0, 8, 6),
        ("BOT_435", 0, 2, 1),
        ("BOT_507", 0, 8, 7),
        ("BOT_523", 0, 10, 9),
        ("BOT_909", 0, 2, 1),
        ("BOT_910", 0, 6, 5),
    ];
    let field = |vid: &str, id: &str, i: usize| {
        let (c, a, h) = stats(vid, id).unwrap();
        [c, a, h][i]
    };
    for (id, i, before, after) in buffs {
        assert_eq!(field("31022", id, i), before, "{id} in 31022");
        assert_eq!(field("31268", id, i), after, "{id} in 31268");
        assert_eq!(field("31761", id, i), after, "{id} in 31761");
    }
}

fn reckless_costs(vid: &str) -> Option<(i64, i64)> {
    let t = game(vid, json!({"hand": [LOOT_HOARDER, SYLVANAS], "board": [RECKLESS]}), json!({}))?;
    Some((t.cost(LOOT_HOARDER), t.cost(SYLVANAS)))
}

#[test]
fn reckless_experimenter_stops_at_1_from_31268() {
    let Some(before) = reckless_costs("31022") else { return };
    assert_eq!(before, (0, 3));
    assert_eq!(reckless_costs("31268"), Some((1, 3)));
    assert_eq!(reckless_costs("31761"), Some((1, 3)));
    // the minion played still dies at the end of the turn
    let mut t = scene!("31268", {"hand": [LOOT_HOARDER], "board": [RECKLESS]}, {});
    t.play(LOOT_HOARDER, NONE);
    assert!(t.has(0, LOOT_HOARDER));
    t.end_turn();
    assert!(!t.has(0, LOOT_HOARDER));
}

#[test]
fn multi_target_spells_need_one_enemy_minion_from_31761() {
    for card in ["VAN_CS2_114", "VAN_DS1_183", "VAN_EX1_251", "AT_025"] {
        let t = scene!("31268", {"hand": [card]}, {"board": [YETI]});
        assert!(!t.can_play(card), "{card} in 31268");
        let t = scene!("31761", {"hand": [card]}, {});
        assert!(!t.can_play(card), "{card} in 31761 without an enemy minion");
        let mut t = scene!("31761", {"hand": [card]}, {"board": [YETI]});
        t.play(card, NONE);
        let hit = t.cards(1).is_empty() || t.stats(t.on_board(1, YETI)).1 < 5;
        assert!(hit, "{card} hit the only enemy minion");
    }
}

#[test]
fn full_board_checks_from_31761() {
    for card in ["DAL_007", "DAL_733"] {
        assert!(scene!("31268", {"hand": [card], "board": FULL}, {}).can_play(card), "{card} in 31268");
        assert!(!scene!("31761", {"hand": [card], "board": FULL}, {}).can_play(card), "{card} in 31761");
        let mut t = scene!("31761", {"hand": [card]}, {});
        t.play(card, NONE);
        assert!(!t.cards(0).is_empty(), "{card} summons");
    }
    let duel = "DAL_731";
    assert!(scene!("31268", {"hand": [duel], "board": FULL}, {"board": FULL}).can_play(duel));
    assert!(!scene!("31761", {"hand": [duel], "board": FULL}, {"board": FULL}).can_play(duel));
    assert!(scene!("31761", {"hand": [duel], "board": FULL}, {}).can_play(duel), "one side has room");
}
