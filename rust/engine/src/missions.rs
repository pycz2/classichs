//! The six tutorial missions (game/missions.gd, game/tutorial.gd): the rules
//! part only (decks, locked powers, Jaina's safety net, turn-end blocks).
//! Hints, boss lines and rewards stay in the client.

use crate::state::Game;
use serde_json::{json, Value};

pub struct Mission {
    pub boss: &'static str,
    pub boss_power: &'static str,
    pub locked: bool,
    pub unlosable: bool,
    pub guarded: bool,
    pub block_mana: bool,
    pub block_attack: bool,
    pub player_hand: &'static [&'static str],
    /// Top card first.
    pub player_deck: &'static [&'static str],
    pub boss_deck: &'static [&'static str],
}

const JAINA: &str = "HERO_08";
const FIREBLAST: &str = "VAN_HERO_08bp";

pub const LIST: [Mission; 6] = [
    Mission { boss: "TU4a_001", boss_power: FIREBLAST, locked: true, unlosable: true, guarded: false,
        block_mana: true, block_attack: true,
        player_hand: &["VAN_CS2_168"],
        player_deck: &["VAN_CS2_172", "VAN_CS2_120", "VAN_CS2_118", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_200",
            "VAN_CS2_172", "VAN_CS2_168", "VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_200", "VAN_CS2_201"],
        boss_deck: &["TU4a_002", "TU4a_003", "TU4a_002", "TU4a_004", "TU4a_005", "TU4a_003", "TU4a_002",
            "TU4a_005", "TU4a_004", "TU4a_003", "TU4a_002", "TU4a_005"] },
    Mission { boss: "TU4b_001", boss_power: FIREBLAST, locked: true, unlosable: true, guarded: false,
        block_mana: true, block_attack: true,
        player_hand: &["VAN_CS2_172", "VAN_CS2_168"],
        player_deck: &["VAN_CS2_120", "VAN_CS2_122", "VAN_CS2_118", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_122",
            "VAN_CS2_200", "VAN_CS2_119", "VAN_CS2_201", "VAN_CS2_222", "VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_200"],
        boss_deck: &["VAN_EX1_277", "VAN_CS2_024", "VAN_CS2_025", "VAN_CS2_024", "VAN_CS2_029", "VAN_EX1_277",
            "VAN_CS2_026", "VAN_CS2_025", "VAN_CS2_029", "VAN_CS2_032", "VAN_EX1_279", "VAN_EX1_279"] },
    Mission { boss: "TU4f_001", boss_power: FIREBLAST, locked: true, unlosable: false, guarded: true,
        block_mana: false, block_attack: true,
        player_hand: &["VAN_EX1_011", "VAN_CS2_189"],
        player_deck: &["VAN_EX1_015", "VAN_CS2_117", "VAN_CS2_172", "VAN_EX1_019", "VAN_DS1_055", "VAN_CS2_120",
            "VAN_CS2_141", "VAN_CS2_182", "VAN_CS2_147", "VAN_CS2_200", "VAN_CS2_150", "VAN_CS2_179", "VAN_CS2_182",
            "VAN_CS2_201", "VAN_CS2_222"],
        boss_deck: &["TU4f_002", "TU4f_003", "TU4f_006", "TU4f_002", "TU4f_004", "TU4f_005", "TU4f_003", "TU4f_005",
            "TU4f_004", "TU4f_002", "TU4f_005", "TU4f_003"] },
    Mission { boss: "TU4c_001", boss_power: FIREBLAST, locked: true, unlosable: false, guarded: false,
        block_mana: false, block_attack: false,
        player_hand: &["VAN_CS1_042", "VAN_CS2_171", "VAN_EX1_019"],
        player_deck: &["VAN_CS2_124", "VAN_CS2_121", "VAN_CS2_022", "VAN_CS2_179", "VAN_CS2_213", "VAN_CS2_182",
            "VAN_CS2_022", "VAN_CS2_200", "VAN_CS2_162", "VAN_CS2_222", "VAN_CS2_179", "VAN_CS2_201", "VAN_CS2_213"],
        boss_deck: &["TU4c_003", "TU4c_002", "TU4f_007", "TU4c_004", "TU4c_005", "TU4c_006", "TU4c_007", "TU4c_008",
            "TU4c_003", "TU4c_002", "TU4f_007", "TU4c_007"] },
    Mission { boss: "TU4d_001", boss_power: "TU4d_003", locked: false, unlosable: false, guarded: false,
        block_mana: false, block_attack: false,
        player_hand: &["VAN_EX1_277", "VAN_CS2_172", "VAN_CS2_027"],
        player_deck: &["VAN_CS2_024", "VAN_CS2_033", "VAN_CS2_029", "VAN_CS2_120", "VAN_CS2_022", "VAN_CS2_182",
            "VAN_CS2_023", "VAN_CS2_024", "VAN_CS2_029", "VAN_CS2_200", "VAN_CS2_032", "VAN_CS2_033", "VAN_CS2_201"],
        boss_deck: &["TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002",
            "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002"] },
    Mission { boss: "TU4e_001", boss_power: "TU4e_002", locked: false, unlosable: false, guarded: false,
        block_mana: false, block_attack: false,
        player_hand: &["VAN_CS2_027", "VAN_CS2_024", "VAN_CS2_172"],
        player_deck: &["VAN_CS2_025", "VAN_CS2_120", "VAN_EX1_277", "VAN_CS2_033", "VAN_CS2_023", "VAN_CS2_182",
            "VAN_CS2_032", "VAN_CS2_029", "VAN_CS2_033", "VAN_CS2_200", "VAN_CS2_022", "VAN_CS2_029", "VAN_CS2_201",
            "VAN_CS2_222", "VAN_CS2_026"],
        boss_deck: &["TU4e_003", "TU4e_004", "TU4e_003", "TU4e_005", "TU4e_003", "TU4e_007", "TU4e_003", "TU4e_003",
            "TU4e_003", "TU4e_003", "TU4e_003", "TU4e_003"] },
];

