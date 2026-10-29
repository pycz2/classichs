//! Game packs: the built-in Classic ruleset against tools/pack.py, loading a
//! pack through the API, the pack's mechanic names in snapshots (D7), Lua
//! hooks, and script errors ending a game cleanly.

use classichs_engine::{ruleset, Engine};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

fn call(e: &mut Engine, req: Value) -> Value {
    serde_json::from_str(&e.call(&req.to_string())).unwrap()
}

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn tmp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("classichs-packs-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

#[test]
fn builtin_rules_hash_matches_pack_py() {
    let out = tmp("classic").join("classic.cardpack");
    let build = std::process::Command::new("python3")
        .current_dir(repo())
        .args(["tools/pack.py", "build", "packs/classic", "-o"])
        .arg(&out)
        .output();
    let Ok(build) = build else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stderr));
    let hash = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "hash"]).arg(&out).output().unwrap();
    let text = String::from_utf8_lossy(&hash.stdout);
    let want = text.lines().find_map(|l| l.strip_prefix("rules_hash")).unwrap().trim().to_string();
    assert_eq!(ruleset::classic().rules_hash, want, "the built-in Classic ruleset and tools/pack.py disagree");
    // the built pack loads (zip reader) and is the same ruleset
    let mut e = Engine::new();
    let r = call(&mut e, json!({"op": "load_pack", "path": out}));
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["pack"], want);
    assert_eq!(r["id"], "classic-2014");
    let bytes = std::fs::read(&out).unwrap();
    assert_eq!(e.load_pack_bytes(&bytes).unwrap().rules_hash, want);
    let d = json!({"hero": "HERO_08", "cards": classichs_engine::deck::basic("MAGE")});
    let a = call(&mut e, json!({"op": "new", "game": "a", "decks": [d, d], "seed": 3}));
    let b = call(&mut e, json!({"op": "new", "game": "b", "decks": [d, d], "seed": 3, "pack": want}));
    assert_eq!(a["hash"], b["hash"]);
}

const RULES: &str = r#"{
 "format": 1,
 "limits": {"champion_health": 20, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 4, "copies": 4},
 "start": {"hand": [1, 2], "coin": null, "mulligan": true},
 "fatigue": {"enabled": true, "first": 2, "step": 2},
 "default_power": "ZAP",
 "classes": [{"id": "RED", "champion": "RED_HERO"}, {"id": "ANY", "neutral": true}],
 "rarities": [{"id": "C", "tier": "common"}],
 "sets": ["CORE"],
 "mechanics": {"FIREWALL": {"engine": "GUARD"}, "SNARE": {"engine": "TRAP"}, "CHILLED": {"engine": "FROZEN"},
   "SHELL": {"engine": "ARMOR"}},
 "modes": {"constructed": {"sets": ["CORE"], "class_cards": "own_and_neutral"}}
}"#;

const CARDS: &str = r#"[
 {"id": "RED_HERO", "type": "CHAMPION", "class": "RED", "set": "CORE", "power": "ZAP"},
 {"id": "ZAP", "type": "POWER", "class": "RED", "set": "CORE", "cost": 2, "script": "scripts/red.lua#ZAP"},
 {"id": "WALL", "type": "MINION", "class": "ANY", "set": "CORE", "collectible": true, "rarity": "C", "cost": 1,
  "attack": 0, "health": 5, "keywords": ["FIREWALL"]},
 {"id": "BOLT", "type": "SPELL", "class": "RED", "set": "CORE", "collectible": true, "rarity": "C", "cost": 1,
  "script": "scripts/red.lua#BOLT"},
 {"id": "OOPS", "type": "SPELL", "class": "RED", "set": "CORE", "collectible": true, "rarity": "C", "cost": 0,
  "script": "scripts/red.lua#OOPS"},
 {"id": "LOOP", "type": "SPELL", "class": "RED", "set": "CORE", "collectible": true, "rarity": "C", "cost": 0,
  "script": "scripts/red.lua#LOOP"},
 {"id": "CHEAP", "type": "MINION", "class": "ANY", "set": "CORE", "collectible": true, "rarity": "C", "cost": 5,
  "attack": 1, "health": 1, "script": "scripts/red.lua#CHEAP"},
 {"id": "BADCOST", "type": "MINION", "class": "ANY", "set": "CORE", "collectible": true, "rarity": "C", "cost": 1,
  "attack": 1, "health": 1, "script": "scripts/red.lua#BADCOST"}
]"#;

