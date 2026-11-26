//! Hearthstone 2014–2019 (packs/eras): every card of every version plays without a script error (as each expansion's
//! every_card_plays_without_a_script_error does for its own cards). ERAS_VERSIONS=13921,14366 limits it to those
//! versions. Needs python3 (skipped without it).

use classichs_engine::entity::int;
use classichs_engine::{bot, pack, ruleset, scenario};
use serde_json::{json, Value};
use std::path::PathBuf;

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const LOOT_HOARDER: &str = "VAN_EX1_096";

#[test]
#[ignore = "slow (11 min); eras_versions.rs covers every version in the usual run: cargo test --release --test eras_every_card -- --ignored"]
fn every_card_of_every_version_plays_without_a_script_error() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out = std::env::temp_dir().join(format!("eras-every-card-{}.cardpack", std::process::id()));
    let Ok(build) = std::process::Command::new("python3").current_dir(&repo).args(["tools/pack.py", "build", "packs/eras", "-o"]).arg(&out).output() else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
    let eras = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    let only = std::env::var("ERAS_VERSIONS").ok();
    for v in pack::versions(&eras) {
        if only.as_ref().is_some_and(|o| !o.split(',').any(|x| x == v.id)) {
            continue;
        }
        let rs = ruleset::load(&pack::version_view(&eras, &v.id).unwrap()).unwrap_or_else(|e| panic!("version {}: {e}", v.id));
        let mut ids: Vec<&String> = rs.cards.keys().collect();
        ids.sort();
        let deck = json!([YETI, FIREBALL, LOOT_HOARDER, WISP, YETI, FIREBALL, LOOT_HOARDER, WISP]);
        let mut n = 0;
        for id in ids {
            let c = rs.card(id);
            if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") || !(c.collectible || !c.script.is_empty()) {
                continue;
            }
            let sc = json!({"current": 0, "seed": 7, "players": [
                {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": deck, "hand": [id, YETI, FIREBALL], "board": [YETI, LOOT_HOARDER, WISP]},
                {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": deck, "hand": [WISP], "board": [YETI, WISP]}]});
            let g0 = scenario::build_in(rs, &sc).unwrap_or_else(|e| panic!("version {} {id}: {e}", v.id));
            let Some(&e) = g0.players[0].hand.iter().find(|&&x| g0.e(x).card_id == *id) else { continue };
            let plays: Vec<_> = g0.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
            for a in plays.into_iter().take(6) {
                let mut g = g0.clone_state();
                assert!(g.apply(&Value::Object(a.clone())).ok, "version {} {id}", v.id);
                for _ in 0..6 {
                    if g.game_over {
                        break;
                    }
                    let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                    let b = bot::choose(&g, p).unwrap();
                    assert!(g.apply(&Value::Object(b)).ok, "version {} {id}", v.id);
                }
                assert_eq!(g.script_error.get(), None, "version {} {id} {a:?}", v.id);
                n += 1;
            }
        }
        assert!(n > 500, "version {}: {n} plays", v.id);
    }
}
