//! Classic cards as they were in 2014 (patch 1.0.0.5834, the last before Naxxramas) where
//! the 2021 Classic data (VAN_*) differs: stats, Bane of Doom, Eaglehorn Bow, Sacrificial
//! Pact on Lord Jaraxxus, Nozdormu's turn time (docs/superpowers/plans/2026-11-09-fixes-and-naxx.md, R).

use classichs_engine::{card_db, Engine};
use serde_json::{json, Value};

fn call(e: &mut Engine, req: Value) -> Value {
    serde_json::from_str(&e.call(&req.to_string())).unwrap()
}

const DECK: [&str; 3] = ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"];

fn scene(e: &mut Engine, p0: Value, p1: Value) -> Value {
    let mut ps = [p0, p1];
    for p in &mut ps {
        p["deck"] = json!(DECK);
    }
    ps[0]["mana"] = json!(10);
    ps[0]["max_mana"] = json!(10);
    let r = call(e, json!({"op": "new", "game": "g", "scenario": {"current": 0, "players": ps}}));
    assert_eq!(r["ok"], true, "{r}");
    state(e)
}

fn state(e: &mut Engine) -> Value {
    call(e, json!({"op": "snapshot", "game": "g"}))["state"].clone()
}

/// The ids of a card's entities in a zone (oldest first).
fn ids(st: &Value, card: &str, zone: &str) -> Vec<i64> {
    let mut v: Vec<i64> = st["entities"]
        .as_object()
        .unwrap()
        .iter()
        .filter(|(_, x)| x["card"] == card && x["zone"] == zone)
        .map(|(k, _)| k.parse().unwrap())
        .collect();
    v.sort();
    v
}

fn ent(st: &Value, id: i64) -> &Value {
    &st["entities"][id.to_string()]
}

fn hero(st: &Value, p: usize) -> i64 {
    st["players"][p]["hero"].as_i64().unwrap()
}

fn act(e: &mut Engine, a: Value) -> Value {
    let r = call(e, json!({"op": "act", "game": "g", "action": a}));
    assert_eq!(r["ok"], true, "{a}: {r}");
    state(e)
}

fn play(e: &mut Engine, card: i64, target: i64) -> Value {
    let pos = if state(e)["entities"][card.to_string()]["type"] == "MINION" { 0 } else { -1 };
    act(e, json!({"type": "play", "player": 0, "entity": card, "target": target, "pos": pos, "choice": -1}))
}

fn targets(e: &mut Engine, card: i64) -> Vec<i64> {
    let legal = call(e, json!({"op": "legal", "game": "g", "player": 0}))["actions"].clone();
    legal.as_array().unwrap().iter().filter(|a| a["entity"] == card).map(|a| a["target"].as_i64().unwrap()).collect()
}

#[test]
fn stats_and_tribes_are_the_2014_ones() {
    let c = |id: &str| card_db::card(id);
    assert_eq!((c("VAN_EX1_131").attack, c("VAN_EX1_131").health), (2, 2), "Defias Ringleader 2/2");
    assert_eq!(c("VAN_DREAM_01").cost, 3, "Laughing Sister costs 3");
    assert_eq!(c("VAN_EX1_finkle").cost, 2, "Finkle Einhorn costs 2");
    assert_eq!(c("PRO_001at").cost, 1, "the Murloc of I Am Murloc costs 1");
    assert_eq!(c("VAN_EX1_538").cost, 3, "Unleash the Hounds: 3 since May 2014 (1.0.0.5314)");
    for id in ["VAN_EX1_556", "VAN_skele21", "VAN_EX1_006", "VAN_EX1_102", "EX1_025t", "Mekka1", "VAN_CS2_221", "VAN_NEW1_005"] {
        assert_eq!(c(id).race, "", "{id}: no Mech or Undead tribe in 2014");
    }
}

#[test]
fn defias_ringleader_combo_summons_a_bandit() {
    let mut e = Engine::new();
    let st = scene(&mut e, json!({"hero": "HERO_03", "hand": ["VAN_CS2_231", "VAN_EX1_131"]}), json!({"hero": "HERO_01"}));
    let st = play(&mut e, ids(&st, "VAN_CS2_231", "HAND")[0], -1);
    let st = play(&mut e, ids(&st, "VAN_EX1_131", "HAND")[0], -1);
    let d = ent(&st, ids(&st, "VAN_EX1_131", "PLAY")[0]);
    assert_eq!((d["atk"].as_i64(), d["health"].as_i64()), (Some(2), Some(2)));
    assert_eq!(ids(&st, "EX1_131t", "PLAY").len(), 1, "the combo's 2/1 Defias Bandit");
}

