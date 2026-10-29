//! The bot's search: the actions it tries, its time limit on a full board, its worlds.

use classichs_engine::{api, scenario};
use classichs_server::bots::brain::{decide, options, Knowledge, Level};
use classichs_server::bots::cards::Library;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

const YETI: &str = "VAN_CS2_182";
const GOLEM: &str = "VAN_CS2_186"; // War Golem 7/7
const ARGUS: &str = "VAN_EX1_093"; // Defender of Argus: adjacent minions get +1/+1 and Taunt
const ARCHER: &str = "VAN_CS2_189"; // Elven Archer: 1 damage to anything

fn game(hand: &[&str], own: usize, foe: usize) -> classichs_engine::state::Game {
    let lib = Library::get();
    scenario::build_in(lib.rs, &json!({"turn": 20, "current": 0, "players": [
        {"hero": "HERO_08", "mana": 10, "max_mana": 10, "hand": hand, "board": vec![YETI; own], "deck": vec![YETI; 10]},
        {"hero": "HERO_01", "mana": 10, "max_mana": 10, "hand": [YETI, YETI, YETI], "board": vec![YETI; foe], "deck": vec![YETI; 10]}]}))
    .expect("scenario")
}

fn plays_of(g: &classichs_engine::state::Game, card: &str) -> Vec<i64> {
    options(g, 0)
        .iter()
        .filter(|a| a["type"] == "play" && g.e(a["entity"].as_i64().unwrap()).card_id == card)
        .map(|a| a["pos"].as_i64().unwrap())
        .collect()
}

#[test]
fn a_minion_goes_only_to_the_right_without_neighbour_cards() {
    let g = game(&[GOLEM], 3, 2);
    assert_eq!(plays_of(&g, GOLEM), vec![3], "one place: the rightmost slot");
}

#[test]
fn every_place_counts_when_a_neighbour_card_is_in_hand() {
    // the big minion now, Defender of Argus next to it later: where the Golem stands matters
    let g = game(&[GOLEM, ARGUS], 3, 2);
    let mut got = plays_of(&g, GOLEM);
    got.sort();
    assert_eq!(got, vec![0, 1, 2, 3]);
    let g = game(&[GOLEM], 0, 2);
    let mut lib_board = g.clone_state();
    let argus = lib_board.new_entity(ARGUS, 0);
    lib_board.place_on_board(argus, -1); // a neighbour card on the board counts too
    lib_board.update_auras();
    assert_eq!(plays_of(&lib_board, GOLEM).len(), 2);
}

#[test]
fn identical_copies_play_once() {
    let g = game(&[ARCHER, ARCHER], 1, 1);
    let targets: Vec<i64> = options(&g, 0).iter().filter(|a| a["type"] == "play").map(|a| a["target"].as_i64().unwrap()).collect();
    let mut unique = targets.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(targets.len(), unique.len(), "one Elven Archer per target, not two");
}

/// A full board with a hand of targeted battlecries: before the search took minutes (L ≈ 480).
#[test]
fn a_full_board_decides_within_the_limit() {
    let lib = Library::get();
    let hand = ["VAN_CS2_189", "VAN_CS2_188", "VAN_EX1_019", "VAN_CS2_203", "VAN_EX1_046", "VAN_CS2_150", "VAN_CS2_029"];
    let g = game(&hand, 5, 7);
    let k = Knowledge { lib, seat: 0, my_deck: vec![YETI.into(); 30], arena: false };
    for (level, budget) in [(Level::Easy, 0), (Level::Medium, 300), (Level::Hard, 1000)] {
        let budget = Duration::from_millis(budget);
        let t = Instant::now();
        let d = decide(&api::snapshot(&g, 0), &k, level, budget).unwrap().expect("a move");
        let took = t.elapsed();
        // the limit plus one action's worth of work after it
        assert!(took < Level::limit(budget) + Duration::from_millis(400), "{level:?}: {took:?}");
        assert!(d.worlds <= 10, "{level:?}: {} worlds", d.worlds);
        assert!(d.action.get("type").and_then(Value::as_str).is_some());
    }
}

#[test]
fn hard_thinks_in_ten_worlds_at_most() {
    let lib = Library::get();
    let g = game(&[YETI], 1, 1);
    let k = Knowledge { lib, seat: 0, my_deck: vec![YETI.into(); 30], arena: false };
    let d = decide(&api::snapshot(&g, 0), &k, Level::Hard, Duration::from_secs(5)).unwrap().unwrap();
    assert!(d.worlds >= 1 && d.worlds <= 10, "{} worlds", d.worlds);
}
