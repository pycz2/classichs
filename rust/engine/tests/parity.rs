//! Replays games recorded from the GDScript engine (tools/engine_record.gd, both
//! removed in 0.27: the fixtures are frozen) and checks that the Rust engine gives
//! the same legal actions, bot choices, events and state hashes at every step.
//! Fixtures: tests/fixtures/*.jsonl (committed) and tests/fixtures/big/*.jsonl
//! (generated earlier, gitignored).
//!
//! `PARITY_FILTER` replays only the games that mention some cards (in their
//! setup, actions or events): a class (`MAGE`), `lua` (every card with Lua
//! hooks), or card ids (`VAN_CS2_029,VAN_EX1_287`); comma-separated, mixed.
//! `PARITY_BIG=0` skips fixtures/big (the committed 1731 games only: a quick check).
//! `PARITY_FIXTURES=<dir>` reads the fixtures from another folder.

use classichs_engine::api::Engine;
use classichs_engine::entity::int;
use classichs_engine::game::mulligan_seed;
use classichs_engine::json::stringify;
use classichs_engine::rng::Rng;
use classichs_engine::state::{hex, Game};
use classichs_engine::{bot, card_db, missions, ruleset, scenario};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::path::Path;

fn short(s: &str) -> String {
    hex(&Sha256::digest(s.as_bytes()))[..16].to_string()
}

fn events_match(want: &Value, got: &[serde_json::Map<String, Value>]) -> bool {
    let got = Value::Array(got.iter().cloned().map(Value::Object).collect());
    match want {
        Value::String(h) => *h == short(&stringify(&got)),
        _ => stringify(want) == stringify(&got),
    }
}

#[derive(Default)]
struct Stats {
    games: usize,
    steps: usize,
    bot_checks: usize,
    mismatches: Vec<String>,
    played: BTreeSet<String>,
    seen: BTreeSet<String>,
}