#[test]
fn bane_of_doom_deals_2_and_summons_one_of_its_six_demons() {
    const DEMONS: [&str; 6] = ["VAN_CS2_059", "VAN_CS2_065", "VAN_EX1_319", "VAN_CS2_064", "VAN_EX1_306", "VAN_EX1_301"];
    let mut seen = std::collections::BTreeSet::new();
    for seed in 0..40 {
        let mut e = Engine::new();
        let r = call(&mut e, json!({"op": "new", "game": "g", "scenario": {"seed": seed, "current": 0, "players": [
            {"hero": "HERO_07", "mana": 10, "max_mana": 10, "hand": ["VAN_EX1_320", "VAN_EX1_320"], "deck": DECK},
            {"hero": "HERO_01", "board": ["VAN_CS2_172", "VAN_CS2_182"], "deck": DECK}]}}));
        assert_eq!(r["ok"], true, "{r}");
        let st = state(&mut e);
        let banes = ids(&st, "VAN_EX1_320", "HAND");
        let yeti = ids(&st, "VAN_CS2_182", "PLAY")[0];
        let st = play(&mut e, banes[0], yeti);
        assert_eq!(ent(&st, yeti)["health"], 3, "2 damage to a 4/5 Chillwind Yeti");
        assert!(st["players"][0]["board"].as_array().unwrap().is_empty(), "it lived: no Demon");
        let raptor = ids(&st, "VAN_CS2_172", "PLAY")[0];
        let st = play(&mut e, banes[1], raptor);
        let board = st["players"][0]["board"].as_array().unwrap();
        assert_eq!(board.len(), 1, "the Bloodfen Raptor (3/2) died: a Demon");
        let demon = ent(&st, board[0].as_i64().unwrap())["card"].as_str().unwrap().to_string();
        assert!(DEMONS.contains(&demon.as_str()), "{demon} is not one of the 2014 Demons");
        seen.insert(demon);
    }
    assert!(seen.len() >= 4, "random among the six: {seen:?}");
}

#[test]
fn eaglehorn_bow_gains_durability_from_an_enemy_secret_too() {
    let mut e = Engine::new();
    // Ice Barrier (the enemy's): revealed when our hero attacks theirs
    let st = scene(&mut e, json!({"hero": "HERO_05", "weapon": "VAN_EX1_536"}), json!({"hero": "HERO_08", "secrets": ["VAN_EX1_289"]}));
    let me = hero(&st, 0);
    let bow = st["players"][0]["weapon"].as_i64().unwrap();
    let st = act(&mut e, json!({"type": "attack", "player": 0, "attacker": me, "defender": hero(&st, 1)}));
    assert_eq!(ent(&st, bow)["tags"]["DURABILITY"], 2, "2 + 1 (the Secret) - 1 (the attack): {}", ent(&st, bow));
}

#[test]
fn sacrificial_pact_destroys_lord_jaraxxus() {
    let mut e = Engine::new();
    let st = scene(&mut e, json!({"hero": "HERO_07", "hand": ["VAN_NEW1_003"]}), json!({"hero": "EX1_323h", "hero_power": "VAN_EX1_tk33"}));
    let pact = ids(&st, "VAN_NEW1_003", "HAND")[0];
    let them = hero(&st, 1);
    assert!(targets(&mut e, pact).contains(&them), "a Demon hero is a target");
    assert!(!targets(&mut e, pact).contains(&hero(&st, 0)), "a hero that is no Demon is not");
    let st = play(&mut e, pact, them);
    assert_eq!(st["game_over"], true, "Lord Jaraxxus destroyed: {}", ent(&st, them));
    assert_eq!(st["winner"], 0);
}

#[test]
fn sacrificial_pact_destroys_a_played_lord_jaraxxus_and_your_own() {
    for own in [false, true] {
        let mut e = Engine::new();
        let jar = json!({"hero": "HERO_07", "hand": ["VAN_EX1_323"], "mana": 10, "max_mana": 10, "deck": DECK});
        let pact = json!({"hero": "HERO_07", "hand": ["VAN_NEW1_003"], "deck": DECK});
        let players = if own { json!([{"hero": "HERO_07", "hand": ["VAN_EX1_323", "VAN_NEW1_003"], "mana": 10, "max_mana": 10, "deck": DECK}, pact]) } else { json!([pact, jar]) };
        let r = call(&mut e, json!({"op": "new", "game": "g", "scenario": {"current": if own { 0 } else { 1 }, "players": players}}));
        assert_eq!(r["ok"], true, "{r}");
        let p = if own { 0 } else { 1 };
        let st = state(&mut e);
        let j = ids(&st, "VAN_EX1_323", "HAND")[0];
        let st = act(&mut e, json!({"type": "play", "player": p, "entity": j, "target": -1, "pos": 0, "choice": -1}));
        let lord = hero(&st, p);
        assert_eq!(ent(&st, lord)["card"], "EX1_323h");
        if !own {
            act(&mut e, json!({"type": "end_turn", "player": 1}));
        }
        let st = state(&mut e);
        let pact = ids(&st, "VAN_NEW1_003", "HAND")[0];
        assert!(targets(&mut e, pact).contains(&lord), "Lord Jaraxxus is a Demon to destroy");
        // a server game's client plans on its own view
        let view = call(&mut e, json!({"op": "snapshot", "game": "g", "view": 0}))["state"].clone();
        assert_eq!(call(&mut e, json!({"op": "new", "game": "v", "state": view}))["ok"], true);
        let legal = call(&mut e, json!({"op": "legal", "game": "v", "player": 0}))["actions"].clone();
        assert!(legal.as_array().unwrap().iter().any(|a| a["entity"] == pact && a["target"] == lord), "from the view too");
        let st = play(&mut e, pact, lord);
        assert_eq!(st["game_over"], true);
        assert_eq!(st["winner"], 1 - p as i64);
    }
}

#[test]
fn nozdormu_shortens_the_turns_while_in_play() {
    let mut e = Engine::new();
    let st = scene(&mut e, json!({"hero": "HERO_08", "hand": ["VAN_EX1_560"]}), json!({"hero": "HERO_01"}));
    assert!(st.get("turn_seconds").is_none(), "no limit without Nozdormu");
    let st = play(&mut e, ids(&st, "VAN_EX1_560", "HAND")[0], -1);
    assert_eq!(st["turn_seconds"], 15);
    for v in [0, 1] {
        let view = call(&mut e, json!({"op": "snapshot", "game": "g", "view": v}))["state"].clone();
        assert_eq!(view["turn_seconds"], 15, "both players' views");
    }
}
