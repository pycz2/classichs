//! How a bot chooses a move from what a player sees (the server's `view`), never more:
//!
//! 1. The view becomes a playable game (`view::from_snapshot_in`); the cards it cannot see are a filler.
//! 2. **Worlds** (determinization): each world puts a plausible card in every hidden place — the own
//!    deck from the own deck list minus the cards already seen, the opponent's hand, deck and secrets
//!    from its class pool — and a new random seed. Probabilities count; the future is not known.
//! 3. The actions worth trying (`options`): a minion goes only to the rightmost slot unless a card whose
//!    effect depends on its neighbours is on the board or in hand; identical copies count once. A quick
//!    look (one step) orders them; Easy and Medium keep only the best few.
//! 4. Sequential halving: every remaining action is tried in a new world — the rest of the turn played
//!    greedily by the evaluation, then (Hard) **the opponent's whole turn** (the engine's bot with the
//!    sampled hand) — and the worse half drops out; again in the next world. Lethal is ±1 000 000.
//! 5. A hard time limit (twice the budget plus 0.2 s) stops the search anywhere, even inside a world;
//!    the best action found so far is played. After it the bot looks again.

use crate::bots::cards::{class_of, Library, Pool};
use classichs_engine::entity::Entity;
use classichs_engine::game::Action;
use classichs_engine::rng::Rng;
use classichs_engine::state::Game;
use classichs_engine::{bot, view};
use rand::seq::SliceRandom;
use rand::SeedableRng;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

pub const WIN: f64 = 1_000_000.0;

/// How strong a bot plays (the admin sets it per bot).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    /// One guess of the hidden cards, the position right after the action only, a wrong pick now and
    /// then (30%: a random one of the best three), the opening hand kept.
    Easy,
    /// 2-3 worlds, the best 10 first actions, the rest of the turn played on, the opponent's reply not looked at.
    Medium,
    /// 4-10 worlds within the time, the turn played on and the opponent's whole turn simulated.
    Hard,
}

impl Level {
    pub fn parse(s: &str) -> Option<Level> {
        match s {
            "easy" => Some(Level::Easy),
            "medium" => Some(Level::Medium),
            "hard" => Some(Level::Hard),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Level::Easy => "easy",
            Level::Medium => "medium",
            Level::Hard => "hard",
        }
    }

    /// (fewest worlds, most worlds, the turn played on, the opponent's turn simulated, first actions kept: 0 = all)
    fn search(self) -> (usize, usize, bool, bool, usize) {
        match self {
            Level::Easy => (1, 1, false, false, 8),
            Level::Medium => (2, 3, true, false, 10),
            Level::Hard => (4, 10, true, true, 0),
        }
    }

    /// The hard stop for one decision: twice the budget plus 0.2 s.
    pub fn limit(budget: Duration) -> Duration {
        budget * 2 + Duration::from_millis(200)
    }
}

/// What the bot knows besides the view: its own deck list and how to guess the opponent's cards.
pub struct Knowledge<'a> {
    pub lib: &'a Library,
    pub seat: usize,
    /// the 30 cards the bot queued with
    pub my_deck: Vec<String>,
    /// an Arena game: the opponent drafted (weights by draft scores), else a constructed deck
    pub arena: bool,
}

#[derive(Clone, Debug)]
pub struct Candidate {
    pub label: String,
    pub score: f64,
}

#[derive(Clone, Debug)]
pub struct Decision {
    pub action: Action,
    pub label: String,
    pub worlds: usize,
    pub ms: u128,
    /// the best few first actions with their average scores
    pub top: Vec<Candidate>,
}