/// Mission n (1-based).
pub fn get(n: usize) -> Option<&'static Mission> {
    LIST.get(n.wrapping_sub(1))
}

/// The scenario of mission n: scripted hands and deck order, Jaina first, no mulligan.
pub fn scenario(m: &Mission) -> Value {
    let rev = |v: &[&str]| v.iter().rev().map(|s| s.to_string()).collect::<Vec<_>>(); // Scenario: the last card is the top
    json!({"current": 0, "players": [
        {"hero": JAINA, "mana": 1, "max_mana": 1, "hand": m.player_hand, "deck": rev(m.player_deck),
            "hero_power_locked": m.locked},
        {"hero": m.boss, "hero_power": m.boss_power, "hand": [], "deck": rev(m.boss_deck), "hero_power_locked": m.locked},
    ]})
}

/// Tutorial.start: the mission's game with Jaina's safety net and the guarded boss.
pub fn start(n: usize) -> Result<Game, String> {
    let m = get(n).ok_or_else(|| format!("no mission {n}"))?;
    let mut g = crate::scenario::build(&scenario(m))?;
    if m.unlosable {
        let h = g.hero(0);
        g.em(h).add_enchant(json!({"hooks": "ench:tutorial_guard"}));
    }
    if m.guarded {
        let h = g.hero(1);
        g.em(h).give_tag("GUARDED", false);
    }
    Ok(g)
}

/// Why player p can't end the turn yet ("" = they can), as in the first original missions.
pub fn end_turn_block(m: &Mission, g: &Game, p: usize) -> &'static str {
    if g.current != p || g.game_over {
        return "";
    }
    let legal = g.legal_actions();
    let any = |ty: &str| legal.iter().any(|a| a["player"] == p && a["type"] == ty);
    if m.block_mana && any("play") {
        return "Not yet! You have more cards to play!";
    }
    if m.block_attack && any("attack") {
        return "Not yet! You can still attack.";
    }
    ""
}
