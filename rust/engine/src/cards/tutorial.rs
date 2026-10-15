//! Cards of the tutorial bosses (cards/tutorial.gd).

use super::*;
use crate::entity::int;
use serde_json::json;

pub fn register(r: &mut Registry) {
    r.insert("TU4a_004", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 4)); }), ..d() }); // Hogger SMASH!
    r.insert("TU4c_002", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 2)); }), ..d() }); // Barrel Toss
    r.insert("TU4c_003", Hooks { deathrattle: Some(|g, me| { g.summon(g.ctrl(me), "TU4c_005", g.died_pos(me)); }), ..d() }); // Barrel
    r.insert("TU4c_004", Hooks { // Stomp
        spell: Some(|g, me, _| {
            for c in g.chars(g.foe(me)) {
                g.damage(me, c, g.spell_dmg(me, 2));
            }
        }),
        ..d()
    });
    r.insert("TU4c_006", Hooks { target: FRIENDLY_MINION, spell: Some(|g, _, t| g.buff(t, 1, 1, false)), ..d() }); // Bananas (tutorial)
    r.insert("TU4c_008", Hooks { target: ANY, spell: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 8)); }), ..d() }); // Will of Mukla
    r.insert("TU4f_007", Hooks { battlecry: Some(|g, me, _| { g.add_to_hand(g.ctrl(me), "TU4c_006"); }), ..d() }); // Crazy Monkey
    r.insert("TU4d_003", Hooks { target: ANY, hero_power: Some(|g, me, t| { g.damage(me, t, g.hp_dmg(me, 1)); }), ..d() }); // Shotgun Blast
    r.insert("TU4e_002", Hooks { // Flames of Azzinoth (Illidan)
        can_play: Some(|g, me| g.board_has_room(me)),
        hero_power: Some(|g, me, _| {
            for _ in 0..2 {
                g.summon(g.ctrl(me), "TU4e_002t", -1);
            }
        }),
        ..d()
    });
    r.insert("TU4e_005", Hooks { // Flame Burst: 5 missiles; spell damage boosts each one
        spell: Some(|g, me, _| {
            for _ in 0..5 {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, g.spell_dmg(me, 1));
            }
        }),
        ..d()
    });
    r.insert("TU4f_004", Hooks { // Legacy of the Emperor
        spell: Some(|g, me, _| {
            for m in g.minions(g.ctrl(me)) {
                g.buff(m, 2, 2, false);
            }
        }),
        ..d()
    });
    r.insert("TU4f_006", Hooks { // Transcendence: Cho can't be attacked or targeted until his minions are dead.
        can_play: Some(|g, me| !g.minions(g.ctrl(me)).is_empty()),
        spell: Some(|g, me, _| {
            let hero = g.hero(g.ctrl(me));
            if !g.minions(g.ctrl(me)).is_empty() {
                g.em(hero).give_tag("STEALTH", false);
                g.em(hero).add_enchant(json!({"hooks": "ench:transcendence"}));
            }
        }),
        ..d()
    });
    r.insert("ench:transcendence", Hooks {
        on: vec![("death", |g, me, _| {
            if g.minions(g.ctrl(me)).is_empty() {
                let x = g.em(me);
                x.erase_tag("STEALTH");
                x.enchantments.retain(|e| e.get("hooks").and_then(|v| v.as_str()) != Some("ench:transcendence"));
            }
        })],
        ..d()
    });
    r.insert("ench:tutorial_guard", Hooks { // Missions 1-2: Jaina can't drop below 1 Health.
        now: vec![("predamage", |g, me, ev| {
            if int(ev.get("target")) == me {
                let x = g.e(me);
                let amount = int(ev.get("amount")).min(0.max(x.health() - 1 + x.tag("ARMOR")));
                ev.insert("amount".into(), json!(amount));
            }
        })],
        ..d()
    });
}
