//! The game's bot (classichs_brain::think) plays Knights of the Frozen Throne (packs/icc, built by tools/pack.py; skipped
//! without python3): hero cards and their powers (Death's Shadow, Build-A-Beast's two choices, Plague Lord's), Lifesteal,
//! from what each player sees, both seats, to the end.

use classichs_engine::Engine;
use serde_json::{json, Value};
use std::path::PathBuf;

fn call(e: &mut Engine, v: Value) -> Value {
    serde_json::from_str(&e.call(&v.to_string())).unwrap()
}

/// The pack's deck templates, in file order.
fn decks() -> Vec<Value> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../packs/icc/decks");
    let mut files: Vec<_> = std::fs::read_dir(dir).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    files.iter().map(|p| {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(p).unwrap()).unwrap();
        json!({"hero": d["champion"], "cards": d["cards"]})
    }).collect()
}

#[test]
fn the_bot_plays_knights_of_the_frozen_throne() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out = std::env::temp_dir().join(format!("icc-brain-{}.cardpack", std::process::id()));
    let Ok(build) = std::process::Command::new("python3").current_dir(&repo).args(["tools/pack.py", "build", "packs/icc", "-o"]).arg(&out).output() else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "{}", String::from_utf8_lossy(&build.stdout));
    let mut e = Engine::new();
    let rs = e.load_pack_bytes(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    let h = rs.rules_hash.clone();
    let all = decks();
    let with = |card: &str| all.iter().position(|d| d["cards"].as_array().unwrap().iter().any(|c| c == card)).unwrap();
    // decks with hero cards: Rexxar, Valeera, Malfurion, Jaina, Gul'dan, Garrosh
    let pairs = [(with("ICC_828"), with("ICC_827")), (with("ICC_832"), with("ICC_833")), (with("ICC_831"), with("ICC_834")),
        (with("ICC_827"), with("ICC_828")), (with("ICC_833"), with("ICC_832")), (with("ICC_834"), with("ICC_831"))];
    let mut heroes = 0;
    let mut powers = std::collections::BTreeMap::new();
    for (i, (a, b)) in pairs.into_iter().enumerate() {
        let decks = [all[a].clone(), all[b].clone()];
        let g = format!("g{i}");
        let r = call(&mut e, json!({"op": "new", "game": g, "pack": h, "seed": 3 + i as i64, "decks": decks}));
        assert_eq!(r["ok"], true, "{r}");
        for _ in 0..800 {
            let st = call(&mut e, json!({"op": "snapshot", "game": g, "view": -1}))["state"].clone();
            if st["game_over"] == true {
                break;
            }
            let mut acted = false;
            for seat in 0..2 {
                let view = call(&mut e, json!({"op": "snapshot", "game": g, "view": seat}))["state"].clone();
                let level = if seat == 0 { "medium" } else { "easy" };
                let t = classichs_brain::think(&json!({"pack": h, "view": view, "seat": seat, "deck": decks[seat]["cards"],
                    "level": level, "budget_ms": 30, "seed": 5}));
                assert_eq!(t["ok"], true, "{t}");
                if t["action"].is_object() {
                    if t["action"]["type"] == "play" {
                        let c = view["entities"][t["action"]["entity"].to_string().as_str()]["card"].as_str().unwrap_or("").to_string();
                        if ["ICC_827", "ICC_828", "ICC_829", "ICC_830", "ICC_831", "ICC_832", "ICC_833", "ICC_834", "ICC_481"].contains(&c.as_str()) {
                            *powers.entry(format!("played {c}")).or_insert(0) += 1;
                        }
                    }
                    if t["action"]["type"] == "hero_power" {
                        let pw = view["players"][seat]["power"].to_string();
                        let c = view["entities"][pw.as_str()]["card"].as_str().unwrap_or("").to_string();
                        *powers.entry(c).or_insert(0) += 1;
                    }
                    let r = call(&mut e, json!({"op": "act", "game": g, "action": t["action"]}));
                    assert_eq!(r["ok"], true, "{r}");
                    assert!(r.get("script_error").is_none(), "{r}");
                    acted = true;
                    break;
                }
            }
            assert!(acted, "nobody could move");
        }
        let st = call(&mut e, json!({"op": "snapshot", "game": g, "view": -1}))["state"].clone();
        assert_eq!(st["game_over"], true, "the game ends: decks {a} vs {b}");
        for p in st["players"].as_array().unwrap() {
            let hero = st["entities"][p["hero"].to_string()]["card"].as_str().unwrap_or("").to_string();
            heroes += hero.starts_with("ICC_") as usize;
        }
    }
    eprintln!("heroes that were hero cards at the end: {heroes}; powers used {powers:?}");
    assert!(heroes > 0, "the bots play hero cards");
}
