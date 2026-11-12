//! The game's bot (classichs_brain::think) plays Journey to Un'Goro (packs/ungoro, built by tools/pack.py; skipped
//! without python3): Kazakus's potions, Jade Golems, the Grimy Goons' hand buffs and the tri-class cards in decks of
//! several classes, from what each player sees, both seats, to the end.

use classichs_engine::Engine;
use serde_json::{json, Value};
use std::path::PathBuf;

fn call(e: &mut Engine, v: Value) -> Value {
    serde_json::from_str(&e.call(&v.to_string())).unwrap()
}

/// The pack's deck templates, in file order.
fn decks() -> Vec<Value> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../packs/ungoro/decks");
    let mut files: Vec<_> = std::fs::read_dir(dir).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    files.iter().map(|p| {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(p).unwrap()).unwrap();
        json!({"hero": d["champion"], "cards": d["cards"]})
    }).collect()
}

#[test]
fn the_bot_plays_journey_to_ungoro() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out = std::env::temp_dir().join(format!("ungoro-brain-{}.cardpack", std::process::id()));
    let Ok(build) = std::process::Command::new("python3").current_dir(&repo).args(["tools/pack.py", "build", "packs/ungoro", "-o"]).arg(&out).output() else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "{}", String::from_utf8_lossy(&build.stdout));
    let mut e = Engine::new();
    let rs = e.load_pack_bytes(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    let h = rs.rules_hash.clone();
    let all = decks();
    let n = all.len();
    // the Quest decks against each other, then an Adapt deck
    let with = |card: &str| {
        all.iter().enumerate().filter(|(_, d)| d["cards"].as_array().unwrap().iter().any(|c| c == card)).map(|(i, _)| i).collect::<Vec<_>>()
    };
    const QUESTS: [&str; 5] = ["UNG_067", "UNG_934", "UNG_942", "UNG_829", "UNG_028"];
    let quests: Vec<usize> = QUESTS.iter().flat_map(|q| with(q)).collect();
    let adapt = with("UNG_089");
    assert!(quests.len() >= 5 && !adapt.is_empty());
    let mut quests_in_play = 0;
    for (i, (a, b)) in [(quests[0], quests[1]), (quests[2], quests[3]), (quests[4], adapt[0]), (adapt[0], (adapt[0] + 3) % n)]
        .into_iter().enumerate() {
        let decks = [all[a].clone(), all[b].clone()];
        let g = format!("g{i}");
        let r = call(&mut e, json!({"op": "new", "game": g, "pack": h, "seed": 3 + i as i64, "decks": decks}));
        assert_eq!(r["ok"], true, "{r}");
        let mut seen = false;
        for _ in 0..600 {
            let st = call(&mut e, json!({"op": "snapshot", "game": g, "view": -1}))["state"].clone();
            if st["game_over"] == true {
                break;
            }
            for p in st["players"].as_array().unwrap() {
                for s in p["secrets"].as_array().unwrap() {
                    seen |= QUESTS.contains(&st["entities"][s.to_string()]["card"].as_str().unwrap_or(""));
                }
            }
            let mut acted = false;
            for seat in 0..2 {
                let view = call(&mut e, json!({"op": "snapshot", "game": g, "view": seat}))["state"].clone();
                let level = if seat == 0 { "medium" } else { "easy" };
                let t = classichs_brain::think(&json!({"pack": h, "view": view, "seat": seat, "deck": decks[seat]["cards"],
                    "level": level, "budget_ms": 30, "seed": 5}));
                assert_eq!(t["ok"], true, "{t}");
                if t["action"].is_object() {
                    let r = call(&mut e, json!({"op": "act", "game": g, "action": t["action"]}));
                    assert_eq!(r["ok"], true, "{r}");
                    assert!(r.get("script_error").is_none(), "{r}");
                    acted = true;
                    break;
                }
            }
            assert!(acted, "nobody could move");
        }
        quests_in_play += seen as usize;
        let st = call(&mut e, json!({"op": "snapshot", "game": g, "view": -1}))["state"].clone();
        assert_eq!(st["game_over"], true, "the game ends: decks {a} vs {b}");
    }
    assert!(quests_in_play >= 2, "the bots play their Quests: {quests_in_play} games");
}
