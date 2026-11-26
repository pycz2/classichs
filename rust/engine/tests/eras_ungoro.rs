//! Hearthstone 2014–2019 (packs/eras): the Journey to Un'Goro versions (18336, 19506, 19632, 20022), each played by its
//! own rules. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{pack, scenario, Game};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;
#[path = "eras_versions/built.rs"]
mod built;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The rules of each Un'Goro version, packs/eras built once; None without python3.
fn rs(vid: &str) -> Option<&'static Ruleset> {
    static R: OnceLock<Option<HashMap<String, &'static Ruleset>>> = OnceLock::new();
    let all = R.get_or_init(|| {
        let files = built::built("packs/eras")?;
        let load = |v: &str| -> &'static Ruleset { Box::leak(Box::new(ruleset::load(&pack::version_view(&files, v).unwrap()).unwrap())) };
        Some(["18336", "19506", "19632", "20022"].into_iter().map(|v| (v.to_string(), load(v))).collect())
    });
    all.as_ref().map(|m| m[vid])
}

const WISP: &str = "VAN_CS2_231";
const CAVERNS: &str = "UNG_067";
const CORE: &str = "UNG_067t1";
const NONE: Id = -1;

/// A game of version vid: p0 (a Rogue) holds `hand`, 10 mana; p0's turn.
fn game(vid: &str, hand: &[&str]) -> Option<Game> {
    let fill = [WISP; 6];
    let sc = json!({"current": 0, "seed": 7, "players": [
        {"hero": "HERO_03", "mana": 10, "max_mana": 10, "deck": fill, "hand": hand},
        {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": fill}]});
    Some(scenario::build_in(rs(vid)?, &sc).unwrap())
}

fn play(g: &mut Game, card: &str) {
    let e = *g.players[0].hand.iter().find(|&&e| g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"));
    let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == NONE)
        .unwrap_or_else(|| panic!("can't play {card}"));
    let r = g.apply(&Value::Object(a));
    assert!(r.ok, "play {card}: {}", r.error);
    assert_eq!(g.script_error.get(), None, "play {card}");
}

fn has_core(g: &Game) -> bool {
    g.players[0].hand.iter().any(|&e| g.e(e).card_id == CORE)
}

/// Patch 8.4.0.20022: The Caverns Below needs five minions with the same name (four before).
#[test]
fn the_caverns_below_needs_five_minions_from_20022() {
    for (vid, goal) in [("18336", 4), ("19632", 4), ("20022", 5)] {
        let Some(mut g) = game(vid, &[CAVERNS, WISP, WISP, WISP, WISP, WISP]) else {
            eprintln!("no python3: skipped");
            return;
        };
        play(&mut g, CAVERNS);
        let q = g.players[0].secrets[0];
        assert_eq!(g.e(q).tag("QUEST_PROGRESS_TOTAL"), goal, "version {vid}");
        for i in 1..goal {
            play(&mut g, WISP);
            assert!(!has_core(&g), "version {vid}: not after {i} Wisps");
        }
        play(&mut g, WISP);
        assert!(has_core(&g), "version {vid}: Crystal Core after {goal} Wisps");
        assert!(g.players[0].secrets.is_empty(), "version {vid}");
    }
}

/// Patch 8.4.0.20022: six more Elementals.
#[test]
fn six_more_elementals_from_20022() {
    for id in ["CFM_606", "CFM_606t", "CFM_715", "VAN_TU4e_002t", "LOE_053", "OG_209"] {
        let (Some(old), Some(new)) = (rs("19632"), rs("20022")) else {
            eprintln!("no python3: skipped");
            return;
        };
        assert_eq!(old.card(id).race, "", "{id} in 19632");
        assert_eq!(new.card(id).race, "ELEMENTAL", "{id} in 20022");
    }
}
