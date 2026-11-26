//! packs/eras, the versions of Rastakhan's Rumble's time (27845, 28116, 28329, 28855, 29349): each version patch's
//! changes as the engine plays them, against the version before. Needs python3 (skipped without it).

#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

const BLOOD: &str = "TRL_541t";
const KOBOLD: &str = "VAN_CS2_142"; // Kobold Geomancer, Spell Damage +1

/// Corrupted Blood drawn by player 1 with a Kobold Geomancer on its board: the damage it takes.
fn blood_damage(vid: &str) -> Option<i64> {
    let mut t = game(vid, json!({}), json!({"board": [KOBOLD], "deck": [YETI, BLOOD]}))?;
    t.end_turn();
    assert_eq!(t.hand(1), vec![YETI], "{vid}: the Blood casts, the player draws on");
    Some(30 - t.hp(1))
}

#[test]
fn corrupted_blood_takes_spell_damage_until_28855() {
    let Some(_) = eras() else { return };
    for vid in ["27845", "28116", "28329"] {
        assert_eq!(blood_damage(vid), Some(4), "{vid}");
    }
    for vid in ["28855", "29349"] {
        assert_eq!(blood_damage(vid), Some(3), "{vid}");
    }
}

/// Astromancer played at the left of two Wisps with two cards left in the hand: where its minion comes.
fn astromancer_summons_at(vid: &str) -> Option<usize> {
    let mut t = game(vid, json!({"hand": ["BOT_256", FIREBALL, FROSTBOLT], "board": [WISP, WISP]}), json!({}))?;
    let e = t.hand_id("BOT_256");
    t.act("play Astromancer at the left", |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("pos")) == 0);
    let cards = t.cards(0);
    assert_eq!(cards.len(), 4, "{vid}: {cards:?}");
    assert_eq!(cards[0], "BOT_256");
    Some(cards.iter().position(|c| c != WISP && c != "BOT_256").unwrap())
}

#[test]
fn astromancer_summons_next_to_her_from_29349() {
    let Some(_) = eras() else { return };
    for vid in ["27845", "28116", "28329", "28855"] {
        assert_eq!(astromancer_summons_at(vid), Some(3), "{vid}: the far right");
    }
    assert_eq!(astromancer_summons_at("29349"), Some(1));
}

#[test]
fn patch_28329_nerfs_wild_growth_nourish_and_level_up() {
    let Some(_) = eras() else { return };
    for (id, old, new) in [("VAN_CS2_013", 2, 3), ("VAN_EX1_164", 5, 6), ("LOOT_333", 5, 6), ("ICC_221", 2, 1)] {
        assert_eq!(stats("28116", id).unwrap().0, old, "{id}");
        for vid in ["28329", "28855", "29349"] {
            assert_eq!(stats(vid, id).unwrap().0, new, "{vid} {id}");
        }
    }
}

/// Leeching Poison, an attack, the next turn another attack: the hero's Health after each.
fn leeching(vid: &str) -> Option<(i64, i64)> {
    let mut t = game(vid, json!({"hero": "HERO_03", "damage": 10, "weapon": "VAN_CS2_080", "hand": ["ICC_221"]}), json!({}))?;
    t.play("ICC_221", NONE);
    t.attack(t.hero(0), t.hero(1)); // Assassin's Blade: 3
    let first = t.hp(0);
    t.end_turn().end_turn();
    t.attack(t.hero(0), t.hero(1));
    Some((first, t.hp(0)))
}

#[test]
fn leeching_poison_lasts_one_turn_from_28329() {
    let Some(_) = eras() else { return };
    assert_eq!(leeching("28116"), Some((23, 26)));
    for vid in ["28329", "28855", "29349"] {
        assert_eq!(leeching(vid), Some((23, 23)), "{vid}");
    }
}

/// Saronite Chain Gang played with +2 Attack from the hand: the minion its Battlecry summons.
fn chain_gang(vid: &str) -> Option<(i64, i64)> {
    let mut t = game(vid, json!({"hand": [{"card": "ICC_466", "enchantments": [{"atk": 2}]}]}), json!({}))?;
    t.play("ICC_466", NONE);
    let b = t.g.players[0].board.clone();
    assert_eq!(b.len(), 2, "{vid}");
    assert_eq!(t.stats(b[0]), (4, 3), "{vid}: the one played");
    Some(t.stats(b[1]))
}

#[test]
fn saronite_chain_gang_summons_a_fresh_one_from_28329() {
    let Some(_) = eras() else { return };
    assert_eq!(chain_gang("28116"), Some((4, 3)), "a copy with the buff");
    for vid in ["28329", "28855", "29349"] {
        assert_eq!(chain_gang(vid), Some((2, 3)), "{vid}");
    }
}

#[test]
fn patch_28855_nerfs_cold_blood_hunters_mark_flametongue_equality_and_the_spellstones() {
    let Some(_) = eras() else { return };
    for (id, old, new) in [("VAN_CS2_073", 1, 2), ("VAN_CS2_084", 1, 2), ("VAN_EX1_565", 2, 3), ("VAN_EX1_619", 2, 4),
        ("LOOT_080", 5, 6), ("LOOT_080t2", 5, 6), ("LOOT_080t3", 5, 6), ("AT_132_SHAMANa", 0, 1)]
    {
        assert_eq!(stats("28329", id).unwrap().0, old, "{id}");
        for vid in ["28855", "29349"] {
            assert_eq!(stats(vid, id).unwrap().0, new, "{vid} {id}");
        }
    }
    // only the costs changed: Flametongue Totem still gives +2 Attack
    let mut t = scene!("28855", {"hand": ["VAN_EX1_565"], "board": [WISP]}, {});
    t.play("VAN_EX1_565", NONE);
    let w = t.on_board(0, WISP);
    assert_eq!(t.stats(w), (3, 1));
}

/// Big Bad Voodoo on a 12-Cost Mountain Giant (no minion costs 13) that then dies: what is summoned.
fn voodoo(vid: &str) -> Option<Vec<String>> {
    let mut t = game(vid, json!({"hand": ["TRL_082", FIREBALL], "board": [{"card": "VAN_EX1_105", "damage": 7}]}), json!({}))?;
    let d = t.on_board(0, "VAN_EX1_105");
    t.play("TRL_082", d);
    t.play(FIREBALL, d);
    Some(t.cards(0))
}

#[test]
fn big_bad_voodoo_falls_back_to_the_same_cost_from_29349() {
    let Some(_) = eras() else { return };
    assert_eq!(voodoo("28855"), Some(vec![]));
    let after = voodoo("29349").unwrap();
    assert_eq!(after.len(), 1);
    assert_eq!(version("29349").unwrap().card(&after[0]).cost, 12, "{after:?}");
}

/// Gral, the Shark eating a Chillwind Yeti buffed +2/+2 in the deck: Gral's stats.
fn gral(vid: &str) -> Option<(i64, i64)> {
    let mut t = game(vid, json!({"hand": ["TRL_409"], "deck": [{"card": YETI, "enchantments": [{"atk": 2, "hp": 2}]}]}), json!({}))?;
    t.play("TRL_409", NONE);
    Some(t.stats(t.on_board(0, "TRL_409")))
}

#[test]
fn gral_gains_the_buffed_stats_from_29349() {
    let Some(_) = eras() else { return };
    let (_, a, h) = stats("29349", "TRL_409").unwrap();
    assert_eq!(gral("28855"), Some((a + 4, h + 5)));
    assert_eq!(gral("29349"), Some((a + 6, h + 7)));
}
