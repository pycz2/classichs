//! The JSON API end to end: a game between two bots, views, errors.

use classichs_engine::Engine;
use serde_json::{json, Value};

fn call(e: &mut Engine, req: Value) -> Value {
    serde_json::from_str(&e.call(&req.to_string())).unwrap()
}

fn deck(class: &str) -> Value {
    let hero = classichs_engine::deck::hero(class).unwrap();
    json!({"hero": hero, "cards": classichs_engine::deck::basic(class)})
}

#[test]
fn bots_play_a_game_through_the_api() {
    let mut e = Engine::new();
    assert_eq!(call(&mut e, json!({"op": "ping"}))["ok"], true);
    let h = call(&mut e, json!({"op": "hooks"}))["hooks"].clone();
    assert_eq!(h["VAN_EX1_160"]["choose_one"], json!(["VAN_EX1_160b", "VAN_EX1_160a"]));
    assert_eq!(h["VAN_EX1_287"]["on"], json!(["play"]));
    let r = call(&mut e, json!({"op": "new", "game": "g1", "decks": [deck("MAGE"), deck("WARRIOR")], "seed": 7}));
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["phase"], "MULLIGAN");
    assert_eq!(r["events"].as_array().unwrap().len(), 7, "opening draws");
    let mut n = 0;
    loop {
        let st = call(&mut e, json!({"op": "snapshot", "game": "g1"}))["state"].clone();
        if st["game_over"] == true {
            break;
        }
        let p = if st["pending"].get("player").is_some() {
            st["pending"]["player"].as_i64().unwrap()
        } else if st["phase"] == "MULLIGAN" {
            if st["players"][0]["mulliganed"] == true { 1 } else { 0 }
        } else {
            st["current"].as_i64().unwrap()
        };
        let a = call(&mut e, json!({"op": "bot", "game": "g1", "player": p}))["action"].clone();
        let r = call(&mut e, json!({"op": "act", "game": "g1", "action": a, "view": p}));
        assert_eq!(r["ok"], true, "{r}");
        n += 1;
        assert!(n < 2000, "game too long");
    }
    let r = call(&mut e, json!({"op": "act", "game": "g1", "action": {"type": "end_turn", "player": 0}}));
    assert_eq!(r["ok"], true, "a move after the end changes nothing");
    assert_eq!(r["over"], true);
    let h = call(&mut e, json!({"op": "history", "game": "g1", "from": 1}));
    assert_eq!(h["history"].as_array().unwrap().len(), n);
}

#[test]
fn player_view_hides_secrets_of_the_other_side() {
    let mut e = Engine::new();
    let sc = json!({"current": 0, "players": [
        {"hero": "HERO_08", "mana": 10, "max_mana": 10, "hand": ["VAN_CS2_029"], "deck": ["VAN_CS2_120", "VAN_CS2_182"],
            "secrets": ["VAN_EX1_287"]},
        {"hero": "HERO_01", "hand": ["VAN_CS2_108"], "deck": ["VAN_CS2_172"], "board": ["VAN_CS2_120"]}]});
    let r = call(&mut e, json!({"op": "new", "game": "s", "scenario": sc}));
    assert_eq!(r["ok"], true, "{r}");
    let full = call(&mut e, json!({"op": "snapshot", "game": "s"}))["state"].clone();
    assert!(full.get("rng").is_some());
    assert_eq!(full["players"][0]["deck"].as_array().unwrap().len(), 2);
    let v1 = call(&mut e, json!({"op": "snapshot", "game": "s", "view": 1}))["state"].clone();
    assert!(v1.get("rng").is_none());
    let secret = v1["players"][0]["secrets"][0].as_i64().unwrap();
    assert_eq!(v1["entities"][secret.to_string()]["card"], "");
    let hand0 = v1["players"][0]["hand"][0].as_i64().unwrap();
    assert_eq!(v1["entities"][hand0.to_string()]["card"], "");
    let hand1 = v1["players"][1]["hand"][0].as_i64().unwrap();
    assert_eq!(v1["entities"][hand1.to_string()]["card"], "VAN_CS2_108");
    assert_eq!(v1["players"][1]["deck"], json!([]));
    assert_eq!(v1["players"][1]["deck_count"], 1);
    let v0 = call(&mut e, json!({"op": "snapshot", "game": "s", "view": 0}))["state"].clone();
    assert_eq!(v0["entities"][secret.to_string()]["card"], "VAN_EX1_287");
    // Player 1's view of player 0's end of turn: player 1 draws (visible to them only).
    let r = call(&mut e, json!({"op": "act", "game": "s", "action": {"type": "end_turn", "player": 0}, "view": 0}));
    let draw = r["events"].as_array().unwrap().iter().find(|ev| ev["type"] == "draw").unwrap().clone();
    assert_eq!(draw["card"], "", "{r}");
}

