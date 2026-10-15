//! A refereed game: the server relays the players' NetSession messages and checks
//! every action with the referee before it reaches the other player.

use crate::db::{self, Account, DbError, DbResult};
use crate::entity::{arena, game as played};
use crate::events::Event;
use crate::ranked::{self, Mode};
use crate::{presence, AppRef, LiveGame};
use rand::Rng;
use sea_orm::{ActiveModelTrait, ConnectionTrait, EntityTrait, Set, TransactionTrait, Unchanged};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;

pub enum Ev {
    /// A NetSession message from player p.
    Msg(usize, Value),
    /// Player p's connection closed.
    Gone(usize),
    /// Player p logged in again.
    Back(usize),
}

const INTENT_MAX: usize = 1024;

struct Ctx {
    app: AppRef,
    id: String,
    mode: Mode,
    ids: [i64; 2],
    names: [String; 2],
    decks: [Value; 2],
    seed: u32,
    started: i64,
    /// The `match` message for each player (sent again on a rejoin).
    hello: [Value; 2],
}

/// Starts a game between two players ([account, deck]); the host (player 0) is drawn at random.
pub async fn start(app: AppRef, mode: Mode, players: [(i64, Value); 2]) {
    let ids = [players[0].0, players[1].0];
    begin(app.clone(), mode, players).await;
    for id in ids {
        presence(&app, id).await;
    }
}

async fn begin(app: AppRef, mode: Mode, mut players: [(i64, Value); 2]) {
    if rand::thread_rng().gen_bool(0.5) {
        players.swap(0, 1);
    }
    let ids = [players[0].0, players[1].0];
    let decks = [players[0].1.clone(), players[1].1.clone()];
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
    let r = app.referee.call(json!({"op": "new", "game": id, "seed": seed, "decks": decks})).await;
    if !matches!(&r, Ok(v) if v["ok"] == true) {
        tracing::warn!("referee refused game {id}: {r:?}");
        app.event(Event::new("error", format!("The referee could not start a game of {} and {}: {r:?}", a0.name, a1.name)).game(&id));
        return fail(&app, "The referee could not start the game");
    }
    let accs = [a0, a1];
    let hello: [Value; 2] = std::array::from_fn(|p| {
        let o = &accs[1 - p];
        json!({"t": "match", "game": id, "host": p == 0, "seed": seed, "mode": mode,
               "opponent": {"user": o.name, "tag": o.tag}})
    });
    let (tx, rx) = mpsc::unbounded_channel();
    let busy = {
        let mut hub = app.hub();
        let busy = ids.iter().any(|id| hub.in_game.contains_key(id));
        if !busy {
            register(&mut hub, &id, ids, &hello, &accs, mode, &tx);
        }
        busy
    };
    if busy {
        let _ = app.referee.call(json!({"op": "drop", "game": id})).await;
        return fail(&app, "Already in a game");
    }
    tracing::info!("game {id} ({}) {} vs {}", mode.as_str(), accs[0].name, accs[1].name);
    let names = [accs[0].name.clone(), accs[1].name.clone()];
    app.event(
        Event::new("match", format!("{} vs {} ({})", names[0], names[1], mode.as_str()))
            .user(ids[0], &names[0])
            .other(&names[1])
            .game(&id)
            .data(json!({"mode": mode, "seed": seed, "players": names, "heroes": [decks[0]["hero"], decks[1]["hero"]]})),
    );
    let ctx = Ctx { app, id, mode, ids, names, decks, seed, started: ranked::now(), hello };
    tokio::spawn(run(ctx, rx));
}

fn register(hub: &mut crate::Hub, id: &str, ids: [i64; 2], hello: &[Value; 2], accs: &[Account; 2], mode: Mode, tx: &mpsc::UnboundedSender<Ev>) {
    {
        for (p, a) in ids.iter().enumerate() {
            hub.queue.remove(a);
            hub.in_game.insert(*a, (id.to_string(), p));
            hub.send(*a, &hello[p]);
        }
        hub.games.insert(id.to_string(), LiveGame {
            tx: tx.clone(), mode, ids, names: [accs[0].name.clone(), accs[1].name.clone()],
            started: ranked::now(), turn: 0, current: 0, actions: 0,
        });
        for (p, a) in ids.iter().enumerate() {
            if !hub.conns.contains_key(a) {
                let _ = tx.send(Ev::Gone(p));
            }
        }
    }
}

