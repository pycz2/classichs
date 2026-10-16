//! Neutral cards and their tokens (cards/neutral.gd). The Basic ones are Lua now
//! (packs/classic/scripts/neutral.lua).

use super::*;
use crate::entity::NONE;
use crate::state::MAX_BOARD;
use serde_json::json;

fn not_me(_g: &Game, me: Id, t: Id) -> bool {
    t != me
}

/// Enrage: while damaged, the minion gets atk and tags.
fn enrage(g: &mut Game, me: Id, atk: i64, tags: &[(&str, serde_json::Value)]) {
    if g.e(me).damage > 0 {
        g.aura_add(me, atk, 0, tags);
    }
}


fn is_murloc_other(g: &Game, me: Id, m: Id) -> bool {
    m != me && g.e(m).race() == "MURLOC"
}

const DREAMS: [&str; 5] = ["VAN_DREAM_01", "VAN_DREAM_02", "VAN_DREAM_03", "VAN_DREAM_04", "VAN_DREAM_05"];
const CHORDS: [&str; 3] = ["PRO_001a", "PRO_001b", "VAN_PRO_001c"];
const HORDE: [&str; 6] = ["VAN_CS2_121", "VAN_CS2_179", "VAN_EX1_023", "VAN_EX1_390", "VAN_EX1_021", "VAN_EX1_110"];
const INVENTIONS: [&str; 4] = ["Mekka1", "Mekka2", "Mekka3", "Mekka4"];

pub fn register(r: &mut Registry) {
    common(r);
    rare(r);
    epic(r);
    legendary(r);
    legendary_tokens(r);
}

