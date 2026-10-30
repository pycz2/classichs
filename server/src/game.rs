//! An authoritative game: the server holds the only game state (the rules engine,
//! `classichs-engine`), applies the players' actions and sends each player its own view.
//! Protocol: docs/superpowers/specs/2026-10-15-thin-client-design.md, "Server games".

use crate::db::{self, DbError, DbResult, Standing};
use crate::entity::{arena, game as played};
use crate::events::Event;
use crate::packs::{self, GameRules};
use crate::ranked::{self, Mode};
use crate::{presence, AppRef, LiveGame, Timers};
use classichs_engine::api::{events_for, snapshot};
use classichs_engine::deck::Deck;
use classichs_engine::state::Ev as Events;
use classichs_engine::Game;
use rand::Rng;
use sea_orm::{ActiveModelTrait, ConnectionTrait, EntityTrait, Set, TransactionTrait, Unchanged};
use serde_json::{json, Value};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;

pub enum Ev {
    /// An action from player p.
    Act(usize, Value),
    Emote(usize, String),
    Intent(usize, Value),
    /// Player p's connection closed.
    Gone(usize),
    /// Player p logged in again.
    Back(usize),
}

const INTENT_MAX: usize = 1024;
/// Refused actions of one player before the game ends (reason `illegal`).
const STRIKES: usize = 3;
pub const DOES_NOT_ADD_UP: &str = "Something does not add up: your game and the server's differ. Nobody is banned.";

struct Ctx {
    app: AppRef,
    id: String,
    mode: Mode,
    rules: Arc<GameRules>,
    /// The game clocks: the pack's, or the app's for every game (tests).
    timers: Timers,
    ids: [i64; 2],
    names: [String; 2],
    started: i64,
    /// The `match` message for each player (sent again on a rejoin).
    hello: [Value; 2],
}

/// Starts a game between two players ([account, deck]) in a pack; the seats are drawn at random.
pub async fn start(app: AppRef, mode: Mode, rules: Arc<GameRules>, players: [(i64, Value); 2]) {
    let ids = [players[0].0, players[1].0];
    begin(app.clone(), mode, rules, players).await;
    for id in ids {
        presence(&app, id).await;
    }
}

async fn begin(app: AppRef, mode: Mode, rules: Arc<GameRules>, mut players: [(i64, Value); 2]) {
    if rand::thread_rng().gen_bool(0.5) {
        players.swap(0, 1);
    }
    let ids = [players[0].0, players[1].0];
    let fail = |app: &AppRef, why: &str| {
        let hub = app.hub();
        for id in ids {
            hub.send(id, &json!({"t": "error", "code": "queue", "text": why}));
        }
    };
    {
        let hub = app.hub();
        if ids.iter().any(|id| hub.in_game.contains_key(id) || !hub.conns.contains_key(id)) {
            drop(hub);
            return fail(&app, "The opponent is gone");
        }
    }
    let (a0, a1) = (db::account_by_id(&app.db, ids[0]).await, db::account_by_id(&app.db, ids[1]).await);
    let (Ok(Some(a0)), Ok(Some(a1))) = (a0, a1) else { return fail(&app, "No such account") };
    let id = format!("{:016x}", rand::thread_rng().gen::<u64>());
    let seed: u32 = rand::thread_rng().gen();
    // The decks were checked when queued or invited; a bad one here is a server bug.
    let rs = rules.rs;
    let decks: Vec<Deck> = players.iter().filter_map(|p| Deck::from_value_in(rs, &p.1)).filter(|d| d.validate_in(rs).is_empty()).collect();
    let game = match decks.as_slice() {
        [d0, d1] => catch_unwind(|| Game::new_in(rs, &d0.hero, &d0.cards, &d1.hero, &d1.cards, seed as i64, -1, true)).ok(),
        _ => None,
    };
    let Some(game) = game else {
        app.event(Event::new("error", format!("The game of {} and {} could not start", a0.name, a1.name)).game(&id));
        return fail(&app, "The game could not start");
    };
    let accs = [a0, a1];
    let hello: [Value; 2] = std::array::from_fn(|p| {
        let o = &accs[1 - p];
        json!({"t": "match", "game": id, "mode": mode, "opponent": {"user": o.name, "tag": o.tag}, "you": p, "pack": rules.rules_hash})
    });
    let (tx, rx) = mpsc::unbounded_channel();
    let names = [accs[0].name.clone(), accs[1].name.clone()];
    {
        let mut hub = app.hub();
        if ids.iter().any(|id| hub.in_game.contains_key(id)) {
            drop(hub);
            return fail(&app, "Already in a game");
        }
        for (p, a) in ids.iter().enumerate() {
            hub.queue.remove(a);
            hub.in_game.insert(*a, (id.clone(), p));
            hub.send(*a, &hello[p]);
        }
        hub.games.insert(id.clone(), LiveGame {
            tx: tx.clone(), mode, pack: rules.rules_hash.clone(), pack_name: packs::short_name(&rules), ids, names: names.clone(), started: ranked::now(), turn: game.turn,
            current: game.current as i64, actions: 0,
        });
        for (p, a) in ids.iter().enumerate() {
            if !hub.conns.contains_key(a) {
                let _ = tx.send(Ev::Gone(p));
            }
        }
    }
    let pack_name = packs::short_name(&rules);
    tracing::info!("game {id} ({}, {pack_name}) {} vs {}", mode.as_str(), names[0], names[1]);
    let heroes = [players[0].1["hero"].clone(), players[1].1["hero"].clone()];
    app.event(
        Event::new("match", format!("{} vs {} ({}, {pack_name})", names[0], names[1], mode.as_str()))
            .user(ids[0], &names[0])
            .other(&names[1])
            .game(&id)
            .data(json!({"mode": mode, "seed": seed, "players": names, "heroes": heroes, "pack": rules.rules_hash, "pack_id": rules.id,
                         "pack_name": pack_name})),
    );
    let timers = app.timers.unwrap_or(rules.timers);
    let ctx = Ctx { app, id, mode, rules, timers, ids, names, started: ranked::now(), hello };
    tokio::spawn(run(ctx, game, rx));
}

