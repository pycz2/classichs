//! Game formats (rules.json `formats`, docs/packs/rules.md): a game made with `"format": "standard"` builds its decks
//! and makes its random cards from that format's cards only; the Arena drafts its own pool (`modes.arena`: `sets`,
//! `banned`, `extra`). A pack with one format plays as before.

use classichs_engine::{arena_draft, pack::Files, ruleset, Engine};
use serde_json::{json, Value};

fn call(e: &mut Engine, req: Value) -> Value {
    serde_json::from_str(&e.call(&req.to_string())).unwrap()
}

const RULES: &str = r#"{
 "format": 1,
 "limits": {"champion_health": 30, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 4, "copies": 4},
 "start": {"hand": [1, 2], "coin": null},
 "default_power": "ZAP",
 "classes": [{"id": "RED", "champion": "RED_HERO"}, {"id": "ANY", "neutral": true}],
 "rarities": [{"id": "C", "tier": "common"}],
 "sets": ["OLD", "NEW"],
 "mechanics": {},
 "formats": {"standard": {"sets": ["NEW"], "exclude": ["FAME"]}, "wild": {"sets": ["OLD", "NEW"]}},
 "modes": {"constructed": {"sets": ["OLD", "NEW"], "class_cards": "own_and_neutral"},
           "arena": {"sets": ["OLD", "NEW"], "banned": ["BAN"], "extra": ["ONLY"], "classes": ["RED"], "picks": 4,
                     "offer": 1, "tier_weights": {"common": 1000}}}
}"#;

const CARDS: &str = r#"[
 {"id": "RED_HERO", "type": "CHAMPION", "class": "RED", "set": "NEW", "power": "ZAP"},
 {"id": "ZAP", "type": "POWER", "class": "RED", "set": "NEW", "cost": 2},
 {"id": "OLD1", "type": "MINION", "class": "ANY", "set": "OLD", "collectible": true, "rarity": "C", "cost": 1, "attack": 1, "health": 1},
 {"id": "NEW1", "type": "MINION", "class": "ANY", "set": "NEW", "collectible": true, "rarity": "C", "cost": 1, "attack": 1, "health": 1},
 {"id": "FAME", "type": "MINION", "class": "ANY", "set": "NEW", "collectible": true, "rarity": "C", "cost": 1, "attack": 1, "health": 1},
 {"id": "BAN", "type": "MINION", "class": "RED", "set": "NEW", "collectible": true, "rarity": "C", "cost": 1, "attack": 1, "health": 1},
 {"id": "ONLY", "type": "MINION", "class": "RED", "set": "NEW", "rarity": "C", "cost": 1, "attack": 1, "health": 1},
 {"id": "GEN", "type": "SPELL", "class": "RED", "set": "NEW", "collectible": true, "rarity": "C", "cost": 0,
  "script": "scripts/gen.lua#GEN"}
]"#;

/// GEN: every card the game makes at random from (`g.collectible()`) to its player's hand.
const GEN: &str = r#"
local cards = {}
cards.GEN = { spell = function(g, me) for _, c in ipairs(g.collectible()) do g.add_to_hand(g.ctrl(me), c) end end }
return cards
"#;