fn setup(s: &Value) -> Game {
    match s["kind"].as_str().unwrap() {
        "new" => {
            let deck = |p: &Value| -> Vec<String> { p["deck"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect() };
            Game::new(s["p0"]["hero"].as_str().unwrap(), &deck(&s["p0"]), s["p1"]["hero"].as_str().unwrap(), &deck(&s["p1"]),
                int(s.get("seed")), int(s.get("first")), true)
        }
        "scenario" => scenario::build(&s["scenario"]).unwrap(),
        "mission" => missions::start(int(s.get("n")) as usize).unwrap(),
        k => panic!("unknown setup {k}"),
    }
}

fn replay(line: &Value, st: &mut Stats) {
    let id = line["id"].as_str().unwrap().to_string();
    st.games += 1;
    let mut g = setup(&line["setup"]);
    let bad = |st: &mut Stats, what: String| {
        if st.mismatches.len() < 40 {
            eprintln!("MISMATCH {id}: {what}");
        }
        st.mismatches.push(format!("{id}: {what}"));
    };
    if short(&g.state_hash()) != line["h0"].as_str().unwrap()[..16] {
        bad(st, "start hash".into());
        return;
    }
    let start: Vec<_> = g.history[0]["events"].as_array().unwrap().iter().map(|e| e.as_object().unwrap().clone()).collect();
    if !events_match(&line["e0"], &start) {
        bad(st, "start events".into());
        return;
    }
    for (i, s) in line["steps"].as_array().unwrap().iter().enumerate() {
        st.steps += 1;
        let legal = Value::Array(g.legal_actions().into_iter().map(Value::Object).collect());
        if short(&stringify(&legal)) != s["l"].as_str().unwrap() {
            bad(st, format!("step {i}: legal actions differ: {}", stringify(&legal)));
            return;
        }
        if let Some(p) = s.get("b") {
            st.bot_checks += 1;
            let mine = bot::choose(&g, int(Some(p)) as usize).map_or(json!({}), Value::Object);
            if mine != s["a"] {
                bad(st, format!("step {i}: bot chose {} not {}", stringify(&mine), stringify(&s["a"])));
                return;
            }
        }
        let res = g.apply(&s["a"]);
        if res.ok != s["ok"].as_bool().unwrap() || (!res.ok && res.error != s["err"].as_str().unwrap_or("")) {
            bad(st, format!("step {i}: ok {} err {:?} want {}", res.ok, res.error, stringify(s)));
            return;
        }
        for ev in &res.events {
            if let Some(c) = ev.get("card").and_then(Value::as_str) {
                st.seen.insert(c.to_string());
                if ev.get("type") == Some(&json!("play")) {
                    st.played.insert(c.to_string());
                }
            }
        }
        if s["a"]["type"] == "hero_power" && res.ok {
            st.played.insert(g.e(g.players[int(s["a"].get("player")) as usize].hero_power).card_id.clone());
        }
        if !events_match(&s["e"], &res.events) {
            let got = Value::Array(res.events.iter().cloned().map(Value::Object).collect());
            bad(st, format!("step {i} {}: events differ: {}", stringify(&s["a"]), stringify(&got)));
            return;
        }
        if short(&g.state_hash()) != s["h"].as_str().unwrap() {
            bad(st, format!("step {i} {}: state differs: {}", stringify(&s["a"]), stringify(&g.to_dict())));
            return;
        }
    }
    if let Some(d) = line.get("dump") {
        if short(&stringify(&scenario::dump(&g))) != d.as_str().unwrap() {
            bad(st, format!("dump differs: {}", stringify(&scenario::dump(&g))));
        }
    }
}

fn misc(line: &Value, st: &mut Stats) {
    match line["t"].as_str().unwrap() {
        "rng" => {
            let mut r = Rng::new(int(line.get("seed")) as u64);
            let range: Vec<i64> = (0..40).map(|k| r.randi_range(0, k)).collect();
            let f: Vec<String> = (0..20).map(|_| format!("{:.17}", r.randf())).collect();
            assert_eq!(json!(range), line["range"], "randi_range seed {}", line["seed"]);
            assert_eq!(json!(f), line["randf"], "randf seed {}", line["seed"]);
            assert_eq!((r.state as i64).to_string(), line["state"].as_str().unwrap());
            assert_eq!(r.randi() as i64, int(line.get("randi")));
        }
        "mulligan_seed" => {
            let s = int(line.get("seed")) as u64;
            let want: Vec<i64> = line["out"].as_array().unwrap().iter().map(|v| int(Some(v))).collect();
            assert_eq!(vec![mulligan_seed(s, 0) as i64, mulligan_seed(s, 1) as i64], want);
        }
        "ref" => {
            let got = Engine::new().handle(&line["req"]);
            if stringify(&got) != stringify(&line["out"]) {
                st.mismatches.push(format!("ref {}: got {} want {}", stringify(&line["req"]), stringify(&got), stringify(&line["out"])));
            }
        }
        t => panic!("unknown misc line {t}"),
    }
}

/// The quoted card ids PARITY_FILTER names (None: replay everything).
fn filter() -> Option<Vec<String>> {
    let f = std::env::var("PARITY_FILTER").ok().filter(|f| !f.trim().is_empty())?;
    let rs = ruleset::classic();
    let mut ids = vec![];
    for w in f.split(',').map(str::trim) {
        if w == "lua" {
            ids.extend(rs.hooks.iter().filter(|(_, h)| h.lua).map(|(id, _)| id.clone()));
        } else if rs.has(w) {
            ids.push(w.to_string());
        } else {
            let class: Vec<String> = rs.cards.values().filter(|c| c.card_class == w).map(|c| c.id.clone()).collect();
            assert!(!class.is_empty(), "PARITY_FILTER: {w} is neither a card id, a class nor 'lua'");
            ids.extend(class);
        }
    }
    eprintln!("PARITY_FILTER={f}: games that mention any of {} cards", ids.len());
    Some(ids.into_iter().map(|id| format!("\"{id}\"")).collect())
}

#[test]
fn parity_with_gdscript() {
    let dir = match std::env::var("PARITY_FIXTURES") {
        Ok(d) => Path::new(&d).to_path_buf(),
        Err(_) => Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures"),
    };
    let mut files = vec![];
    let big = std::env::var("PARITY_BIG").map_or(true, |v| v != "0");
    for d in [dir.clone(), dir.join("big")].into_iter().take(if big { 2 } else { 1 }) {
        if let Ok(rd) = std::fs::read_dir(&d) {
            for e in rd.flatten() {
                if e.path().extension().is_some_and(|x| x == "jsonl") {
                    files.push(e.path());
                }
            }
        }
    }
    files.sort();
    assert!(!files.is_empty(), "no fixtures in {}", dir.display());
    let needles = filter();
    let t0 = std::time::Instant::now();
    let mut st = Stats::default();
    for f in &files {
        let text = std::fs::read_to_string(f).unwrap();
        for line in text.lines().filter(|l| !l.trim().is_empty()) {
            if let Some(n) = &needles {
                if !n.iter().any(|x| line.contains(x.as_str())) {
                    continue;
                }
            }
            let Ok(v) = serde_json::from_str::<Value>(line) else {
                eprintln!("skipping a broken line in {}", f.display());
                continue;
            };
            if v.get("t").is_some() {
                misc(&v, &mut st);
            } else {
                replay(&v, &mut st);
            }
        }
    }
    let playable: Vec<&String> = card_db::collectible().iter().filter(|id| card_db::card(id).kind != "HERO").collect();
    let missing: Vec<&&String> = playable.iter().filter(|id| !st.played.contains(**id)).collect();
    eprintln!(
        "parity: {} files, {} games, {} steps, {} bot choices checked, {} cards played ({} of {} collectible), {} cards seen in events, {} mismatches, {:.1} s",
        files.len(), st.games, st.steps, st.bot_checks, st.played.len(), playable.len() - missing.len(), playable.len(),
        st.seen.len(), st.mismatches.len(), t0.elapsed().as_secs_f64()
    );
    if !missing.is_empty() && needles.is_none() {
        eprintln!("collectible cards never played: {:?}", missing);
    }
    let rs = ruleset::classic();
    let mut hooked: Vec<&str> = rs
        .hooks
        .keys()
        .map(String::as_str)
        .filter(|id| card_db::has(id) && !st.played.contains(*id) && !st.seen.contains(*id))
        .filter(|id| needles.as_ref().is_none_or(|n| n.contains(&format!("\"{id}\""))))
        .collect();
    hooked.sort();
    eprintln!("cards with hooks never played or seen in an event: {:?}", hooked);
    assert!(st.mismatches.is_empty(), "{} mismatches, first: {}", st.mismatches.len(), st.mismatches[0]);
}