const RED: &str = r#"
local cards = {}
cards.ZAP = { target = "any", hero_power = function(g, me, t) g.damage(me, t, g.hp_dmg(me, 1)) end }
cards.BOLT = {
  target = { base = "any", filter = function(g, me, t) return g.is_champion(t) end },
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, lib.three))
    g.freeze(t)
  end,
}
cards.OOPS = { spell = function(g, me) g.nope(me) end }
cards.LOOP = { spell = function(g, me) while true do end end }
cards.CHEAP = { cost_mod = function(g, me) return -#g.hand(g.ctrl(me)) end }
cards.BADCOST = { cost_mod = function(g, me) return g.damage(me, me, 1) end }
return cards
"#;

fn mini_pack(dir: &Path, red: &str) {
    std::fs::create_dir_all(dir.join("scripts")).unwrap();
    std::fs::write(dir.join("manifest.json"), r#"{"format": 1, "id": "test-mini", "version": "0.0.1"}"#).unwrap();
    std::fs::write(dir.join("rules.json"), RULES).unwrap();
    std::fs::write(dir.join("cards.json"), CARDS).unwrap();
    std::fs::write(dir.join("scripts/lib.lua"), "return { three = 3 }\n").unwrap();
    std::fs::write(dir.join("scripts/red.lua"), red).unwrap();
}

fn scenario(hand: &[&str]) -> Value {
    json!({"current": 0, "players": [
        {"hero": "RED_HERO", "mana": 10, "max_mana": 10, "hand": hand, "board": ["WALL"], "deck": ["WALL"]},
        {"hero": "RED_HERO", "board": ["WALL"], "deck": ["WALL"]}]})
}

fn entity_of<'a>(st: &'a Value, card: &str, ctrl: i64) -> (i64, &'a Value) {
    let (id, e) = st["entities"]
        .as_object()
        .unwrap()
        .iter()
        .find(|(_, e)| e["card"] == card && e["ctrl"] == ctrl && e["zone"] != "SETASIDE")
        .unwrap();
    (id.parse().unwrap(), e)
}

#[test]
fn a_pack_plays_with_its_own_names_and_lua_hooks() {
    let dir = tmp("mini");
    mini_pack(&dir, RED);
    let mut e = Engine::new();
    let r = call(&mut e, json!({"op": "load_pack", "path": dir}));
    assert_eq!(r["ok"], true, "{r}");
    let pack = r["pack"].clone();
    let list = call(&mut e, json!({"op": "packs"}))["packs"].clone();
    assert!(list.as_array().unwrap().iter().any(|p| p["pack"] == pack && p["id"] == "test-mini"), "{list}");
    let r = call(&mut e, json!({"op": "new", "game": "m", "pack": pack, "scenario": scenario(&["BOLT", "CHEAP"])}));
    assert_eq!(r["ok"], true, "{r}");
    let st = call(&mut e, json!({"op": "snapshot", "game": "m"}))["state"].clone();
    let (_, wall) = entity_of(&st, "WALL", 1);
    assert_eq!(wall["tags"], json!({"FIREWALL": true}), "the pack's name of GUARD");
    let (hero1, h) = entity_of(&st, "RED_HERO", 1);
    assert_eq!(h["tags"]["SHELL"], 0, "the pack's name of ARMOR");
    assert_eq!(h["health"], 20, "rules.json limits.champion_health");
    let (cheap, c) = entity_of(&st, "CHEAP", 0);
    assert_eq!(c["cost"], 3, "a Lua cost_mod: 5 - 2 cards in hand");
    let (bolt, _) = entity_of(&st, "BOLT", 0);
    // the Lua target filter: champions only
    let legal = call(&mut e, json!({"op": "legal", "game": "m", "player": 0}))["actions"].clone();
    let targets: Vec<i64> = legal.as_array().unwrap().iter().filter(|a| a["entity"] == bolt).map(|a| a["target"].as_i64().unwrap()).collect();
    assert_eq!(targets.len(), 2, "{legal}");
    assert!(targets.contains(&hero1));
    let a = json!({"type": "play", "player": 0, "entity": bolt, "target": hero1, "pos": -1, "choice": -1});
    let r = call(&mut e, json!({"op": "act", "game": "m", "action": a}));
    assert_eq!(r["ok"], true, "{r}");
    let st = call(&mut e, json!({"op": "snapshot", "game": "m"}))["state"].clone();
    let h = &st["entities"][hero1.to_string()];
    assert_eq!(h["health"], 17);
    assert_eq!(h["tags"]["CHILLED"], true, "the pack's name of FROZEN");
    assert_eq!(st["entities"][cheap.to_string()]["cost"], 4);
    // a copy plays on identically
    let r = call(&mut e, json!({"op": "new", "game": "m2", "copy": "m"}));
    assert_eq!(r["hash"], call(&mut e, json!({"op": "hash", "game": "m"}))["hash"]);
    // the opponent's view of the deck count and the hooks op
    let hooks = call(&mut e, json!({"op": "hooks", "pack": pack}))["hooks"].clone();
    assert_eq!(hooks["BOLT"], json!({"spell": true, "target": true}));
    assert_eq!(call(&mut e, json!({"op": "validate", "pack": pack, "deck": {"hero": "RED_HERO", "cards": ["WALL", "BOLT", "BOLT", "WALL"]}}))["ok"], true);
}

fn play_first(e: &mut Engine, game: &str, card: &str) -> Value {
    let st = call(e, json!({"op": "snapshot", "game": game}))["state"].clone();
    let (id, _) = entity_of(&st, card, 0);
    let a = json!({"type": "play", "player": 0, "entity": id, "target": -1, "pos": -1, "choice": -1});
    call(e, json!({"op": "act", "game": game, "action": a}))
}

#[test]
fn a_script_error_ends_the_game_as_a_draw() {
    let dir = tmp("errors");
    mini_pack(&dir, RED);
    let mut e = Engine::new();
    let pack = call(&mut e, json!({"op": "load_pack", "path": dir}))["pack"].clone();
    for (card, why) in [("OOPS", "attempt to call a nil value (field 'nope')"), ("LOOP", "step limit exceeded")] {
        call(&mut e, json!({"op": "new", "game": card, "pack": pack, "scenario": scenario(&[card])}));
        let r = play_first(&mut e, card, card);
        assert_eq!(r["ok"], true, "{r}");
        assert_eq!(r["over"], true, "{r}");
        assert_eq!(r["winner"], -1);
        let msg = r["script_error"].as_str().unwrap();
        assert!(msg.contains("scripts/red.lua:") && msg.contains(why), "{msg}");
        let last = r["events"].as_array().unwrap().last().unwrap().clone();
        assert_eq!(last["type"], "game_over");
        assert_eq!(last["reason"], "script_error");
        assert!(call(&mut e, json!({"op": "legal", "game": card}))["actions"].as_array().unwrap().is_empty());
    }
    // a read-only hook (a cost) that tries to change the game: the error ends the game at the next step
    call(&mut e, json!({"op": "new", "game": "ro", "pack": pack, "scenario": scenario(&["BADCOST"])}));
    let r = call(&mut e, json!({"op": "act", "game": "ro", "action": {"type": "end_turn", "player": 0}}));
    assert_eq!(r["over"], true, "{r}");
    assert!(r["script_error"].as_str().unwrap().contains("field 'damage'"), "{r}");
}

#[test]
fn bad_packs_are_refused() {
    let dir = tmp("bad");
    mini_pack(&dir, "return { BOLT = { spel = function() end } }");
    let mut e = Engine::new();
    let r = call(&mut e, json!({"op": "load_pack", "path": dir}));
    assert_eq!(r["ok"], false);
    assert!(r["error"].as_str().unwrap().contains("unknown hook 'spel'"), "{r}");
    mini_pack(&dir, "return { BOLT = { spell = function() x = 1 end } }");
    let r = call(&mut e, json!({"op": "load_pack", "path": dir}));
    assert!(r["error"].as_str().unwrap().contains("assignment to undeclared global 'x'"), "{r}");
    let r = call(&mut e, json!({"op": "load_pack", "data": "UEsFBgAAAAA="}));
    assert_eq!(r["ok"], false, "{r}");
    let r = call(&mut e, json!({"op": "new", "game": "x", "pack": "0000", "seed": 1, "decks": []}));
    assert!(r["error"].as_str().unwrap().contains("unknown pack"), "{r}");
}

#[test]
fn games_and_engines_go_between_threads() {
    fn send_sync<T: Send + Sync>() {}
    send_sync::<classichs_engine::Game>();
    send_sync::<Engine>();
}


/// The cards whose script uses their own neighbours (the bots try every board position for them).
#[test]
fn classic_knows_the_neighbour_cards() {
    let mut got: Vec<&str> = classichs_engine::ruleset::classic().neighbours.iter().map(String::as_str).collect();
    got.sort();
    assert_eq!(got, ["VAN_EX1_093", "VAN_EX1_162", "VAN_EX1_304", "VAN_EX1_565", "VAN_EX1_584", "VAN_EX1_058"].iter().copied().collect::<std::collections::BTreeSet<_>>().into_iter().collect::<Vec<_>>());
}
