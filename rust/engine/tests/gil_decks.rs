//! The Witchwood deck templates (packs/gil/decks) in whole bot-vs-bot games: every template plays three games to the
//! end with no script error; the bots play the set's cards, Echo copies, Baku's and Genn's Start of Game. Needs
//! python3 (skipped without it).

use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, pack, Game};
use serde_json::Value;
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The pack, built once (its recipe needs tools/pack.py); None without python3.
fn rs() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("gil-decks-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/gil", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/gil/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30, "{f:?}");
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert!(decks.len() >= 12);
    let mut over = 0;
    let mut errors = vec![];
    let mut played = std::collections::BTreeSet::new();
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 7) % decks.len()];
        for seed in 0..3 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" {
                    (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
                } else {
                    g.pending.as_ref().map_or(g.current, |c| c.player)
                };
                let a = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(a)).ok);
                steps += 1;
                assert!(steps < 4000);
            }
            if let Some(err) = g.script_error.get() {
                errors.push(format!("deck {i} ({c0}) vs {} ({c1}), seed {seed}: {err}", (i + 7) % decks.len()));
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("GIL_") {
                        played.insert(card.to_string());
                    }
                }
            }
        }
    }
    eprintln!("The Witchwood cards played: {}: {played:?}", played.len());
    assert!(errors.is_empty(), "script errors:\n{}", errors.join("\n"));
    assert!(over >= decks.len() * 2, "most games end");
    assert!(played.len() >= 15, "the decks play the set (22 Witchwood cards in the templates)");
}
