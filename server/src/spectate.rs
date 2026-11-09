//! Spectators: a friend watches a live game from the friend's seat (`spectate {user}`: the
//! friend's view, never more), a tournament's spectators see both hands (`add` with `full`).
//! The game loop sends them `spectate_state` (the shape of `state`) after every change and
//! `spectate_end` at the end; the players are never told who watches, and spectators get
//! none of the players' emotes or intents.

use crate::game::{state_msg, Ev};
use crate::AppRef;
use classichs_engine::api::{events_for, snapshot};
use classichs_engine::state::Ev as Events;
use classichs_engine::Game;
use serde_json::{json, Value};
use std::collections::HashMap;

/// Spectators of one game at most.
pub const MAX_PER_GAME: usize = 20;

/// What one spectator watches (one game at a time).
pub struct Watch {
    pub game: String,
    /// The seat whose view it gets (with `full`: the seat drawn at the bottom).
    pub seat: usize,
    /// Both hands open (tournament spectators).
    pub full: bool,
}

/// Lets an account watch a live game with everything open (`full`) or seat 0's view; who may
/// watch is the caller's business (tournaments: part D). Errors are human texts.
pub fn add(app: &AppRef, game: &str, account: i64, full: bool) -> Result<(), &'static str> {
    join(app, game, account, 0, full)
}

/// Starts watching (a game watched before is left): `spectating` now, the current
/// `spectate_state` from the game loop right after it.
pub fn join(app: &AppRef, game: &str, account: i64, seat: usize, full: bool) -> Result<(), &'static str> {
    let mut hub = app.hub();
    if hub.in_game.contains_key(&account) {
        return Err("You are in a game");
    }
    let Some(lg) = hub.games.get(game) else { return Err("The game is over") };
    let already = hub.watching.get(&account).is_some_and(|w| w.game == game);
    if !already && hub.watching.values().filter(|w| w.game == game).count() >= MAX_PER_GAME {
        return Err("This game has the most spectators it can have");
    }
    let m = json!({"t": "spectating", "game": game, "mode": lg.mode, "pack": lg.pack, "players": lg.names, "seat": seat, "full": full});
    let tx = lg.tx.clone();
    hub.watching.insert(account, Watch { game: game.into(), seat, full });
    hub.send(account, &m);
    let _ = tx.send(Ev::Watch(account));
    Ok(())
}

/// Stops watching (unspectate, a disconnect, the spectator's own game starting).
pub fn leave(app: &AppRef, account: i64) {
    app.hub().watching.remove(&account);
}

/// A spectator's `spectate_state`: the seat's view, or with `full` what both players see.
pub fn state(game: &str, g: &Game, events: &[Events], seat: usize, full: bool, deadline: u64) -> Value {
    let mut m = state_msg(game, g, events, seat, deadline);
    m["t"] = json!("spectate_state");
    if full {
        let (other, theirs) = (snapshot(g, 1 - seat as i64), events_for(g, events, 1 - seat as i64));
        if let (Some(mine), Some(o)) = (m["view"]["entities"].as_object_mut(), other["entities"].as_object()) {
            for (id, e) in o {
                if mine.get(id).is_none_or(|x| x["card"] == "") {
                    mine.insert(id.clone(), e.clone());
                }
            }
        }
        if let (Some(mine), Some(o)) = (m["events"].as_array_mut(), theirs.as_array()) {
            for (x, y) in mine.iter_mut().zip(o) {
                if x["card"] == "" {
                    *x = y.clone();
                }
            }
        }
    }
    m
}

/// Sends every spectator of a game its state (one message per (seat, full) made once).
// ponytail: scans all spectators of the server per action; index them by game if there are thousands.
pub fn states(app: &AppRef, game: &str, g: &Game, events: &[Events], deadline: u64) {
    let who: Vec<(i64, usize, bool)> =
        app.hub().watching.iter().filter(|(_, w)| w.game == game).map(|(a, w)| (*a, w.seat, w.full)).collect();
    if who.is_empty() {
        return;
    }
    let mut made: HashMap<(usize, bool), Value> = HashMap::new();
    for &(_, seat, full) in &who {
        made.entry((seat, full)).or_insert_with(|| state(game, g, events, seat, full, deadline));
    }
    let hub = app.hub();
    for (a, seat, full) in who {
        if hub.watching.get(&a).is_some_and(|w| w.game == game) {
            hub.send(a, &made[&(seat, full)]);
        }
    }
}

/// The current state for one new spectator (the game loop got `Ev::Watch`).
pub fn first(app: &AppRef, game: &str, g: &Game, account: i64, deadline: u64) {
    let w = app.hub().watching.get(&account).filter(|w| w.game == game).map(|w| (w.seat, w.full));
    if let Some((seat, full)) = w {
        let m = state(game, g, &[], seat, full, deadline);
        app.hub().send(account, &m);
    }
}

/// The game ended: its spectators get `spectate_end {game, winner (seat, −1 = nobody), reason}`.
pub fn end(app: &AppRef, game: &str, winner: i64, reason: &str) {
    let mut hub = app.hub();
    let who: Vec<i64> = hub.watching.iter().filter(|(_, w)| w.game == game).map(|(a, _)| *a).collect();
    let m = json!({"t": "spectate_end", "game": game, "winner": winner, "reason": reason});
    for a in who {
        hub.watching.remove(&a);
        hub.send(a, &m);
    }
}
