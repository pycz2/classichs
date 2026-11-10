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
//!
//! Super hard (`super_hard`) searches whole turns instead: a beam over the turn's positions in one world
//! gives plans; the best ones are played in many worlds through the opponent's turn and one more round,
//! and judged by a chance to win learned from Hard's games (`eval_sh`).

use crate::cards::{class_of, Library, Pool};
use classichs_engine::entity::Entity;
use classichs_engine::game::{Act, Action};
use classichs_engine::rng::Rng;
use classichs_engine::state::Game;
use classichs_engine::{bot, view};
use rand::seq::SliceRandom;
use rand::SeedableRng;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use crate::clock;
use std::time::Duration;

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
    /// Its own search (`super_hard`): whole-turn plans, each played in up to 400 worlds through the
    /// opponent's turn and one more round, judged by a learned chance to win. The caller bounds the time
    /// (training: the turn's end less 10 s).
    SuperHard,
}

impl Level {
    pub fn parse(s: &str) -> Option<Level> {
        match s {
            "easy" => Some(Level::Easy),
            "medium" => Some(Level::Medium),
            "hard" => Some(Level::Hard),
            "superhard" => Some(Level::SuperHard),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Level::Easy => "easy",
            Level::Medium => "medium",
            Level::Hard => "hard",
            Level::SuperHard => "superhard",
        }
    }

