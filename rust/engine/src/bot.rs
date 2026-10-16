//! Greedy one-step bot (game/bot.gd): tries every legal action on a clone and
//! keeps the best one if it beats ending the turn. Sees hidden information.

use crate::entity::int;
use crate::game::Action;
use crate::state::Game;
use serde_json::Value;

pub const WIN: f64 = 100000.0;
pub const MULLIGAN_MAX_COST: i64 = 3;

/// Position value for player p: own side minus the opponent's side.
pub fn value(g: &Game, p: usize) -> f64 {
    if g.game_over {
        return if g.winner == -1 {
            0.0
        } else if g.winner == p as i64 {
            WIN
        } else {
            -WIN
        };
    }
    side(g, p, true) - side(g, 1 - p, false)
}

fn side(g: &Game, p: usize, own: bool) -> f64 {
    let (pl, n) = (&g.players[p], g.n());
    let hero = g.e(pl.hero);
    let mut v = (hero.health() + hero.tag(n.armor)) as f64;
    for &m in &pl.board {
        let e = g.e(m);
        v += 1.5 * e.atk() as f64 + e.health() as f64;
        if e.has(n.guard) {
            v += 1.0;
        }
        if e.has(n.barrier) {
            v += e.atk() as f64;
        }
    }
    if let Some(w) = pl.weapon {
        v += 0.5 * g.e(w).atk() as f64 * g.e(w).tag(n.durability) as f64;
    }
    if own {
        v += 1.0 * pl.hand.len() as f64;
    }
    v
}

/// The action player p should take now (None if p has nothing to do).
pub fn choose(g: &Game, p: usize) -> Option<Action> {
    let legal: Vec<Action> = g
        .legal_actions()
        .into_iter()
        .filter(|a| int(a.get("player")) == p as i64 && a["type"] != "concede")
        .collect();
    if legal.is_empty() {
        return None;
    }
    if g.phase == "MULLIGAN" {
        return Some(mulligan(g, p, legal));
    }
    let mut best: Option<Action> = None;
    let mut best_score = f64::NEG_INFINITY;
    let last = g.players[p].board.len() as i64;
    for a in legal {
        if a["type"] == "play" && int(a.get("pos")) >= 0 && int(a.get("pos")) != last {
            continue; // ponytail: rightmost slot only; adjacency-aware placement if the bot needs it
        }
        if a["type"] == "end_turn" {
            let v = value(g, p);
            if v > best_score {
                best = Some(a);
                best_score = v;
            }
            continue;
        }
        let mut c = g.clone_state();
        if !c.apply(&Value::Object(a.clone())).ok {
            continue;
        }
        let s = value(&c, p);
        if s > best_score + 0.01 || best.is_none() {
            best = Some(a);
            best_score = s;
        }
    }
    best
}

fn mulligan(g: &Game, p: usize, legal: Vec<Action>) -> Action {
    let mut replace: Vec<i64> = g.players[p].hand.iter().copied().filter(|&e| g.cost(e) > MULLIGAN_MAX_COST).collect();
    replace.sort();
    let want = serde_json::json!(replace);
    legal.iter().find(|a| a.get("replace") == Some(&want)).cloned().unwrap_or_else(|| legal[0].clone())
}