/// The move for this view, or None when it is not the bot's move.
pub fn decide(view_json: &Value, k: &Knowledge, level: Level, budget: Duration) -> Result<Option<Decision>, String> {
    let t0 = Instant::now();
    let base = view::from_snapshot_in(k.lib.rs, view_json)?;
    let me = k.seat;
    if base.game_over {
        return Ok(None);
    }
    if base.phase == "MULLIGAN" {
        if base.players[me].mulliganed {
            return Ok(None);
        }
        let a = if level == Level::Easy {
            json!({"type": "mulligan", "player": me, "replace": []}).as_object().unwrap().clone()
        } else {
            mulligan(&base, me)
        };
        let label = format!("mulligan: replace {}", a["replace"].as_array().map_or(0, |r| r.len()));
        return Ok(Some(Decision { action: a, label, worlds: 0, ms: t0.elapsed().as_millis(), top: vec![] }));
    }
    let legal = options(&base, me);
    if legal.is_empty() {
        return Ok(None);
    }
    if legal.len() == 1 {
        let a = legal[0].clone();
        return Ok(Some(Decision { label: label(k, &base, &a), action: a, worlds: 0, ms: t0.elapsed().as_millis(), top: vec![] }));
    }
    let deadline = t0 + Level::limit(budget);
    let hidden = hidden_ids(view_json);
    let mut rng = rand::rngs::StdRng::from_entropy();
    let (fewest, most, play_on, reply, keep) = level.search();
    // a quick look (one step) in the first world orders the actions: the time limit then cuts the weak ones
    let first = determinize(&base, view_json, &hidden, k, &mut rng);
    let quick: Vec<f64> = legal.iter().map(|a| score_first(&first, me, a, false, false, deadline)).collect();
    let mut alive: Vec<usize> = (0..legal.len()).collect();
    alive.sort_by(|&x, &y| quick[y].partial_cmp(&quick[x]).unwrap_or(std::cmp::Ordering::Equal).then(x.cmp(&y)));
    if keep > 0 {
        alive.truncate(keep);
    }
    // sequential halving: each world tries every action still in; then the worse half drops out
    let mut sums = vec![0.0f64; legal.len()];
    let mut counts = vec![0usize; legal.len()];
    let mut worlds = 0usize;
    let mut world = Some(first);
    while worlds < most && (worlds < fewest || t0.elapsed() < budget) && Instant::now() < deadline && !alive.is_empty() {
        let w = world.take().unwrap_or_else(|| determinize(&base, view_json, &hidden, k, &mut rng));
        for &i in &alive {
            if Instant::now() >= deadline {
                break;
            }
            sums[i] += score_first(&w, me, &legal[i], play_on, reply, deadline);
            counts[i] += 1;
        }
        worlds += 1;
        alive.retain(|&i| counts[i] > 0);
        let mean = |i: usize| sums[i] / counts[i] as f64;
        alive.sort_by(|&x, &y| mean(y).partial_cmp(&mean(x)).unwrap_or(std::cmp::Ordering::Equal).then(x.cmp(&y)));
        if alive.len() <= 1 {
            break;
        }
        alive.truncate(alive.len().div_ceil(2).max(2));
    }
    // the best average of the last ones in; nothing tried in time: the quick look decides
    let mut order: Vec<usize> = if alive.is_empty() { (0..legal.len()).collect() } else { alive.clone() };
    let mean = |i: usize| if counts[i] > 0 { sums[i] / counts[i] as f64 } else { quick[i] };
    order.sort_by(|&x, &y| mean(y).partial_cmp(&mean(x)).unwrap_or(std::cmp::Ordering::Equal).then(x.cmp(&y)));
    let mut best = order[0];
    if level == Level::Easy && rand::Rng::gen_bool(&mut rng, 0.3) {
        best = order[rand::Rng::gen_range(&mut rng, 0..order.len().min(3))]; // (the easy bot errs)
    }
    let top = order
        .iter()
        .take(6)
        .map(|&i| Candidate { label: label(k, &base, &legal[i]), score: mean(i) })
        .collect();
    Ok(Some(Decision { action: legal[best].clone(), label: label(k, &base, &legal[best]), worlds, ms: t0.elapsed().as_millis(), top }))
}

