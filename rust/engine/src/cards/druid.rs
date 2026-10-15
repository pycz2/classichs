//! Druid cards and their Choose One options (cards/druid.gd). Option order follows the card text.

use super::*;
use crate::state::MAX_MANA;
use serde_json::json;

fn hero_attack(g: &mut Game, me: Id, n: i64, armor: i64) {
    g.buff(g.hero(g.ctrl(me)), n, 0, true);
    g.gain_armor(g.ctrl(me), armor);
}

fn taunt_buff(g: &mut Game, t: Id, atk: i64, hp: i64) {
    g.buff(t, atk, hp, false);
    g.em(t).give_tag("TAUNT", false);
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_EX1_169", Hooks { // Innervate
        spell: Some(|g, me, _| {
            let c = g.ctrl(me);
            let p = &mut g.players[c];
            p.mana = MAX_MANA.min(p.mana + 2);
        }),
        ..d()
    });
    r.insert("VAN_CS2_008", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 1)); }), ..d() }); // Moonfire
    r.insert("VAN_CS2_005", Hooks { spell: Some(|g, me, _| hero_attack(g, me, 2, 2)), ..d() }); // Claw
    r.insert("VAN_EX1_570", Hooks { spell: Some(|g, me, _| hero_attack(g, me, 4, 4)), ..d() }); // Bite
    r.insert("VAN_EX1_161", Hooks { // Naturalize
        target: MINION,
        spell: Some(|g, me, t| {
            g.destroy(t);
            g.draw(g.foe(me), 2);
        }),
        ..d()
    });
    r.insert("VAN_EX1_578", Hooks { // Savagery
        target: MINION,
        spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, g.hero_atk(g.hero(g.ctrl(me))))); }),
        ..d()
    });
    r.insert("VAN_CS2_009", Hooks { target: MINION, spell: Some(|g, _, t| taunt_buff(g, t, 2, 2)), ..d() }); // Mark of the Wild
    r.insert("VAN_EX1_160", Hooks { choose_one: Some(["VAN_EX1_160b", "VAN_EX1_160a"]), ..d() }); // Power of the Wild
    r.insert("VAN_EX1_160b", Hooks { // Leader of the Pack
        effect: Some(|g, me, _| {
            for m in g.minions(g.ctrl(me)) {
                g.buff(m, 1, 1, false);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_160a", Hooks { effect: Some(|g, me, _| { g.summon(g.ctrl(me), "EX1_160t", -1); }), ..d() }); // Summon a Panther
    r.insert("VAN_CS2_013", Hooks { // Wild Growth: at 10 crystals, Excess Mana instead.
        spell: Some(|g, me, _| {
            let p = g.ctrl(me);
            if g.players[p].max_mana >= MAX_MANA {
                g.add_to_hand(p, "CS2_013t");
            } else {
                g.gain_mana(p, 1, true);
            }
        }),
        ..d()
    });
    r.insert("CS2_013t", Hooks { spell: Some(|g, me, _| { g.draw(g.ctrl(me), 1); }), ..d() }); // Excess Mana
    r.insert("VAN_EX1_154", Hooks { choose_one: Some(["VAN_EX1_154a", "VAN_EX1_154b"]), ..d() }); // Wrath
    r.insert("VAN_EX1_154a", Hooks { target: MINION, effect: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 3)); }), ..d() }); // Solar Wrath
    r.insert("VAN_EX1_154b", Hooks { // Nature's Wrath
        target: MINION,
        effect: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 1));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_CS2_007", Hooks { target: ANY, spell: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 8)); }), ..d() }); // Healing Touch
    r.insert("VAN_EX1_155", Hooks { choose_one: Some(["VAN_EX1_155a", "VAN_EX1_155b"]), ..d() }); // Mark of Nature
    r.insert("VAN_EX1_155a", Hooks { target: MINION, effect: Some(|g, _, t| g.buff(t, 4, 0, false)), ..d() }); // Tiger's Fury
    r.insert("VAN_EX1_155b", Hooks { target: MINION, effect: Some(|g, _, t| taunt_buff(g, t, 0, 4)), ..d() }); // Thick Hide
    r.insert("VAN_CS2_011", Hooks { // Savage Roar
        spell: Some(|g, me, _| {
            for c in g.chars(g.ctrl(me)) {
                g.buff(c, 2, 0, true);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_166", Hooks { choose_one: Some(["VAN_EX1_166a", "VAN_EX1_166b"]), ..d() }); // Keeper of the Grove
    r.insert("VAN_EX1_166a", Hooks { target: ANY, effect: Some(|g, me, t| { g.damage(me, t, 2); }), ..d() }); // Moonfire
    r.insert("VAN_EX1_166b", Hooks { target: MINION, effect: Some(|g, _, t| g.silence(t)), ..d() }); // Dispel
    r.insert("VAN_EX1_158", Hooks { // Soul of the Forest
        spell: Some(|g, me, _| {
            for m in g.minions(g.ctrl(me)) {
                g.em(m).add_enchant(json!({"hooks": "ench:soul_of_the_forest"}));
            }
        }),
        ..d()
    });
    r.insert("ench:soul_of_the_forest", Hooks {
        deathrattle: Some(|g, me| { g.summon(g.ctrl(me), "VAN_EX1_tk9", g.died_pos(me)); }),
        ..d()
    });
    r.insert("VAN_CS2_012", Hooks { // Swipe
        target: ENEMY_CHAR,
        spell: Some(|g, me, t| {
            let others: Vec<Id> = g.chars(g.ctrl(t)).into_iter().filter(|&c| c != t).collect();
            g.damage(me, t, g.spell_dmg(me, 4));
            for c in others {
                g.damage(me, c, g.spell_dmg(me, 1));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_165", Hooks { choose_one: Some(["VAN_EX1_165a", "VAN_EX1_165b"]), ..d() }); // Druid of the Claw
    r.insert("VAN_EX1_165a", Hooks { effect: Some(|g, me, _| { g.transform(me, "VAN_EX1_165t1"); }), ..d() }); // Cat Form
    r.insert("VAN_EX1_165b", Hooks { effect: Some(|g, me, _| { g.transform(me, "VAN_EX1_165t2"); }), ..d() }); // Bear Form
    r.insert("VAN_EX1_164", Hooks { choose_one: Some(["VAN_EX1_164a", "VAN_EX1_164b"]), ..d() }); // Nourish
    r.insert("VAN_EX1_164a", Hooks { effect: Some(|g, me, _| g.gain_mana(g.ctrl(me), 2, false)), ..d() }); // Rampant Growth
    r.insert("VAN_EX1_164b", Hooks { effect: Some(|g, me, _| { g.draw(g.ctrl(me), 3); }), ..d() }); // Enrich
    r.insert("VAN_NEW1_007", Hooks { choose_one: Some(["VAN_NEW1_007b", "VAN_NEW1_007a"]), ..d() }); // Starfall
    r.insert("VAN_NEW1_007b", Hooks { target: MINION, effect: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 5)); }), ..d() }); // Starlord
    r.insert("VAN_NEW1_007a", Hooks { // Stellar Drift
        effect: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, g.spell_dmg(me, 2));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_571", Hooks { // Force of Nature
        spell: Some(|g, me, _| {
            for _ in 0..3 {
                g.summon(g.ctrl(me), "VAN_EX1_tk9b", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_tk9b", Hooks { on: vec![("turn_end", |g, me, _| g.destroy(me))], ..d() }); // Treant: destroyed at the end of the turn.
    r.insert("VAN_EX1_173", Hooks { // Starfire
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 5));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_008", Hooks { choose_one: Some(["VAN_NEW1_008a", "VAN_NEW1_008b"]), ..d() }); // Ancient of Lore
    r.insert("VAN_NEW1_008a", Hooks { effect: Some(|g, me, _| { g.draw(g.ctrl(me), 2); }), ..d() }); // Ancient Teachings
    r.insert("VAN_NEW1_008b", Hooks { target: ANY, effect: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 5)); }), ..d() }); // Ancient Secrets
    r.insert("VAN_EX1_178", Hooks { choose_one: Some(["VAN_EX1_178b", "VAN_EX1_178a"]), ..d() }); // Ancient of War
    r.insert("VAN_EX1_178b", Hooks { effect: Some(|g, me, _| g.buff(me, 5, 0, false)), ..d() }); // Uproot
    r.insert("VAN_EX1_178a", Hooks { effect: Some(|g, me, _| taunt_buff(g, me, 0, 5)), ..d() }); // Rooted
    r.insert("VAN_EX1_573", Hooks { choose_one: Some(["VAN_EX1_573a", "VAN_EX1_573b"]), ..d() }); // Cenarius
    r.insert("VAN_EX1_573a", Hooks { // Demigod's Favor
        effect: Some(|g, me, _| {
            for m in g.others(me) {
                g.buff(m, 2, 2, false);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_573b", Hooks { // Shan'do's Lesson: Treants with Taunt on both sides.
        effect: Some(|g, me, _| {
            let right = g.summon_right(me, "VAN_EX1_tk9");
            let pos = g.board_pos(me).map_or(-1, |i| i as i64);
            let left = g.summon(g.ctrl(me), "VAN_EX1_tk9", pos);
            for t in [right, left] {
                if t != crate::entity::NONE {
                    g.em(t).give_tag("TAUNT", false);
                }
            }
        }),
        ..d()
    });
}
