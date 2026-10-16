//! Hero powers (cards/heroes.gd); The Coin and Fireblast are Lua now
//! (packs/classic/scripts/neutral.lua, mage.lua). Upgraded powers and Demon Hunter
//! powers are unreachable in Classic: no hooks.

use super::*;

const BASIC_TOTEMS: [&str; 4] = ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"];

fn missing_totems(g: &Game, me: Id) -> Vec<&'static str> {
    let board = &g.players[g.ctrl(me)].board;
    BASIC_TOTEMS.into_iter().filter(|id| !board.iter().any(|&m| g.e(m).card_id == *id)).collect()
}

fn board_has_room(g: &Game, me: Id) -> bool {
    g.board_has_room(me)
}

pub fn register(r: &mut Registry) {
    r.insert("VAN_HERO_01bp", Hooks { hero_power: Some(|g, me, _| g.gain_armor(g.ctrl(me), 2)), ..d() }); // Armor Up!
    r.insert("VAN_HERO_02bp", Hooks { // Totemic Call
        can_play: Some(|g, me| board_has_room(g, me) && !missing_totems(g, me).is_empty()),
        hero_power: Some(|g, me, _| {
            let c = g.pick(&missing_totems(g, me)).unwrap_or("");
            g.summon(g.ctrl(me), c, -1);
        }),
        ..d()
    });
    r.insert("VAN_NEW1_009", Hooks { // Healing Totem (from Totemic Call)
        on: vec![("turn_end", |g, me, ev| {
            if ev_mine(g, me, ev) {
                for m in g.minions(g.ctrl(me)) {
                    g.heal(me, m, g.heal_amt(me, 1));
                }
            }
        })],
        ..d()
    });
    r.insert("VAN_HERO_03bp", Hooks { hero_power: Some(|g, me, _| { g.equip(g.ctrl(me), "VAN_CS2_082"); }), ..d() }); // Dagger Mastery
    r.insert("VAN_HERO_04bp", Hooks { // Reinforce
        can_play: Some(board_has_room),
        hero_power: Some(|g, me, _| { g.summon(g.ctrl(me), "VAN_CS2_101t", -1); }),
        ..d()
    });
    r.insert("VAN_HERO_05bp", Hooks { hero_power: Some(|g, me, _| { g.damage(me, g.hero(g.foe(me)), g.hp_dmg(me, 2)); }), ..d() }); // Steady Shot
    r.insert("VAN_HERO_06bp", Hooks { // Shapeshift
        hero_power: Some(|g, me, _| {
            g.buff(g.hero(g.ctrl(me)), 1, 0, true);
            g.gain_armor(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_HERO_07bp", Hooks { // Life Tap. 2014: damage first, then draw (as Fireplace).
        hero_power: Some(|g, me, _| {
            g.damage(me, g.hero(g.ctrl(me)), g.hp_dmg(me, 2));
            g.draw(g.ctrl(me), 1);
        }),
        ..d()
    });
    r.insert("VAN_HERO_09bp", Hooks { target: ANY, hero_power: Some(|g, me, t| { g.heal(me, t, g.heal_amt(me, 2)); }), ..d() }); // Lesser Heal
    r.insert("VAN_EX1_tk33", Hooks { // INFERNO! (Lord Jaraxxus)
        can_play: Some(board_has_room),
        hero_power: Some(|g, me, _| { g.summon(g.ctrl(me), "VAN_EX1_tk34", -1); }),
        ..d()
    });
    r.insert("EX1_625t", Hooks { target: ANY, hero_power: Some(|g, me, t| { g.damage(me, t, g.hp_dmg(me, 2)); }), ..d() }); // Mind Spike
    r.insert("EX1_625t2", Hooks { target: ANY, hero_power: Some(|g, me, t| { g.damage(me, t, g.hp_dmg(me, 3)); }), ..d() }); // Mind Shatter
}