/// me's actions worth trying: no concede; a minion only to the rightmost slot unless a card whose effect
/// depends on its neighbours (`Ruleset::neighbours`) is on me's board or in me's hand (then where a
/// minion stands may matter: a big one now, Defender of Argus next to it later); plays of identical
/// copies (same card and cost, no enchantments) once.
pub fn options(g: &Game, me: usize) -> Vec<Action> {
    let p = &g.players[me];
    let places = p.board.iter().chain(p.hand.iter()).any(|&e| g.rs.neighbours.contains(&g.e(e).card_id));
    let last = p.board.len() as i64;
    let mut seen = HashSet::new();
    let num = |a: &Action, f: &str| a.get(f).and_then(Value::as_i64).unwrap_or(-1);
    g.legal_actions()
        .into_iter()
        .filter(|a| num(a, "player") == me as i64 && a["type"] != "concede")
        .filter(|a| {
            if a["type"] != "play" {
                return true;
            }
            let pos = num(a, "pos");
            if pos >= 0 && pos != last && !places {
                return false;
            }
            let e = g.e(num(a, "entity"));
            !e.enchantments.is_empty()
                || seen.insert((e.card_id.clone(), g.cost(e.id), num(a, "target"), pos, num(a, "choice")))
        })
        .collect()
}

/// Entities the view hides: its "card": "" ones (the opponent's hand and secrets) and the ids it
/// leaves out (both decks).
fn hidden_ids(v: &Value) -> HashSet<i64> {
    let ents = v["entities"].as_object();
    let next = v["next_id"].as_i64().unwrap_or(1);
    (1..next).filter(|id| ents.and_then(|e| e.get(&id.to_string())).is_none_or(|d| d["card"] == "")).collect()
}

/// One world: the hidden cards made plausible, a new random seed.
fn determinize(base: &Game, view_json: &Value, hidden: &HashSet<i64>, k: &Knowledge, rng: &mut impl rand::Rng) -> Game {
    let mut g = base.clone_state();
    g.rng = Rng::new(rng.gen());
    let rs = k.lib.rs;
    let me = k.seat;
    let opp = 1 - me;
    // cards seen per side (each copy once): what is left of a deck is what was not seen yet
    let mut seen: [HashMap<String, i64>; 2] = [HashMap::new(), HashMap::new()];
    if let Some(ents) = view_json["entities"].as_object() {
        for d in ents.values() {
            let c = d["card"].as_str().unwrap_or_default();
            let ctrl = d["ctrl"].as_i64().unwrap_or(0).clamp(0, 1) as usize;
            if !c.is_empty() && c.starts_with("VAN_") {
                *seen[ctrl].entry(c.to_string()).or_default() += 1;
            }
        }
    }
    // the own deck: the list minus what was seen, shuffled
    let mut left: Vec<String> = vec![];
    let mut counts: HashMap<&str, i64> = HashMap::new();
    for c in &k.my_deck {
        *counts.entry(c.as_str()).or_default() += 1;
    }
    for (c, n) in counts {
        let s = seen[me].get(c).copied().unwrap_or(0);
        for _ in 0..(n - s).max(0) {
            left.push(c.to_string());
        }
    }
    left.shuffle(rng);
    let opp_class = class_of(rs, &g.e(g.players[opp].hero).card_id);
    let my_class = class_of(rs, &g.e(g.players[me].hero).card_id);
    let pools = if k.arena { &k.lib.arena_pools } else { &k.lib.ladder_pools };
    let empty = Pool::default();
    let opp_pool = pools.get(&opp_class).unwrap_or(&empty);
    let my_pool = pools.get(&my_class).unwrap_or(&empty);
    let secret_pool = Pool::from(opp_pool.cards.iter().filter(|(c, _)| rs.card(c).trap).cloned().collect::<Vec<_>>());
    let mut used: HashMap<String, i64> = seen[opp].clone();
    let mut pick_opp = |rng: &mut dyn rand::RngCore, only_secrets: bool| -> Option<String> {
        let full = |c: &str| {
            let max = if rs.card(c).rarity == "LEGENDARY" { 1 } else { 2 };
            used.get(c).copied().unwrap_or(0) >= max
        };
        let pool = if only_secrets { &secret_pool } else { opp_pool };
        let c = pool.sample(&mut RngWrap(rng), full)?;
        *used.entry(c.clone()).or_default() += 1;
        Some(c)
    };
    for side in [me, opp] {
        let (hand, deck, secs) = (g.players[side].hand.clone(), g.players[side].deck.clone(), g.players[side].secrets.clone());
        for (ids, zone_secret) in [(hand, false), (deck, false), (secs, true)] {
            for id in ids.into_iter().filter(|id| hidden.contains(id)) {
                let card = if side == me {
                    left.pop().or_else(|| my_pool.sample(&mut RngWrap(rng), |_| false))
                } else {
                    pick_opp(rng, zone_secret).or_else(|| pick_opp(rng, false))
                };
                if let Some(c) = card.filter(|c| rs.has(c)) {
                    let old = g.e(id);
                    let (zone, order) = (old.zone, old.play_order);
                    let mut e = Entity::new(id, rs.card(&c), side);
                    e.zone = zone;
                    e.play_order = order;
                    *g.em(id) = e;
                }
            }
        }
    }
    g.update_auras();
    g
}

