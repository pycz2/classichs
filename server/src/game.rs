//! A refereed game: the server relays the players' NetSession messages and checks
//! every action with the referee before it reaches the other player.

use crate::db::{self, Account};
use crate::ranked::{self, Mode};
use crate::{AppRef, LiveGame};
use rand::Rng;
use rusqlite::{params, Connection, OptionalExtension};
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
    decks: [Value; 2],
    seed: u32,
    started: i64,
    /// The `match` message for each player (sent again on a rejoin).
    hello: [Value; 2],
}

/// Starts a game between two players ([account, deck]); the host (player 0) is drawn at random.
pub async fn start(app: AppRef, mode: Mode, mut players: [(i64, Value); 2]) {
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
    let accounts = app.db.run(move |c| Ok([db::account_by_id(c, ids[0])?, db::account_by_id(c, ids[1])?])).await;
    let Ok([Some(a0), Some(a1)]) = accounts else { return fail(&app, "No such account") };
    let id = format!("{:016x}", rand::thread_rng().gen::<u64>());
    let seed: u32 = rand::thread_rng().gen();
    let r = app.referee.call(json!({"op": "new", "game": id, "seed": seed, "decks": decks})).await;
    if !matches!(&r, Ok(v) if v["ok"] == true) {
        tracing::warn!("referee refused game {id}: {r:?}");
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
    let ctx = Ctx { app, id, mode, ids, decks, seed, started: ranked::now(), hello };
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
            started: ranked::now(), turn: 0, current: 0,
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
    let end = loop {
        let deadline = gone.iter().flatten().min().copied();
        let ev = tokio::select! {
            ev = rx.recv() => ev,
            _ = tokio::time::sleep_until(deadline.unwrap_or_else(|| Instant::now() + Duration::from_secs(3600))), if deadline.is_some() => {
                let p = if gone[0] == deadline { 0 } else { 1 };
                break (1 - p as i64, "disconnect");
            }
        };
        match ev {
            None => break (-1, "aborted"),
            Some(Ev::Gone(p)) => gone[p] = Some(Instant::now() + ctx.app.grace),
            Some(Ev::Back(p)) => {
                gone[p] = None;
                let mut m = ctx.hello[p].clone();
                m["rejoin"] = json!(true);
                m["log"] = json!(play.log);
                ctx.app.hub().send(ctx.ids[p], &m);
            }
            Some(Ev::Msg(p, m)) => {
                if let Some(end) = relay(&ctx, &mut play, p, m).await {
                    break end;
                }
            }
        }
    };
    finish(&ctx, end.0, end.1).await;
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
            }
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

async fn finish(ctx: &Ctx, winner: i64, reason: &'static str) {
    {
        let mut hub = ctx.app.hub();
        hub.games.remove(&ctx.id);
        for a in ctx.ids {
            hub.in_game.remove(&a);
        }
    }
    let _ = ctx.app.referee.call(json!({"op": "drop", "game": ctx.id})).await;
    let (mode, ids, id, started) = (ctx.mode, ctx.ids, ctx.id.clone(), ctx.started);
    let extra = ctx
        .app
        .db
        .run(move |c| {
            let tx = c.transaction()?;
            let extra = apply_results(&tx, mode, ids, winner)?;
            tx.execute(
                "INSERT INTO games (id, mode, p0, p1, started, ended, winner, reason) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![id, mode.as_str(), ids[0], ids[1], started, ranked::now(), winner, reason],
            )?;
            tx.commit()?;
            Ok(extra)
        })
        .await
        .unwrap_or_else(|e| {
            tracing::error!("game {}: results not saved: {e}", ctx.id);
            [json!({}), json!({})]
        });
    tracing::info!("game {} over: winner {winner} ({reason})", ctx.id);
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

pub fn rank_json(c: &Connection, a: &Account) -> rusqlite::Result<Value> {
    Ok(json!({"rank": a.rank.rank, "stars": a.rank.stars, "legend": db::legend_number(c, a)?, "streak": a.rank.streak}))
}

/// MMR, ranked stars and the Arena record; returns what each player's game_over adds.
fn apply_results(c: &Connection, mode: Mode, ids: [i64; 2], winner: i64) -> rusqlite::Result<[Value; 2]> {
    if winner < 0 || mode == Mode::Friendly {
        return Ok([json!({}), json!({})]);
    }
    let w = winner as usize;
    let load = |id| db::account_by_id(c, id)?.ok_or(rusqlite::Error::QueryReturnedNoRows);
    match mode {
        Mode::Casual => {
            let (a, b) = (load(ids[w])?, load(ids[1 - w])?);
            let (ma, mb) = ranked::elo(a.casual_mmr, b.casual_mmr, true);
            c.execute("UPDATE accounts SET casual_mmr = ?1 WHERE id = ?2", params![ma, a.id])?;
            c.execute("UPDATE accounts SET casual_mmr = ?1 WHERE id = ?2", params![mb, b.id])?;
            Ok([json!({}), json!({})])
        }
        Mode::Ranked => {
            let mut acc = [load(ids[0])?, load(ids[1])?];
            for a in acc.iter_mut() {
                db::refresh_season(c, a)?;
            }
            let (mw, ml) = ranked::elo(acc[w].ranked_mmr, acc[1 - w].ranked_mmr, true);
            acc[w].ranked_mmr = mw;
            acc[1 - w].ranked_mmr = ml;
            acc[w].rank.win();
            acc[1 - w].rank.lose();
            for a in &acc {
                c.execute(
                    "UPDATE accounts SET ranked_mmr = ?1, rank = ?2, stars = ?3, streak = ?4 WHERE id = ?5",
                    params![a.ranked_mmr, a.rank.rank, a.rank.stars, a.rank.streak, a.id],
                )?;
            }
            Ok([json!({"rank": rank_json(c, &acc[0])?}), json!({"rank": rank_json(c, &acc[1])?})])
        }
        Mode::Arena => {
            let mut out = [json!({}), json!({})];
            for (p, id) in ids.iter().enumerate() {
                let col = if p == w { "wins" } else { "losses" };
                c.execute(&format!("UPDATE arena SET {col} = {col} + 1 WHERE account = ?1"), [id])?;
                let rec: Option<(i64, i64)> =
                    c.query_row("SELECT wins, losses FROM arena WHERE account = ?1", [id], |r| Ok((r.get(0)?, r.get(1)?))).optional()?;
                if let Some((wins, losses)) = rec {
                    let over = wins >= 12 || losses >= 3;
                    if over {
                        c.execute("DELETE FROM arena WHERE account = ?1", [id])?;
                    }
                    out[p] = json!({"arena": {"wins": wins, "losses": losses, "over": over}});
                }
            }
            Ok(out)
        }
        Mode::Friendly => unreachable!(),
    }
}