fn common(r: &mut Registry) {
    r.insert("VAN_CS2_188", Hooks { target: MINION, battlecry: Some(|g, _, t| g.buff(t, 2, 0, true)), ..d() }); // Abusive Sergeant
    r.insert("VAN_EX1_029", Hooks { deathrattle: Some(|g, me| { g.damage(me, g.hero(g.foe(me)), 2); }), ..d() }); // Leper Gnome
    r.insert("VAN_CS2_146", Hooks { // Southsea Deckhand
        aura: Some(|g, me| {
            if g.weapon(g.ctrl(me)).is_some() {
                g.aura_add(me, 0, 0, &[("CHARGE", json!(true))]);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_393", Hooks { aura: Some(|g, me| enrage(g, me, 3, &[])), ..d() }); // Amani Berserker
    r.insert("VAN_NEW1_018", Hooks { // Bloodsail Raider
        battlecry: Some(|g, me, _| {
            if let Some(w) = g.weapon(g.ctrl(me)) {
                g.buff(me, g.e(w).atk(), 0, false);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_162", Hooks { // Dire Wolf Alpha
        aura: Some(|g, me| {
            for m in g.adjacent(me) {
                g.aura_add(m, 1, 0, &[]);
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_203", Hooks { target: MINION, battlecry: Some(|g, _, t| g.silence(t)), ..d() }); // Ironbeak Owl
    r.insert("VAN_EX1_096", Hooks { deathrattle: Some(|g, me| { g.draw(g.ctrl(me), 1); }), ..d() }); // Loot Hoarder
    r.insert("VAN_EX1_082", Hooks { // Mad Bomber: 3 damage randomly split between all other characters.
        battlecry: Some(|g, me, _| {
            for _ in 0..3 {
                let pool: Vec<Id> = g.all_chars().into_iter().filter(|&c| c != me && g.e(c).health() > 0).collect();
                let t = g.random_choice(&pool);
                g.damage(me, t, 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_049", Hooks { target: spec_if(Base::FriendlyMinion, not_me), battlecry: Some(|g, _, t| { g.return_to_hand(t); }), ..d() }); // Youthful Brewmaster
    r.insert("VAN_EX1_007", Hooks { // Acolyte of Pain
        on: vec![("damage", |g, me, ev| {
            if g.ev_i(ev, "target") == me {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_117", Hooks { target: ANY, battlecry: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 3)); }), ..d() }); // Earthen Ring Farseer
    r.insert("VAN_tt_004", Hooks { // Flesheating Ghoul
        on: vec![("death", |g, me, ev| {
            if g.ev_b(ev, "minion") {
                g.buff(me, 1, 0, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_556", Hooks { deathrattle: Some(|g, me| { g.summon(g.ctrl(me), "VAN_skele21", g.died_pos(me)); }), ..d() }); // Harvest Golem
    r.insert("VAN_EX1_412", Hooks { aura: Some(|g, me| enrage(g, me, 1, &[("WINDFURY", json!(true))])), ..d() }); // Raging Worgen
    r.insert("VAN_EX1_390", Hooks { aura: Some(|g, me| enrage(g, me, 3, &[])), ..d() }); // Tauren Warrior
    r.insert("VAN_EX1_057", Hooks { target: spec_if(Base::FriendlyMinion, not_me), battlecry: Some(|g, _, t| { g.return_to_hand(t); }), ..d() }); // Ancient Brewmaster
    r.insert("VAN_EX1_595", Hooks { // Cult Master. 2014: no draw if it dies at the same time.
        on: vec![("death", |g, me, ev| {
            if g.ev_b(ev, "minion") && ev_mine(g, me, ev) {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_046", Hooks { target: MINION, battlecry: Some(|g, _, t| g.buff(t, 2, 0, true)), ..d() }); // Dark Iron Dwarf
    r.insert("VAN_NEW1_022", Hooks { // Dread Corsair
        cost_mod: Some(|g, me| g.weapon(g.ctrl(me)).map_or(0, |w| -g.e(w).atk())),
        ..d()
    });
    r.insert("VAN_EX1_048", Hooks { target: MINION, battlecry: Some(|g, _, t| g.silence(t)), ..d() }); // Spellbreaker
    r.insert("VAN_CS2_151", Hooks { battlecry: Some(|g, me, _| { g.summon_right(me, "VAN_CS2_152"); }), ..d() }); // Silver Hand Knight
    r.insert("VAN_CS2_221", Hooks { // Spiteful Smith
        aura: Some(|g, me| {
            if let Some(w) = g.weapon(g.ctrl(me)) {
                if g.e(me).damage > 0 {
                    g.aura_add(w, 2, 0, &[]);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_CS2_227", Hooks { // Venture Co. Mercenary
        cost_aura: Some(|g, me, card, c| {
            let x = g.e(card);
            if x.controller == g.ctrl(me) && x.is_minion() && x.zone == "HAND" { c + 3 } else { c }
        }),
        ..d()
    });
    r.insert("VAN_EX1_283", Hooks { target: ANY, battlecry: Some(|g, _, t| g.freeze(t)), ..d() }); // Frost Elemental
    r.insert("VAN_EX1_583", Hooks { battlecry: Some(|g, me, _| { g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 4)); }), ..d() }); // Priestess of Elune
}

fn rare(r: &mut Registry) {
    r.insert("VAN_EX1_009", Hooks { aura: Some(|g, me| enrage(g, me, 5, &[])), ..d() }); // Angry Chicken
    r.insert("VAN_NEW1_025", Hooks { // Bloodsail Corsair
        battlecry: Some(|g, me, _| {
            if let Some(w) = g.weapon(g.foe(me)) {
                g.add_tag_int(w, "DURABILITY", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_001", Hooks { on: vec![("heal", |g, me, _| g.buff(me, 2, 0, false))], ..d() }); // Lightwarden
    r.insert("VAN_EX1_509", Hooks { // Murloc Tidecaller
        on: vec![("summon", |g, me, ev| {
            let e = g.ev_i(ev, "entity");
            if e != me && g.e(e).race() == "MURLOC" {
                g.buff(me, 1, 0, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_080", Hooks { // Secretkeeper
        on: vec![("play", |g, me, ev| {
            if g.ev_b(ev, "secret") {
                g.buff(me, 1, 1, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_004", Hooks { // Young Priestess
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
    r.insert("VAN_EX1_059", Hooks { // Crazed Alchemist
        target: MINION,
        battlecry: Some(|g, _, t| {
            let (h, a) = (g.e(t).health(), g.e(t).atk());
            g.set_stats(t, h, a);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_019", Hooks { // Knife Juggler
        on: vec![("after_summon", |g, me, ev| {
            if ev_mine(g, me, ev) && g.ev_i(ev, "entity") != me {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_055", Hooks { // Mana Addict
        on: vec![("play", |g, me, ev| {
            if g.ev_s(ev, "kind") == "spell" && ev_mine(g, me, ev) {
                g.buff(me, 2, 0, true);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_616", Hooks { // Mana Wraith
        cost_aura: Some(|g, _, card, c| if g.e(card).is_minion() && g.e(card).zone == "HAND" { c + 1 } else { c }),
        ..d()
    });
    r.insert("VAN_NEW1_037", Hooks { // Master Swordsmith
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.others(me));
                if t != NONE {
                    g.buff(t, 1, 0, false);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_076", Hooks { // Pint-Sized Summoner
        cost_aura: Some(|g, me, card, c| {
            let first = g.players[g.ctrl(me)].minions_played_this_turn == 0;
            let x = g.e(card);
            if first && x.controller == g.ctrl(me) && x.is_minion() && x.zone == "HAND" { c - 1 } else { c }
        }),
        ..d()
    });
    r.insert("VAN_EX1_058", Hooks { // Sunfury Protector
        battlecry: Some(|g, me, _| {
            for m in g.adjacent(me) {
                g.em(m).give_tag("TAUNT", false);
            }
        }),
        ..d()
    });
    r.insert("VAN_NEW1_020", Hooks { // Wild Pyromancer
        on: vec![("after_spell", |g, me, ev| {
            if ev_mine(g, me, ev) {
                for m in g.all_minions() {
                    g.damage(me, m, 1);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_006", Hooks { // Alarm-o-Bot
        on: vec![("turn_start", |g, me, ev| {
            if !ev_mine(g, me, ev) {
                return;
            }
            let p = g.ctrl(me);
            let minions: Vec<Id> = g.players[p].hand.iter().copied().filter(|&e| g.e(e).is_minion()).collect();
            let m = g.random_choice(&minions);
            if m == NONE {
                return;
            }
            let pos = g.board_pos(me).map_or(-1, |i| i as i64);
            g.players[p].hand.retain(|&x| x != m);
            g.return_to_hand(me);
            g.summon_entity(m, pos);
        })],
        ..d()
    });
    r.insert("VAN_EX1_089", Hooks { battlecry: Some(|g, me, _| g.gain_mana(g.foe(me), 1, false)), ..d() }); // Arcane Golem
    r.insert("VAN_EX1_050", Hooks { // Coldlight Oracle
        battlecry: Some(|g, me, _| {
            g.draw(g.ctrl(me), 2);
            g.draw(g.foe(me), 2);
        }),
        ..d()
    });
    r.insert("VAN_EX1_103", Hooks { // Coldlight Seer
        battlecry: Some(|g, me, _| {
            for m in g.all_minions() {
                if is_murloc_other(g, me, m) {
                    g.buff(m, 0, 2, false);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_102", Hooks { // Demolisher
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, 2);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_170", Hooks { // Emperor Cobra
        on: vec![("damage", |g, me, ev| {
            let t = g.ev_i(ev, "target");
            if g.ev_i(ev, "source") == me && g.e(t).is_minion() {
                g.destroy(t);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_597", Hooks { // Imp Master
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.damage(me, me, 1);
                g.summon_right(me, "VAN_EX1_598");
            }
        })],
        ..d()
    });
    r.insert("VAN_CS2_181", Hooks { battlecry: Some(|g, me, _| { g.damage(me, me, 4); }), ..d() }); // Injured Blademaster
    r.insert("VAN_EX1_085", Hooks { // Mind Control Tech
        battlecry: Some(|g, me, _| {
            let enemy = g.minions(g.foe(me));
            if enemy.len() >= 4 {
                let t = g.random_choice(&enemy);
                g.take_control(t, g.ctrl(me));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_044", Hooks { // Questing Adventurer
        on: vec![("play", |g, me, ev| {
            if ev_mine(g, me, ev) && g.ev_i(ev, "entity") != me {
                g.buff(me, 1, 1, false);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_584", Hooks { // Ancient Mage
        battlecry: Some(|g, me, _| {
            for m in g.adjacent(me) {
                g.add_tag_int(m, "SPELLPOWER", 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_093", Hooks { // Defender of Argus
        battlecry: Some(|g, me, _| {
            for m in g.adjacent(me) {
                g.buff(m, 1, 1, false);
                g.em(m).give_tag("TAUNT", false);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_043", Hooks { // Twilight Drake
        battlecry: Some(|g, me, _| {
            let n = g.players[g.ctrl(me)].hand.len() as i64;
            g.buff(me, 0, n, false);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_026", Hooks { // Violet Teacher
        on: vec![("play", |g, me, ev| {
            if g.ev_s(ev, "kind") == "spell" && ev_mine(g, me, ev) {
                g.summon_right(me, "VAN_NEW1_026t");
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_097", Hooks { // Abomination
        deathrattle: Some(|g, me| {
            for c in g.all_chars() {
                g.damage(me, c, 2);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_284", Hooks { battlecry: Some(|g, me, _| { g.draw(g.ctrl(me), 1); }), ..d() }); // Azure Drake
    r.insert("VAN_EX1_095", Hooks { // Gadgetzan Auctioneer
        on: vec![("play", |g, me, ev| {
            if g.ev_s(ev, "kind") == "spell" && ev_mine(g, me, ev) {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_NEW1_041", Hooks { // Stampeding Kodo
        battlecry: Some(|g, me, _| {
            let small: Vec<Id> = g.minions(g.foe(me)).into_iter().filter(|&m| g.e(m).atk() <= 2).collect();
            let t = g.random_alive(&small);
            g.destroy(t);
        }),
        ..d()
    });
}

fn epic(r: &mut Registry) {
    r.insert("VAN_NEW1_017", Hooks { // Hungry Crab
        target: spec_if(Base::Minion, |g, _, t| g.e(t).race() == "MURLOC"),
        battlecry: Some(|g, me, t| {
            g.destroy(t);
            g.buff(me, 2, 2, false);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_016", Hooks { // Captain's Parrot
        battlecry: Some(|g, me, _| {
            let p = g.ctrl(me);
            let pirates: Vec<Id> = g.players[p].deck.iter().copied().filter(|&e| g.e(e).race() == "PIRATE").collect();
            let e = g.random_choice(&pirates);
            if e != NONE {
                g.draw_entity(p, e);
            }
        }),
        ..d()
    });
    r.insert("VAN_NEW1_021", Hooks { // Doomsayer
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) {
                for m in g.all_minions() {
                    g.destroy(m);
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_005", Hooks { target: spec_if(Base::Minion, |g, _, t| g.e(t).atk() >= 7), battlecry: Some(|g, _, t| g.destroy(t)), ..d() }); // Big Game Hunter
    r.insert("VAN_EX1_590", Hooks { // Blood Knight
        battlecry: Some(|g, me, _| {
            let mut n = 0;
            for m in g.all_minions() {
                if g.e(m).has("DIVINE_SHIELD") {
                    g.em(m).erase_tag("DIVINE_SHIELD");
                    n += 1;
                }
            }
            g.buff(me, 3 * n, 3 * n, false);
        }),
        ..d()
    });
    r.insert("VAN_EX1_507", Hooks { // Murloc Warleader
        aura: Some(|g, me| {
            for m in g.all_minions() {
                if is_murloc_other(g, me, m) {
                    g.aura_add(m, 2, 1, &[]);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_NEW1_027", Hooks { // Southsea Captain
        aura: Some(|g, me| {
            for m in g.others(me) {
                if g.e(m).race() == "PIRATE" {
                    g.aura_add(m, 1, 1, &[]);
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_564", Hooks { target: spec_if(Base::Minion, not_me), battlecry: Some(|g, me, t| { copy_minion(g, me, t); }), ..d() }); // Faceless Manipulator
    r.insert("VAN_EX1_586", Hooks { cost_mod: Some(|g, _| -(g.all_minions().len() as i64)), ..d() }); // Sea Giant
    r.insert("VAN_EX1_105", Hooks { cost_mod: Some(|g, me| -(g.players[g.ctrl(me)].hand.len() as i64 - 1)), ..d() }); // Mountain Giant
    r.insert("VAN_EX1_620", Hooks { cost_mod: Some(|g, me| -g.e(g.hero(g.ctrl(me))).damage), ..d() }); // Molten Giant
}

fn legendary(r: &mut Registry) {
    r.insert("VAN_EX1_012", Hooks { deathrattle: Some(|g, me| { g.draw(g.ctrl(me), 1); }), ..d() }); // Bloodmage Thalnos
    r.insert("VAN_EX1_100", Hooks { // Lorewalker Cho
        on: vec![("play", |g, _, ev| {
            if g.ev_s(ev, "kind") == "spell" {
                let p = 1 - g.ev_i(ev, "player") as usize;
                let card = g.ev_s(ev, "card").to_string();
                g.add_to_hand(p, &card);
            }
        })],
        ..d()
    });
    r.insert("VAN_NEW1_029", Hooks { // Millhouse Manastorm: enemy spells cost (0) next turn.
        battlecry: Some(|g, me, _| {
            let m = json!({"kind": "spell", "set": 0, "until": "turn_end", "turn": g.turn + 1});
            let p = g.foe(me);
            g.players[p].cost_mods.push(m.as_object().unwrap().clone());
        }),
        ..d()
    });
    r.insert("VAN_EX1_557", Hooks { // Nat Pagle
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) && g.rng.randi_range(0, 1) == 1 {
                g.draw(g.ctrl(me), 1);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_014", Hooks { // King Mukla
        battlecry: Some(|g, me, _| {
            for _ in 0..2 {
                g.add_to_hand(g.foe(me), "EX1_014t");
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_083", Hooks { // Tinkmaster Overspark
        battlecry: Some(|g, me, _| {
            let pool: Vec<Id> = g.all_minions().into_iter().filter(|&m| m != me).collect();
            let t = g.random_alive(&pool);
            if t != NONE {
                let c = g.pick(&["VAN_EX1_tk29", "VAN_EX1_tk28"]).unwrap();
                g.transform(t, c);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_116", Hooks { // Leeroy Jenkins
        battlecry: Some(|g, me, _| {
            for _ in 0..2 {
                g.summon(g.foe(me), "EX1_116t", -1);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_062", Hooks { // Old Murk-Eye
        aura: Some(|g, me| {
            let n = g.all_minions().into_iter().filter(|&m| is_murloc_other(g, me, m)).count() as i64;
            g.aura_add(me, n, 0, &[]);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_024", Hooks { // Captain Greenskin
        battlecry: Some(|g, me, _| {
            if let Some(w) = g.weapon(g.ctrl(me)) {
                g.buff(w, 1, 0, false);
                g.add_tag_int(w, "DURABILITY", 1);
            }
        }),
        ..d()
    });
    r.insert("VAN_PRO_001", Hooks { // Elite Tauren Chieftain
        battlecry: Some(|g, me, _| {
            for p in [g.ctrl(me), g.foe(me)] {
                let c = g.pick(&CHORDS).unwrap();
                g.add_to_hand(p, c);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_558", Hooks { // Harrison Jones
        battlecry: Some(|g, me, _| {
            if let Some(w) = g.weapon(g.foe(me)) {
                let n = g.e(w).tag("DURABILITY");
                g.destroy(w);
                g.draw(g.ctrl(me), n);
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_110", Hooks { deathrattle: Some(|g, me| { g.summon(g.ctrl(me), "VAN_EX1_110t", g.died_pos(me)); }), ..d() }); // Cairne Bloodhoof
    r.insert("VAN_EX1_112", Hooks { // Gelbin Mekkatorque
        battlecry: Some(|g, me, _| {
            let c = g.pick(&INVENTIONS).unwrap();
            g.summon_right(me, c);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_040", Hooks { // Hogger
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.summon_right(me, "NEW1_040t");
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_614", Hooks { // Illidan Stormrage. 2014: any card you play, The Coin included.
        on: vec![("play", |g, me, ev| {
            if ev_mine(g, me, ev) && g.ev_i(ev, "entity") != me {
                g.summon_right(me, "VAN_TU4e_002t");
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_016", Hooks { // Sylvanas Windrunner
        deathrattle: Some(|g, me| {
            let t = g.random_alive(&g.minions(g.foe(me)));
            if t != NONE {
                g.take_control(t, g.ctrl(me));
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_577", Hooks { deathrattle: Some(|g, me| { g.summon(g.foe(me), "VAN_EX1_finkle", -1); }), ..d() }); // The Beast
    r.insert("VAN_EX1_002", Hooks { target: spec_if(Base::EnemyMinion, |g, _, t| g.e(t).has("TAUNT")), battlecry: Some(|g, _, t| g.destroy(t)), ..d() }); // The Black Knight
    r.insert("VAN_EX1_249", Hooks { // Baron Geddon
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                for c in g.all_chars() {
                    if c != me {
                        g.damage(me, c, 2);
                    }
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_NEW1_038", Hooks { on: vec![("turn_end", |g, me, _| g.buff(me, 1, 1, false))], ..d() }); // Gruul: at the end of each turn.
    r.insert("VAN_EX1_298", Hooks { // Ragnaros the Firelord
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.chars(g.foe(me)));
                g.damage(me, t, 8);
            }
        })],
        ..d()
    });
    r.insert("VAN_EX1_561", Hooks { // Alexstrasza: set a hero's remaining Health to 15.
        target: spec_if(Base::Any, |g, _, t| g.e(t).is_hero()),
        battlecry: Some(|g, _, t| {
            let x = g.em(t);
            x.damage = 0.max(x.max_health() - 15);
            let h = x.health();
            g.log_event(json!({"type": "set_health", "target": t, "health": h}));
        }),
        ..d()
    });
    r.insert("VAN_EX1_562", Hooks { // Onyxia: whelps alternate right and left until the side is full.
        battlecry: Some(|g, me, _| {
            let p = g.ctrl(me);
            let mut right = true;
            while g.players[p].board.len() < MAX_BOARD {
                let i = g.players[p].board.iter().position(|&x| x == me).map_or(-1, |i| i as i64);
                g.summon(p, "ds1_whelptoken", if right { i + 1 } else { i });
                right = !right;
            }
        }),
        ..d()
    });
    r.insert("VAN_EX1_572", Hooks { // Ysera
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let c = g.pick(&DREAMS).unwrap();
                g.add_to_hand(g.ctrl(me), c);
            }
        })],
        ..d()
    });
    r.insert("VAN_NEW1_030", Hooks { // Deathwing
        battlecry: Some(|g, me, _| {
            for m in g.all_minions() {
                if m != me {
                    g.destroy(m);
                }
            }
            let p = g.ctrl(me);
            for e in g.players[p].hand.clone() {
                g.players[p].hand.retain(|&x| x != e);
                g.em(e).zone = "GRAVEYARD";
                let card = g.e(e).card_id.clone();
                g.emit(json!({"type": "discard", "player": p, "entity": e, "card": card}));
            }
        }),
        ..d()
    });
}

fn legendary_tokens(r: &mut Registry) {
    r.insert("EX1_014t", Hooks { target: MINION, spell: Some(|g, _, t| g.buff(t, 1, 1, false)), ..d() }); // Bananas
    r.insert("PRO_001a", Hooks { // I Am Murloc
        spell: Some(|g, me, _| {
            for _ in 0..g.rng.randi_range(3, 5) {
                g.summon(g.ctrl(me), "PRO_001at", -1);
            }
        }),
        ..d()
    });
    r.insert("PRO_001b", Hooks { // Rogues Do It...
        target: ANY,
        spell: Some(|g, me, t| {
            g.damage(me, t, g.spell_dmg(me, 4));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_PRO_001c", Hooks { // Power of the Horde
        spell: Some(|g, me, _| {
            let c = g.pick(&HORDE).unwrap();
            g.summon(g.ctrl(me), c, -1);
        }),
        ..d()
    });
    r.insert("Mekka1", Hooks { // Homing Chicken
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) {
                g.destroy(me);
                g.draw(g.ctrl(me), 3);
            }
        })],
        ..d()
    });
    r.insert("Mekka2", Hooks { // Repair Bot
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let hurt: Vec<Id> =
                    g.all_chars().into_iter().filter(|&c| g.e(c).damage > 0 && g.e(c).health() > 0).collect();
                let t = g.random_choice(&hurt);
                if t != NONE {
                    g.heal(me, t, g.heal_amt(me, 6));
                }
            }
        })],
        ..d()
    });
    r.insert("Mekka3", Hooks { // Emboldener 3000
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.all_minions());
                if t != NONE {
                    g.buff(t, 1, 1, false);
                }
            }
        })],
        ..d()
    });
    r.insert("Mekka4", Hooks { // Poultryizer
        on: vec![("turn_start", |g, me, ev| {
            if ev_mine(g, me, ev) {
                let t = g.random_alive(&g.all_minions());
                if t != NONE {
                    g.transform(t, "Mekka4t");
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_DREAM_02", Hooks { // Ysera Awakens
        spell: Some(|g, me, _| {
            for c in g.all_chars() {
                if g.e(c).card_id != "VAN_EX1_572" {
                    g.damage(me, c, g.spell_dmg(me, 5));
                }
            }
        }),
        ..d()
    });
    r.insert("VAN_DREAM_04", Hooks { target: MINION, spell: Some(|g, _, t| { g.return_to_hand(t); }), ..d() }); // Dream
    r.insert("VAN_DREAM_05", Hooks { // Nightmare
        target: MINION,
        spell: Some(|g, me, t| {
            g.buff(t, 5, 5, false);
            let p = g.ctrl(me);
            g.em(t).add_enchant(json!({"hooks": "ench:nightmare", "player": p}));
        }),
        ..d()
    });
    r.insert("ench:nightmare", Hooks { // At the start of the caster's next turn, destroy it.
        on: vec![("turn_start", |g, me, ev| {
            for p in g.e(me).ench_players("ench:nightmare") {
                if g.ev_i(ev, "player") == p as i64 {
                    g.destroy(me);
                }
            }
        })],
        ..d()
    });
}