#[test]
fn bad_requests_are_refused() {
    let mut e = Engine::new();
    assert_eq!(call(&mut e, json!(5))["error"], "not an object");
    assert_eq!(call(&mut e, json!({"op": "act", "game": "x", "action": {}}))["error"], "no such game");
    assert_eq!(call(&mut e, json!({"op": "dance"}))["error"], "unknown op");
    assert_eq!(call(&mut e, json!({"op": "new", "game": "x", "decks": [deck("MAGE")], "seed": 1}))["error"], "bad new request");
    let bad = json!({"hero": "HERO_08", "cards": ["VAN_CS2_029"]});
    assert_eq!(call(&mut e, json!({"op": "new", "game": "x", "decks": [bad, deck("MAGE")], "seed": 1}))["error"], "bad deck");
    let r = call(&mut e, json!({"op": "new", "game": "x", "decks": [bad, deck("MAGE")], "seed": 1, "check": false}));
    assert_eq!(r["ok"], true, "unchecked decks for tests and the debug table");
    let r = call(&mut e, json!({"op": "act", "game": "x", "action": {"type": "end_turn", "player": 0}}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"], r#"illegal action {"player":0,"type":"end_turn"}"#);
    assert_eq!(call(&mut e, json!({"op": "validate", "deck": deck("MAGE")}))["ok"], true);
    assert_eq!(call(&mut e, json!({"op": "new", "game": "y", "scenario": {"players": []}}))["error"], "scenario: players: need exactly 2");
    assert_eq!(e.call("{"), r#"{"error":"bad json: EOF while parsing an object at line 1 column 1","ok":false}"#);
    let d = call(&mut e, json!({"op": "draft", "seed": 3, "hero": 0, "picks": [0, 1, 2]}));
    assert_eq!(d["cards"].as_array().unwrap().len(), 3);
    assert_eq!(call(&mut e, json!({"op": "drop", "game": "x"}))["ok"], true);
    assert_eq!(call(&mut e, json!({"op": "hash", "game": "x"}))["error"], "no such game");
}

#[test]
fn tutorial_mission_blocks_the_turn_end() {
    let mut e = Engine::new();
    assert_eq!(call(&mut e, json!({"op": "new", "game": "t", "mission": 1}))["ok"], true);
    let b = call(&mut e, json!({"op": "end_turn_block", "game": "t", "player": 0}));
    assert_eq!(b["reason"], "while_can_play");
}

#[test]
fn engine_can_move_between_threads() {
    fn send_sync<T: Send + Sync>() {}
    send_sync::<Engine>();
}

/// A player's view rebuilt into a game (`new` with `state`) gives that player the
/// same legal actions as the real game: a client of a server finds its moves with it.
#[test]
fn a_view_gives_the_same_legal_actions() {
    let mut e = Engine::new();
    let classes = ["MAGE", "HUNTER", "PALADIN", "WARRIOR", "DRUID", "WARLOCK", "SHAMAN", "ROGUE", "PRIEST"];
    let mut checked = 0;
    for seed in 0..18i64 {
        let (a, b) = (classes[seed as usize % 9], classes[(seed as usize * 4 + 1) % 9]);
        let decks = if seed % 2 == 0 {
            json!([deck(a), deck(b)])
        } else {
            // 30 cards from the whole pool (every class): Secrets, auras, choices, giants
            let all = classichs_engine::card_db::collectible();
            let pick = |k: i64| -> Vec<String> { (0..30).map(|i| all[((seed * 7919 + k * 104729 + i * 7907) as usize) % all.len()].clone()).collect() };
            json!([{"hero": "HERO_08", "cards": pick(1)}, {"hero": "HERO_05", "cards": pick(2)}])
        };
        let r = call(&mut e, json!({"op": "new", "game": "g", "decks": decks, "seed": seed, "check": false}));
        assert_eq!(r["ok"], true, "{r}");
        for _ in 0..400 {
            let st = call(&mut e, json!({"op": "snapshot", "game": "g"}))["state"].clone();
            if st["game_over"] == true {
                break;
            }
            for p in 0..2 {
                let view = call(&mut e, json!({"op": "snapshot", "game": "g", "view": p}))["state"].clone();
                let r = call(&mut e, json!({"op": "new", "game": "v", "state": view}));
                assert_eq!(r["ok"], true, "{r}");
                let want = call(&mut e, json!({"op": "legal", "game": "g", "player": p}))["actions"].clone();
                let got = call(&mut e, json!({"op": "legal", "game": "v", "player": p}))["actions"].clone();
                assert_eq!(got, want, "seed {seed}, player {p}");
                checked += 1;
            }
            let p = if st["pending"].get("player").is_some() {
                st["pending"]["player"].as_i64().unwrap()
            } else if st["phase"] == "MULLIGAN" {
                if st["players"][0]["mulliganed"] == true { 1 } else { 0 }
            } else {
                st["current"].as_i64().unwrap()
            };
            let a = call(&mut e, json!({"op": "bot", "game": "g", "player": p}))["action"].clone();
            assert_eq!(call(&mut e, json!({"op": "act", "game": "g", "action": a}))["ok"], true);
        }
    }
    assert!(checked > 1000, "{checked}");
    let r = call(&mut e, json!({"op": "new", "game": "c", "copy": "g"}));
    assert_eq!(r["hash"], call(&mut e, json!({"op": "hash", "game": "g"}))["hash"], "a copy is the same game");
}
