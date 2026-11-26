//! packs/eras, the versions of The Boomsday Project's time (25770, 26996, 27358, 27405): each version patch's changes
//! as the engine plays them, against the version before. Needs python3 (skipped without it).

#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

const SHADOWBOXER: &str = "GVG_072";
const VOODOO_DOCTOR: &str = "VAN_EX1_011"; // Battlecry: restore 2 Health
const BOMB: &str = "BOT_511t";
const NEW_CLASSIC: [&str; 4] = ["EX1_179", "EX1_180", "EX1_181", "EX1_182"];

#[test]
fn patch_25770_is_the_boomsday_pack_where_shadowboxer_sees_only_minions_healed() {
    let Some(rs) = version("25770") else { return };
    assert_eq!(stats("25770", "BOT_270"), Some((5, 2, 1)), "Giggling Inventor before its nerf");
    assert!(NEW_CLASSIC.iter().all(|id| !rs.cards.contains_key(*id)));
    // healing the hero: nothing (patch 12.0.0.25770: "Whenever a minion is healed")
    let mut t = scene!("25770", {"hand": [VOODOO_DOCTOR, VOODOO_DOCTOR], "board": [SHADOWBOXER, {"card": YETI, "damage": 3}], "damage": 5}, {});
    let me = t.hero(0);
    t.play(VOODOO_DOCTOR, me);
    assert_eq!((t.hp(0), t.hp(1)), (27, 30));
    let yeti = t.on_board(0, YETI);
    t.play(VOODOO_DOCTOR, yeti);
    assert_eq!(t.hp(1), 29, "a minion healed: 1 damage to the only enemy");
}

#[test]
fn patch_26996_rewords_casts_when_drawn_and_the_bomb_still_draws_another_card() {
    let Some(_) = eras() else { return };
    assert_eq!(version("26996").unwrap().card(BOMB).keywords, version("25770").unwrap().card(BOMB).keywords);
    let mut t = scene!("26996", {}, {"deck": [BOMB, WISP, BOMB], "hand": []});
    t.end_turn();
    assert_eq!(t.hp(1), 25, "the Bomb went off");
    assert_eq!(t.hand(1), vec![WISP.to_string()], "and the card after it was drawn");
}

#[test]
fn patch_26996_the_darkness_no_longer_advances_jungle_giants() {
    let progress = |v: &str| -> Option<Vec<i64>> {
        let mut t = game(v, json!({"hand": ["UNG_116", "LOOT_526", "VAN_EX1_028"]}), json!({}))?;
        t.play("UNG_116", NONE).play("LOOT_526", NONE);
        let q = t.g.players[0].secrets[0];
        let after_darkness = t.g.e(q).tag("QUEST_PROGRESS");
        t.play("VAN_EX1_028", NONE); // Stranglethorn Tiger, 5/5
        Some(vec![after_darkness, t.g.e(q).tag("QUEST_PROGRESS")])
    };
    let Some(old) = progress("25770") else { return };
    assert_eq!(old, vec![1, 2], "25770 (the boom pack): The Darkness counted");
    // every later version too (the trl and dal packs leave The Darkness out themselves)
    for v in ["26996", "27358", "27405", "27845", "28116", "28329", "28855", "29349", "29933", "30103", "30795", "31022",
        "31268", "31761"] {
        assert_eq!(progress(v), Some(vec![0, 1]), "{v}");
    }
}

#[test]
fn patch_27358_nerfs_giggling_inventor_mana_wyrm_and_aviana() {
    let Some(_) = eras() else { return };
    assert_eq!(stats("26996", "BOT_270"), Some((5, 2, 1)));
    assert_eq!(stats("27358", "BOT_270"), Some((7, 2, 1)));
    assert_eq!(stats("26996", "VAN_NEW1_012"), Some((1, 1, 3)));
    assert_eq!(stats("27358", "VAN_NEW1_012"), Some((2, 1, 3)));
    assert_eq!(stats("26996", "AT_045"), Some((9, 5, 5)));
    assert_eq!(stats("27358", "AT_045"), Some((10, 5, 5)));
    let t = scene!("27358", {"hand": ["VAN_NEW1_012"]}, {});
    assert_eq!(t.cost("VAN_NEW1_012"), 2);
}

#[test]
fn patch_27405_adds_icicle_tome_of_intellect_call_of_the_void_and_pilfer() {
    let Some(rs) = version("27405") else { return };
    assert!(NEW_CLASSIC.iter().all(|id| !version("27358").unwrap().cards.contains_key(*id)));
    for id in NEW_CLASSIC {
        let c = rs.card(id);
        assert!(c.collectible, "{id}");
        assert_eq!(c.set, "VANILLA", "{id}");
    }
    assert_eq!(stats("27405", "EX1_179"), Some((2, 0, 0)));
    assert_eq!(stats("27405", "BOT_270"), Some((7, 2, 1)), "27358's nerfs stay");

    // Icicle: 2 damage; a Frozen minion: draw a card too
    let mut t = scene!("27405", {"hand": ["EX1_179", "EX1_179"], "deck": [WISP, WISP, WISP]}, {"board": [{"card": YETI, "tags": ["FROZEN"]}, YETI]});
    let frozen = t.g.players[1].board[0];
    let warm = t.g.players[1].board[1];
    t.play("EX1_179", warm);
    assert_eq!((t.stats(warm), t.hand(0).len()), ((4, 3), 1));
    t.play("EX1_179", frozen);
    assert_eq!((t.stats(frozen), t.hand(0).len()), ((4, 3), 1), "the drawn card replaces the Icicle");

    // Tome of Intellect: a Mage spell; Call of the Void: a Demon; Pilfer: a card of the opponent's class (Warrior)
    let mut t = scene!("27405", {"hand": ["EX1_180", "EX1_181", "EX1_182"]}, {});
    t.play("EX1_180", NONE).play("EX1_181", NONE).play("EX1_182", NONE);
    let got: Vec<_> = t.hand(0).iter().map(|id| rs.card(id)).collect();
    assert_eq!(got.len(), 3);
    assert_eq!((got[0].kind.as_str(), got[0].card_class.as_str()), ("SPELL", "MAGE"));
    assert_eq!((got[1].kind.as_str(), got[1].race.as_str()), ("MINION", "DEMON"));
    assert!(got[2].card_class == "WARRIOR" || got[2].classes.iter().any(|c| c == "WARRIOR"), "{}", got[2].id);
}