    /// (fewest worlds, most worlds, the turn played on, the opponent's turn simulated, first actions kept
    /// (0 = all), worlds before the first half drops out)
    fn search(self) -> (usize, usize, bool, bool, usize, usize) {
        match self {
            Level::Easy => (1, 1, false, false, 8, 1),
            Level::Medium => (2, 3, true, false, 10, 1),
            Level::Hard => (4, 10, true, true, 0, 2),
            Level::SuperHard => unreachable!("Super hard searches with super_hard"),
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
    /// the seed of its guesses (the caller's randomness: the browser's WASM has none)
    pub seed: u64,
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
    let t0 = clock::now();
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
        return Ok(Some(Decision { action: a, label, worlds: 0, ms: (clock::now() - t0).as_millis(), top: vec![] }));
    }
    let legal = options(&base, me);
    if legal.is_empty() {
        return Ok(None);
    }
    if legal.len() == 1 {
        let a = legal[0].clone();
        return Ok(Some(Decision { label: label(k, &base, &a), action: a, worlds: 0, ms: (clock::now() - t0).as_millis(), top: vec![] }));
    }
    let deadline = t0 + Level::limit(budget);
    let hidden = hidden_ids(view_json);
    let mut rng = rand::rngs::StdRng::seed_from_u64(k.seed);
    if level == Level::SuperHard {
        return Ok(Some(super_hard(&base, view_json, &hidden, k, &legal, budget, t0, deadline, &mut rng)));
    }
    let (fewest, most, play_on, reply, keep, settle) = level.search();
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
    while worlds < most && (worlds < fewest || clock::now() - t0 < budget) && clock::now() < deadline && !alive.is_empty() {
        let w = world.take().unwrap_or_else(|| determinize(&base, view_json, &hidden, k, &mut rng));
        for &i in &alive {
            if clock::now() >= deadline {
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
        if worlds >= settle {
            alive.truncate(alive.len().div_ceil(2).max(2));
        }
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
    Ok(Some(Decision { action: legal[best].clone(), label: label(k, &base, &legal[best]), worlds, ms: (clock::now() - t0).as_millis(), top }))
}

/// A plan of the bot's turn: its actions from the start, the position after them (in the world it was made in).
struct Plan {
    seq: Vec<Action>,
    g: Game,
    score: f64,
}

/// A cheap fingerprint of a position (two plans that reach it are one).
fn sig(g: &Game) -> u64 {
    use std::hash::{Hash, Hasher};
    let n = g.n();
    let mut h = std::collections::hash_map::DefaultHasher::new();
    (g.current, g.game_over, g.pending.as_ref().map(|p| p.source)).hash(&mut h);
    for p in &g.players {
        (p.mana, &p.hand, &p.board, p.secrets.len(), p.weapon, p.deck.len()).hash(&mut h);
        for &e in p.board.iter().chain([p.hero, p.hero_power].iter()).chain(p.weapon.iter()) {
            let e = g.e(e);
            (e.atk(), e.health(), e.tag(n.armor), e.tag(n.attacks), e.has(n.exhausted), e.has(n.barrier), e.has(n.frozen), e.has(n.used), e.tag(n.durability)).hash(&mut h);
        }
    }
    h.finish()
}

/// Super hard: the whole turn searched as plans (a beam by the evaluation in one world), the best plans then
/// played in many worlds with the opponent's reply (sequential halving); the first action of the best one.
#[allow(clippy::too_many_arguments)]
fn super_hard(base: &Game, view_json: &Value, hidden: &HashSet<i64>, k: &Knowledge, legal: &[Action], budget: Duration,
    t0: Duration, deadline: Duration, rng: &mut rand::rngs::StdRng) -> Decision {
    const BEAM: usize = 24;
    const KEEP: usize = 32;
    // a plain position settles in a few hundred worlds (1 s or 6 s of them played alike against Hard)
    const MOST_WORLDS: usize = 400;
    let me = k.seat;
    // one step of a simulation may take a few ms past a check: the hard stop keeps a margin
    let deadline = deadline.saturating_sub(Duration::from_millis(100));
    let first = determinize(base, view_json, hidden, k, rng);
    // the beam: every position the turn can reach (each once), the best BEAM of each depth expanded
    let mut plans: Vec<Plan> = vec![Plan { seq: vec![], score: eval_sh(&first, me), g: first.clone_state() }];
    let mut seen: HashSet<u64> = HashSet::from([sig(&first)]);
    let mut frontier: Vec<usize> = vec![0];
    for _ in 0..20 {
        if clock::now() >= deadline {
            break;
        }
        let mut next: Vec<Plan> = vec![];
        for &i in &frontier {
            let p = &plans[i];
            if p.g.game_over || p.g.current != me {
                continue;
            }
            for a in options(&p.g, me) {
                if a["type"] == "end_turn" {
                    continue;
                }
                let mut c = p.g.clone_state();
                if !c.apply(&Value::Object(a.clone())).ok || !seen.insert(sig(&c)) {
                    continue;
                }
                let mut seq = p.seq.clone();
                seq.push(a);
                next.push(Plan { seq, score: eval_sh(&c, me), g: c });
            }
        }
        if next.is_empty() {
            break;
        }
        next.sort_by(|x, y| y.score.partial_cmp(&x.score).unwrap_or(std::cmp::Ordering::Equal));
        let start = plans.len();
        frontier = (start..start + next.len().min(BEAM)).collect();
        plans.extend(next);
    }
    // the plans to try: the best KEEP by the evaluation, and the best of each first action
    let mut order: Vec<usize> = (0..plans.len()).collect();
    order.sort_by(|&x, &y| plans[y].score.partial_cmp(&plans[x].score).unwrap_or(std::cmp::Ordering::Equal).then(x.cmp(&y)));
    let mut alive: Vec<usize> = order.iter().copied().take(KEEP).collect();
    let mut firsts: HashSet<String> = alive.iter().map(|&i| first_key(&plans[i].seq)).collect();
    for &i in &order {
        if firsts.insert(first_key(&plans[i].seq)) {
            alive.push(i);
        }
    }
    let mut sums = vec![0.0f64; plans.len()];
    let mut counts = vec![0usize; plans.len()];
    let mut worlds = 0usize;
    let mut world = Some(first);
    while worlds < MOST_WORLDS && (worlds < 2 || clock::now() - t0 < budget) && clock::now() < deadline && alive.len() > 1 {
        let w = world.take().unwrap_or_else(|| determinize(base, view_json, hidden, k, rng));
        for &i in &alive {
            if clock::now() >= deadline || (worlds >= 2 && clock::now() - t0 >= budget) {
                break;
            }
            sums[i] += play_plan(&w, me, &plans[i].seq, deadline);
            counts[i] += 1;
        }
        worlds += 1;
        alive.retain(|&i| counts[i] > 0);
        let mean = |i: usize| sums[i] / counts[i] as f64;
        alive.sort_by(|&x, &y| mean(y).partial_cmp(&mean(x)).unwrap_or(std::cmp::Ordering::Equal).then(x.cmp(&y)));
        if worlds >= 4 {
            let half = alive.len().div_ceil(2).max(2);
            alive.truncate(half);
        }
        // the plans left all start alike: that first action is the move
        if alive.iter().all(|&i| first_key(&plans[i].seq) == first_key(&plans[alive[0]].seq)) {
            alive.truncate(1);
        }
    }
    let mean = |i: usize| if counts[i] > 0 { sums[i] / counts[i] as f64 } else { plans[i].score };
    let best = alive.first().copied().unwrap_or(order[0]);
    let end = json!({"type": "end_turn", "player": me}).as_object().unwrap().clone();
    let act = plans[best].seq.first().cloned().unwrap_or(end);
    // the action as the base position lists it (else the first legal one: should not happen)
    let act = legal.iter().find(|a| Act::from_map(a) == Act::from_map(&act)).cloned().unwrap_or_else(|| legal[0].clone());
    let top = alive.iter().take(6).map(|&i| Candidate { label: label(k, base, plans[i].seq.first().unwrap_or(&act)), score: mean(i) }).collect();
    Decision { label: label(k, base, &act), action: act, worlds, ms: (clock::now() - t0).as_millis(), top }
}

fn first_key(seq: &[Action]) -> String {
    seq.first().map_or("end".into(), |a| Value::Object(a.clone()).to_string())
}

/// A plan in one world: its actions while they are legal (then the turn played on greedily), the opponent's turn,
/// then one more round (the bot's next turn greedily, the opponent's), the score.
fn play_plan(w: &Game, me: usize, seq: &[Action], deadline: Duration) -> f64 {
    let mut g = w.clone_state();
    let mut broke = false;
    for a in seq {
        if g.game_over || !g.apply(&Value::Object(a.clone())).ok {
            broke = true;
            break;
        }
    }
    if broke || g.pending.as_ref().is_some_and(|p| p.player == me) {
        finish_turn(&mut g, me, deadline, eval_sh);
    }
    if !g.game_over && g.current == me && g.phase == "PLAY" {
        g.apply(&json!({"type": "end_turn", "player": me}));
    }
    opponent_turn(&mut g, me, deadline);
    if !g.game_over && g.current == me {
        finish_turn(&mut g, me, deadline, eval_sh);
        opponent_turn(&mut g, me, deadline);
    }
    eval_sh(&g, me)
}

/// me's actions worth trying: no concede; a minion only to the rightmost slot unless a card whose effect
/// depends on its neighbours (`Ruleset::neighbours`) is on me's board or in me's hand (then where a
/// minion stands may matter: a big one now, Defender of Argus next to it later); plays of identical
/// copies (same card and cost, no enchantments) once.
pub fn options(g: &Game, me: usize) -> Vec<Action> {
    let p = &g.players[me];
    let places = p.board.iter().chain(p.hand.iter()).any(|&e| g.rs.neighbours.contains(g.e(e).card_id));
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
            if rs.has(c) && rs.card(c).collectible {
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
fn score_first(w: &Game, me: usize, a: &Action, play_on: bool, reply: bool, deadline: Duration) -> f64 {
    let mut g = w.clone_state();
    if !g.apply(&Value::Object(a.clone())).ok {
        return -WIN; // (not legal in this world: should not happen, its cards are the same)
    }
    if play_on && a["type"] != "end_turn" {
        finish_turn(&mut g, me, deadline, eval);
    }
    if reply {
        if !g.game_over && g.current == me && g.phase == "PLAY" {
            g.apply(&json!({"type": "end_turn", "player": me}));
        }
        opponent_turn(&mut g, me, deadline);
    }
    eval(&g, me)
}

/// The rest of the bot's turn: the best action by the evaluation `ev` while it beats ending the turn
/// (until the time limit).
fn finish_turn(g: &mut Game, me: usize, deadline: Duration, ev: fn(&Game, usize) -> f64) {
    for _ in 0..25 {
        if g.game_over || g.current != me || g.phase != "PLAY" || clock::now() >= deadline {
            break;
        }
        let here = ev(g, me);
        let mut best: Option<(Action, f64)> = None;
        for a in options(g, me) {
            if a["type"] == "end_turn" {
                continue;
            }
            let mut c = g.clone_state();
            if !c.apply(&Value::Object(a.clone())).ok {
                continue;
            }
            let s = ev(&c, me);
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
fn opponent_turn(g: &mut Game, me: usize, deadline: Duration) {
    let opp = 1 - me;
    for _ in 0..30 {
        if g.game_over || g.current != opp || clock::now() >= deadline {
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

/// Super hard's evaluation: the chance to win, from -100 (lost) to 100 (won), by a logistic model of `features`
/// fitted on 2000 Hard-against-Hard games with the library's decks (rust/brain/tests/duel.rs `fit`; 305 288
/// positions, log loss 0.52). An average over worlds is then an expected result, not swamped by ±WIN.
pub fn eval_sh(g: &Game, me: usize) -> f64 {
    if g.game_over {
        return if g.winner == me as i64 { 100.0 } else if g.winner == -1 { 0.0 } else { -100.0 };
    }
    let z: f64 = LEARNED[0] + features(g, me).iter().zip(&LEARNED[1..]).map(|(a, b)| a * b).sum::<f64>();
    100.0 * (2.0 / (1.0 + (-z).exp()) - 1.0)
}

/// The bias, then a weight per feature.
const LEARNED: [f64; FEATURES + 1] = [
    0.36826, 0.87498, -0.78050, -0.02078, 0.18191, 0.32895, 0.42099, -0.05036, 0.34565, 0.13907, 0.10905, 0.29581,
    0.40985, 0.50443, 0.37821, 0.88284, -0.08550, -0.87546, 0.78120, 0.02133, -0.18180, -0.32872, -0.42080, 0.05060,
    -0.34571, -0.13886, -0.10623, -0.29602, -0.41003, -0.50352, -0.38356, -0.88183, 0.09769, -0.69598,
];

pub const FEATURES: usize = 2 * SIDE_FEATURES + 1;
const SIDE_FEATURES: usize = 16;

/// What the learned evaluation looks at: each side's numbers (me first), whose turn it is.
pub fn features(g: &Game, me: usize) -> Vec<f64> {
    let mut f = Vec::with_capacity(FEATURES);
    for p in [me, 1 - me] {
        let n = g.n();
        let pl = &g.players[p];
        let foe = &g.players[1 - p];
        let hero = g.e(pl.hero);
        let life = (hero.health() + hero.tag(n.armor)) as f64;
        let (mut atk, mut hp, mut taunt, mut shield, mut big) = (0.0, 0.0, 0.0, 0.0, 0.0);
        for &m in &pl.board {
            let e = g.e(m);
            let (a, h) = (e.atk() as f64, e.health() as f64);
            if !e.has(n.cant_attack) {
                atk += a * if e.has(n.double_attack) { 2.0 } else { 1.0 };
            }
            hp += h;
            if e.has(n.guard) {
                taunt += h;
            }
            if e.has(n.barrier) {
                shield += 1.0;
            }
            big += (a * h).sqrt();
        }
        let weapon = pl.weapon.map_or(0.0, |w| (g.e(w).atk() * g.e(w).tag(n.durability).max(0)) as f64);
        let wa = pl.weapon.map_or(0.0, |w| g.e(w).atk() as f64);
        let threat: f64 = foe.board.iter().map(|&m| {
            let e = g.e(m);
            if e.has(n.cant_attack) { 0.0 } else { (e.atk() * if e.has(n.double_attack) { 2 } else { 1 }) as f64 }
        }).sum::<f64>() + foe.weapon.map_or(0.0, |w| g.e(w).atk() as f64);
        let guards = pl.board.iter().any(|&m| g.e(m).has(n.guard));
        let hand = pl.hand.len() as f64;
        let cost: f64 = pl.hand.iter().map(|&c| g.cost(c).min(10) as f64).sum();
        f.extend([
            life / 10.0,
            (15.0 - life).max(0.0).powi(2) / 100.0,
            if threat >= life && !guards { 1.0 } else { 0.0 },
            pl.board.len() as f64,
            (atk + wa) / 5.0,
            hp / 5.0,
            taunt / 5.0,
            shield,
            big / 5.0,
            weapon / 5.0,
            hand.min(10.0),
            cost / 10.0,
            pl.max_mana as f64,
            (pl.deck.len() as f64).min(5.0),
            pl.secrets.len() as f64,
            if pl.deck.is_empty() { (pl.fatigue + 1) as f64 } else { 0.0 },
        ]);
    }
    f.push(if g.current == me { 1.0 } else { 0.0 });
    debug_assert_eq!(f.len(), FEATURES);
    f
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
