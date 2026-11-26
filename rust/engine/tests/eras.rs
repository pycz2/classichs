//! Hearthstone 2014–2019 (packs/eras, docs/packs/format.md §13): a pack with versions, built by tools/pack.py from
//! version patches; each version's view plays as a one-version pack. Needs python3 (skipped without it).

use classichs_engine::pack::{self, Files};
use classichs_engine::{ruleset, Engine};
use serde_json::{json, Value};
use std::path::PathBuf;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A pack source built by tools/pack.py, read as the engine reads it; None without python3.
fn built(src: &str) -> Option<Files> {
    let out = std::env::temp_dir().join(format!("eras-test-{}-{}.cardpack", src.replace('/', "_"), std::process::id()));
    let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", src, "-o"]).arg(&out).output().ok()?;
    assert!(build.status.success(), "pack.py build {src}: {}", String::from_utf8_lossy(&build.stdout));
    let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    Some(files)
}

#[test]
fn every_version_is_a_pack_of_its_own() {
    let (Some(eras), Some(naxx)) = (built("packs/eras"), built("packs/naxx")) else {
        eprintln!("no python3: skipped");
        return;
    };
    let vs = pack::versions(&eras);
    assert_eq!(vs.iter().map(|v| v.id.as_str()).take(2).collect::<Vec<_>>(), ["6024", "6485"]);
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
    assert_eq!(r["pack"].as_str(), Some(pack::versions(&eras)[1].rules_hash.as_str()));
    let d = json!({"hero": "HERO_08", "cards": classichs_engine::deck::basic("MAGE")});
    let r: Value = serde_json::from_str(&e.call(&json!({"op": "new", "game": "v", "pack": r["pack"], "decks": [d, d], "seed": 1}).to_string())).unwrap();
    assert_eq!(r["ok"], true, "{r}");
}
