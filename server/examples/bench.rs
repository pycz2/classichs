//! What one game costs the server: `cargo run --release --example bench [games]`.
//! Bot-vs-bot games (Basic decks); times only the server's part of each action (apply,
//! state hash, both players' `state` messages serialized) and the memory the finished games hold.

use classichs_engine::{bot, deck, Game};
use classichs_server::game::state_msg;
use serde_json::{json, Value};
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};
use std::time::{Duration, Instant};

/// Counts the bytes live on the heap (for the memory a game holds).
struct Counting;
static LIVE: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        LIVE.fetch_add(l.size(), Relaxed);
        unsafe { System.alloc(l) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        LIVE.fetch_sub(l.size(), Relaxed);
        unsafe { System.dealloc(p, l) }
    }
}

#[global_allocator]
static A: Counting = Counting;

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(200);
    let classes = ["MAGE", "WARRIOR", "HUNTER", "PRIEST", "ROGUE", "DRUID", "SHAMAN", "PALADIN", "WARLOCK"];
    let (mut server, mut actions, mut bytes, mut biggest) = (Duration::ZERO, 0u64, 0usize, 0usize);
    let mut parts = [Duration::ZERO; 3];
    let before = LIVE.load(Relaxed);
    let mut held: Vec<Game> = vec![];
    for i in 0..n {
        let (a, b) = (classes[i % 9], classes[(i / 9 + i + 1) % 9]);
        let mut g = Game::new(deck::hero(a).unwrap(), &deck::basic(a), deck::hero(b).unwrap(), &deck::basic(b), i as i64, -1, true);
        while !g.game_over {
            let p = if g.phase == "MULLIGAN" {
                (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
            } else {
                g.pending.as_ref().map_or(g.current, |c| c.player)
            };
            let act = bot::choose(&g, p).map_or(json!({"type": "end_turn", "player": p}), Value::Object);
            let t = Instant::now();
            let r = g.apply(&act);
            let t1 = Instant::now();
            let _hash = g.state_hash();
            let t2 = Instant::now();
            for q in 0..2 {
                let s = state_msg("0123456789abcdef", &g, &r.events(), q, 75).to_string();
                bytes += s.len();
                biggest = biggest.max(s.len());
            }
            let t3 = Instant::now();
            parts[0] += t1 - t;
            parts[1] += t2 - t1;
            parts[2] += t3 - t2;
            server += t.elapsed();
            actions += 1;
        }
        held.push(g); // a finished game: the most a game holds (its whole history)
    }
    let after = LIVE.load(Relaxed);
    let per_action = server / actions as u32;
    println!("{n} games, {actions} actions: {per_action:?} per action on one core = {:.0} actions/s", 1.0 / per_action.as_secs_f64());
    let pa = |d: Duration| d / actions as u32;
    println!("  apply {:?}, state hash {:?}, two state messages {:?}", pa(parts[0]), pa(parts[1]), pa(parts[2]));
    println!("state message: {} bytes on average, {biggest} at most", bytes / (2 * actions as usize));
    println!("{} finished games held: {} KB of heap per game (state and whole history)", held.len(),
             after.saturating_sub(before) / held.len().max(1) / 1024);
    for g in held.iter_mut() {
        g.history.clear();
    }
    println!("  without the history: {} KB per game", LIVE.load(Relaxed).saturating_sub(before) / held.len().max(1) / 1024);
}
