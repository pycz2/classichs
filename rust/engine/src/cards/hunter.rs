//! Hunter cards and their tokens (cards/hunter.gd).

use super::*;
use crate::card_db;
use crate::entity::NONE;
use crate::state::MAX_BOARD;
use serde_json::json;

const COMPANIONS: [&str; 3] = ["VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034"];

fn is_beast(g: &Game, _me: Id, t: Id) -> bool {
    g.e(t).race() == "BEAST"
}

fn has_enemy_minions(g: &Game, me: Id) -> bool {
    !g.minions(g.foe(me)).is_empty()
}

pub(crate) fn attacks_my_hero(g: &Game, me: Id, ev: usize) -> bool {
    g.ev_i(ev, "defender") == g.hero(g.ctrl(me))
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_CS2_084", Hooks { target: MINION, spell: Some(|g, _, t| g.set_stats(t, -1, 1)), ..d() }); // Hunter's Mark
    r.insert("VAN_DS1_185", Hooks { target: ANY, spell: Some(|g, me, t| { g.damage(me, t, g.spell_dmg(me, 2)); }), ..d() }); // Arcane Shot
    r.insert("VAN_EX1_549", Hooks { // Bestial Wrath. 2014: any Beast.
        target: spec_if(Base::Minion, is_beast),
        spell: Some(|g, _, t| {
            g.buff(t, 2, 0, true);
            g.em(t).give_tag("IMMUNE", true);
        }),
        ..d()
    });
    r.insert("VAN_EX1_544", Hooks { // Flare
        spell: Some(|g, me, _| {
            for m in g.all_minions() {
                g.em(m).erase_tag("STEALTH");
            }
            let enemy = g.foe(me);
            for s in g.players[enemy].secrets.clone() {
                g.players[enemy].secrets.retain(|&x| x != s);
                g.em(s).zone = "GRAVEYARD";
                g.log_event(json!({"type": "destroy", "target": s}));
            }
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_DS1_175", Hooks { // Timber Wolf
        aura: Some(|g, me| {
            for m in g.others(me) {
                if g.e(m).race() == "BEAST" {
                    g.aura_add(m, 1, 0, &[]);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_DS1_184", Hooks { // Tracking
        spell: Some(|g, me, _| {
            let deck = &g.players[g.ctrl(me)].deck;
            let opts: Vec<Id> = deck[deck.len().saturating_sub(3)..].to_vec();
            if !opts.is_empty() {
                g.request_choice(me, opts);
            }
        }),
        on_choose: Some(|g, me, opt, still| {
            let p = g.ctrl(me);
            let rest: Vec<Id> = still.into_iter().filter(|&id| id != opt).collect();
            g.draw_entity(p, opt);
            for e in rest {
                g.players[p].deck.retain(|&x| x != e);
                g.em(e).zone = "GRAVEYARD";
                let card = g.e(e).card_id.clone();
                g.log_event(json!({"type": "discard", "player": p, "entity": e, "card": card}));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_610", Hooks { // Explosive Trap
        secret: Some(Secret { event: "attack", cond: attacks_my_hero, effect: |g, me, _| {
            for c in g.chars(g.foe(me)) {
                g.damage(me, c, g.spell_dmg(me, 2));
            }
        }}),
        ..d()
    });
    r.insert("VAN_EX1_611", Hooks { // Freezing Trap
        secret: Some(Secret {
            event: "attack",
            cond: |g, me, ev| g.e(g.ev_i(ev, "attacker")).is_minion() && !ev_mine(g, me, ev),
            effect: |g, _, ev| {
                let n = g.return_to_hand(g.ev_i(ev, "attacker"));
                if n != NONE {
                    g.em(n).add_enchant(json!({"cost": 2}));
                }
            },
        }),
        ..d()
    });
    r.insert("VAN_EX1_533", Hooks { // Misdirection
        secret: Some(Secret { event: "attack", cond: attacks_my_hero, effect: |g, me, ev| {
            let attacker = g.ev_i(ev, "attacker");
            let my_hero = g.hero(g.ctrl(me));
            let pool: Vec<Id> = g.all_chars().into_iter().filter(|&c| c != attacker && c != my_hero).collect();
            let t = g.random_alive(&pool);
            if t != NONE {
                g.ev_set(ev, "defender", json!(t));
            }
        }}),
        ..d()
    });
    r.insert("VAN_EX1_531", Hooks { // Scavenging Hyena
        on: vec![("death", |g, me, ev| {
            if g.ev_b(ev, "minion") && ev_mine(g, me, ev) && card_db::card(g.ev_s(ev, "card")).race == "BEAST" {
                g.buff(me, 2, 1, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_554", Hooks { // Snake Trap
        secret: Some(Secret {
            event: "attack",
            cond: |g, me, ev| {
                let d = g.e(g.ev_i(ev, "defender"));
                d.is_minion() && d.controller == g.ctrl(me) && g.minions(g.ctrl(me)).len() < MAX_BOARD
            },
            effect: |g, me, _| {
                for _ in 0..3 {
                    g.summon(g.ctrl(me), "VAN_EX1_554t", -1);
                }
            },
        }),
        ..d()
    });
    r.insert("VAN_EX1_609", Hooks { // Snipe
        secret: Some(Secret {
            event: "after_summon",
            cond: |g, me, ev| g.ev_b(ev, "played") && !ev_mine(g, me, ev),
            effect: |g, me, ev| { g.damage(me, g.ev_i(ev, "entity"), g.spell_dmg(me, 4)); },
        }),
        ..d()
    });
    r.insert("VAN_CS2_237", Hooks { // Starving Buzzard
        on: vec![("summon", |g, me, ev| {
            let e = g.ev_i(ev, "entity");
            if ev_mine(g, me, ev) && e != me && g.e(e).race() == "BEAST" {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_NEW1_031", Hooks { // Animal Companion
        spell: Some(|g, me, _| {
            let c = g.pick(&COMPANIONS).unwrap();
            g.summon(g.ctrl(me), c, -1);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_033", Hooks { // Leokk: your other minions have +1 Attack.
        aura: Some(|g, me| {
            for m in g.others(me) {
                g.aura_add(m, 1, 0, &[]);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_617", Hooks { // Deadly Shot
        can_play: Some(has_enemy_minions),
        spell: Some(|g, me, _| {
            let t = g.random_alive(&g.minions(g.foe(me)));
            g.destroy(t);
        }),
        ..d()
    });
    r.insert("VAN_EX1_536", Hooks { // Eaglehorn Bow
        on: vec![("secret_revealed", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.add_tag_int(me, "DURABILITY", 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_539", Hooks { // Kill Command
        target: ANY,
        spell: Some(|g, me, t| {
            let beast = g.minions(g.ctrl(me)).iter().any(|&m| g.e(m).race() == "BEAST");
            g.damage(me, t, g.spell_dmg(me, if beast { 5 } else { 3 }));
        }),
        ..d()
    });
    r.insert("VAN_EX1_538", Hooks { // Unleash the Hounds
        can_play: Some(has_enemy_minions),
        spell: Some(|g, me, _| {
            for _ in 0..g.minions(g.foe(me)).len() {
                g.summon(g.ctrl(me), "EX1_538t", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_DS1_070", Hooks { // Houndmaster
        target: spec_if(Base::FriendlyMinion, is_beast),
        battlecry: Some(|g, _, t| {
            g.buff(t, 2, 2, false);
            g.em(t).give_tag("TAUNT", false);
        }),
        ..d()
    });
    r.insert("VAN_DS1_183", Hooks { // Multi-Shot. 2014: needs two enemy minions (as Fireplace).
        can_play: Some(|g, me| g.minions(g.foe(me)).len() >= 2),
        spell: Some(|g, me, _| super::shaman::two_random_enemies(g, me, 3)),
        ..d()
    });
    r.insert("VAN_EX1_537", Hooks { // Explosive Shot
        target: MINION,
        spell: Some(|g, me, t| {
            let near = g.adjacent(t);
            g.damage(me, t, g.spell_dmg(me, 5));
            for m in near {
                g.damage(me, m, g.spell_dmg(me, 2));
            }
        }),
        ..d()
    });
    r.insert("VAN_DS1_178", Hooks { // Tundra Rhino: your Beasts have Charge.
        aura: Some(|g, me| {
            for m in g.minions(g.ctrl(me)) {
                if g.e(m).race() == "BEAST" {
                    g.aura_add(m, 0, 0, &[("CHARGE", json!(true))]);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_534", Hooks { // Savannah Highmane
        deathrattle: Some(|g, me| {
            for _ in 0..2 {
                g.summon(g.ctrl(me), "EX1_534t", g.died_pos(me));
            }
        }),
        ..d()
    });
    r.insert("VAN_DS1_188", Hooks { immune_while_attacking: true, ..d() }); // Gladiator's Longbow
}
