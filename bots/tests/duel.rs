//! The bots' brain against the engine's built-in greedy bot, on the Classic decks: it must win
//! clearly more often, though it sees only a player's view and the built-in one sees everything.
//! `cargo test --release --test duel -- --nocapture` prints the record and the time per decision.

use classichs_bots::brain::{decide, Knowledge};
use classichs_bots::cards::Library;
use classichs_engine::{api, bot};
use classichs_engine::state::Game;
use serde_json::Value;
use std::path::Path;
use std::time::Duration;

fn play(lib: &Library, a: usize, b: usize, seed: i64, brain_seat: usize, ms: &mut Vec<u128>) -> i64 {
    let (da, db) = (&lib.decks[a], &lib.decks[b]);
    let (d0, d1) = if brain_seat == 0 { (da, db) } else { (db, da) };
    let mut g = Game::new_in(lib.rs, &d0.hero, &d0.cards, &d1.hero, &d1.cards, seed, -1, true);
    let k = Knowledge { lib, seat: brain_seat, my_deck: da.cards.clone(), arena: false };
    for _ in 0..400 {
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
            let action = if p == brain_seat {
                let view = api::snapshot(&g, p as i64);
                match decide(&view, &k, Duration::from_millis(300)).expect("decide") {
                    Some(d) => {
                        ms.push(d.ms);
                        d.action
                    }
                    None => continue,
                }
            } else {
                match bot::choose(&g, p) {
                    Some(a) => a,
                    None => continue,
                }
            };
            let r = g.apply(&Value::Object(action.clone()));
            assert!(r.ok, "seat {p} made an illegal move {action:?}: {}", r.error);
        }
    }
    if g.winner == brain_seat as i64 { 1 } else if g.winner == -1 { 0 } else { -1 }
}

#[test]
fn the_brain_beats_the_greedy_bot() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let lib = Library::load(&root).unwrap();
    let n = lib.decks.len();
    let (mut won, mut lost, mut ms) = (0, 0, vec![]);
    for i in 0..n {
        let r = play(&lib, i, (i + 3) % n, 1000 + i as i64, i % 2, &mut ms);
        if r > 0 { won += 1 } else if r < 0 { lost += 1 }
    }
    ms.sort();
    let avg = ms.iter().sum::<u128>() as f64 / ms.len().max(1) as f64;
    println!("brain vs greedy: {won} won, {lost} lost of {n}; decision time avg {avg:.0} ms, p90 {} ms", ms[ms.len() * 9 / 10]);
    assert!(won > lost, "the brain must beat the greedy bot");
}
