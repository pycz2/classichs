//! Paladin cards and their tokens (cards/paladin.gd).

use super::*;
use crate::entity::NONE;
use serde_json::json;

fn not_me(_g: &Game, me: Id, t: Id) -> bool {
    t != me
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_CS2_087", Hooks { target: MINION, spell: Some(|g, _, t| g.buff(t, 3, 0, false)), ..d() }); // Blessing of Might
    r.insert("VAN_EX1_363", Hooks { // Blessing of Wisdom
        target: MINION,
        spell: Some(|g, me, t| {
            let p = g.ctrl(me);
            g.em(t).add_enchant(json!({"hooks": "ench:blessing_of_wisdom", "player": p}));
        }),
        ..d()
    });
    r.insert("ench:blessing_of_wisdom", Hooks { // Whenever it attacks, the caster draws a card.
        on: vec![("attack", |g, me, ev| {
            if g.ev_i(ev, "attacker") == me {
                for p in g.e(me).ench_players("ench:blessing_of_wisdom") {
                    g.draw(p, 1);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_132", Hooks { // Eye for an Eye
        secret: Some(Secret {
            event: "damage",
            cond: |g, me, ev| g.ev_i(ev, "target") == g.hero(g.ctrl(me)),
            effect: |g, me, ev| { g.damage(me, g.hero(g.foe(me)), g.ev_i(ev, "amount")); },
        }),
        ..d()
    });
    r.insert("VAN_EX1_371", Hooks { target: MINION, spell: Some(|g, _, t| g.em(t).give_tag("DIVINE_SHIELD", false)), ..d() }); // Hand of Protection
    r.insert("VAN_EX1_360", Hooks { target: MINION, spell: Some(|g, _, t| g.set_stats(t, 1, -1)), ..d() }); // Humility
    r.insert("VAN_EX1_130", Hooks { // Noble Sacrifice
        secret: Some(Secret {
            event: "attack",
            cond: |g, me, ev| !ev_mine(g, me, ev) && g.board_has_room(me),
            effect: |g, me, ev| {
                let n = g.summon(g.ctrl(me), "VAN_EX1_130a", -1);
                if n != NONE {
                    g.ev_set(ev, "defender", json!(n));
                }
            },
        }),
        ..d()
    });
    r.insert("VAN_EX1_136", Hooks { // Redemption
        secret: Some(Secret {
            event: "death",
            cond: |g, me, ev| g.ev_b(ev, "minion") && ev_mine(g, me, ev),
            effect: |g, me, ev| {
                let dead = g.ev_i(ev, "entity");
                let card = g.ev_s(ev, "card").to_string();
                let n = g.summon(g.ctrl(me), &card, g.died_pos(dead));
                if n != NONE {
                    let x = g.em(n);
                    x.damage = x.max_health() - 1;
                }
            },
        }),
        ..d()
    });
    r.insert("VAN_EX1_379", Hooks { // Repentance
        secret: Some(Secret {
            event: "after_summon",
            cond: |g, me, ev| g.ev_b(ev, "played") && !ev_mine(g, me, ev),
            effect: |g, _, ev| g.set_stats(g.ev_i(ev, "entity"), -1, 1),
        }),
        ..d()
    });
    r.insert("VAN_EX1_362", Hooks { // Argent Protector
        target: spec_if(Base::FriendlyMinion, not_me),
        battlecry: Some(|g, _, t| g.em(t).give_tag("DIVINE_SHIELD", false)),
        ..d()
    });
    r.insert("VAN_EX1_619", Hooks { // Equality
        spell: Some(|g, _, _| {
            for m in g.all_minions() {
                g.set_stats(m, -1, 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_089", Hooks { target: ANY, spell: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 6)); }), ..d() }); // Holy Light
    r.insert("VAN_EX1_382", Hooks { target: ENEMY_MINION, battlecry: Some(|g, _, t| g.set_stats(t, 1, -1)), ..d() }); // Aldor Peacekeeper
    r.insert("VAN_EX1_349", Hooks { // Divine Favor
        spell: Some(|g, me, _| {
            let n = g.players[g.foe(me)].hand.len() as i64 - g.players[g.ctrl(me)].hand.len() as i64;
            if n > 0 {
                g.draw(g.ctrl(me), n);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_366", Hooks { // Sword of Justice
        on: vec![("after_summon", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.buff(g.ev_i(ev, "entity"), 1, 1, false);
                g.add_tag_int(me, "DURABILITY", -1);
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_092", Hooks { target: MINION, spell: Some(|g, _, t| g.buff(t, 4, 4, false)), ..d() }); // Blessing of Kings
    r.insert("VAN_CS2_093", Hooks { // Consecration
        spell: Some(|g, me, _| {
            for c in g.chars(g.foe(me)) {
                g.damage(me, c, g.spell_dmg(me, 2));
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_094", Hooks { // Hammer of Wrath
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 3));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_CS2_097", Hooks { // Truesilver Champion
        on: vec![("attack", |g, me, ev| {
            let hero = g.hero(g.ctrl(me));
            if g.ev_i(ev, "attacker") == hero {
                g.heal(me, hero, g.heal_amt(me, 2));
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_355", Hooks { target: MINION, spell: Some(|g, _, t| g.buff(t, g.e(t).atk(), 0, false)), ..d() }); // Blessed Champion
    r.insert("VAN_EX1_365", Hooks { // Holy Wrath
        target: ANY,
        spell: Some(|g, me, t| {
            let drawn = g.draw(g.ctrl(me), 1);
            if let Some(&c) = drawn.first() {
                g.damage(me, t, g.spell_dmg(me, g.cost(c)));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_384", Hooks { // Avenging Wrath: spell damage adds missiles.
        spell: Some(|g, me, _| {
            for _ in 0..g.spell_dmg(me, 8) {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_088", Hooks { battlecry: Some(|g, me, _| { g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 6)); }), ..d() }); // Guardian of Kings
    r.insert("VAN_EX1_354", Hooks { // Lay on Hands
        target: ANY,
        spell: Some(|g, me, t| {
            g.heal(me, t, g.heal_amt(me, 8));
            g.draw(g.ctrl(me), 3);
        }),
        ..d()
    });
    r.insert("VAN_EX1_383", Hooks { deathrattle: Some(|g, me| { g.equip(g.ctrl(me), "EX1_383t"); }), ..d() }); // Tirion Fordring
}
