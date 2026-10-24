//! The three bot levels against the engine's built-in greedy bot (which sees every card; the bots
//! see only their player's view): the levels must be stronger in that order.
//! `cargo test --release --test bot_levels -- --ignored --nocapture` (a few minutes).

use classichs_engine::{api, bot};
use classichs_engine::state::Game;
use classichs_server::bots::brain::{decide, Knowledge, Level};
use classichs_server::bots::cards::Library;
use serde_json::Value;
use std::time::Duration;

fn play(lib: &'static Library, a: usize, b: usize, seed: i64, seat: usize, level: Level) -> i64 {
    let (da, db) = (&lib.decks[a], &lib.decks[b]);
    let (d0, d1) = if seat == 0 { (da, db) } else { (db, da) };
    let mut g = Game::new_in(lib.rs, &d0.hero, &d0.cards, &d1.hero, &d1.cards, seed, -1, true);
    let k = Knowledge { lib, seat, my_deck: da.cards.clone(), arena: false };
    let budget = match level {
        Level::Easy => Duration::ZERO,
        Level::Medium => Duration::from_millis(300),
        Level::Hard => Duration::from_millis(1000),
    };
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
            let action = if p == seat {
                match decide(&api::snapshot(&g, p as i64), &k, level, budget).expect("decide") {
                    Some(d) => d.action,
                    None => continue,
                }
            } else {
                match bot::choose(&g, p) {
                    Some(a) => a,
                    None => continue,
                }
            };
            let r = g.apply(&Value::Object(action.clone()));
            assert!(r.ok, "seat {p}: an illegal move {action:?}: {}", r.error);
        }
    }
    if g.winner == seat as i64 { 1 } else if g.winner == -1 { 0 } else { -1 }
}

#[test]
#[ignore]
fn levels_get_stronger() {
    let lib = Library::get();
    let n = 18;
    let mut rate = vec![];
    for level in [Level::Easy, Level::Medium, Level::Hard] {
        let (mut won, mut lost) = (0, 0);
        for i in 0..n {
            let a = (i * 7) % lib.decks.len();
            let b = (i * 11 + 3) % lib.decks.len();
            match play(lib, a, b, 5000 + i as i64, i % 2, level) {
                1 => won += 1,
                -1 => lost += 1,
                _ => {}
            }
        }
        println!("{:?} vs the greedy bot: {won} won, {lost} lost of {n}", level);
        rate.push(won);
    }
    assert!(rate[0] <= rate[1] && rate[1] <= rate[2], "stronger in order: {rate:?}");
}
