//! The game's bot (classichs_brain::think) plays a pack's game: Naxxramas (packs/naxx, built by
//! tools/pack.py; skipped without python3), from what each player sees, both seats, to the end.

use classichs_engine::Engine;
use serde_json::{json, Value};
use std::path::PathBuf;

fn call(e: &mut Engine, v: Value) -> Value {
    serde_json::from_str(&e.call(&v.to_string())).unwrap()
}

fn deck(name: &str) -> Value {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../packs/naxx/decks").join(name);
    let d: Value = serde_json::from_str(&std::fs::read_to_string(p).unwrap()).unwrap();
    json!({"hero": d["champion"], "cards": d["cards"]})
}

#[test]
fn the_bot_plays_naxxramas() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out = std::env::temp_dir().join(format!("naxx-brain-{}.cardpack", std::process::id()));
    let Ok(build) = std::process::Command::new("python3").current_dir(&repo).args(["tools/pack.py", "build", "packs/naxx", "-o"]).arg(&out).output() else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "{}", String::from_utf8_lossy(&build.stdout));
    let mut e = Engine::new();
    let rs = e.load_pack_bytes(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    let h = rs.rules_hash.clone();
    // a process that has not loaded it: the bot asks for it
    let need = classichs_brain::think(&json!({"pack": "0".repeat(64), "view": {}, "seat": 0, "deck": [], "level": "easy"}));
    assert_eq!(need["need_pack"], true);
    let decks = [deck("02_undertaker_hunter.json"), deck("01_zoolock.json")];
    let r = call(&mut e, json!({"op": "new", "game": "n", "pack": h, "seed": 3, "decks": decks}));
    assert_eq!(r["ok"], true, "{r}");
    for _ in 0..600 {
        let st = call(&mut e, json!({"op": "snapshot", "game": "n", "view": -1}))["state"].clone();
        if st["game_over"] == true {
            break;
        }
        let mut acted = false;
        for seat in 0..2 {
            let view = call(&mut e, json!({"op": "snapshot", "game": "n", "view": seat}))["state"].clone();
            let level = if seat == 0 { "medium" } else { "easy" };
            let t = classichs_brain::think(&json!({"pack": h, "view": view, "seat": seat, "deck": decks[seat]["cards"],
                "level": level, "budget_ms": 30, "seed": 5}));
            assert_eq!(t["ok"], true, "{t}");
            if t["action"].is_object() {
                let r = call(&mut e, json!({"op": "act", "game": "n", "action": t["action"]}));
                assert_eq!(r["ok"], true, "{r}");
                assert!(r.get("script_error").is_none(), "{r}");
                acted = true;
                break;
            }
        }
        assert!(acted, "nobody could move");
    }
    let st = call(&mut e, json!({"op": "snapshot", "game": "n", "view": -1}))["state"].clone();
    assert_eq!(st["game_over"], true, "the game ends");
}
