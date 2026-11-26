//! Hearthstone 2014–2019 (packs/eras): every version's cards play without a script error, and each version patch's
//! changes as the engine plays them (one file per era in eras_versions/: the card values of that version against the
//! version before, the behaviour changes played out). The pack is built once by tools/pack.py; a version's view is
//! loaded as a one-version pack. Needs python3 (skipped without it).


#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

/// The card ids a version's patch names (`cards`, `add`) and its own scripts define.
fn patched(vid: &str) -> BTreeSet<String> {
    let dir = repo().join("packs/eras/versions").join(vid);
    let p: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("patch.json")).unwrap()).unwrap();
    let mut ids: BTreeSet<String> = p["cards"].as_object().map(|m| m.keys().cloned().collect()).unwrap_or_default();
    ids.extend(p["add"].as_array().into_iter().flatten().filter_map(|c| c["id"].as_str().map(String::from)));
    if let Ok(dir) = std::fs::read_dir(dir.join("scripts")) {
        for f in dir {
            let lua = std::fs::read_to_string(f.unwrap().path()).unwrap();
            // `cards.<ID> = {` / `cards["<ID>"] = {`
            for line in lua.lines() {
                let l = line.trim_start();
                if let Some(rest) = l.strip_prefix("cards.").or_else(|| l.strip_prefix("cards[\"")) {
                    let id: String = rest.chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '_').collect();
                    if !id.is_empty() && l.contains('=') {
                        ids.insert(id);
                    }
                }
            }
        }
    }
    ids
}

/// Every collectible card of every version (and every card its patch or scripts change, collectible or not) is played
/// in a small scenario, each of its plays (up to 3; 6 for a changed card) followed by a few bot moves: no script error.
/// Versions with the same rules are played once, several at a time.
#[test]
fn every_card_of_every_version_plays_without_a_script_error() {
    let Some(files) = eras() else { return };
    let mut seen = BTreeSet::new();
    let vids: Vec<String> = pack::versions(files).into_iter().filter(|v| seen.insert(v.rules_hash.clone())).map(|v| v.id).collect();
    let threads = std::thread::available_parallelism().map_or(4, |n| n.get());
    let bad: Vec<String> = std::thread::scope(|s| {
        let hs: Vec<_> = vids.chunks(vids.len().div_ceil(threads)).map(|part| s.spawn(move || part.iter().flat_map(|v| plays(v)).collect::<Vec<_>>())).collect();
        hs.into_iter().flat_map(|h| h.join().unwrap()).collect()
    });
    assert!(bad.is_empty(), "{} problems:\n{}", bad.len(), bad.join("\n"));
}

/// The problems of one version's every-card run.
fn plays(vid: &str) -> Vec<String> {
    let rs = version(vid).unwrap();
    let changed = patched(vid);
    let mut ids: Vec<&String> = rs.cards.keys().filter(|k| rs.card(k).collectible || changed.contains(*k)).collect();
    ids.sort();
    let (mut n, mut bad) = (0, vec![]);
    for id in ids {
        let c = rs.card(id);
        if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") {
            continue;
        }
        let deck = json!([RAPTOR, YETI, FIREBALL, "VAN_CS2_008", "VAN_EX1_012", WISP, RAPTOR, YETI]);
        let t = game(vid, json!({"hand": [id, YETI, FIREBALL, RAPTOR], "board": [RAPTOR, "VAN_CS2_146", WISP], "deck": deck,
            "weapon": "VAN_CS2_106"}), json!({"board": [YETI, "VAN_CS2_125"], "hand": [WISP, FROSTBOLT], "deck": deck})).unwrap();
        let e = *t.g.players[0].hand.iter().find(|&&x| t.g.e(x).card_id == *id).unwrap();
        let plays: Vec<_> = t.g.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
        for a in plays.into_iter().take(if changed.contains(id) { 6 } else { 3 }) {
            let mut g = t.g.clone_state();
            if !g.apply(&Value::Object(a.clone())).ok {
                bad.push(format!("version {vid}: {id}: {a:?} not applied"));
                break;
            }
            for _ in 0..4 {
                if g.game_over || g.script_error.get().is_some() {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok);
            }
            if let Some(err) = g.script_error.get() {
                bad.push(format!("version {vid}: {id} {a:?}: {err}"));
                break;
            }
            n += 1;
        }
    }
    if n < 300 {
        bad.push(format!("version {vid}: only {n} plays"));
    }
    bad
}