/// The end of a game: (winner, reason); winner −1 = nobody.
type End = (i64, &'static str);

/// The turn clock: a new deadline whenever the phase, the turn or the player to move changes.
struct Clock {
    key: (&'static str, i64, usize),
    at: Instant,
}

impl Clock {
    fn update(&mut self, g: &Game, t: &crate::Timers) {
        let key = (g.phase, g.turn, g.current);
        if key != self.key {
            self.key = key;
            self.at = Instant::now() + if g.phase == "MULLIGAN" { t.mulligan } else { t.turn };
        }
    }

    /// Seconds left before the deadline the players see (rounded up).
    fn left(&self) -> u64 {
        self.at.saturating_duration_since(Instant::now()).as_millis().div_ceil(1000) as u64
    }
}

/// What a player gets after the start and after every applied action.
pub fn state_msg(game: &str, g: &Game, events: &[Events], p: usize, deadline: u64) -> Value {
    let v = p as i64;
    json!({"t": "state", "game": game, "view": snapshot(g, v), "events": events_for(g, events, v),
           "result": {"over": g.game_over, "winner": g.winner, "turn": g.turn, "current": g.current, "phase": g.phase,
                      "deadline": if g.game_over { 0 } else { deadline }}})
}

enum Step {
    Done,
    Refused(String),
    Crashed,
}

impl Ctx {
    /// An event of this game by player p.
    fn ev(&self, p: usize, kind: &'static str, text: String) -> Event {
        Event::new(kind, text).user(self.ids[p], &self.names[p]).other(&self.names[1 - p]).game(&self.id)
    }

    fn send(&self, p: usize, m: &Value) {
        self.app.hub().send(self.ids[p], m);
    }

    fn states(&self, g: &Game, events: &[Events], clock: &Clock) {
        let left = clock.left();
        for p in 0..2 {
            self.send(p, &state_msg(&self.id, g, events, p, left));
        }
    }

    /// Applies player p's action: on success logs it and sends both players their state.
    // ponytail: the engine runs on the async worker (about 0.5 ms an action with the hash and
    // both views); move it to spawn_blocking if a slow card ever stalls other tasks.
    fn step(&self, g: &mut Game, clock: &mut Clock, p: usize, a: &Value, timeout: bool) -> Step {
        let mut text = action_text(&self.names[p], a, g);
        let r = match catch_unwind(AssertUnwindSafe(|| g.apply(a))) {
            Ok(r) => r,
            Err(_) => {
                tracing::error!("game {}: the engine panicked on {a}", self.id);
                self.app.event(self.ev(p, "error", format!("The rules engine failed on {text}")).data(json!({"action": a})));
                return Step::Crashed;
            }
        };
        if !r.ok {
            return Step::Refused(r.error);
        }
        let events = r.events();
        clock.update(g, &self.timers);
        if let Some(lg) = self.app.hub().games.get_mut(&self.id) {
            lg.turn = g.turn;
            lg.current = g.current as i64;
            lg.actions += 1;
        }
        if timeout {
            text.push_str(" (time ran out)");
        }
        self.app.event(self.ev(p, "game_action", text).data(json!({
            "p": p, "action": a, "turn": g.turn, "current": g.current, "phase": g.phase, "hash": g.state_hash(),
            "over": g.game_over, "timeout": timeout, "events": events})));
        self.states(g, &events, clock);
        Step::Done
    }

    /// The moves the server plays when time runs out; Some = the game ends.
    fn timeout(&self, g: &mut Game, clock: &mut Clock) -> Option<End> {
        let key = clock.key;
        let mut moves: Vec<(usize, Value)> = vec![];
        if g.phase == "MULLIGAN" {
            moves.extend((0..2).filter(|&p| !g.players[p].mulliganed).map(|p| (p, json!({"type": "mulligan", "player": p, "replace": []}))));
        } else {
            if let Some(c) = g.legal_actions().into_iter().find(|a| a["type"] == "choose") {
                let p = c["player"].as_u64().unwrap_or(0) as usize;
                moves.push((p, Value::Object(c)));
            }
            moves.push((g.current, json!({"type": "end_turn", "player": g.current})));
        }
        for (p, a) in moves {
            if g.game_over {
                break;
            }
            match self.step(g, clock, p, &a, true) {
                Step::Done => {}
                Step::Refused(e) => tracing::warn!("game {}: timeout move {a} refused: {e}", self.id),
                Step::Crashed => return Some((-1, "aborted")),
            }
        }
        if g.game_over {
            return Some((g.winner, "over"));
        }
        if clock.key == key {
            clock.at = Instant::now() + self.timers.turn; // never spin on a move that does not take
        }
        None
    }
}

/// Whether player p has a move now: a mulligan not made yet, a choice to make, or the turn.
fn moves(g: &Game, p: usize) -> bool {
    if g.game_over {
        return false;
    }
    if g.phase == "MULLIGAN" {
        return !g.players[p].mulliganed;
    }
    match &g.pending {
        Some(c) => c.player == p,
        None => g.current == p,
    }
}

/// What ended a game early: who, and what they sent.
struct Cause {
    p: usize,
    message: Option<Value>,
    refused: Vec<Value>,
}

async fn run(ctx: Ctx, mut g: Game, mut rx: mpsc::UnboundedReceiver<Ev>) {
    let t = ctx.timers;
    let mut clock = Clock { key: ("", -1, 9), at: Instant::now() };
    clock.update(&g, &t);
    let opening: Vec<Events> =
        g.history[0].events();
    ctx.app.event(ctx.ev(g.current, "game_start", format!("The game started: {} goes first", ctx.names[g.current]))
        .data(json!({"first": g.current, "turn": g.turn, "hash": g.state_hash(), "events": opening})));
    ctx.states(&g, &opening, &clock);
    let mut gone: [Option<Instant>; 2] = [None; 2];
    let mut refused: [Vec<Value>; 2] = Default::default();
    let mut cause: Option<Cause> = None;
    let end = loop {
        let away = gone.iter().flatten().min().copied();
        let ev = tokio::select! {
            ev = rx.recv() => ev,
            _ = tokio::time::sleep_until(away.unwrap_or_else(|| Instant::now() + Duration::from_secs(3600))), if away.is_some() => {
                let p = if gone[0] == away { 0 } else { 1 };
                cause = Some(Cause { p, message: None, refused: vec![] });
                break (1 - p as i64, "disconnect");
            }
            _ = tokio::time::sleep_until(clock.at + t.slack) => {
                match ctx.timeout(&mut g, &mut clock) {
                    Some(end) => break end,
                    None => continue,
                }
            }
        };
        match ev {
            None => break (-1, "aborted"),
            Some(Ev::Gone(p)) => {
                gone[p] = Some(Instant::now() + t.away);
                ctx.app.event(ctx.ev(p, "game_left", format!("{} dropped out of the game", ctx.names[p])));
            }
            Some(Ev::Back(p)) => {
                gone[p] = None;
                ctx.app.event(ctx.ev(p, "game_back", format!("{} is back in the game", ctx.names[p])));
                let mut m = ctx.hello[p].clone();
                m["rejoin"] = json!(true);
                ctx.send(p, &m);
                ctx.send(p, &state_msg(&ctx.id, &g, &[], p, clock.left()));
            }
            Some(Ev::Act(p, a)) if !moves(&g, p) && a["type"] != "concede" => {
                // not p's move now (conceding always is): most often a move sent just before the clock ended p's turn
                // (it crossed the timeout); refused, but no strike: nobody's game differs
                ctx.send(p, &json!({"t": "act_error", "game": ctx.id, "error": "not your move now (the turn may have ended)", "late": true}));
            }
            Some(Ev::Act(p, a)) => {
                let r = if a["player"].as_f64() != Some(p as f64) {
                    Step::Refused(format!("not your action: you are player {p}"))
                } else {
                    ctx.step(&mut g, &mut clock, p, &a, false)
                };
                match r {
                    Step::Done if g.game_over => break (g.winner, "over"),
                    Step::Done => {}
                    Step::Crashed => break (-1, "aborted"),
                    Step::Refused(error) => {
                        ctx.send(p, &json!({"t": "act_error", "game": ctx.id, "error": error}));
                        refused[p].push(json!({"action": a, "error": error}));
                        if refused[p].len() >= STRIKES {
                            cause = Some(Cause { p, message: Some(a), refused: std::mem::take(&mut refused[p]) });
                            break (1 - p as i64, "illegal");
                        }
                    }
                }
            }
            Some(Ev::Emote(p, id)) => {
                if id.len() <= 32 {
                    ctx.send(1 - p, &json!({"t": "emote", "game": ctx.id, "id": id, "from": p}));
                }
            }
            Some(Ev::Intent(p, i)) => {
                if i.to_string().len() <= INTENT_MAX {
                    ctx.send(1 - p, &json!({"t": "intent", "game": ctx.id, "i": i, "from": p}));
                }
            }
        }
    };
    finish(&ctx, &g, end.0, end.1, cause).await;
}

/// "alice: attack VAN_CS2_120 #12 → HERO_08 #1".
fn action_text(name: &str, a: &Value, g: &Game) -> String {
    let t = a["type"].as_str().unwrap_or("?");
    let card = |k: &str| {
        let id = a[k].as_f64().filter(|x| *x >= 0.0)? as i64;
        Some(g.ent(id).map_or(format!("#{id}"), |e| format!("{} #{id}", e.card_id)))
    };
    let pair = |x: &str, y: &str| [card(x), card(y)].into_iter().flatten().collect::<Vec<_>>().join(" → ");
    let detail = match t {
        "play" => pair("entity", "target"),
        "attack" => pair("attacker", "defender"),
        "hero_power" => card("target").map(|x| format!("→ {x}")).unwrap_or_default(),
        "mulligan" => format!("replaces {}", a["replace"].as_array().map_or(0, |r| r.len())),
        "choose" => card("option").unwrap_or_default(),
        _ => String::new(),
    };
    if detail.is_empty() { format!("{name}: {t}") } else { format!("{name}: {t} {detail}") }
}

async fn finish(ctx: &Ctx, g: &Game, winner: i64, reason: &'static str, cause: Option<Cause>) {
    {
        let mut hub = ctx.app.hub();
        hub.games.remove(&ctx.id);
        for a in ctx.ids {
            hub.in_game.remove(&a);
        }
    }
    let saved = async {
        let tx = ctx.app.db.begin().await?;
        let extra = apply_results(&tx, &ctx.rules, ctx.mode, ctx.ids, winner).await?;
        let row = played::ActiveModel {
            id: Set(ctx.id.clone()),
            mode: Set(ctx.mode.as_str().into()),
            p0: Set(Some(ctx.ids[0])),
            p1: Set(Some(ctx.ids[1])),
            started: Set(ctx.started),
            ended: Set(ranked::now()),
            winner: Set(winner),
            reason: Set(reason.into()),
            pack: Set(ctx.rules.rules_hash.clone()),
        };
        played::Entity::insert(row).exec_without_returning(&tx).await?;
        tx.commit().await?;
        Ok::<_, DbError>(extra)
    };
    let extra = saved.await.unwrap_or_else(|e| {
        tracing::error!("game {}: results not saved: {e}", ctx.id);
        ctx.app.event(Event::new("error", format!("The results of game {} were not saved: {e}", ctx.id)).game(&ctx.id));
        [json!({}), json!({})]
    });
    tracing::info!("game {} over: winner {winner} ({reason})", ctx.id);
    let text = match winner {
        0 | 1 => format!("{} beat {} ({}, {reason})", ctx.names[winner as usize], ctx.names[1 - winner as usize], ctx.mode.as_str()),
        _ => format!("{} and {}: no winner ({}, {reason})", ctx.names[0], ctx.names[1], ctx.mode.as_str()),
    };
    let w = winner.clamp(0, 1) as usize;
    let mut data = json!({"winner": winner, "reason": reason, "mode": ctx.mode, "pack": ctx.rules.rules_hash, "players": ctx.names, "results": extra,
                          "duration": ranked::now() - ctx.started, "turn": g.turn, "hash": g.state_hash()});
    if let Some(c) = &cause {
        data["by"] = json!(ctx.names[c.p]);
        data["message"] = json!(c.message);
        if !c.refused.is_empty() {
            data["refused"] = json!(c.refused);
        }
    }
    ctx.app.event(ctx.ev(w, "game_end", text).data(data));
    {
        let hub = ctx.app.hub();
        for (p, a) in ctx.ids.iter().enumerate() {
            let result = if winner < 0 { "draw" } else if winner == p as i64 { "win" } else { "loss" };
            let mut m = json!({"t": "game_over", "game": ctx.id, "result": result, "reason": reason});
            if reason == "illegal" {
                m["message"] = json!(DOES_NOT_ADD_UP);
            }
            if let Some(o) = extra[p].as_object() {
                for (k, v) in o {
                    m[k] = v.clone();
                }
            }
            hub.send(*a, &m);
        }
    }
    // Friends see both players back online (or offline).
    for id in ctx.ids {
        presence(&ctx.app, id).await;
    }
}

pub async fn rank_json(c: &impl ConnectionTrait, s: &Standing) -> DbResult<Value> {
    Ok(json!({"rank": s.rank, "stars": s.stars, "legend": db::legend_number(c, s).await?, "streak": s.streak}))
}

/// MMR, ranked stars (both in the game's pack) and the Arena record; returns what each
/// player's game_over adds.
async fn apply_results(c: &impl ConnectionTrait, rules: &GameRules, mode: Mode, ids: [i64; 2], winner: i64) -> DbResult<[Value; 2]> {
    if winner < 0 || mode == Mode::Friendly {
        return Ok([json!({}), json!({})]);
    }
    let w = winner as usize;
    let l = &rules.ladder;
    match mode {
        Mode::Casual => {
            let (mut a, mut b) = (db::standing(c, ids[w], &rules.id, l).await?, db::standing(c, ids[1 - w], &rules.id, l).await?);
            (a.casual_mmr, b.casual_mmr) = ranked::elo(a.casual_mmr, b.casual_mmr, true);
            db::save_standing(c, &a).await?;
            db::save_standing(c, &b).await?;
            Ok([json!({}), json!({})])
        }
        Mode::Ranked => {
            let mut st = [db::standing(c, ids[0], &rules.id, l).await?, db::standing(c, ids[1], &rules.id, l).await?];
            (st[w].ranked_mmr, st[1 - w].ranked_mmr) = ranked::elo(st[w].ranked_mmr, st[1 - w].ranked_mmr, true);
            for (p, s) in st.iter_mut().enumerate() {
                let mut r = s.rank();
                if p == w { r.win(l) } else { r.lose(l) }
                (s.rank, s.stars, s.streak) = (r.rank, r.stars, r.streak);
                db::save_standing(c, s).await?;
            }
            Ok([json!({"rank": rank_json(c, &st[0]).await?}), json!({"rank": rank_json(c, &st[1]).await?})])
        }
        Mode::Arena => {
            let mut out = [json!({}), json!({})];
            for (p, id) in ids.iter().enumerate() {
                let Some(run) = arena::Entity::find_by_id(*id).one(c).await? else { continue };
                let (wins, losses) = if p == w { (run.wins + 1, run.losses) } else { (run.wins, run.losses + 1) };
                let over = wins >= rules.arena_wins || losses >= rules.arena_losses;
                if over {
                    arena::Entity::delete_by_id(*id).exec(c).await?;
                } else {
                    arena::ActiveModel { account: Unchanged(*id), wins: Set(wins), losses: Set(losses), ..Default::default() }.update(c).await?;
                }
                out[p] = json!({"arena": {"wins": wins, "losses": losses, "over": over}});
            }
            Ok(out)
        }
        Mode::Friendly => unreachable!(),
    }
}
