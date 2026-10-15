//! Rogue cards and their tokens (cards/rogue.gd).

use super::*;
use crate::entity::NONE;
use serde_json::json;

fn has_weapon(g: &Game, me: Id) -> bool {
    g.weapon(g.ctrl(me)).is_some()
}

fn not_me(_g: &Game, me: Id, t: Id) -> bool {
    t != me
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_CS2_072", Hooks { // Backstab
        target: spec_if(Base::Minion, |g, _, t| g.e(t).damage == 0),
        spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 2)); }),
        ..d()
    });
    r.insert("VAN_EX1_145", Hooks { // Preparation
        spell: Some(|g, me, _| g.add_cost_mod(g.ctrl(me), json!({"kind": "spell", "delta": -3, "until": "use"}))),
        ..d()
    });
    r.insert("VAN_EX1_144", Hooks { // Shadowstep
        target: FRIENDLY_MINION,
        spell: Some(|g, _, t| {
            let n = g.return_to_hand(t);
            if n != NONE {
                g.em(n).add_enchant(json!({"cost": -2}));
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_073", Hooks { // Cold Blood
        target: MINION,
        spell: Some(|g, _, t| g.buff(t, 2, 0, false)),
        combo: Some(|g, _, t| g.buff(t, 4, 0, false)),
        ..d()
    });
    r.insert("VAN_EX1_128", Hooks { // Conceal: Stealth until your next turn.
        spell: Some(|g, me, _| {
            let p = g.ctrl(me);
            for m in g.minions(p) {
                if !g.e(m).has("STEALTH") {
                    // natural Stealth is not Conceal's to remove
                    g.em(m).give_tag("STEALTH", false);
                    g.em(m).add_enchant(json!({"hooks": "ench:conceal", "player": p}));
                }
            }
        }),
        ..d()
    });
    r.insert("ench:conceal", Hooks {
        on: vec![("turn_start", |g, me, ev| {
            remove_mine(g, me, ev, "ench:conceal", |g, me, _| g.em(me).erase_tag("STEALTH"));
        })],
        ..d()
    });
    r.insert("VAN_CS2_074", Hooks { // Deadly Poison
        can_play: Some(has_weapon),
        spell: Some(|g, me, _| g.buff(g.weapon_of(g.ctrl(me)), 2, 0, false)),
        ..d()
    });
    r.insert("VAN_CS2_075", Hooks { spell: Some(|g, me, _| { g.damage(me, g.hero(g.foe(me)), g.spell_dmg(me, 3)); }), ..d() }); // Sinister Strike
    r.insert("VAN_EX1_126", Hooks { // Betrayal
        target: ENEMY_MINION,
        spell: Some(|g, _, t| {
            for m in g.adjacent(t) {
                g.damage(t, m, g.e(t).atk());
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_233", Hooks { // Blade Flurry
        can_play: Some(has_weapon),
        spell: Some(|g, me, _| {
            let w = g.weapon_of(g.ctrl(me));
            let n = g.spell_dmg(me, g.e(w).atk());
            g.destroy(w);
            for c in g.chars(g.foe(me)) {
                g.damage(me, c, n);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_131", Hooks { combo: Some(|g, me, _| { g.summon_right(me, "EX1_131t"); }), ..d() }); // Defias Ringleader
    r.insert("VAN_EX1_124", Hooks { // Eviscerate
        target: ANY,
        spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 2)); }),
        combo: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 4)); }),
        ..d()
    });
    r.insert("VAN_EX1_522", Hooks { // Patient Assassin
        on: vec![("damage", |g, me, ev| {
            let t = g.ev_i(ev, "target");
            if g.ev_i(ev, "source") == me && g.e(t).is_minion() {
                g.destroy(t);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_581", Hooks { target: ENEMY_MINION, spell: Some(|g, _, t| { g.return_to_hand(t); }), ..d() }); // Sap
    r.insert("VAN_EX1_278", Hooks { // Shiv
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 1));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_EX1_613", Hooks { // Edwin VanCleef
        combo: Some(|g, me, _| {
            let n = 2 * (g.players[g.ctrl(me)].cards_played_this_turn - 1);
            g.buff(me, n, n, false);
        }),
        ..d()
    });
    r.insert("VAN_EX1_129", Hooks { // Fan of Knives
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, g.spell_dmg(me, 1));
            }
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_EX1_137", Hooks { // Headcrack
        spell: Some(|g, me, _| { g.damage(me, g.hero(g.foe(me)), g.spell_dmg(me, 2)); }),
        combo: Some(|g, me, _| {
            g.damage(me, g.hero(g.foe(me)), g.spell_dmg(me, 2));
            let p = g.ctrl(me);
            g.em(g.hero(p)).add_enchant(json!({"hooks": "ench:headcrack", "player": p}));
        }),
        ..d()
    });
    r.insert("ench:headcrack", Hooks { // Return Headcrack to the hand at the start of the next own turn.
        on: vec![("turn_start", |g, me, ev| {
            remove_mine(g, me, ev, "ench:headcrack", |g, _, p| {
                g.add_to_hand(p, "VAN_EX1_137");
            });
        })],
        ..d()
    });
    r.insert("VAN_EX1_133", Hooks { // Perdition's Blade
        target: ANY,
        battlecry: Some(|g, me, t| { g.damage(me, t, 1); }),
        combo: Some(|g, me, t| { g.damage(me, t, 2); }),
        ..d()
    });
    r.insert("VAN_EX1_134", Hooks { // SI:7 Agent: targets only with Combo.
        combo_target: ANY,
        combo: Some(|g, me, t| { g.damage(me, t, 2); }),
        ..d()
    });
    r.insert("VAN_NEW1_014", Hooks { // Master of Disguise
        target: spec_if(Base::FriendlyMinion, not_me),
        battlecry: Some(|g, _, t| g.em(t).give_tag("STEALTH", false)),
        ..d()
    });
    r.insert("VAN_CS2_076", Hooks { target: ENEMY_MINION, spell: Some(|g, _, t| g.destroy(t)), ..d() }); // Assassinate
    r.insert("VAN_NEW1_005", Hooks { // Kidnapper
        combo_target: MINION,
        combo: Some(|g, _, t| { g.return_to_hand(t); }),
        ..d()
    });
    r.insert("VAN_NEW1_004", Hooks { // Vanish
        spell: Some(|g, _, _| {
            for m in g.all_minions() {
                g.return_to_hand(m);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_077", Hooks { spell: Some(|g, me, _| { g.draw(g.ctrl(me), 4); }), ..d() }); // Sprint
}

/// For each enchantment with these hooks whose "player" is the event's player
/// (iterating a copy): removes it, then runs f(g, me, player).
fn remove_mine(g: &mut Game, me: Id, ev: usize, hooks: &str, f: fn(&mut Game, Id, usize)) {
    for e in g.e(me).enchantments.clone() {
        if e.get("hooks").and_then(|v| v.as_str()) == Some(hooks) {
            let p = crate::entity::int(e.get("player"));
            if g.ev_i(ev, "player") == p {
                let x = g.em(me);
                if let Some(i) = x.enchantments.iter().position(|y| *y == e) {
                    x.enchantments.remove(i);
                }
                f(g, me, p as usize);
            }
        }
    }
}
