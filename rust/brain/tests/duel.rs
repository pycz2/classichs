//! Two bot levels play each other, both from their own player's view only, over Classic's deck templates and the
//! Basic class decks: every pair of decks with each bot on each deck and on each seat (4 games, one seed).
//! Super hard gets the training clock of game/match.gd: half of what is left of its 65 s (75 s less 10), at most
//! SUPER_HARD_MS per decision, Medium at 100 ms once less than 1.5 s is left.
//!
//! `cargo test --release -p classichs-brain --test duel duel -- --ignored --nocapture` (Super hard against Hard,
//! 200 games: about an hour on 8 threads of an M1 Pro; Hard against Hard: 20 s)
//! env: DUEL_A=superhard DUEL_B=hard DUEL_GAMES=200 (rounded up to 4) DUEL_THREADS=8 DUEL_SEED=1
//!      DUEL_MS=<Super hard's most per decision, default SUPER_HARD_MS>; DUEL_LOG=1 prints every decision
//!      (`--features names` for card names); DUEL_CHEAT=1 gives A the whole game instead of its view, a ceiling
//!      of what knowing the hidden cards is worth (a measurement only: the bots never get it).

use classichs_brain::brain::{decide, Knowledge, Level};
use classichs_brain::cards::Library;
use classichs_brain::clock;
use classichs_engine::api;
use classichs_engine::state::Game;
use serde_json::Value;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

fn env<T: std::str::FromStr>(k: &str, d: T) -> T {
    std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d)
}

fn decks(lib: &Library) -> Vec<(String, String, Vec<String>)> {
    let rs = lib.rs;
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../packs/classic/decks");
    let mut files: Vec<_> = std::fs::read_dir(dir).expect("packs/classic/decks").map(|f| f.unwrap().path()).collect();
    files.sort();
    let mut out = vec![];
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        out.push((d["name"].as_str().unwrap().to_string(), d["champion"].as_str().unwrap().to_string(), cards));
    }
    for c in rs.classes.iter().filter(|c| c.playable && !c.champion.is_empty()) {
        out.push((format!("Basic {}", c.id), c.champion.clone(), classichs_engine::deck::basic_in(rs, &c.id)));
    }
    out
}

#[derive(Default)]
struct Stats {
    worst_decision: u128,
    worst_turn: u128,
    decisions: usize,
}

/// One game: level `la` on seat `sa` with deck `da`; 1 a win of A, 0 a draw, -1 a loss.
fn game(lib: &'static Library, la: Level, lb: Level, sa: usize, da: &[String], ha: &str, db: &[String], hb: &str, seed: i64,
    ms: u64, st: &mut Stats) -> i64 {
    let (h, d) = if sa == 0 { ([ha, hb], [da, db]) } else { ([hb, ha], [db, da]) };
    let mut g = Game::new_in(lib.rs, h[0], d[0], h[1], d[1], seed, 0, true);
    let mut turn_start: (i64, usize, Duration) = (-1, 9, Duration::ZERO);
    for _ in 0..600 {
        if g.game_over {
            break;
        }
        let movers: Vec<usize> = if g.phase == "MULLIGAN" {
            (0..2).filter(|&p| !g.players[p].mulliganed).collect()
        } else if let Some(p) = &g.pending {
            vec![p.player]
        } else {
            vec![g.current]
        };
        for p in movers {
            let mut level = if p == sa { la } else { lb };
            let mut budget = Duration::from_millis(match level {
                Level::Easy => 0,
                Level::Medium => 300,
                Level::Hard => 1000,
                Level::SuperHard => ms,
            });
            let now = clock::now();
            if level == Level::SuperHard && g.phase != "MULLIGAN" {
                if (g.turn, p) != (turn_start.0, turn_start.1) {
                    turn_start = (g.turn, p, now);
                }
                let left = 65_000.0 - (now - turn_start.2).as_secs_f64() * 1000.0;
                if left < 1500.0 {
                    (level, budget) = (Level::Medium, Duration::from_millis(100));
                } else {
                    budget = Duration::from_millis((left / 2.0 - 100.0).clamp(100.0, ms as f64) as u64);
                }
            }
            let k = Knowledge { lib, seat: p, my_deck: d[p].to_vec(), arena: false, seed: (seed as u64) << 16 ^ g.history.len() as u64 ^ (p as u64) << 40 };
            let t0 = clock::now();
            let dec = decide(&api::snapshot(&g, if p == sa && std::env::var("DUEL_CHEAT").is_ok() { -1 } else { p as i64 }), &k, level, budget).expect("decide");
            let took = (clock::now() - t0).as_millis();
            if p == sa {
                st.worst_decision = st.worst_decision.max(took);
                st.decisions += 1;
                if (g.turn, p) == (turn_start.0, turn_start.1) {
                    st.worst_turn = st.worst_turn.max((clock::now() - turn_start.2).as_millis());
                }
            }
            let Some(dec) = dec else { continue };
            if std::env::var("DUEL_LOG").is_ok() {
                let life = |q: usize| g.e(g.players[q].hero).health();
                let top: Vec<String> = dec.top.iter().map(|c| format!("{} {:.1}", c.label, c.score)).collect();
                eprintln!("t{} p{p} {} ({}:{} life, {} ms, {} worlds) {}   [{}]", g.turn, level.name(), life(p), life(1 - p), took, dec.worlds, dec.label, top.join(" | "));
            }
            let r = g.apply(&Value::Object(dec.action.clone()));
            assert!(r.ok, "seat {p}: an illegal move {:?}: {}", dec.action, r.error);
        }
    }
    if g.winner == sa as i64 { 1 } else if g.winner == -1 { 0 } else { -1 }
}