/// The end of a game: (winner, reason); winner −1 = nobody.
type End = (i64, &'static str);

/// What ended a game early: who, and the message (if a message did).
type Cause = Option<(usize, Option<Value>)>;

struct Play {
    hello: [bool; 2],
    started: bool,
    n: [u64; 2],
    /// hello/start/action messages in order, for a player who rejoins.
    log: Vec<Value>,
}

async fn run(ctx: Ctx, mut rx: mpsc::UnboundedReceiver<Ev>) {
    let mut play = Play { hello: [false; 2], started: false, n: [0; 2], log: vec![] };
    let mut gone: [Option<Instant>; 2] = [None; 2];
    let mut cause: Cause = None;
    let end = loop {
        let deadline = gone.iter().flatten().min().copied();
        let ev = tokio::select! {
            ev = rx.recv() => ev,
            _ = tokio::time::sleep_until(deadline.unwrap_or_else(|| Instant::now() + Duration::from_secs(3600))), if deadline.is_some() => {
                let p = if gone[0] == deadline { 0 } else { 1 };
                cause = Some((p, None));
                break (1 - p as i64, "disconnect");
            }
        };
        match ev {
            None => break (-1, "aborted"),
            Some(Ev::Gone(p)) => {
                gone[p] = Some(Instant::now() + ctx.app.grace);
                ctx.app.event(ctx.ev(p, "game_left", format!("{} dropped out of the game", ctx.names[p])));
            }
            Some(Ev::Back(p)) => {
                gone[p] = None;
                ctx.app.event(ctx.ev(p, "game_back", format!("{} is back in the game", ctx.names[p])));
                let mut m = ctx.hello[p].clone();
                m["rejoin"] = json!(true);
                m["log"] = json!(play.log);
                ctx.app.hub().send(ctx.ids[p], &m);
            }
            Some(Ev::Msg(p, m)) => {
                let copy = m.clone();
                if let Some(end) = relay(&ctx, &mut play, p, m).await {
                    if end.1 != "over" {
                        cause = Some((p, Some(copy)));
                    }
                    break end;
                }
            }
        }
    };
    finish(&ctx, end.0, end.1, cause).await;
}

impl Ctx {
    /// An event of this game by player p.
    fn ev(&self, p: usize, kind: &'static str, text: String) -> Event {
        Event::new(kind, text).user(self.ids[p], &self.names[p]).other(&self.names[1 - p]).game(&self.id)
    }
}

/// One line for an action: "alice: attack 12 → 7".
fn action_text(name: &str, a: &Value) -> String {
    let t = a["type"].as_str().unwrap_or("?");
    let n = |k: &str| a[k].as_i64().map(|x| x.to_string());
    let detail = match t {
        "play" => [n("entity"), n("target").filter(|x| x != "-1")].into_iter().flatten().collect::<Vec<_>>().join(" → "),
        "attack" => [n("attacker"), n("defender")].into_iter().flatten().collect::<Vec<_>>().join(" → "),
        "hero_power" => n("target").filter(|x| x != "-1").map(|x| format!("→ {x}")).unwrap_or_default(),
        "mulligan" => format!("replaces {}", a["replace"].as_array().map_or(0, |r| r.len())),
        "choose" => n("option").unwrap_or_default(),
        _ => String::new(),
    };
    if detail.is_empty() { format!("{name}: {t}") } else { format!("{name}: {t} {detail}") }
}

/// Checks one message from player p and forwards it; Some = the game ends.
async fn relay(ctx: &Ctx, play: &mut Play, p: usize, m: Value) -> Option<End> {
    let lose = |reason| Some((1 - p as i64, reason));
    let deck_pair = |d: &Value| json!([d["hero"], d["cards"]]);
    let mut logged = true;
    match m["t"].as_str().unwrap_or("") {
        "hello" => {
            if play.hello[p] {
                return lose("protocol");
            }
            if m["hero"] != ctx.decks[p]["hero"] || m["cards"] != ctx.decks[p]["cards"] {
                return lose("cheat");
            }
            play.hello[p] = true;
        }
        "start" => {
            if p != 0 || play.started || !(play.hello[0] && play.hello[1]) {
                return lose("protocol");
            }
            if m["seed"].as_f64() != Some(ctx.seed as f64) || m["decks"] != json!([deck_pair(&ctx.decks[0]), deck_pair(&ctx.decks[1])]) {
                return lose("cheat");
            }
            play.started = true;
            ctx.app.event(ctx.ev(p, "game_start", format!("{} started the game", ctx.names[p])).data(json!({"seed": ctx.seed})));
        }
        "action" => {
            if !play.started || m["n"].as_f64() != Some(play.n[p] as f64) {
                return lose("protocol");
            }
            let a = &m["action"];
            if !a.is_object() || a["player"].as_f64() != Some(p as f64) {
                return lose("cheat");
            }
            let r = match ctx.app.referee.call(json!({"op": "act", "game": ctx.id, "action": a})).await {
                Ok(r) => r,
                Err(e) => {
                    tracing::error!("game {}: referee failed: {e}", ctx.id);
                    ctx.app.event(ctx.ev(p, "error", format!("The referee failed: {e}")));
                    return Some((-1, "aborted"));
                }
            };
            if r["ok"] != true {
                return lose("illegal");
            }
            let simultaneous = matches!(a["type"].as_str(), Some("mulligan" | "concede"));
            if !simultaneous && m["hash"] != r["hash"] {
                return lose("desync");
            }
            play.n[p] += 1;
            if let Some(g) = ctx.app.hub().games.get_mut(&ctx.id) {
                g.turn = r["turn"].as_f64().map_or(g.turn, |x| x as i64);
                g.current = r["current"].as_f64().map_or(g.current, |x| x as i64);
                g.actions += 1;
            }
            ctx.app.event(ctx.ev(p, "game_action", action_text(&ctx.names[p], a)).data(json!({
                "p": p, "n": play.n[p] - 1, "action": a, "turn": r["turn"], "current": r["current"], "hash": r["hash"], "over": r["over"]})));
            if r["over"] == true {
                forward(ctx, p, &m);
                return Some((r["winner"].as_f64().map_or(-1, |x| x as i64), "over"));
            }
        }
        "emote" => {
            if !m["id"].as_str().is_some_and(|s| s.len() <= 32) {
                return None;
            }
            logged = false;
        }
        "intent" => {
            if m.to_string().len() > INTENT_MAX {
                return None;
            }
            logged = false;
        }
        "bye" => return lose("left"),
        _ => return lose("protocol"),
    }
    if logged {
        play.log.push(json!({"from": p, "m": m}));
    }
    forward(ctx, p, &m);
    None
}

fn forward(ctx: &Ctx, from: usize, m: &Value) {
    ctx.app.hub().send(ctx.ids[1 - from], &json!({"t": "game", "game": ctx.id, "m": m}));
}

async fn finish(ctx: &Ctx, winner: i64, reason: &'static str, cause: Cause) {
    {
        let mut hub = ctx.app.hub();
        hub.games.remove(&ctx.id);
        for a in ctx.ids {
            hub.in_game.remove(&a);
        }
    }
    let _ = ctx.app.referee.call(json!({"op": "drop", "game": ctx.id})).await;
    let saved = async {
        let tx = ctx.app.db.begin().await?;
        let extra = apply_results(&tx, ctx.mode, ctx.ids, winner).await?;
        let g = played::ActiveModel {
            id: Set(ctx.id.clone()),
            mode: Set(ctx.mode.as_str().into()),
            p0: Set(Some(ctx.ids[0])),
            p1: Set(Some(ctx.ids[1])),
            started: Set(ctx.started),
            ended: Set(ranked::now()),
            winner: Set(winner),
            reason: Set(reason.into()),
        };
        played::Entity::insert(g).exec_without_returning(&tx).await?;
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
    let mut data = json!({"winner": winner, "reason": reason, "mode": ctx.mode, "players": ctx.names, "results": extra,
                          "duration": ranked::now() - ctx.started});
    if let Some((p, m)) = &cause {
        data["by"] = json!(ctx.names[*p]);
        data["message"] = json!(m);
    }
    ctx.app.event(ctx.ev(w, "game_end", text).data(data));
    {
        let hub = ctx.app.hub();
        for (p, a) in ctx.ids.iter().enumerate() {
            let result = if winner < 0 { "draw" } else if winner == p as i64 { "win" } else { "loss" };
            let mut m = json!({"t": "game_over", "game": ctx.id, "result": result, "reason": reason});
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

pub async fn rank_json(c: &impl ConnectionTrait, a: &Account) -> DbResult<Value> {
    Ok(json!({"rank": a.rank, "stars": a.stars, "legend": db::legend_number(c, a).await?, "streak": a.streak}))
}

/// MMR, ranked stars and the Arena record; returns what each player's game_over adds.
async fn apply_results(c: &impl ConnectionTrait, mode: Mode, ids: [i64; 2], winner: i64) -> DbResult<[Value; 2]> {
    if winner < 0 || mode == Mode::Friendly {
        return Ok([json!({}), json!({})]);
    }
    let w = winner as usize;
    let load = |id| async move { db::account_by_id(c, id).await?.ok_or(DbError::RecordNotFound("account".into())) };
    match mode {
        Mode::Casual => {
            let (mut a, mut b) = (load(ids[w]).await?, load(ids[1 - w]).await?);
            (a.casual_mmr, b.casual_mmr) = ranked::elo(a.casual_mmr, b.casual_mmr, true);
            db::save_standing(c, &a).await?;
            db::save_standing(c, &b).await?;
            Ok([json!({}), json!({})])
        }
        Mode::Ranked => {
            let mut acc = [load(ids[0]).await?, load(ids[1]).await?];
            for a in acc.iter_mut() {
                db::refresh_season(c, a).await?;
            }
            (acc[w].ranked_mmr, acc[1 - w].ranked_mmr) = ranked::elo(acc[w].ranked_mmr, acc[1 - w].ranked_mmr, true);
            for (p, a) in acc.iter_mut().enumerate() {
                let mut r = a.rank();
                if p == w { r.win() } else { r.lose() }
                (a.rank, a.stars, a.streak) = (r.rank, r.stars, r.streak);
                db::save_standing(c, a).await?;
            }
            Ok([json!({"rank": rank_json(c, &acc[0]).await?}), json!({"rank": rank_json(c, &acc[1]).await?})])
        }
        Mode::Arena => {
            let mut out = [json!({}), json!({})];
            for (p, id) in ids.iter().enumerate() {
                let Some(run) = arena::Entity::find_by_id(*id).one(c).await? else { continue };
                let (wins, losses) = if p == w { (run.wins + 1, run.losses) } else { (run.wins, run.losses + 1) };
                let over = wins >= 12 || losses >= 3;
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
