//! Mage cards and their tokens (cards/mage.gd).

use super::hunter::attacks_my_hero;
use super::*;
use crate::entity::NONE;
use serde_json::json;

fn enemy_spell(g: &Game, me: Id, ev: usize) -> bool {
    g.ev_s(ev, "kind") == "spell" && !ev_mine(g, me, ev)
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_EX1_277", Hooks { // Arcane Missiles: spell damage adds missiles.
        spell: Some(|g, me, _| {
            for _ in 0..g.spell_dmg(me, 3) {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_031", Hooks { // Ice Lance
        target: ANY,
        spell: Some(|g, me, t| {
            if g.e(t).has("FROZEN") {
                g.damage(me, t, g.spell_dmg(me, 4));
            } else {
                g.freeze(t);
            }
        }),
        ..d()
    });
    r.insert("VAN_NEW1_012", Hooks { // Mana Wyrm
        on: vec![("play", |g, me, ev| {
            if g.ev_s(ev, "kind") == "spell" && ev_mine(g, me, ev) {
                g.buff(me, 1, 0, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_027", Hooks { // Mirror Image
        spell: Some(|g, me, _| {
            for _ in 0..2 {
                g.summon(g.ctrl(me), "VAN_CS2_mirror", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_025", Hooks { // Arcane Explosion
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, g.spell_dmg(me, 1));
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_024", Hooks { // Frostbolt
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 3));
            g.freeze(t);
        }),
        ..d()
    });
    r.insert("VAN_EX1_608", Hooks { // Sorcerer's Apprentice
        cost_aura: Some(|g, me, card, c| {
            let x = g.e(card);
            if x.controller == g.ctrl(me) && x.kind() == "SPELL" && x.zone == "HAND" { c - 1 } else { c }
        }),
        ..d()
    });
    r.insert("VAN_CS2_023", Hooks { spell: Some(|g, me, _| { g.draw(g.ctrl(me), 2); }), ..d() }); // Arcane Intellect
    r.insert("VAN_EX1_287", Hooks { // Counterspell
        secret: Some(Secret { event: "play", cond: enemy_spell, effect: |g, _, ev| g.ev_set(ev, "countered", json!(true)) }),
        ..d()
    });
    r.insert("VAN_CS2_026", Hooks { // Frost Nova
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.freeze(m);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_289", Hooks { // Ice Barrier
        secret: Some(Secret { event: "attack", cond: attacks_my_hero, effect: |g, me, _| g.gain_armor(g.ctrl(me), 8) }),
        ..d()
    });
    r.insert("VAN_EX1_295", Hooks { // Ice Block: replaces fatal damage to my hero.
        now: vec![("predamage", |g, me, ev| {
            let hero = g.hero(g.ctrl(me));
            let h = g.e(hero);
            let fatal = crate::entity::int(ev.get("amount")) >= h.health() + h.tag("ARMOR");
            if g.secret_ready(me) && crate::entity::int(ev.get("target")) == hero && fatal {
                ev.insert("amount".into(), json!(0));
                g.reveal(me);
                g.em(hero).give_tag("IMMUNE", true);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_612", Hooks { // Kirin Tor Mage
        battlecry: Some(|g, me, _| g.add_cost_mod(g.ctrl(me), json!({"kind": "secret", "set": 0, "until": "use"}))),
        ..d()
    });
    r.insert("VAN_EX1_294", Hooks { // Mirror Entity
        secret: Some(Secret {
            event: "after_summon",
            cond: |g, me, ev| g.ev_b(ev, "played") && !ev_mine(g, me, ev) && g.board_has_room(me),
            effect: |g, me, ev| {
                let card = g.ev_s(ev, "card").to_string();
                g.summon(g.ctrl(me), &card, -1);
            },
        }),
        ..d()
    });
    r.insert("VAN_tt_010", Hooks { // Spellbender
        secret: Some(Secret {
            event: "play",
            cond: |g, me, ev| {
                let t = g.ev_i(ev, "target");
                enemy_spell(g, me, ev) && t >= 0 && g.e(t).is_minion() && g.board_has_room(me)
            },
            effect: |g, me, ev| {
                let n = g.summon(g.ctrl(me), "VAN_tt_010a", -1);
                if n != NONE {
                    g.ev_set(ev, "target", json!(n));
                }
            },
        }),
        ..d()
    });
    r.insert("VAN_EX1_594", Hooks { // Vaporize
        secret: Some(Secret {
            event: "attack",
            cond: |g, me, ev| attacks_my_hero(g, me, ev) && g.e(g.ev_i(ev, "attacker")).is_minion(),
            effect: |g, _, ev| g.destroy(g.ev_i(ev, "attacker")),
        }),
        ..d()
    });
    r.insert("VAN_EX1_275", Hooks { // Cone of Cold
        target: MINION,
        spell: Some(|g, me, t| {
            let mut group = vec![t];
            group.extend(g.adjacent(t));
            for m in group {
                g.damage(me, m, g.spell_dmg(me, 1));
                g.freeze(m);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_274", Hooks { // Ethereal Arcanist
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) && !g.players[g.ctrl(me)].secrets.is_empty() {
                g.buff(me, 2, 2, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_029", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 6)); }), ..d() }); // Fireball
    r.insert("VAN_CS2_022", Hooks { target: MINION, spell: Some(|g, _, t| { g.transform(t, "VAN_CS2_tk1"); }), ..d() }); // Polymorph
    r.insert("VAN_CS2_033", Hooks { // Water Elemental
        on: vec![("damage", |g, me, ev| {
            if g.ev_i(ev, "source") == me {
                g.freeze(g.ev_i(ev, "target"));
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_028", Hooks { // Blizzard
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, g.spell_dmg(me, 2));
                g.freeze(m);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_559", Hooks { // Archmage Antonidas
        on: vec![("play", |g, me, ev| {
            if g.ev_s(ev, "kind") == "spell" && ev_mine(g, me, ev) {
                g.add_to_hand(g.ctrl(me), "VAN_CS2_029");
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_032", Hooks { // Flamestrike
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.damage(me, m, g.spell_dmg(me, 4));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_279", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 10)); }), ..d() }); // Pyroblast
}
