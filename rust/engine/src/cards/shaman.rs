//! Shaman cards and their tokens (cards/shaman.gd). Overload comes from card data.

use super::*;
use crate::card_db;
use serde_json::json;

fn not_me(_g: &Game, me: Id, t: Id) -> bool {
    t != me
}

/// Forked Lightning, Multi-Shot, Cleave: n spell damage to two random enemy minions.
pub(crate) fn two_random_enemies(g: &mut Game, me: Id, n: i64) {
    let mut pool = g.minions(g.foe(me));
    g.shuffle_ids(&mut pool);
    for &m in pool.iter().take(2) {
        g.damage(me, m, g.spell_dmg(me, n));
    }
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_CS2_041", Hooks { // Ancestral Healing
        target: MINION,
        spell: Some(|g, me, t| {
            g.heal(me, t, g.e(t).damage);
            g.em(t).give_tag("TAUNT", false);
        }),
        ..d()
    });
    r.insert("VAN_EX1_244", Hooks { // Totemic Might
        spell: Some(|g, me, _| {
            for m in g.minions(g.ctrl(me)) {
                if g.e(m).race() == "TOTEM" {
                    g.buff(m, 0, 2, false);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_245", Hooks { // Earth Shock
        target: MINION,
        spell: Some(|g, me, t| {
            g.silence(t);
            g.damage(me, t, g.spell_dmg(me, 1));
        }),
        ..d()
    });
    r.insert("VAN_EX1_251", Hooks { // Forked Lightning
        can_play: Some(|g, me| g.minions(g.foe(me)).len() >= 2),
        spell: Some(|g, me, _| two_random_enemies(g, me, 2)),
        ..d()
    });
    r.insert("VAN_CS2_037", Hooks { // Frost Shock
        target: ENEMY_CHAR,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 1));
            g.freeze(t);
        }),
        ..d()
    });
    r.insert("VAN_EX1_238", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 3)); }), ..d() }); // Lightning Bolt
    r.insert("VAN_CS2_045", Hooks { target: FRIENDLY_CHAR, spell: Some(|g, _, t| g.buff(t, 3, 0, true)), ..d() }); // Rockbiter Weapon
    r.insert("VAN_CS2_038", Hooks { // Ancestral Spirit
        target: MINION,
        spell: Some(|g, _, t| g.em(t).add_enchant(json!({"hooks": "ench:ancestral_spirit"}))),
        ..d()
    });
    r.insert("ench:ancestral_spirit", Hooks {
        deathrattle: Some(|g, me| {
            let card = g.e(me).card_id.clone();
            g.summon(g.ctrl(me), &card, g.died_pos(me));
        }),
        ..d()
    });
    r.insert("VAN_EX1_565", Hooks { // Flametongue Totem
        aura: Some(|g, me| {
            for m in g.adjacent(me) {
                g.aura_add(m, 2, 0, &[]);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_039", Hooks { target: MINION, spell: Some(|g, _, t| g.em(t).give_tag("WINDFURY", false)), ..d() }); // Windfury
    r.insert("VAN_CS2_053", Hooks { // Far Sight
        spell: Some(|g, me, _| {
            for e in g.draw(g.ctrl(me), 1) {
                g.em(e).add_enchant(json!({"cost": -3}));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_248", Hooks { // Feral Spirit
        spell: Some(|g, me, _| {
            for _ in 0..2 {
                g.summon(g.ctrl(me), "VAN_EX1_tk11", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_246", Hooks { target: MINION, spell: Some(|g, _, t| { g.transform(t, "hexfrog"); }), ..d() }); // Hex
    r.insert("VAN_EX1_241", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 5)); }), ..d() }); // Lava Burst
    r.insert("VAN_EX1_259", Hooks { // Lightning Storm: 2-3 damage, rolled per minion.
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                let n = g.rng.randi_range(2, 3);
                g.damage(me, m, g.spell_dmg(me, n));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_575", Hooks { // Mana Tide Totem
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_258", Hooks { // Unbound Elemental
        on: vec![("play", |g, me, ev| {
            if ev_mine(g, me, ev) && g.ev_i(ev, "entity") != me && card_db::card(g.ev_s(ev, "card")).overload > 0 {
                g.buff(me, 1, 1, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_587", Hooks { // Windspeaker
        target: spec_if(Base::FriendlyMinion, not_me),
        battlecry: Some(|g, _, t| g.em(t).give_tag("WINDFURY", false)),
        ..d()
    });
    r.insert("VAN_CS2_046", Hooks { // Bloodlust
        spell: Some(|g, me, _| {
            for m in g.minions(g.ctrl(me)) {
                g.buff(m, 3, 0, true);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_042", Hooks { target: ANY, battlecry: Some(|g, me, t| { g.damage(me, t, 3); }), ..d() }); // Fire Elemental
}