impl From<Vec<(String, f64)>> for Pool {
    fn from(v: Vec<(String, f64)>) -> Pool {
        let mut p = Pool::default();
        for (c, w) in v {
            p.add(&c, w);
        }
        p
    }
}

/// A `&mut dyn RngCore` as a sized Rng.
struct RngWrap<'a>(&'a mut dyn rand::RngCore);
impl rand::RngCore for RngWrap<'_> {
    fn next_u32(&mut self) -> u32 {
        self.0.next_u32()
    }
    fn next_u64(&mut self) -> u64 {
        self.0.next_u64()
    }
    fn fill_bytes(&mut self, d: &mut [u8]) {
        self.0.fill_bytes(d)
    }
    fn try_fill_bytes(&mut self, d: &mut [u8]) -> Result<(), rand::Error> {
        self.0.try_fill_bytes(d)
    }
}

/// A first action in one world: (play_on) the turn played on greedily, (reply) then the opponent's
/// turn, then the score.
fn score_first(w: &Game, me: usize, a: &Action, play_on: bool, reply: bool, deadline: Instant) -> f64 {
    let mut g = w.clone_state();
    if !g.apply(&Value::Object(a.clone())).ok {
        return -WIN; // (not legal in this world: should not happen, its cards are the same)
    }
    if play_on && a["type"] != "end_turn" {
        finish_turn(&mut g, me, deadline);
    }
    if reply {
        if !g.game_over && g.current == me && g.phase == "PLAY" {
            g.apply(&json!({"type": "end_turn", "player": me}));
        }
        opponent_turn(&mut g, me, deadline);
    }
    eval(&g, me)
}

/// The rest of the bot's turn: the best action by the evaluation while it beats ending the turn
/// (until the time limit).
fn finish_turn(g: &mut Game, me: usize, deadline: Instant) {
    for _ in 0..25 {
        if g.game_over || g.current != me || g.phase != "PLAY" || Instant::now() >= deadline {
            break;
        }
        let here = eval(g, me);
        let mut best: Option<(Action, f64)> = None;
        for a in options(g, me) {
            if a["type"] == "end_turn" {
                continue;
            }
            let mut c = g.clone_state();
            if !c.apply(&Value::Object(a.clone())).ok {
                continue;
            }
            let s = eval(&c, me);
            if best.as_ref().is_none_or(|b| s > b.1) {
                best = Some((a, s));
            }
        }
        match best {
            Some((a, s)) if s > here + 0.05 => {
                g.apply(&Value::Object(a));
            }
            _ => break,
        }
    }
    if !g.game_over && g.current == me && g.phase == "PLAY" {
        g.apply(&json!({"type": "end_turn", "player": me}));
    }
}

/// The opponent's turn in this world, played by the engine's bot (greedy, it sees this world).
fn opponent_turn(g: &mut Game, me: usize, deadline: Instant) {
    let opp = 1 - me;
    for _ in 0..30 {
        if g.game_over || g.current != opp || Instant::now() >= deadline {
            return;
        }
        if let Some(p) = &g.pending {
            if p.player != opp {
                return;
            }
        }
        match bot::choose(g, opp) {
            Some(a) => {
                if !g.apply(&Value::Object(a)).ok {
                    return;
                }
            }
            None => return,
        }
    }
}

