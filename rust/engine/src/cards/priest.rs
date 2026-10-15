//! Priest cards and their tokens (cards/priest.gd).

use super::*;
use crate::entity::NONE;
use serde_json::json;

fn board_has_room(g: &Game, me: Id) -> bool {
    g.board_has_room(me)
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_EX1_621", Hooks { // Circle of Healing
        spell: Some(|g, me, _| {
            for m in g.all_minions() {
                g.heal(me, m, g.heal_amt(me, 4));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_332", Hooks { target: MINION, spell: Some(|g, _, t| g.silence(t)), ..d() }); // Silence
    r.insert("VAN_CS1_130", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 2)); }), ..d() }); // Holy Smite
    r.insert("VAN_CS1_129", Hooks { target: MINION, spell: Some(|g, _, t| g.set_stats(t, g.e(t).health(), -1)), ..d() }); // Inner Fire
    r.insert("VAN_CS2_003", Hooks { // Mind Vision
        spell: Some(|g, me, _| {
            let hand = g.players[g.foe(me)].hand.clone();
            let e = g.random_choice(&hand);
            if e != NONE {
                let card = g.e(e).card_id.clone();
                g.add_to_hand(g.ctrl(me), &card);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_235", Hooks { // Northshire Cleric
        on: vec![("heal", |g, me, ev| {
            if g.e(g.ev_i(ev, "target")).is_minion() {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_004", Hooks { // Power Word: Shield
        target: MINION,
        spell: Some(|g, me, t| {
            g.buff(t, 0, 2, false);
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_CS2_236", Hooks { target: MINION, spell: Some(|g, _, t| g.buff(t, 0, g.e(t).health(), false)), ..d() }); // Divine Spirit
    r.insert("VAN_EX1_341", Hooks { // Lightwell
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let hurt: Vec<Id> =
                    g.chars(g.ctrl(me)).into_iter().filter(|&c| g.e(c).damage > 0 && g.e(c).health() > 0).collect();
                let t = g.random_choice(&hurt);
                if t != NONE {
                    g.heal(me, t, g.heal_amt(me, 3));
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_DS1_233", Hooks { spell: Some(|g, me, _| { g.damage(me, g.hero(g.foe(me)), g.spell_dmg(me, 5)); }), ..d() }); // Mind Blast
    r.insert("VAN_CS2_234", Hooks { target: spec_if(Base::Minion, |g, _, t| g.e(t).atk() <= 3), spell: Some(|g, _, t| g.destroy(t)), ..d() }); // Shadow Word: Pain
    r.insert("VAN_EX1_622", Hooks { target: spec_if(Base::Minion, |g, _, t| g.e(t).atk() >= 5), spell: Some(|g, _, t| g.destroy(t)), ..d() }); // Shadow Word: Death
    r.insert("VAN_EX1_625", Hooks { // Shadowform: Mind Spike, then Mind Shatter. The new power is unused.
        spell: Some(|g, me, _| {
            let p = g.ctrl(me);
            let cur = &g.e(g.players[p].hero_power).card_id;
            let next = if cur.starts_with("EX1_625t") { "EX1_625t2" } else { "EX1_625t" };
            g.set_hero_power(p, next);
        }),
        ..d()
    });
    r.insert("VAN_EX1_339", Hooks { // Thoughtsteal
        spell: Some(|g, me, _| {
            let mut deck = g.players[g.foe(me)].deck.clone();
            g.shuffle_ids(&mut deck);
            for &e in deck.iter().take(2) {
                let card = g.e(e).card_id.clone();
                g.add_to_hand(g.ctrl(me), &card);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_591", Hooks { // Auchenai Soulpriest
        aura: Some(|g, me| g.aura_add(g.hero(g.ctrl(me)), 0, 0, &[("HEAL_IS_DAMAGE", json!(true))])),
        ..d()
    });
    r.insert("VAN_EX1_335", Hooks { // Lightspawn: attack always equals health; runs after all other auras.
        aura_final: Some(|g, me| g.aura_add(me, g.e(me).health() - g.e(me).atk(), 0, &[])),
        ..d()
    });
    r.insert("VAN_EX1_626", Hooks { // Mass Dispel
        spell: Some(|g, me, _| {
            for m in g.minions(g.foe(me)) {
                g.silence(m);
            }
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_EX1_345", Hooks { // Mindgames
        spell: Some(|g, me, _| {
            let pool: Vec<Id> = g.players[g.foe(me)].deck.iter().copied().filter(|&e| g.e(e).is_minion()).collect();
            let e = g.random_choice(&pool);
            let card = if e != NONE { g.e(e).card_id.clone() } else { "VAN_EX1_345t".to_string() };
            g.summon(g.ctrl(me), &card, -1);
        }),
        ..d()
    });
    r.insert("VAN_EX1_334", Hooks { // Shadow Madness: control until end of turn; it can attack at once.
        target: spec_if(Base::EnemyMinion, |g, _, t| g.e(t).atk() <= 3),
        can_play: Some(board_has_room),
        spell: Some(|g, me, t| {
            let owner = g.ctrl(t);
            g.take_control(t, g.ctrl(me));
            g.em(t).erase_tag("EXHAUSTED");
            g.em(t).add_enchant(json!({"hooks": "ench:shadow_madness", "player": owner}));
        }),
        ..d()
    });
    r.insert("ench:shadow_madness", Hooks {
        on: vec![("turn_end", |g, me, _| {
            for e in g.e(me).enchantments.clone() {
                if e.get("hooks").and_then(|v| v.as_str()) == Some("ench:shadow_madness") {
                    let x = g.em(me);
                    if let Some(i) = x.enchantments.iter().position(|y| *y == e) {
                        x.enchantments.remove(i);
                    }
                    g.take_control(me, crate::entity::int(e.get("player")) as usize);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_CS1_112", Hooks { // Holy Nova
        spell: Some(|g, me, _| {
            for c in g.chars(g.foe(me)) {
                g.damage(me, c, g.spell_dmg(me, 2));
            }
            for c in g.chars(g.ctrl(me)) {
                g.heal(me, c, g.heal_amt(me, 2));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_091", Hooks { // Cabal Shadow Priest
        target: spec_if(Base::EnemyMinion, |g, _, t| g.e(t).atk() <= 2),
        battlecry: Some(|g, me, t| g.take_control(t, g.ctrl(me))),
        ..d()
    });
    r.insert("VAN_EX1_624", Hooks { // Holy Fire
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 5));
            g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5));
        }),
        ..d()
    });
    r.insert("VAN_EX1_623", Hooks { // Temple Enforcer
        target: spec_if(Base::FriendlyMinion, |_, me, t| t != me),
        battlecry: Some(|g, _, t| g.buff(t, 0, 3, false)),
        ..d()
    });
    r.insert("VAN_EX1_350", Hooks { // Prophet Velen
        aura: Some(|g, me| g.aura_add(g.hero(g.ctrl(me)), 0, 0, &[("DOUBLE_HEAL_DAMAGE", json!(1))])),
        ..d()
    });
    r.insert("VAN_CS1_113", Hooks { // Mind Control
        target: ENEMY_MINION,
        can_play: Some(board_has_room),
        spell: Some(|g, me, t| g.take_control(t, g.ctrl(me))),
        ..d()
    });
}
