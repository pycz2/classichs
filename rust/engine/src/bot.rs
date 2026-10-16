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
        v += 1.0 * pl.hand.len() as f64 + g.rs.bot_trap * pl.secrets.len() as f64;
    }
    v
}

/// p's actions the bot considers: no concede, a minion only to the rightmost slot.
fn options(g: &Game, p: usize) -> Vec<Action> {
    let last = g.players[p].board.len() as i64;
    g.legal_actions()
        .into_iter()
        .filter(|a| int(a.get("player")) == p as i64 && a["type"] != "concede")
        // ponytail: rightmost slot only; adjacency-aware placement if the bot needs it
        .filter(|a| !(a["type"] == "play" && int(a.get("pos")) >= 0 && int(a.get("pos")) != last))
        .collect()
}

/// The action player p should take now (None if p has nothing to do).
pub fn choose(g: &Game, p: usize) -> Option<Action> {
    let legal = options(g, p);
    if legal.is_empty() {
        return None;
    }
    if g.phase == "MULLIGAN" {
        return Some(mulligan(g, p, legal));
    }
    let (best, score) = greedy(g, p, &legal);
    if g.rs.bot_depth < 2 || best.as_ref().is_none_or(|a| a["type"] != "end_turn") {
        return best;
    }
    // bot.depth 2: before ending the turn, an action that pays off only with the next one
    // (a temporary Mana card, then a minion)
    let mut two: Option<(Action, f64)> = None;
    for a in legal.into_iter().filter(|a| a["type"] != "end_turn") {
        let mut c = g.clone_state();
        if !c.apply(&Value::Object(a.clone())).ok || c.game_over {
            continue;
        }
        let s = greedy(&c, p, &options(&c, p)).1;
        if s > two.as_ref().map_or(score, |t| t.1) + 0.01 {
            two = Some((a, s));
        }
    }
    two.map(|t| t.0).or(best)
}

/// The best of these actions one step ahead (ending the turn wins ties) and its value.
fn greedy(g: &Game, p: usize, legal: &[Action]) -> (Option<Action>, f64) {
    let mut best: Option<Action> = None;
    let mut best_score = f64::NEG_INFINITY;
    for a in legal {
        if a["type"] == "end_turn" {
            let v = value(g, p);
            if v > best_score {
                best = Some(a.clone());
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
            best = Some(a.clone());
            best_score = s;
        }
    }
    (best, best_score)
}

fn mulligan(g: &Game, p: usize, legal: Vec<Action>) -> Action {
    let mut replace: Vec<i64> = g.players[p].hand.iter().copied().filter(|&e| g.cost(e) > MULLIGAN_MAX_COST).collect();
    replace.sort();
    let want = serde_json::json!(replace);
    legal.iter().find(|a| a.get("replace") == Some(&want)).cloned().unwrap_or_else(|| legal[0].clone())
}