fn files() -> Files {
    let mut f = Files::new();
    f.insert("manifest.json".into(), br#"{"format": 1, "id": "test-formats", "version": "0.0.1"}"#.to_vec());
    f.insert("rules.json".into(), RULES.as_bytes().to_vec());
    f.insert("cards.json".into(), CARDS.as_bytes().to_vec());
    f.insert("scripts/gen.lua".into(), GEN.as_bytes().to_vec());
    f
}

fn engine() -> (Engine, String) {
    let rs = ruleset::load(&files()).unwrap();
    (Engine::new(), rs.rules_hash.clone())
}

fn deck(cards: &[&str]) -> Value {
    json!({"hero": "RED_HERO", "cards": cards})
}

/// The cards a GEN played in game `id` put into the hand.
fn made(e: &mut Engine, id: &str) -> Vec<String> {
    let st = call(e, json!({"op": "snapshot", "game": id}))["state"].clone();
    let gen = st["entities"].as_object().unwrap().iter().find(|(_, x)| x["card"] == "GEN" && x["zone"] == "HAND").unwrap().0.clone();
    let a = json!({"type": "play", "player": 0, "entity": gen.parse::<i64>().unwrap(), "target": -1, "pos": -1, "choice": -1});
    let r = call(e, json!({"op": "act", "game": id, "action": a}));
    assert_eq!(r["ok"], true, "{r}");
    let st = call(e, json!({"op": "snapshot", "game": id}))["state"].clone();
    let mut out: Vec<String> = st["entities"]
        .as_object()
        .unwrap()
        .values()
        .filter(|x| x["zone"] == "HAND" && x["ctrl"] == 0 && x["card"] != "GEN") // (the GEN made, the GENs drawn)
        .map(|x| x["card"].as_str().unwrap().to_string())
        .collect();
    out.sort();
    out
}

fn scenario(format: Option<&str>) -> Value {
    let mut sc = json!({"current": 0, "players": [{"hero": "RED_HERO", "mana": 10, "max_mana": 10, "hand": ["GEN"]},
        {"hero": "RED_HERO"}]});
    if let Some(f) = format {
        sc["format"] = json!(f);
    }
    sc
}

#[test]
fn a_standard_game_makes_no_wild_card() {
    let (mut e, pack) = engine();
    for (format, want) in [("standard", vec!["BAN", "NEW1"]), ("wild", vec!["BAN", "FAME", "NEW1", "OLD1"])] {
        // a game of decks, then a scenario of that format
        let r = call(&mut e, json!({"op": "new", "game": "d", "pack": pack, "format": format, "seed": 1, "first": 0,
            "decks": [deck(&["GEN", "GEN", "GEN", "GEN"]), deck(&["NEW1", "NEW1", "NEW1", "NEW1"])]}));
        assert_eq!(r["ok"], true, "{r}");
        for p in 0..2 {
            call(&mut e, json!({"op": "act", "game": "d", "action": {"type": "mulligan", "player": p, "replace": []}}));
        }
        assert_eq!(made(&mut e, "d"), want, "{format}: a game of decks");
        call(&mut e, json!({"op": "new", "game": "s", "pack": pack, "scenario": scenario(Some(format))}));
        assert_eq!(made(&mut e, "s"), want, "{format}: a scenario");
    }
    // no format: every card (as before formats)
    call(&mut e, json!({"op": "new", "game": "n", "pack": pack, "scenario": scenario(None)}));
    assert_eq!(made(&mut e, "n"), ["BAN", "FAME", "NEW1", "OLD1"]);
}

#[test]
fn the_format_goes_with_the_game() {
    let (mut e, pack) = engine();
    call(&mut e, json!({"op": "new", "game": "s", "pack": pack, "scenario": scenario(Some("standard"))}));
    let st = call(&mut e, json!({"op": "snapshot", "game": "s", "view": 0}))["state"].clone();
    assert_eq!(st["format"], "standard");
    assert_eq!(call(&mut e, json!({"op": "dump", "game": "s"}))["scenario"]["format"], "standard");
    // a copy, a game from a player's view and the request's own format
    for (id, req) in [("c", json!({"copy": "s"})), ("v", json!({"state": st})), ("r", json!({"scenario": scenario(None), "format": "standard"}))] {
        let mut req = req;
        req["op"] = json!("new");
        req["game"] = json!(id);
        req["pack"] = json!(pack);
        assert_eq!(call(&mut e, req.clone())["ok"], true, "{req}");
        assert_eq!(made(&mut e, id), ["BAN", "NEW1"], "{id}");
    }
}

#[test]
fn decks_are_checked_by_the_format() {
    let (mut e, pack) = engine();
    let old = deck(&["OLD1", "NEW1", "NEW1", "NEW1"]);
    let fame = deck(&["FAME", "NEW1", "NEW1", "NEW1"]);
    let new = deck(&["NEW1", "NEW1", "NEW1", "NEW1"]);
    let v = |e: &mut Engine, d: &Value, f: Option<&str>| {
        let mut r = json!({"op": "validate", "pack": pack, "deck": d});
        if let Some(f) = f {
            r["format"] = json!(f);
        }
        call(e, r)
    };
    for d in [&old, &fame] {
        let r = v(&mut e, d, Some("standard"));
        assert_eq!(r["ok"], false);
        assert_eq!(r["error"], "This deck has cards that are not in this format");
        assert_eq!(v(&mut e, d, Some("wild"))["ok"], true);
        assert_eq!(v(&mut e, d, None)["ok"], true);
        let r = call(&mut e, json!({"op": "new", "game": "x", "pack": pack, "format": "standard", "seed": 1, "decks": [d, new]}));
        assert_eq!(r["error"], "bad deck", "{r}");
    }
    assert_eq!(v(&mut e, &new, Some("standard"))["ok"], true);
    // an Arena deck: any drafted card
    assert_eq!(v(&mut e, &json!({"hero": "RED_HERO", "cards": ["OLD1", "OLD1", "OLD1", "OLD1"], "arena": true}), Some("standard"))["ok"], true);
    // a format the pack does not have
    assert_eq!(v(&mut e, &new, Some("modern"))["error"], "unknown format");
    let r = call(&mut e, json!({"op": "new", "game": "x", "pack": pack, "format": "modern", "seed": 1, "decks": [new, new]}));
    assert_eq!(r["error"], "unknown format");
    let r = call(&mut e, json!({"op": "new", "game": "x", "pack": pack, "scenario": scenario(Some("modern"))}));
    assert_eq!(r["error"], "scenario: format: unknown format");
}

#[test]
fn the_arena_drafts_its_own_pool() {
    let rs = ruleset::load(&files()).unwrap();
    let pool: Vec<String> = arena_draft::pool(rs, "RED", "common").into_iter().map(|(c, _)| c).collect();
    assert_eq!(pool, ["FAME", "GEN", "NEW1", "OLD1", "ONLY"], "BAN is banned, ONLY is an Arena-only card");
}

/// A pack with one format (Classic): "standard" and "wild" play every card, as a game without a format does.
#[test]
fn a_pack_with_one_format_plays_as_before() {
    let mut e = Engine::new();
    let d = json!({"hero": "HERO_08", "cards": classichs_engine::deck::basic("MAGE")});
    let plain = call(&mut e, json!({"op": "new", "game": "a", "decks": [d, d], "seed": 3}))["hash"].clone();
    for f in ["standard", "wild"] {
        let r = call(&mut e, json!({"op": "new", "game": f, "decks": [d, d], "seed": 3, "format": f}));
        assert_eq!(r["hash"], plain, "{f}");
    }
    assert_eq!(call(&mut e, json!({"op": "new", "game": "m", "decks": [d, d], "seed": 3, "format": "modern"}))["error"], "unknown format");
    assert!(ruleset::classic().formats.is_empty());
    assert_eq!(ruleset::classic().pool("standard"), &ruleset::classic().collectible[..]);
}
