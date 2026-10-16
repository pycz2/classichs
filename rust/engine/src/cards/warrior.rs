//! Warrior cards and their tokens (cards/warrior.gd).

use super::*;
use serde_json::json;

fn damaged(g: &Game, _me: Id, t: Id) -> bool {
    g.e(t).damage > 0
}

fn hit_and_rage(g: &mut Game, me: Id, t: Id) {
    let n = if g.e(me).kind() == "SPELL" { g.spell_dmg(me, 1) } else { 1 };
    g.damage(me, t, n);
    g.buff(t, 2, 0, false);
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_EX1_607", Hooks { target: MINION, spell: Some(hit_and_rage), ..d() }); // Inner Rage
    r.insert("VAN_CS2_108", Hooks { target: spec_if(Base::EnemyMinion, damaged), spell: Some(|g, _, t| g.destroy(t)), ..d() }); // Execute
    r.insert("VAN_EX1_410", Hooks { // Shield Slam
        target: MINION,
        spell: Some(|g, me, t| {
            let armor = g.e(g.hero(g.ctrl(me))).tag("ARMOR");
            g.damage(me, t, g.spell_dmg(me, armor));
        }),
        ..d()
    });
    r.insert("VAN_EX1_409", Hooks { // Upgrade!
        spell: Some(|g, me, _| {
            if let Some(w) = g.weapon(g.ctrl(me)) {
                g.buff(w, 1, 0, false);
                g.add_tag_int(w, "DURABILITY", 1);
            } else {
                g.equip(g.ctrl(me), "EX1_409t");
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_400", Hooks { // Whirlwind
        spell: Some(|g, me, _| {
            for m in g.all_minions() {
                g.damage(me, m, g.spell_dmg(me, 1));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_402", Hooks { // Armorsmith
        on: vec![("damage", |g, me, ev| {
            let t = g.e(g.ev_i(ev, "target"));
            if t.is_minion() && t.controller == g.ctrl(me) {
                g.gain_armor(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_392", Hooks { // Battle Rage
        spell: Some(|g, me, _| {
            let n = g.chars(g.ctrl(me)).into_iter().filter(|&c| g.e(c).damage > 0).count() as i64;
            g.draw(g.ctrl(me), n);
        }),
        ..d()
    });
    r.insert("VAN_CS2_114", Hooks { // Cleave
        can_play: Some(|g, me| g.minions(g.foe(me)).len() >= 2),
        spell: Some(|g, me, _| super::two_random_enemies(g, me, 2)),
        ..d()
    });
    r.insert("VAN_NEW1_036", Hooks { // Commanding Shout: lives on the hero this turn, so later minions count too.
        spell: Some(|g, me, _| {
            let h = g.hero(g.ctrl(me));
            g.em(h).add_enchant(json!({"hooks": "ench:commanding_shout", "eot": true}));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("ench:commanding_shout", Hooks {
        now: vec![("predamage", |g, me, ev| {
            let t = g.e(crate::entity::int(ev.get("target")));
            if t.is_minion() && t.controller == g.ctrl(me) {
                let amount = crate::entity::int(ev.get("amount")).min(0.max(t.health() - 1));
                ev.insert("amount".into(), json!(amount));
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_603", Hooks { target: MINION, battlecry: Some(hit_and_rage), ..d() }); // Cruel Taskmaster
    r.insert("VAN_CS2_105", Hooks { spell: Some(|g, me, _| g.buff(g.hero(g.ctrl(me)), 4, 0, true)), ..d() }); // Heroic Strike
    r.insert("VAN_CS2_104", Hooks { target: spec_if(Base::Minion, damaged), spell: Some(|g, _, t| g.buff(t, 3, 3, false)), ..d() }); // Rampage
    r.insert("VAN_EX1_391", Hooks { // Slam
        target: MINION,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 2));
            if g.e(t).zone == "PLAY" && g.e(t).health() > 0 {
                g.draw(g.ctrl(me), 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_103", Hooks { // Charge
        target: FRIENDLY_MINION,
        spell: Some(|g, _, t| {
            g.buff(t, 2, 0, false);
            g.em(t).give_tag("CHARGE", false);
        }),
        ..d()
    });
    r.insert("VAN_EX1_604", Hooks { // Frothing Berserker
        on: vec![("damage", |g, me, ev| {
            if g.e(g.ev_i(ev, "target")).is_minion() {
                g.buff(me, 1, 0, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_606", Hooks { // Shield Block
        spell: Some(|g, me, _| {
            g.gain_armor(g.ctrl(me), 5);
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_EX1_084", Hooks { // Warsong Commander (2014): summoned minions with 3 or less Attack get Charge.
        on: vec![("summon", |g, me, ev| {
            let m = g.ev_i(ev, "entity");
            if ev_mine(g, me, ev) && m != me && g.e(m).atk() <= 3 {
                g.em(m).give_tag("CHARGE", false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_398", Hooks { battlecry: Some(|g, me, _| { g.equip(g.ctrl(me), "EX1_398t"); }), ..d() }); // Arathi Weaponsmith
    r.insert("VAN_EX1_408", Hooks { // Mortal Strike
        target: ANY,
        spell: Some(|g, me, t| {
            let n = if g.e(g.hero(g.ctrl(me))).health() <= 12 { 6 } else { 4 };
            g.damage(me, t, g.spell_dmg(me, n));
        }),
        ..d()
    });
    r.insert("VAN_EX1_407", Hooks { // Brawl
        can_play: Some(|g, _| g.all_minions().len() >= 2),
        spell: Some(|g, _, _| {
            let all = g.all_minions();
            let keep = g.random_choice(&all);
            for m in all {
                if m != keep {
                    g.destroy(m);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_411", Hooks { // Gorehowl: attacking a minion costs 1 Attack instead of 1 Durability.
        durability_on_attack: Some(|g, w, defender| {
            if !g.e(defender).is_minion() {
                return true;
            }
            g.buff(w, -1, 0, false);
            if g.e(w).atk() <= 0 {
                g.destroy(w);
            }
            false
        }),
        ..d()
    });
    r.insert("VAN_EX1_414", Hooks { // Grommash Hellscream: Enrage +6 Attack.
        aura: Some(|g, me| {
            if g.e(me).damage > 0 {
                g.aura_add(me, 6, 0, &[]);
            }
        }),
        ..d()
    });
}
