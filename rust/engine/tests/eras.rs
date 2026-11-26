//! Hearthstone 2014–2019 (packs/eras, docs/packs/format.md §13): a pack with versions, built by tools/pack.py from
//! version patches; each version's view plays as a one-version pack. Needs python3 (skipped without it).

use classichs_engine::pack::{self, Files};
use classichs_engine::{ruleset, Engine};
use serde_json::{json, Value};
use std::path::PathBuf;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A pack source built by tools/pack.py, read as the engine reads it; None without python3. Built once per test
/// run (the tests run in parallel and would share the output file).
fn built(src: &str) -> Option<Files> {
    static BUILT: std::sync::Mutex<Vec<(String, Option<Files>)>> = std::sync::Mutex::new(Vec::new());
    let mut done = BUILT.lock().unwrap_or_else(|e| e.into_inner());
    if let Some((_, f)) = done.iter().find(|(s, _)| s == src) {
        return f.clone();
    }
    let out = std::env::temp_dir().join(format!("eras-test-{}-{}.cardpack", src.replace('/', "_"), std::process::id()));
    let files = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", src, "-o"]).arg(&out).output().ok().map(|build| {
        assert!(build.status.success(), "pack.py build {src}: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        files
    });
    done.push((src.to_string(), files.clone()));
    files
}

#[test]
fn every_version_is_a_pack_of_its_own() {
    let (Some(eras), Some(naxx)) = (built("packs/eras"), built("packs/naxx")) else {
        eprintln!("no python3: skipped");
        return;
    };
    let vs = pack::versions(&eras);
    assert!(vs.windows(2).all(|w| w[0].date <= w[1].date), "oldest first");
    assert!(["6024", "6485"].iter().all(|id| vs.iter().any(|v| v.id == *id)));
    assert!(pack::versions(&naxx).is_empty());
    for v in &vs {
        let view = pack::version_view(&eras, &v.id).unwrap();
        assert_eq!(pack::rules_hash(&view).unwrap(), v.rules_hash, "version {}", v.id);
        assert!(!view.keys().any(|p| p.starts_with("versions/")));
        ruleset::load(&view).unwrap_or_else(|e| panic!("version {}: {e}", v.id));
    }
    // 6024 is the Naxxramas pack as it is
    let v6024 = pack::version_view(&eras, "6024").unwrap();
    assert_eq!(pack::rules_hash(&v6024).unwrap(), pack::rules_hash(&naxx).unwrap());
    // the top is the default version (a client that knows no versions plays it)
    let man: Value = serde_json::from_slice(&eras["manifest.json"]).unwrap();
    let default = man["default_version"].as_str().unwrap();
    assert_eq!(pack::rules_hash(&eras).unwrap(), pack::rules_hash(&pack::version_view(&eras, default).unwrap()).unwrap());
    assert_eq!(man["rules_hash"].as_str(), Some(pack::rules_hash(&eras).unwrap().as_str()));
}

#[test]
fn patch_6485_nerfs_leeroy_jenkins_and_starving_buzzard() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let stats = |vid: &str, id: &str| {
        let rs = ruleset::load(&pack::version_view(&eras, vid).unwrap()).unwrap();
        let c = rs.card(id);
        (c.cost, c.attack, c.health)
    };
    assert_eq!(stats("6024", "VAN_EX1_116"), (4, 6, 2));
    assert_eq!(stats("6485", "VAN_EX1_116"), (5, 6, 2));
    assert_eq!(stats("6024", "VAN_CS2_237"), (2, 2, 1));
    assert_eq!(stats("6485", "VAN_CS2_237"), (5, 3, 2));
}

/// Every card of every version (collectible or not: tokens, the cards powers make) played from the hand into a
/// busy board, a few bot moves after, and every hero's power used: no script error.
#[test]
fn every_card_of_every_version_plays_without_a_script_error() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const WISP: &str = "VAN_CS2_231";
    const YETI: &str = "VAN_CS2_182";
    const RAPTOR: &str = "VAN_CS2_172";
    for v in pack::versions(&eras) {
        let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(&eras, &v.id).unwrap()).unwrap()));
        let deck = json!([RAPTOR, YETI, "VAN_CS2_029", WISP, "VAN_CS2_008", "VAN_EX1_012", WISP, YETI]);
        let game = |hero: &str, hand: Value| {
            let sc = json!({"current": 0, "seed": 7, "players": [
                {"hero": hero, "mana": 10, "max_mana": 10, "deck": deck, "hand": hand, "board": [RAPTOR, "VAN_CS2_146", WISP], "weapon": "VAN_CS2_106"},
                {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": deck, "board": [YETI, "VAN_CS2_125"], "hand": [WISP, "VAN_CS2_024"]}]});
            classichs_engine::scenario::build_in(rs, &sc).unwrap()
        };
        let run = |mut g: classichs_engine::Game, a: &serde_json::Map<String, Value>, what: &str| {
            assert!(g.apply(&Value::Object(a.clone())).ok, "version {} {what}", v.id);
            for _ in 0..4 {
                if g.game_over {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = classichs_engine::bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok, "version {} {what}", v.id);
            }
            assert_eq!(g.script_error.get(), None, "version {} {what} {a:?}", v.id);
        };
        let mut ids: Vec<&String> = rs.cards.keys().collect();
        ids.sort();
        let mut n = 0;
        for id in ids {
            let c = rs.card(id);
            if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") || c.script.is_empty() || c.set == "MISSIONS" {
                continue;
            }
            let g = game("HERO_08", json!([id, YETI]));
            let e = *g.players[0].hand.iter().find(|&&x| g.e(x).card_id == *id).unwrap();
            for a in g.legal_actions().into_iter().filter(|a| a["type"] == "play" && classichs_engine::entity::int(a.get("entity")) == e).take(3) {
                run(g.clone_state(), &a, id);
                n += 1;
            }
        }
        for hero in ["HERO_01", "HERO_02", "HERO_03", "HERO_04", "HERO_05", "HERO_06", "HERO_07", "HERO_08", "HERO_09"] {
            let g = game(hero, json!([]));
            for a in g.legal_actions().into_iter().filter(|a| a["type"] == "hero_power").take(3) {
                run(g.clone_state(), &a, hero);
            }
        }
        eprintln!("version {}: {n} plays", v.id);
        assert!(n > 300, "version {}: {n}", v.id);
    }
}

/// The client hands the engine a version's view as a pack of its own (game/rules.gd): load_pack takes it and plays
/// by that version's rules.
#[test]
fn load_pack_takes_a_version_view() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let view = pack::version_view(&eras, "6485").unwrap();
    let dir = std::env::temp_dir().join(format!("eras-view-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for (p, d) in &view {
        std::fs::create_dir_all(dir.join(p).parent().unwrap()).unwrap();
        std::fs::write(dir.join(p), d).unwrap();
    }
    let mut e = Engine::new();
    let r: Value = serde_json::from_str(&e.call(&json!({"op": "load_pack", "path": dir}).to_string())).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["pack"].as_str(), pack::versions(&eras).iter().find(|v| v.id == "6485").map(|v| v.rules_hash.as_str()));
    let d = json!({"hero": "HERO_08", "cards": classichs_engine::deck::basic("MAGE")});
    let r: Value = serde_json::from_str(&e.call(&json!({"op": "new", "game": "v", "pack": r["pack"], "decks": [d, d], "seed": 1}).to_string())).unwrap();
    assert_eq!(r["ok"], true, "{r}");
}
