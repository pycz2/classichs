//! Warlock cards and their tokens (cards/warlock.gd).

use super::*;
use crate::card_db;
use crate::entity::NONE;
use serde_json::json;

fn is_demon(g: &Game, _me: Id, t: Id) -> bool {
    g.e(t).race() == "DEMON"
}

/// Damage, then true if the target is now dying (Mortal Coil, Bane of Doom).
fn kills(g: &mut Game, me: Id, t: Id, amount: i64) -> bool {
    g.damage(me, t, amount);
    g.e(t).zone == "PLAY" && g.e(t).health() <= 0
}

fn collectible_demons() -> Vec<&'static str> {
    card_db::collectible()
        .iter()
        .filter(|id| {
            let c = card_db::card(id);
            c.kind == "MINION" && c.race == "DEMON"
        })
        .map(|s| s.as_str())
        .collect()
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_NEW1_003", Hooks { // Sacrificial Pact: any Demon, Lord Jaraxxus as hero included.
        target: spec_if(Base::Any, is_demon),
        spell: Some(|g, me, t| {
            g.destroy(t);
            g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5));
        }),
        ..d()
    });
    r.insert("VAN_EX1_308", Hooks { // Soulfire
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 4));
            g.discard_random(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_CS2_059", Hooks { // Blood Imp
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.others(me));
                if t != NONE {
                    g.buff(t, 0, 1, false);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_063", Hooks { // Corruption
        target: ENEMY_MINION,
        spell: Some(|g, me, t| {
            let p = g.ctrl(me);
            g.em(t).add_enchant(json!({"hooks": "ench:corruption", "player": p}));
        }),
        ..d()
    });
    r.insert("ench:corruption", Hooks { // At the start of the caster's turn, destroy it.
        on: vec![("turn_start", |g, me, ev| {
            for p in g.e(me).ench_players("ench:corruption") {
                if g.ev_i(ev, "player") == p as i64 {
                    g.destroy(me);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_319", Hooks { battlecry: Some(|g, me, _| { g.damage(me, g.hero(g.ctrl(me)), 3); }), ..d() }); // Flame Imp
    r.insert("VAN_EX1_302", Hooks { // Mortal Coil
        target: MINION,
        spell: Some(|g, me, t| {
            if kills(g, me, t, g.spell_dmg(me, 1)) {
                g.draw(g.ctrl(me), 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_316", Hooks { // Power Overwhelming
        target: FRIENDLY_MINION,
        spell: Some(|g, _, t| {
            g.buff(t, 4, 4, true);
            g.em(t).add_enchant(json!({"hooks": "ench:power_overwhelming"}));
        }),
        ..d()
    });
    r.insert("ench:power_overwhelming", Hooks { on: vec![("turn_end", |g, me, _| g.destroy(me))], ..d() });
    r.insert("VAN_EX1_596", Hooks { // Demonfire
        target: MINION,
        spell: Some(|g, me, t| {
            if g.ctrl(t) == g.ctrl(me) && g.e(t).race() == "DEMON" {
                g.buff(t, 2, 2, false);
            } else {
                g.damage(me, t, g.spell_dmg(me, 2));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_306", Hooks { battlecry: Some(|g, me, _| g.discard_random(g.ctrl(me), 1)), ..d() }); // Felstalker
    r.insert("VAN_CS2_061", Hooks { // Drain Life
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 2));
            g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 2));
        }),
        ..d()
    });
    r.insert("VAN_EX1_301", Hooks { // Felguard
        battlecry: Some(|g, me, _| {
            let c = g.ctrl(me);
            let p = &mut g.players[c];
            p.max_mana = 0.max(p.max_mana - 1);
            p.mana = p.mana.min(p.max_mana);
        }),
        ..d()
    });
    r.insert("VAN_EX1_317", Hooks { // Sense Demons: missing demons become Worthless Imps.
        spell: Some(|g, me, _| {
            let p = g.ctrl(me);
            let mut demons: Vec<Id> = g.players[p].deck.iter().copied().filter(|&e| g.e(e).race() == "DEMON").collect();
            g.shuffle_ids(&mut demons);
            for i in 0..2 {
                if i < demons.len() {
                    g.draw_entity(p, demons[i]);
                } else {
                    g.add_to_hand(p, "EX1_317t");
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_057", Hooks { target: MINION, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 4)); }), ..d() }); // Shadow Bolt
    r.insert("VAN_EX1_304", Hooks { // Void Terror
        battlecry: Some(|g, me, _| {
            let (mut atk, mut hp) = (0, 0);
            for m in g.adjacent(me) {
                atk += g.e(m).atk();
                hp += g.e(m).health();
                g.destroy(m);
            }
            g.buff(me, atk, hp, false);
        }),
        ..d()
    });
    r.insert("VAN_CS2_062", Hooks { // Hellfire
        spell: Some(|g, me, _| {
            for c in g.all_chars() {
                g.damage(me, c, g.spell_dmg(me, 3));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_313", Hooks { battlecry: Some(|g, me, _| { g.damage(me, g.hero(g.ctrl(me)), 5); }), ..d() }); // Pit Lord
    r.insert("VAN_EX1_303", Hooks { // Shadowflame
        target: FRIENDLY_MINION,
        spell: Some(|g, me, t| {
            let n = g.spell_dmg(me, g.e(t).atk());
            g.destroy(t);
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, n);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_315", Hooks { // Summoning Portal
        cost_aura: Some(|g, me, card, c| {
            let x = g.e(card);
            if x.controller != g.ctrl(me) || !x.is_minion() || x.zone != "HAND" || c <= 1 {
                return c;
            }
            1.max(c - 2)
        }),
        ..d()
    });
    r.insert("VAN_EX1_320", Hooks { // Bane of Doom
        target: ANY,
        spell: Some(|g, me, t| {
            if kills(g, me, t, g.spell_dmg(me, 3)) {
                let c = g.pick(&collectible_demons()).unwrap();
                g.summon(g.ctrl(me), c, -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_310", Hooks { battlecry: Some(|g, me, _| g.discard_random(g.ctrl(me), 2)), ..d() }); // Doomguard
    r.insert("VAN_CS2_064", Hooks { // Dread Infernal
        battlecry: Some(|g, me, _| {
            for c in g.all_chars() {
                if c != me {
                    g.damage(me, c, 1);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_309", Hooks { // Siphon Soul
        target: MINION,
        spell: Some(|g, me, t| {
            g.destroy(t);
            g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 3));
        }),
        ..d()
    });
    r.insert("VAN_EX1_312", Hooks { // Twisting Nether
        spell: Some(|g, _, _| {
            for m in g.all_minions() {
                g.destroy(m);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_323", Hooks { // Lord Jaraxxus: new 15/15 hero, Blood Fury, INFERNO!; secrets stay.
        battlecry: Some(|g, me, _| {
            let p = g.ctrl(me);
            g.players[p].board.retain(|&x| x != me);
            g.em(me).zone = "SETASIDE";
            g.replace_hero(p, "EX1_323h");
            g.equip(p, "EX1_323w");
            g.set_hero_power(p, "VAN_EX1_tk33");
        }),
        ..d()
    });
}