/// The 95% Wilson interval of a rate of n tries.
fn wilson(p: f64, n: f64) -> (f64, f64) {
    let z = 1.96;
    let c = (p + z * z / (2.0 * n)) / (1.0 + z * z / n);
    let h = z * (p * (1.0 - p) / n + z * z / (4.0 * n * n)).sqrt() / (1.0 + z * z / n);
    (c - h, c + h)
}

#[test]
#[ignore]
fn duel() {
    let lib = Library::get();
    let la = Level::parse(&env("DUEL_A", "superhard".to_string())).expect("DUEL_A");
    let lb = Level::parse(&env("DUEL_B", "hard".to_string())).expect("DUEL_B");
    let units = env("DUEL_GAMES", 200usize).div_ceil(4);
    let threads = env("DUEL_THREADS", 8usize);
    let seed0 = env("DUEL_SEED", 1i64);
    let ms = env("DUEL_MS", classichs_brain::SUPER_HARD_MS);
    let ds = decks(lib);
    let n = ds.len();
    // the pairs of decks (a != b), spread over all of them
    let pairs: Vec<(usize, usize)> = (0..units).map(|u| {
        let a = u % n;
        let b = (a + 1 + (u / n * 7 + u * 3) % (n - 1)) % n;
        (a, b)
    }).collect();
    let next = AtomicUsize::new(0);
    let out = Mutex::new((0i64, 0i64, 0i64, Stats::default(), vec![0i64; n]));
    let t0 = std::time::Instant::now();
    std::thread::scope(|s| {
        for _ in 0..threads {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= units * 4 {
                    break;
                }
                let (u, k) = (i / 4, i % 4);
                let (a, b) = pairs[u];
                let (mine, theirs) = if k % 2 == 0 { (a, b) } else { (b, a) };
                let mut st = Stats::default();
                let r = game(lib, la, lb, k / 2, &ds[mine].2, &ds[mine].1, &ds[theirs].2, &ds[theirs].1, seed0 * 100_000 + u as i64, ms, &mut st);
                let mut o = out.lock().unwrap();
                match r {
                    1 => o.0 += 1,
                    0 => o.1 += 1,
                    _ => o.2 += 1,
                }
                o.4[mine] += r;
                o.3.worst_decision = o.3.worst_decision.max(st.worst_decision);
                o.3.worst_turn = o.3.worst_turn.max(st.worst_turn);
                o.3.decisions += st.decisions;
                let done = o.0 + o.1 + o.2;
                if done % 20 == 0 {
                    eprintln!("{done} games: {} won, {} drawn, {} lost ({:.0} s)", o.0, o.1, o.2, t0.elapsed().as_secs_f64());
                }
            });
        }
    });
    let (w, dr, l, st, per) = out.into_inner().unwrap();
    let games = (w + dr + l) as f64;
    let p = (w as f64 + 0.5 * dr as f64) / games;
    let (lo, hi) = wilson(p, games);
    for (i, d) in ds.iter().enumerate() {
        eprintln!("  {:<24} {:+}", d.0, per[i]);
    }
    println!(
        "{} vs {}: {w} won, {dr} drawn, {l} lost of {games} = {:.1}% (95% CI {:.1}-{:.1}%); {}: worst decision {} ms, worst turn {} ms, {} decisions; {:.0} s",
        la.name(), lb.name(), 100.0 * p, 100.0 * lo, 100.0 * hi, la.name(), st.worst_decision, st.worst_turn, st.decisions, t0.elapsed().as_secs_f64()
    );
}