/// The position for player `me`: own side minus the opponent's; a finished game is ±WIN.
pub fn eval(g: &Game, me: usize) -> f64 {
    if g.game_over {
        return if g.winner == me as i64 { WIN } else if g.winner == -1 { 0.0 } else { -WIN };
    }
    side(g, me, true) - side(g, 1 - me, false)
}

fn side(g: &Game, p: usize, own: bool) -> f64 {
    let n = g.n();
    let pl = &g.players[p];
    let hero = g.e(pl.hero);
    let life = (hero.health() + hero.tag(n.armor)) as f64;
    // each point of life counts more when little is left
    let mut v = life - 0.12 * (15.0 - life).max(0.0).powi(2);
    for &m in &pl.board {
        let e = g.e(m);
        let (a, h) = (e.atk() as f64, e.health() as f64);
        let mut mv = 1.0 + 1.5 * a + h;
        if e.has(n.guard) {
            mv += 1.5;
        }
        if e.has(n.barrier) {
            mv += a + 1.0;
        }
        if e.has(n.double_attack) {
            mv += 0.8 * a;
        }
        if e.has(n.stealth) {
            mv += 1.0;
        }
        if e.has(n.frozen) {
            mv -= 0.7 * a;
        }
        if e.has(n.cant_attack) {
            mv -= 0.8 * a;
        }
        mv += 1.5 * e.spell_power(n.spell_power) as f64;
        v += mv;
    }
    if let Some(w) = pl.weapon {
        let w = g.e(w);
        v += 0.75 * w.atk() as f64 * w.tag(n.durability).max(0) as f64;
    }
    let hand = pl.hand.len() as f64;
    v += 2.2 * hand.min(8.0) + 0.5 * (hand - 8.0).max(0.0);
    if own {
        v += 3.0 * pl.secrets.len() as f64;
    } else {
        v += 2.5 * pl.secrets.len() as f64;
    }
    if pl.deck.is_empty() {
        v -= (pl.fatigue + 1) as f64;
    }
    v
}

/// The opening hand: keep the cheap cards (and the Coin), replace those costing 4 or more; a 3 stays
/// only next to a cheaper card.
fn mulligan(g: &Game, me: usize) -> Action {
    let hand = &g.players[me].hand;
    let cheap = hand.iter().any(|&e| g.cost(e) <= 2);
    let mut replace: Vec<i64> = hand.iter().copied().filter(|&e| g.cost(e) >= 4 || (g.cost(e) == 3 && !cheap)).collect();
    replace.sort();
    json!({"type": "mulligan", "player": me, "replace": replace}).as_object().unwrap().clone()
}

/// An action in words, with card names.
pub fn label(k: &Knowledge, g: &Game, a: &Action) -> String {
    let name = |id: Option<i64>| -> String {
        match id {
            Some(id) if id >= 1 && (id as usize) <= g.entities.len() => {
                let e = g.e(id);
                if e.is_champion() {
                    if e.controller == k.seat { "own hero".into() } else { "enemy hero".into() }
                } else {
                    k.lib.name(&e.card_id)
                }
            }
            _ => "?".into(),
        }
    };
    let get = |f: &str| a.get(f).and_then(Value::as_i64).filter(|&x| x > 0);
    match a["type"].as_str().unwrap_or("") {
        "end_turn" => "end turn".into(),
        "attack" => format!("{} → {}", name(get("attacker")), name(get("defender"))),
        "hero_power" => match get("target") {
            Some(t) => format!("hero power → {}", name(Some(t))),
            None => "hero power".into(),
        },
        "play" => match get("target") {
            Some(t) => format!("{} → {}", name(get("entity")), name(Some(t))),
            None => name(get("entity")),
        },
        "choose" => format!("choose: {}", name(get("option"))),
        "mulligan" => "mulligan".into(),
        t => t.to_string(),
    }
}