/// Fits Super hard's learned evaluation (brain::features → the chance to win, logistic) on Hard against Hard
/// with the bot library's decks (not the duel's), and prints the weights.
/// `FIT_GAMES=2000 cargo test --release -p classichs-brain --test duel fit -- --ignored --nocapture`
#[test]
#[ignore]
fn fit() {
    let lib = Library::get();
    let games = env("FIT_GAMES", 2000usize);
    let threads = env("DUEL_THREADS", 8usize);
    let next = AtomicUsize::new(0);
    let data: Mutex<Vec<(Vec<f64>, f64)>> = Mutex::new(vec![]);
    std::thread::scope(|s| {
        for _ in 0..threads {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= games {
                    break;
                }
                let n = lib.decks.len();
                let (a, b) = (i % n, (i * 7 + 3 + i / n) % n);
                let (d0, d1) = (&lib.decks[a], &lib.decks[b]);
                let mut g = Game::new_in(lib.rs, &d0.hero, &d0.cards, &d1.hero, &d1.cards, 900_000 + i as i64, -1, true);
                let mut rows: Vec<(Vec<f64>, usize)> = vec![];
                for _ in 0..600 {
                    if g.game_over {
                        break;
                    }
                    let movers: Vec<usize> = if g.phase == "MULLIGAN" {
                        (0..2).filter(|&p| !g.players[p].mulliganed).collect()
                    } else if let Some(p) = &g.pending {
                        vec![p.player]
                    } else {
                        vec![g.current]
                    };
                    for p in movers {
                        if g.phase != "MULLIGAN" {
                            rows.push((classichs_brain::brain::features(&g, p), p));
                            rows.push((classichs_brain::brain::features(&g, 1 - p), 1 - p));
                        }
                        let deck = if p == 0 { &d0.cards } else { &d1.cards };
                        let k = Knowledge { lib, seat: p, my_deck: deck.clone(), arena: false, seed: i as u64 * 7919 + g.history.len() as u64 };
                        let Some(dec) = decide(&api::snapshot(&g, p as i64), &k, Level::Hard, Duration::from_millis(1000)).expect("decide") else { continue };
                        assert!(g.apply(&Value::Object(dec.action)).ok);
                    }
                }
                if g.winner >= 0 {
                    let mut d = data.lock().unwrap();
                    for (f, p) in rows {
                        d.push((f, if g.winner == p as i64 { 1.0 } else { 0.0 }));
                    }
                }
            });
        }
    });
    let data = data.into_inner().unwrap();
    let m = data[0].0.len();
    let rows = data.len() as f64;
    let mean: Vec<f64> = (0..m).map(|j| data.iter().map(|r| r.0[j]).sum::<f64>() / rows).collect();
    let sd: Vec<f64> = (0..m).map(|j| (data.iter().map(|r| (r.0[j] - mean[j]).powi(2)).sum::<f64>() / rows).sqrt().max(1e-6)).collect();
    let x: Vec<Vec<f64>> = data.iter().map(|r| (0..m).map(|j| (r.0[j] - mean[j]) / sd[j]).collect()).collect();
    let mut w = vec![0.0f64; m + 1];
    let (mut mom, mut vel) = (vec![0.0f64; m + 1], vec![0.0f64; m + 1]);
    let mut loss = 0.0;
    for it in 1..=env("FIT_STEPS", 600i32) {
        let mut grad = vec![0.0f64; m + 1];
        loss = 0.0;
        for (xi, r) in x.iter().zip(&data) {
            let z = w[0] + xi.iter().zip(&w[1..]).map(|(a, b)| a * b).sum::<f64>();
            let p = 1.0 / (1.0 + (-z).exp());
            loss -= r.1 * p.max(1e-12).ln() + (1.0 - r.1) * (1.0 - p).max(1e-12).ln();
            let e = p - r.1;
            grad[0] += e;
            for j in 0..m {
                grad[j + 1] += e * xi[j];
            }
        }
        // Adam
        for j in 0..=m {
            let gj = grad[j] / rows + if j > 0 { 1e-4 * w[j] } else { 0.0 };
            mom[j] = 0.9 * mom[j] + 0.1 * gj;
            vel[j] = 0.999 * vel[j] + 0.001 * gj * gj;
            let (mh, vh) = (mom[j] / (1.0 - 0.9f64.powi(it)), vel[j] / (1.0 - 0.999f64.powi(it)));
            w[j] -= 0.05 * mh / (vh.sqrt() + 1e-8);
        }
    }
    let mut raw = vec![w[0] - (0..m).map(|j| w[j + 1] * mean[j] / sd[j]).sum::<f64>()];
    raw.extend((0..m).map(|j| w[j + 1] / sd[j]));
    println!("{} positions, log loss {:.4}", data.len(), loss / rows);
    println!("SH_W={}", raw.iter().map(|v| format!("{v:.5}")).collect::<Vec<_>>().join(","));
}
