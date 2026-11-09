//! Tournaments (0.50): any player creates one, players join with copied decks, the scheduler
//! (`spawn`: every 2 s and after each tournament game) moves it through its life (open → locked
//! → seeded → running → finished) and plays its matches: series (Conquest or Last Hero
//! Standing) with accept, ban and pick steps on 60-second deadlines, each game started through
//! `game::start_with` (mode `tournament`, no rating change). Everything is in the database, so
//! a restart carries on. Pairings and places: `format`. Protocol: server/README.md, "Tournaments".

pub mod format;

use crate::entity::game as played;
use crate::entity::tournament::{self as tour, entrant, games as tgame, matches as tmatch};
use crate::events::{now_ms, Event};
use crate::game;
use crate::packs::{self, GameRules};
use crate::ranked::Mode;
use crate::AppRef;
use classichs_engine::deck::Deck;
use format::{Played, Side, Slot};
use rand::seq::SliceRandom;
use rand::Rng;
use sea_orm::{
    ActiveModelTrait, ColumnTrait, Condition, ConnectionTrait, DbErr, EntityTrait, IntoActiveModel, NotSet, PaginatorTrait, QueryFilter,
    QueryOrder, QuerySelect, TransactionTrait,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::time::Duration;

const MINUTE: i64 = 60_000;
/// The accept, ban and pick deadlines.
pub const STEP_MS: i64 = 60_000;
/// Tournaments of a creator that are not over yet.
const MAX_OPEN: u64 = 3;
const MAX_PER_DAY: u64 = 10;
const ACTIVE: [&str; 4] = ["open", "locked", "seeded", "running"];
/// Matches whose players are busy with them.
const BUSY: [&str; 4] = ["accept", "ban", "pick", "playing"];

/// What the app keeps for tournaments (`App::tour`).
pub struct State {
    /// Every change of a tournament holds this (the scheduler and the players' messages).
    // ponytail: one lock for all tournaments; per-tournament locks if many run at once
    pub lock: tokio::sync::Mutex<()>,
    /// Tournament → the accounts that get its `tournament` pushes (`t_get` until `t_unwatch`).
    pub watchers: std::sync::Mutex<HashMap<i64, HashSet<i64>>>,
    /// A tournament game ended: tick now.
    pub wake: tokio::sync::Notify,
    /// This process: a match whose game was started by another one lost it in a restart.
    pub boot: i64,
}

impl Default for State {
    fn default() -> State {
        State { lock: Default::default(), watchers: Default::default(), wake: Default::default(), boot: rand::thread_rng().gen_range(1..i64::MAX) }
    }
}

/// A refusal: `{"t": "error", "code", "text"}` (code "tournament", or "server" for a database error).
#[derive(Debug)]
pub struct TErr(pub &'static str, pub String);

impl From<DbErr> for TErr {
    fn from(e: DbErr) -> TErr {
        tracing::error!("tournament: database: {e}");
        TErr("server", format!("database: {e}"))
    }
}

fn no(text: &str) -> TErr {
    TErr("tournament", text.into())
}

type Res<T> = Result<T, TErr>;

/// A whole number from a message (clients may send 3.0).
fn num(v: &Value, k: &str) -> Option<i64> {
    v.get(k)?.as_f64().filter(|x| x.fract() == 0.0 && x.abs() < 9e15).map(|x| x as i64)
}

/// A match that is over: played out (`done`, forfeits too) or a `bye` (one side, or none, there).
fn over(m: &tmatch::Model) -> bool {
    m.status == "done" || m.status == "bye"
}

fn wins_needed(best_of: i64) -> i64 {
    (best_of + 1) / 2
}

/// Decks per entrant: the wins a series needs plus the bans.
fn deck_count(t: &tour::Model) -> usize {
    (wins_needed(t.best_of) + t.bans) as usize
}

// --- the series ---------------------------------------------------------------------------

/// A match's series between its sides a (0) and b (1): `t_matches.state`.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Series {
    /// Accepted the coming game.
    pub acc: [bool; 2],
    /// The index of the opponent's deck each side banned (once a match).
    pub ban: [Option<usize>; 2],
    /// The deck each side plays the coming game with.
    pub pick: [Option<usize>; 2],
    /// Each side's decks: ok | banned | won (Conquest: spent) | lost (LHS: out).
    pub decks: [Vec<String>; 2],
    /// LHS: the side that won the last game keeps its deck.
    pub keep: Option<usize>,
    /// The game being played.
    pub game: Option<String>,
    /// The process that started it (`State::boot`).
    pub boot: i64,
    /// Games started.
    pub n: i64,
}

impl Series {
    fn of(m: &tmatch::Model) -> Series {
        serde_json::from_str(&m.state).unwrap_or_default()
    }

    fn usable(&self, side: usize) -> Vec<usize> {
        (0..self.decks[side].len()).filter(|&i| self.decks[side][i] == "ok").collect()
    }

    /// The result of a game (`forfeit`: no game was played) won by side w (None: no winner,
    /// the game is played again). Returns the new score.
    fn record(&mut self, w: Option<usize>, forfeit: bool, conquest: bool, score: [i64; 2]) -> [i64; 2] {
        let mut score = score;
        if let Some(w) = w {
            let l = 1 - w;
            score[w] += 1;
            if conquest {
                if !forfeit {
                    if let Some(d) = self.pick[w] {
                        self.decks[w][d] = "won".into();
                    }
                }
                self.keep = None;
            } else {
                // LHS: the losing deck is out (a forfeit costs the deck in hand, or the first usable)
                if let Some(d) = self.pick[l].or_else(|| self.usable(l).first().copied()) {
                    self.decks[l][d] = "lost".into();
                }
                if !forfeit || self.keep == Some(l) {
                    self.keep = if forfeit { None } else { Some(w) };
                }
            }
        }
        for s in 0..2 {
            if self.keep != Some(s) {
                self.pick[s] = None;
            }
        }
        self.acc = [false, false];
        self.game = None;
        score
    }
}

// --- loading and saving -------------------------------------------------------------------------

/// A tournament with its entrants and matches (by `n`), as loaded.
#[derive(Clone)]
struct T {
    t: tour::Model,
    es: Vec<entrant::Model>,
    ms: Vec<tmatch::Model>,
}

impl T {
    fn entrant(&self, account: i64) -> Option<&entrant::Model> {
        self.es.iter().find(|e| e.account == account)
    }

    fn decks_of(&self, account: Option<i64>) -> Vec<Value> {
        account.and_then(|a| self.entrant(a)).and_then(|e| serde_json::from_str(&e.decks).ok()).unwrap_or_default()
    }

    fn opt(&self, k: &str) -> Option<i64> {
        num(&serde_json::from_str::<Value>(&self.t.options).unwrap_or_default(), k)
    }

    fn played(&self) -> Vec<Played> {
        self.ms
            .iter()
            .filter(|m| over(m) && m.winner.is_some())
            .map(|m| Played { p: [m.a, m.b], winner: m.winner, score: [m.score_a, m.score_b] })
            .collect()
    }

    fn standings(&self) -> HashMap<i64, format::Stand> {
        format::standings(&self.es.iter().map(|e| e.account).collect::<Vec<_>>(), &self.played())
    }

    /// Elimination: the stage each loser went out at.
    fn outs(&self) -> HashMap<i64, i64> {
        let mut out = HashMap::new();
        for m in self.ms.iter().filter(|m| m.status == "done" && m.out > 0) {
            if let (Some(w), Some(a), Some(b)) = (m.winner, m.a, m.b) {
                out.insert(if w == a { b } else { a }, m.out);
            }
        }
        out
    }

    fn eliminated(&self, account: i64, st: &HashMap<i64, format::Stand>, outs: &HashMap<i64, i64>) -> bool {
        match self.t.format.as_str() {
            "elimination" => outs.contains_key(&account),
            "swiss" => {
                let d = self.opt("drop_after").unwrap_or(0);
                d > 0 && st.get(&account).is_some_and(|s| s.match_losses >= d)
            }
            _ => {
                let mine: Vec<_> = self.ms.iter().filter(|m| m.a == Some(account) || m.b == Some(account)).collect();
                self.t.status == "running" && !mine.is_empty() && mine.iter().all(|m| over(m))
            }
        }
    }
}

async fn load(c: &impl ConnectionTrait, id: i64) -> Res<T> {
    let t = tour::Entity::find_by_id(id).one(c).await?.ok_or_else(|| no("No such tournament"))?;
    let es = entrant::Entity::find().filter(entrant::Column::Tournament.eq(id)).order_by_asc(entrant::Column::Joined).all(c).await?;
    let ms = tmatch::Entity::find().filter(tmatch::Column::Tournament.eq(id)).order_by_asc(tmatch::Column::N).all(c).await?;
    Ok(T { t, es, ms })
}

/// Writes what changed since `orig`.
async fn save(app: &AppRef, t: &T, orig: &T) -> Res<()> {
    let tx = app.db.begin().await?;
    if t.t != orig.t {
        t.t.clone().into_active_model().reset_all().update(&tx).await?;
    }
    for e in &t.es {
        if orig.entrant(e.account) != Some(e) {
            e.clone().into_active_model().reset_all().update(&tx).await?;
        }
    }
    for (i, m) in t.ms.iter().enumerate() {
        if orig.ms.get(i) != Some(m) {
            m.clone().into_active_model().reset_all().update(&tx).await?;
        }
    }
    tx.commit().await?;
    Ok(())
}

async fn insert_match(app: &AppRef, m: tmatch::Model) -> Res<tmatch::Model> {
    let mut am = m.into_active_model().reset_all();
    am.id = NotSet;
    Ok(am.insert(&app.db).await?)
}

async fn names(c: &impl ConnectionTrait, ids: impl IntoIterator<Item = i64>) -> Res<HashMap<i64, String>> {
    let mut ids: Vec<i64> = ids.into_iter().collect();
    ids.sort_unstable();
    ids.dedup();
    Ok(crate::ws::accounts_in_order(c, &ids).await?.into_iter().map(|a| (a.id, a.name)).collect())
}

async fn pack_name(app: &AppRef, hash: &str) -> String {
    packs::rules_for(app, hash).await.map(|r| packs::short_name(&r)).unwrap_or_default()
}

// --- the JSON players see ------------------------------------------------------------------------

fn summary(t: &tour::Model, entrants: usize, joined: bool, creator: &str, pack_name: &str) -> Value {
    json!({"id": t.id, "name": t.name, "creator": creator, "pack": t.pack, "pack_name": pack_name, "format": t.format, "series": t.series,
           "best_of": t.best_of, "start_at": t.start_at, "status": t.status, "entrants": entrants, "max_players": t.max_players, "joined": joined})
}

/// The whole tournament as `viewer` sees it (`viewer` None: the admin panel, every deck shown).
async fn full_json(app: &AppRef, t: &T, viewer: Option<i64>) -> Res<Value> {
    let now = now_ms();
    let names = names(&app.db, t.es.iter().map(|e| e.account).chain([t.t.creator])).await?;
    let name = |a: Option<i64>| a.map(|a| names.get(&a).cloned().unwrap_or_else(|| "?".into()));
    let st = t.standings();
    let outs = t.outs();
    let revealed = t.t.deck_reveal && now >= t.t.start_at - 10 * MINUTE;
    let mut entrants: Vec<Value> = t
        .es
        .iter()
        .map(|e| {
            let s = st.get(&e.account).cloned().unwrap_or_default();
            let mut v = json!({"name": name(Some(e.account)), "seed": e.seed, "team": e.team, "eliminated": t.eliminated(e.account, &st, &outs),
                               "place": e.place, "points": s.points, "wins": s.wins, "losses": s.losses, "buchholz": s.buchholz});
            if viewer.is_none_or(|me| me == e.account) || revealed {
                v["decks"] = serde_json::from_str(&e.decks).unwrap_or(json!([]));
            }
            v
        })
        .collect();
    entrants.sort_by_key(|e| (e["place"].as_i64().filter(|p| *p > 0).unwrap_or(i64::MAX), e["seed"].as_i64()));
    let gs = tgame::Entity::find().filter(tgame::Column::Tournament.eq(t.t.id)).order_by_asc(tgame::Column::N).all(&app.db).await?;
    let matches: Vec<Value> = t
        .ms
        .iter()
        .map(|m| {
            let games: Vec<&str> = gs.iter().filter(|g| g.match_id == m.id).map(|g| g.game.as_str()).collect();
            json!({"id": m.id, "round": m.round, "bracket": m.bracket, "slot": m.slot, "p": [name(m.a), name(m.b)], "status": m.status,
                   "score": [m.score_a, m.score_b], "winner": name(m.winner), "games": games, "deadline": m.deadline})
        })
        .collect();
    let me = viewer.unwrap_or(-1);
    let mine = t.entrant(me).is_some();
    let creator = me == t.t.creator;
    let open = t.t.status == "open" && now < t.t.start_at - 10 * MINUTE;
    let joinable = matches!(t.t.status.as_str(), "open" | "locked") && now < t.t.start_at - MINUTE;
    let can = json!({
        "edit": creator && open, "reschedule": creator && open, "cancel": creator && ACTIVE.contains(&t.t.status.as_str()),
        "join": !mine && joinable && (t.es.len() as i64) < t.t.max_players, "leave": mine && joinable, "decks": mine && open,
        "spectate": may_spectate(t, me, &st, &outs),
    });
    let mut v = summary(&t.t, t.es.len(), mine, &name(Some(t.t.creator)).unwrap_or_default(), &pack_name(app, &t.t.pack).await);
    let extra = json!({
        "options": serde_json::from_str::<Value>(&t.t.options).unwrap_or(json!({})), "bans": t.t.bans, "min_players": t.t.min_players,
        "deck_reveal": t.t.deck_reveal, "spectators": t.t.spectators, "reason": t.t.reason, "created": t.t.created, "ended": t.t.ended,
        "decks_per_entrant": deck_count(&t.t), "wins_needed": wins_needed(t.t.best_of),
        "round": t.ms.iter().map(|m| m.round).max().unwrap_or(0),
        "entrants": entrants, "matches": matches, "can": can,
    });
    // the format's options also at the top level (rounds, drop_after, losses)
    let opts = extra["options"].clone();
    for (k, x) in opts.as_object().into_iter().flatten().chain(extra.as_object().into_iter().flatten()) {
        v[k] = x.clone();
    }
    Ok(v)
}

fn may_spectate(t: &T, me: i64, st: &HashMap<i64, format::Stand>, outs: &HashMap<i64, i64>) -> bool {
    t.t.spectators && t.t.status == "running" && (me == t.t.creator || (t.entrant(me).is_some() && t.eliminated(me, st, outs)))
}

/// `t_match` for one side of a match.
fn t_match_msg(t: &T, m: &tmatch::Model, side: usize, names: &HashMap<i64, String>) -> Value {
    let s = Series::of(m);
    let p = [m.a, m.b];
    let phase = match m.status.as_str() {
        _ if t.t.status != "running" => "done",
        "accept" if !s.acc[side] => "accept",
        "ban" if s.ban[side].is_none() => "ban",
        "pick" if s.pick[side].is_none() => "pick",
        "done" => "done",
        _ => "wait",
    };
    let decks = |x: usize| t.decks_of(p[x]);
    let state = |x: usize, i: usize| s.decks[x].get(i).cloned().unwrap_or_else(|| "ok".into());
    let mine: Vec<Value> = decks(side).iter().enumerate().map(|(i, d)| json!({"hero": d["hero"], "name": d["name"], "state": state(side, i)})).collect();
    let theirs: Vec<Value> = decks(1 - side).iter().enumerate().map(|(i, d)| json!({"hero": d["hero"], "state": state(1 - side, i)})).collect();
    let score = [m.score_a, m.score_b];
    json!({"t": "t_match", "tournament": t.t.id, "name": t.t.name, "match": m.id, "phase": phase, "status": m.status, "deadline": m.deadline,
           "opponent": p[1 - side].and_then(|a| names.get(&a)), "score": [score[side], score[1 - side]], "mine": mine, "theirs": theirs,
           "pick": s.pick[side], "game": s.game, "series": t.t.series, "best_of": t.t.best_of, "bans": t.t.bans,
           "winner": m.winner.and_then(|a| names.get(&a))})
}

/// Sends `t_match` to both sides of the matches given, then `tournament` to its watchers.
async fn push(app: &AppRef, t: &T, matches: &HashSet<i64>) -> Res<()> {
    if !matches.is_empty() {
        let names = names(&app.db, t.es.iter().map(|e| e.account)).await?;
        let hub = app.hub();
        for m in t.ms.iter().filter(|m| matches.contains(&m.id)) {
            for (side, p) in [m.a, m.b].into_iter().enumerate() {
                if let Some(p) = p {
                    hub.send(p, &t_match_msg(t, m, side, &names));
                }
            }
        }
    }
    let watchers: Vec<i64> = app.tour.watchers.lock().unwrap_or_else(|e| e.into_inner()).get(&t.t.id).map(|w| w.iter().copied().collect()).unwrap_or_default();
    for w in watchers {
        if app.hub().conns.contains_key(&w) {
            let v = json!({"t": "tournament", "tournament": full_json(app, t, Some(w)).await?});
            app.hub().send(w, &v);
        }
    }
    Ok(())
}

fn watch(app: &AppRef, id: i64, account: i64) {
    app.tour.watchers.lock().unwrap_or_else(|e| e.into_inner()).entry(id).or_default().insert(account);
}

fn ev(app: &AppRef, t: &tour::Model, text: String) {
    app.event(Event::new("tournament", text).data(json!({"tournament": t.id, "name": t.name})));
}

// --- the scheduler -------------------------------------------------------------------------------

/// The scheduler: every 2 seconds, and at once when a tournament game ends.
pub fn spawn(app: AppRef) {
    tokio::spawn(async move {
        let mut every = tokio::time::interval(Duration::from_secs(2));
        loop {
            tokio::select! {
                _ = every.tick() => {}
                _ = app.tour.wake.notified() => {}
            }
            tick(&app).await;
        }
    });
}

/// Moves every tournament that is not over on (tests call it to skip the wait).
pub async fn tick(app: &AppRef) {
    let ids: Result<Vec<i64>, DbErr> = tour::Entity::find()
        .select_only()
        .column(tour::Column::Id)
        .filter(tour::Column::Status.is_in(ACTIVE))
        .into_tuple()
        .all(&app.db)
        .await;
    for id in ids.unwrap_or_default() {
        let _g = app.tour.lock.lock().await;
        let r = async {
            let mut t = load(&app.db, id).await?;
            let orig = t.clone();
            commit(app, &mut t, &orig, HashSet::new()).await
        };
        if let Err(TErr(_, e)) = r.await {
            tracing::error!("tournament {id}: {e}");
        }
    }
}

/// After a change (or none: a tick): the lifecycle and the matches move on, the changes are
/// saved and pushed (true: something changed). The caller holds `State::lock`.
async fn commit(app: &AppRef, t: &mut T, orig: &T, mut changed: HashSet<i64>) -> Res<bool> {
    let now = now_ms();
    lifecycle(app, t, now).await?;
    if t.t.status == "running" {
        progress(app, t, now, &mut changed).await?;
    }
    save(app, t, orig).await?;
    for (i, m) in t.ms.iter().enumerate() {
        if orig.ms.get(i) != Some(m) && m.status != "pending" {
            changed.insert(m.id);
        }
    }
    let dirty = t.t != orig.t || t.es != orig.es || t.ms != orig.ms || !changed.is_empty();
    if dirty {
        push(app, t, &changed).await?;
    }
    Ok(dirty)
}

/// open → (T−10 min) locked or closed → (T−1 min) seeded → (T) running.
async fn lifecycle(app: &AppRef, t: &mut T, now: i64) -> Res<()> {
    loop {
        let start = t.t.start_at;
        let n = t.es.len() as i64;
        match t.t.status.as_str() {
            "open" | "locked" if now >= start - 10 * MINUTE && n < t.t.min_players.max(2) => {
                t.t.status = "closed".into();
                t.t.reason = "not enough players".into();
                t.t.ended = now;
                ev(app, &t.t, format!("Tournament {} closed: not enough players ({n} of {})", t.t.name, t.t.min_players));
            }
            "open" if now >= start - 10 * MINUTE => t.t.status = "locked".into(),
            "locked" if now >= start - MINUTE => seed(app, t).await?,
            "seeded" if now >= start => {
                t.t.status = "running".into();
                ev(app, &t.t, format!("Tournament {} started with {n} players", t.t.name));
            }
            _ => return Ok(()),
        }
    }
}

/// Random seeds (and Scheveningen teams), then the matches the format plans.
async fn seed(app: &AppRef, t: &mut T) -> Res<()> {
    t.es.shuffle(&mut rand::thread_rng());
    let n = t.es.len();
    for (i, e) in t.es.iter_mut().enumerate() {
        e.seed = i as i64;
        e.team = if t.t.format == "scheveningen" { format::team(n, i) } else { -1 };
    }
    let order: Vec<i64> = t.es.iter().map(|e| e.account).collect();
    t.t.status = "seeded".into();
    let specs = match t.t.format.as_str() {
        "round_robin" => format::round_robin(n, t.opt("rounds").unwrap_or(1) as usize),
        "scheveningen" => format::scheveningen(n),
        "elimination" => format::elimination(n, t.opt("losses") == Some(2)),
        _ => vec![],
    };
    let rows: Vec<tmatch::ActiveModel> = specs
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let side = |x: Side| match x {
                Side::Seed(k) => (Some(order[k]), String::new()),
                Side::Bye => (None, String::new()),
                Side::Winner(j) => (None, format!("w{j}")),
                Side::Loser(j) => (None, format!("l{j}")),
            };
            let ((a, sa), (b, sb)) = (side(s.sides[0]), side(s.sides[1]));
            let m = new_match(t.t.id, i, s.round, s.bracket, s.slot, a, b);
            let mut am = tmatch::Model { out: s.out, src: json!([sa, sb]).to_string(), ..m }.into_active_model().reset_all();
            am.id = NotSet;
            am
        })
        .collect();
    let tx = app.db.begin().await?;
    for chunk in rows.chunks(500) {
        tmatch::Entity::insert_many(chunk.to_vec()).exec_without_returning(&tx).await?;
    }
    tx.commit().await?;
    t.ms = tmatch::Entity::find().filter(tmatch::Column::Tournament.eq(t.t.id)).order_by_asc(tmatch::Column::N).all(&app.db).await?;
    if t.t.format == "swiss" {
        let mut o: Value = serde_json::from_str(&t.t.options).unwrap_or(json!({}));
        if num(&o, "rounds").is_none() {
            o["rounds"] = json!(format::swiss_rounds(n));
            t.t.options = o.to_string();
        }
        swiss_round(app, t).await?;
    }
    ev(app, &t.t, format!("Tournament {} seeded: {n} players, {} matches planned", t.t.name, t.ms.len()));
    Ok(())
}

fn new_match(tournament: i64, n: usize, round: i64, bracket: &str, slot: i64, a: Option<i64>, b: Option<i64>) -> tmatch::Model {
    tmatch::Model {
        id: 0, tournament, n: n as i64, round, bracket: bracket.into(), slot, out: 0, a, b, src: r#"["",""]"#.into(), status: "pending".into(),
        deadline: 0, score_a: 0, score_b: 0, winner: None, state: "{}".into(),
    }
}

/// Swiss: pairs the next round (same points first, no rematch, a bye for an odd count).
async fn swiss_round(app: &AppRef, t: &mut T) -> Res<bool> {
    let round = t.ms.iter().map(|m| m.round).max().unwrap_or(0) + 1;
    if round > t.opt("rounds").unwrap_or(1) {
        return Ok(false);
    }
    let st = t.standings();
    let drop = t.opt("drop_after").unwrap_or(0);
    let mut order: Vec<(i64, i64)> = t.es.iter().filter(|e| drop == 0 || st[&e.account].match_losses < drop).map(|e| (e.account, e.seed)).collect();
    if order.len() < 2 {
        return Ok(false);
    }
    order.sort_by_key(|(a, seed)| {
        let s = &st[a];
        (-s.points, -(s.wins - s.losses), -s.buchholz, *seed)
    });
    let order: Vec<i64> = order.into_iter().map(|x| x.0).collect();
    let played: HashSet<(i64, i64)> = t.ms.iter().filter_map(|m| Some((m.a?, m.b?))).collect();
    let byes: HashSet<i64> = t.ms.iter().filter(|m| m.b.is_none()).filter_map(|m| m.a).collect();
    let (pairs, bye) = format::swiss_pairs(&order, &played, &byes);
    let sides = pairs.into_iter().map(|(a, b)| (Some(a), Some(b))).chain(bye.map(|x| (Some(x), None)));
    for (slot, (a, b)) in sides.enumerate() {
        let m = new_match(t.t.id, t.ms.len(), round, "", slot as i64, a, b);
        t.ms.push(insert_match(app, m).await?);
    }
    Ok(true)
}

/// The matches move on: results, deadlines, brackets, byes, readiness, game starts; at the
/// end the places.
async fn progress(app: &AppRef, t: &mut T, now: i64, changed: &mut HashSet<i64>) -> Res<()> {
    loop {
        let mut moved = false;
        for i in 0..t.ms.len() {
            let before = t.ms[i].clone();
            step(app, t, i, now).await?;
            if t.ms[i] != before {
                moved = true;
                changed.insert(t.ms[i].id);
            }
        }
        // readiness: both sides known and free (not busy in another match of this tournament)
        let mut busy: HashSet<i64> = t.ms.iter().filter(|m| BUSY.contains(&m.status.as_str())).flat_map(|m| [m.a, m.b]).flatten().collect();
        let mut order: Vec<usize> = (0..t.ms.len()).filter(|&i| t.ms[i].status == "pending" && t.ms[i].src == r#"["",""]"#).collect();
        order.sort_by_key(|&i| (t.ms[i].round, t.ms[i].n));
        for i in order {
            let m = &mut t.ms[i];
            let (Some(a), Some(b)) = (m.a, m.b) else { continue };
            if busy.contains(&a) || busy.contains(&b) {
                continue;
            }
            busy.extend([a, b]);
            let decks = [t.es.iter().find(|e| e.account == a), t.es.iter().find(|e| e.account == b)]
                .map(|e| e.map_or(0, |e| serde_json::from_str::<Vec<Value>>(&e.decks).map_or(0, |d| d.len())));
            let mut s = Series::of(m);
            s.decks = decks.map(|k| vec!["ok".to_string(); k]);
            m.state = serde_json::to_string(&s).unwrap_or_default();
            to_accept(m, now);
            changed.insert(m.id);
            moved = true;
        }
        if !moved && t.t.format == "swiss" && t.ms.iter().all(|m| over(m)) && swiss_round(app, t).await? {
            moved = true;
        }
        if !moved {
            break;
        }
    }
    if t.ms.iter().all(|m| over(m)) {
        finish(app, t, now).await?;
    }
    Ok(())
}

fn to_accept(m: &mut tmatch::Model, now: i64) {
    let mut s = Series::of(m);
    s.acc = [false, false];
    m.state = serde_json::to_string(&s).unwrap_or_default();
    m.status = "accept".into();
    m.deadline = now + STEP_MS;
}

/// One match: the side sources of a bracket, byes, game results, the step deadlines and the start of a game.
async fn step(app: &AppRef, t: &mut T, i: usize, now: i64) -> Res<()> {
    let conquest = t.t.series == "conquest";
    let wins = wins_needed(t.t.best_of);
    let m = t.ms[i].clone();
    match m.status.as_str() {
        "pending" => {
            let src: Vec<String> = serde_json::from_str(&m.src).unwrap_or_default();
            if src.iter().any(|s| !s.is_empty()) {
                let ms = &t.ms;
                let outcome = |j: usize| {
                    let o = ms.get(j).filter(|o| over(o))?;
                    let loser = match o.winner {
                        Some(w) if o.a == Some(w) => o.b,
                        Some(_) => o.a,
                        None => None,
                    };
                    Some((o.winner, loser))
                };
                let side = |x: &str, fixed: Option<i64>| {
                    let j = x.get(1..).and_then(|j| j.parse::<usize>().ok());
                    let s = match (x.chars().next(), j) {
                        (Some('w'), Some(j)) => Side::Winner(j),
                        (Some('l'), Some(j)) => Side::Loser(j),
                        _ => return fixed.map_or(Slot::Empty, Slot::Known),
                    };
                    format::resolve(s, &[], &outcome)
                };
                let s = [side(src.first().map_or("", |s| s), m.a), side(src.get(1).map_or("", |s| s), m.b)];
                if s.contains(&Slot::Pending) {
                    return Ok(());
                }
                let known = |x: Slot| if let Slot::Known(p) = x { Some(p) } else { None };
                let m = &mut t.ms[i];
                (m.a, m.b, m.src) = (known(s[0]), known(s[1]), r#"["",""]"#.into());
            }
            let m = &mut t.ms[i];
            // a bye: the side that is there wins; nobody on either side: nobody wins
            if m.a.is_none() || m.b.is_none() {
                m.winner = m.a.or(m.b);
                m.status = "bye".into();
            }
        }
        "accept" if now >= m.deadline => {
            // who did not accept loses this game (both: one of them, drawn)
            let s = Series::of(&m);
            let missing: Vec<usize> = (0..2).filter(|&x| !s.acc[x]).collect();
            let loser = *missing.choose(&mut rand::thread_rng()).unwrap_or(&0);
            tracing::info!("tournament {}: match {}: no accept in time", t.t.id, m.id);
            forfeit(t, i, loser, now, conquest, wins);
        }
        "ban" if now >= m.deadline => {
            let mut s = Series::of(&m);
            for x in 0..2 {
                if s.ban[x].is_none() {
                    let d = *s.usable(1 - x).choose(&mut rand::thread_rng()).unwrap_or(&0);
                    ban(&mut s, x, d);
                }
            }
            let m = &mut t.ms[i];
            m.state = serde_json::to_string(&s).unwrap_or_default();
            to_pick(m, now);
        }
        "pick" => {
            let mut s = Series::of(&m);
            if now >= m.deadline {
                for x in 0..2 {
                    if s.pick[x].is_none() {
                        s.pick[x] = s.usable(x).first().copied();
                    }
                }
                t.ms[i].state = serde_json::to_string(&s).unwrap_or_default();
            }
            if s.pick.iter().all(Option::is_some) {
                start(app, t, i, now).await?;
            }
        }
        "playing" => {
            let s = Series::of(&m);
            let Some(g) = s.game.clone() else { return Ok(()) };
            if let Some(row) = played::Entity::find_by_id(&g).one(&app.db).await? {
                let w = match row.winner {
                    0 => row.p0,
                    1 => row.p1,
                    _ => None,
                };
                let side = w.and_then(|w| [m.a, m.b].iter().position(|p| *p == Some(w)));
                tgame::Entity::update_many()
                    .col_expr(tgame::Column::Winner, sea_orm::sea_query::Expr::value(w))
                    .col_expr(tgame::Column::Reason, sea_orm::sea_query::Expr::value(row.reason.clone()))
                    .filter(tgame::Column::Game.eq(&g))
                    .exec(&app.db)
                    .await?;
                result(t, i, side, false, now, conquest, wins);
            } else if !app.hub().games.contains_key(&g) && s.boot != app.tour.boot {
                // the server restarted during the game: it is played again
                tracing::info!("tournament {}: match {}: game {g} was lost in a restart", t.t.id, m.id);
                result(t, i, None, false, now, conquest, wins);
            }
        }
        _ => {}
    }
    Ok(())
}

fn ban(s: &mut Series, side: usize, deck: usize) {
    s.ban[side] = Some(deck);
    if let Some(d) = s.decks[1 - side].get_mut(deck) {
        *d = "banned".into();
    }
}

fn to_pick(m: &mut tmatch::Model, now: i64) {
    m.status = "pick".into();
    m.deadline = now + STEP_MS;
}

/// Side `loser` loses the coming game without playing it.
fn forfeit(t: &mut T, i: usize, loser: usize, now: i64, conquest: bool, wins: i64) {
    result(t, i, Some(1 - loser), true, now, conquest, wins);
}

/// A game's result (`w`: the winning side; None = played again): the score, the decks, the
/// next game or the end of the match.
fn result(t: &mut T, i: usize, w: Option<usize>, forfeit: bool, now: i64, conquest: bool, wins: i64) {
    let m = &mut t.ms[i];
    let mut s = Series::of(m);
    let [a, b] = s.record(w, forfeit, conquest, [m.score_a, m.score_b]);
    (m.score_a, m.score_b) = (a, b);
    m.state = serde_json::to_string(&s).unwrap_or_default();
    if a >= wins || b >= wins {
        m.winner = if a >= wins { m.a } else { m.b };
        m.status = "done".into();
        m.deadline = 0;
    } else {
        to_accept(m, now);
    }
}

/// Both picked: the game starts (a side that is offline or in another game loses it).
async fn start(app: &AppRef, t: &mut T, i: usize, now: i64) -> Res<()> {
    let conquest = t.t.series == "conquest";
    let wins = wins_needed(t.t.best_of);
    let m = t.ms[i].clone();
    let (Some(a), Some(b)) = (m.a, m.b) else { return Ok(()) };
    let away: Vec<usize> = {
        let hub = app.hub();
        [a, b].iter().enumerate().filter(|(_, p)| !hub.conns.contains_key(p) || hub.in_game.contains_key(p)).map(|(x, _)| x).collect()
    };
    if let Some(&x) = away.choose(&mut rand::thread_rng()) {
        tracing::info!("tournament {}: match {}: side {x} is away at the start", t.t.id, m.id);
        forfeit(t, i, x, now, conquest, wins);
        return Ok(());
    }
    let mut s = Series::of(&m);
    let (da, db) = (s.pick[0].unwrap_or(0), s.pick[1].unwrap_or(0));
    let deck = |p: i64, d: usize| {
        let v = t.decks_of(Some(p)).get(d).cloned().unwrap_or_default();
        json!({"hero": v["hero"], "cards": v["cards"]})
    };
    let Ok(rules) = packs::rules_for(app, &t.t.pack).await else {
        return Err(no("The game of this tournament is no longer on the server"));
    };
    let extra = json!({"tournament": t.t.id, "match": m.id, "tournament_name": t.t.name});
    match game::start_with(app.clone(), Mode::Tournament, rules, [(a, deck(a, da)), (b, deck(b, db))], extra).await {
        Some(g) => {
            s.n += 1;
            s.game = Some(g.clone());
            s.boot = app.tour.boot;
            tgame::Entity::insert(tgame::ActiveModel {
                game: sea_orm::Set(g),
                tournament: sea_orm::Set(t.t.id),
                match_id: sea_orm::Set(m.id),
                n: sea_orm::Set(s.n),
                deck_a: sea_orm::Set(da as i64),
                deck_b: sea_orm::Set(db as i64),
                winner: sea_orm::Set(None),
                reason: sea_orm::Set(String::new()),
            })
            .exec_without_returning(&app.db)
            .await?;
            let m = &mut t.ms[i];
            m.state = serde_json::to_string(&s).unwrap_or_default();
            m.status = "playing".into();
            m.deadline = 0;
        }
        None => to_accept(&mut t.ms[i], now), // could not start: asked again
    }
    Ok(())
}

/// All matches are done: the places.
async fn finish(app: &AppRef, t: &mut T, now: i64) -> Res<()> {
    let players: Vec<i64> = t.es.iter().map(|e| e.account).collect();
    let places = if t.t.format == "elimination" {
        format::elimination_places(&t.outs(), &players)
    } else {
        format::table_places(&t.standings(), t.t.format == "swiss")
    };
    for e in t.es.iter_mut() {
        e.place = places.get(&e.account).copied().unwrap_or(0);
    }
    t.t.status = "finished".into();
    t.t.ended = now;
    let names = names(&app.db, players).await?;
    let top: Vec<String> = t.es.iter().filter(|e| e.place == 1).filter_map(|e| names.get(&e.account).cloned()).collect();
    ev(app, &t.t, format!("Tournament {} finished: won by {}", t.t.name, top.join(", ")));
    Ok(())
}

// --- what players send ---------------------------------------------------------------------------

/// The checked decks of a join (`count` of them, each of another class, each valid in the
/// pack): [{name, hero, cards}].
fn check_decks(rules: &GameRules, decks: &Value, count: usize) -> Res<String> {
    let list = decks.as_array().ok_or_else(|| no("decks: a list"))?;
    if list.len() != count {
        return Err(TErr("tournament", format!("This tournament needs {count} decks")));
    }
    let rs = rules.rs;
    let mut classes = HashSet::new();
    let mut out = vec![];
    for d in list {
        let name = d.get("name").and_then(Value::as_str).unwrap_or("");
        let cards = d.get("cards").and_then(Value::as_array).map_or(0, |c| c.len());
        if name.chars().count() > 60 || cards > 200 {
            return Err(no("This deck is not valid"));
        }
        let deck = Deck::from_value_in(rs, d).ok_or_else(|| no("This deck is not valid"))?;
        if deck.cards.len() != cards {
            return Err(no("This deck has cards this game does not have"));
        }
        let why = deck.validate_in(rs);
        if !why.is_empty() {
            return Err(TErr("tournament", why));
        }
        if !classes.insert(rs.class_of_champion(&deck.hero).unwrap_or_default().to_string()) {
            return Err(no("Each deck must be of another class"));
        }
        out.push(json!({"name": name, "hero": deck.hero, "cards": deck.cards}));
    }
    Ok(Value::Array(out).to_string())
}

/// The format's options, checked and filled in.
fn options(format: &str, o: &Value) -> Res<String> {
    let v = match format {
        "round_robin" => {
            let r = num(o, "rounds").unwrap_or(1);
            if !(1..=2).contains(&r) {
                return Err(no("Round robin: 1 or 2 rounds"));
            }
            json!({"rounds": r})
        }
        "swiss" => {
            let r = num(o, "rounds");
            let d = num(o, "drop_after").unwrap_or(0);
            if r.is_some_and(|r| !(1..=10).contains(&r)) || !(0..=5).contains(&d) {
                return Err(no("Swiss: 1 to 10 rounds; drop after 0 (never) to 5 losses"));
            }
            json!({"rounds": r, "drop_after": d})
        }
        "elimination" => {
            let l = num(o, "losses").unwrap_or(1);
            if !(1..=2).contains(&l) {
                return Err(no("Elimination: 1 (single) or 2 (double) losses"));
            }
            json!({"losses": l})
        }
        "scheveningen" => json!({}),
        _ => return Err(no("No such format")),
    };
    Ok(v.to_string())
}

/// The options that can change (create and edit): name, format and options, bans, players,
/// deck reveal, spectators. Checked.
fn apply(t: &mut tour::Model, v: &Value) -> Res<()> {
    if let Some(n) = v.get("name") {
        let n = n.as_str().unwrap_or("").trim();
        if !(3..=40).contains(&n.chars().count()) {
            return Err(no("A name is 3 to 40 characters"));
        }
        t.name = n.into();
    }
    if v.get("format").is_some() || v.get("options").is_some() {
        if let Some(f) = v.get("format") {
            t.format = f.as_str().unwrap_or("").into();
        }
        let o = v.get("options").cloned().unwrap_or_else(|| serde_json::from_str(&t.options).unwrap_or(json!({})));
        t.options = options(&t.format, &o)?;
    }
    if v.get("bans").is_some() {
        t.bans = num(v, "bans").filter(|b| (0..=1).contains(b)).ok_or_else(|| no("Bans: 0 or 1"))?;
    }
    if v.get("max_players").is_some() {
        t.max_players = num(v, "max_players").filter(|n| (2..=128).contains(n)).ok_or_else(|| no("Players: 2 to 128"))?;
    }
    if v.get("min_players").is_some() {
        t.min_players = num(v, "min_players").ok_or_else(|| no("Players: 2 to 128"))?;
    }
    if !(2..=t.max_players).contains(&t.min_players) {
        return Err(no("The minimum of players is 2 up to the maximum"));
    }
    for (k, f) in [("deck_reveal", &mut t.deck_reveal), ("spectators", &mut t.spectators)] {
        if let Some(b) = v.get(k) {
            *f = b.as_bool().ok_or_else(|| no("deck_reveal, spectators: true or false"))?;
        }
    }
    Ok(())
}

fn check_start(start: i64, now: i64) -> Res<()> {
    if start < now + 11 * MINUTE || start > now + 14 * 24 * 60 * MINUTE {
        return Err(no("The start is from 11 minutes to 14 days from now"));
    }
    Ok(())
}

/// One of the tournament messages (`t_*`); answers and pushes go to the player through the hub.
pub async fn handle(app: &AppRef, me: i64, v: &Value) -> Res<()> {
    let kind = v["t"].as_str().unwrap_or("");
    let id = || num(v, "id").ok_or_else(|| no("id: which tournament"));
    let now = now_ms();
    match kind {
        "t_list" => list(app, me, v["tab"].as_str().unwrap_or("upcoming")).await,
        "t_get" => {
            let t = load(&app.db, id()?).await?;
            watch(app, t.t.id, me);
            send(app, me, json!({"t": "tournament", "tournament": full_json(app, &t, Some(me)).await?}));
            // the player's match step, if one waits (a reconnect)
            let names = names(&app.db, t.es.iter().map(|e| e.account)).await?;
            for m in t.ms.iter().filter(|m| t.t.status == "running" && BUSY.contains(&m.status.as_str())) {
                if let Some(side) = [m.a, m.b].iter().position(|p| *p == Some(me)) {
                    send(app, me, t_match_msg(&t, m, side, &names));
                }
            }
            Ok(())
        }
        "t_unwatch" => {
            if let Some(w) = app.tour.watchers.lock().unwrap_or_else(|e| e.into_inner()).get_mut(&id()?) {
                w.remove(&me);
            }
            Ok(())
        }
        "t_create" => create(app, me, v, now).await,
        "t_spectate" => {
            let mid = num(v, "match").ok_or_else(|| no("match: which one"))?;
            let m = tmatch::Entity::find_by_id(mid).one(&app.db).await?.ok_or_else(|| no("No such match"))?;
            let t = load(&app.db, m.tournament).await?;
            if !may_spectate(&t, me, &t.standings(), &t.outs()) {
                return Err(no("You may not watch this tournament's matches"));
            }
            let g = Series::of(&m).game.filter(|_| m.status == "playing").ok_or_else(|| no("This match is not being played now"))?;
            crate::spectate::add(app, &g, me, true).map_err(no)
        }
        "t_accept" | "t_ban" | "t_pick" => match_step(app, me, kind, v, now).await,
        "t_edit" | "t_reschedule" | "t_cancel" | "t_join" | "t_decks" | "t_leave" => change(app, me, kind, v, id()?, now).await,
        _ => Err(TErr("bad_request", format!("Unknown message {}", kind.chars().take(32).collect::<String>()))),
    }
}

async fn list(app: &AppRef, me: i64, tab: &str) -> Res<()> {
    let q = tour::Entity::find();
    let q = match tab {
        "upcoming" => q.filter(tour::Column::Status.is_in(ACTIVE)).order_by_asc(tour::Column::StartAt),
        "finished" => q.filter(tour::Column::Status.eq("finished")).order_by_desc(tour::Column::Ended),
        "closed" => q.filter(tour::Column::Status.is_in(["closed", "cancelled"])).order_by_desc(tour::Column::StartAt),
        _ => return Err(no("tab: upcoming, finished or closed")),
    };
    let rows = q.limit(100).all(&app.db).await?;
    let es = entrant::Entity::find().filter(entrant::Column::Tournament.is_in(rows.iter().map(|r| r.id))).all(&app.db).await?;
    let names = names(&app.db, rows.iter().map(|r| r.creator)).await?;
    let mut list = vec![];
    for r in &rows {
        let n = es.iter().filter(|e| e.tournament == r.id).count();
        let joined = es.iter().any(|e| e.tournament == r.id && e.account == me);
        list.push(summary(r, n, joined, names.get(&r.creator).map_or("?", |s| s), &pack_name(app, &r.pack).await));
    }
    send(app, me, json!({"t": "t_list", "tab": tab, "list": list}));
    Ok(())
}

/// `t_accept`, `t_ban`, `t_pick`: a step of the player's match.
async fn match_step(app: &AppRef, me: i64, kind: &str, v: &Value, now: i64) -> Res<()> {
    let mid = num(v, "match").ok_or_else(|| no("match: which one"))?;
    let tid = tmatch::Entity::find_by_id(mid).one(&app.db).await?.ok_or_else(|| no("No such match"))?.tournament;
    let _g = app.tour.lock.lock().await;
    let mut t = load(&app.db, tid).await?;
    let orig = t.clone();
    if t.t.status != "running" {
        return Err(no("The tournament is not running"));
    }
    let bans = t.t.bans;
    let i = t.ms.iter().position(|x| x.id == mid).ok_or_else(|| no("No such match"))?;
    let m = &mut t.ms[i];
    let side = [m.a, m.b].iter().position(|p| *p == Some(me)).ok_or_else(|| no("Not your match"))?;
    let mut s = Series::of(m);
    let deck = num(v, "deck").filter(|d| *d >= 0).map(|d| d as usize);
    match (kind, m.status.as_str()) {
        ("t_accept", "accept") => {
            s.acc[side] = true;
            if s.acc == [true, true] {
                if bans > 0 && s.ban.iter().any(Option::is_none) {
                    m.status = "ban".into();
                    m.deadline = now + STEP_MS;
                } else {
                    to_pick(m, now);
                }
            }
        }
        ("t_ban", "ban") => {
            if s.ban[side].is_some() {
                return Err(no("You already banned a deck"));
            }
            let d = deck.filter(|d| s.usable(1 - side).contains(d)).ok_or_else(|| no("No such deck to ban"))?;
            ban(&mut s, side, d);
            if s.ban.iter().all(Option::is_some) {
                to_pick(m, now);
            }
        }
        ("t_pick", "pick") => {
            if s.pick[side].is_some() {
                return Err(no("Your deck is already chosen"));
            }
            s.pick[side] = Some(deck.filter(|d| s.usable(side).contains(d)).ok_or_else(|| no("No such deck to pick"))?);
        }
        _ => return Err(no("Not now: the match is at another step")),
    }
    m.state = serde_json::to_string(&s).unwrap_or_default();
    commit(app, &mut t, &orig, HashSet::from([mid])).await.map(|_| ())
}

/// The creator's changes (`t_edit`, `t_reschedule`, `t_cancel`) and the players' (`t_join`,
/// `t_decks`, `t_leave`). The answer is the `tournament` push (the player watches it now).
async fn change(app: &AppRef, me: i64, kind: &str, v: &Value, id: i64, now: i64) -> Res<()> {
    let _g = app.tour.lock.lock().await;
    let mut t = load(&app.db, id).await?;
    let orig = t.clone();
    let creator = t.t.creator == me;
    let open = t.t.status == "open" && now < t.t.start_at - 10 * MINUTE;
    let joinable = matches!(t.t.status.as_str(), "open" | "locked") && now < t.t.start_at - MINUTE;
    let mine = t.entrant(me).is_some();
    let name = crate::db::name_of(&app.db, me).await?;
    let pev = |text: String| Event::new("tournament", text).user(me, &name).data(json!({"tournament": id}));
    if matches!(kind, "t_edit" | "t_reschedule" | "t_cancel") && !creator {
        return Err(no("Only the creator changes a tournament"));
    }
    let rules = || async { packs::rules_for(app, &t.t.pack).await.map_err(|_| no("The game of this tournament is no longer on the server")) };
    match kind {
        "t_edit" => {
            if !open {
                return Err(no("The rules are frozen 10 minutes before the start"));
            }
            let fixed = [
                ("pack", v.get("pack").is_some_and(|x| x.as_str() != Some(&t.t.pack))),
                ("series", v.get("series").is_some_and(|x| x.as_str() != Some(&t.t.series))),
                ("best_of", v.get("best_of").is_some_and(|_| num(v, "best_of") != Some(t.t.best_of))),
            ];
            if let Some((k, _)) = fixed.iter().find(|f| f.1) {
                return Err(TErr("tournament", format!("{k} is fixed after the creation")));
            }
            apply(&mut t.t, v)?;
            if t.t.bans != orig.t.bans && !t.es.is_empty() {
                return Err(no("Bans can't change once players have joined (their decks count on them)"));
            }
            if t.es.len() as i64 > t.t.max_players {
                return Err(no("More players have joined than that"));
            }
            if let Some(s) = num(v, "start_at").filter(|s| *s != t.t.start_at) {
                reschedule(&mut t.t, s, now)?;
            }
        }
        "t_reschedule" => {
            if !open {
                return Err(no("The start is frozen 10 minutes before it"));
            }
            reschedule(&mut t.t, num(v, "start_at").ok_or_else(|| no("start_at: unix ms"))?, now)?;
        }
        "t_cancel" => {
            if !ACTIVE.contains(&t.t.status.as_str()) {
                return Err(no("This tournament is over"));
            }
            t.t.status = "cancelled".into();
            t.t.ended = now;
            ev(app, &t.t, format!("{name} cancelled the tournament {}", t.t.name));
            watch(app, id, me);
            let busy: HashSet<i64> = t.ms.iter().filter(|m| BUSY.contains(&m.status.as_str())).map(|m| m.id).collect();
            save(app, &t, &orig).await?;
            return push(app, &t, &busy).await;
        }
        "t_join" => {
            if mine {
                return Err(no("You are in this tournament"));
            }
            if !joinable {
                return Err(no("Joining ended a minute before the start"));
            }
            if t.es.len() as i64 >= t.t.max_players {
                return Err(no("This tournament is full"));
            }
            let decks = check_decks(&*rules().await?, &v["decks"], deck_count(&t.t))?;
            let e = entrant::Model { tournament: id, account: me, decks, seed: -1, team: -1, place: 0, joined: now };
            e.clone().into_active_model().reset_all().insert(&app.db).await?;
            t.es.push(e);
            app.event(pev(format!("{name} joined the tournament {}", t.t.name)));
        }
        "t_decks" => {
            if !mine {
                return Err(no("You are not in this tournament"));
            }
            if !open {
                return Err(no("Decks are frozen 10 minutes before the start"));
            }
            let decks = check_decks(&*rules().await?, &v["decks"], deck_count(&t.t))?;
            if let Some(e) = t.es.iter_mut().find(|e| e.account == me) {
                e.decks = decks;
            }
        }
        _ => {
            if !mine {
                return Err(no("You are not in this tournament"));
            }
            if !joinable {
                return Err(no("Leaving ended a minute before the start"));
            }
            entrant::Entity::delete_by_id((id, me)).exec(&app.db).await?;
            t.es.retain(|e| e.account != me);
            app.event(pev(format!("{name} left the tournament {}", t.t.name)));
        }
    }
    watch(app, id, me);
    if !commit(app, &mut t, &orig, HashSet::new()).await? {
        // nothing changed (an edit to the same values): the answer all the same
        send(app, me, json!({"t": "tournament", "tournament": full_json(app, &t, Some(me)).await?}));
    }
    Ok(())
}

fn send(app: &AppRef, me: i64, v: Value) {
    app.hub().send(me, &v);
}

fn reschedule(t: &mut tour::Model, start: i64, now: i64) -> Res<()> {
    if start <= t.start_at {
        return Err(no("A tournament can only move later"));
    }
    if start > now + 14 * 24 * 60 * MINUTE {
        return Err(no("The start is at most 14 days from now"));
    }
    t.start_at = start;
    Ok(())
}

async fn create(app: &AppRef, me: i64, v: &Value, now: i64) -> Res<()> {
    let pack = v["pack"].as_str().ok_or_else(|| no("pack: the game's rules_hash"))?;
    let rules = packs::playable(app, Some(pack), None).await.map_err(|(_, text)| TErr("tournament", text))?.0;
    let series = v["series"].as_str().filter(|s| matches!(*s, "conquest" | "lhs")).ok_or_else(|| no("Series: conquest or lhs"))?;
    let best_of = num(v, "best_of").filter(|b| matches!(b, 1 | 3 | 5 | 7)).ok_or_else(|| no("Best of 1, 3, 5 or 7"))?;
    let start_at = num(v, "start_at").ok_or_else(|| no("start_at: unix ms"))?;
    check_start(start_at, now)?;
    for k in ["name", "format", "max_players"] {
        if v.get(k).is_none() {
            return Err(TErr("tournament", format!("{k} is missing")));
        }
    }
    let mut t = tour::Model {
        id: 0, name: String::new(), creator: me, pack: rules.rules_hash.clone(), format: String::new(), options: "{}".into(), series: series.into(),
        best_of, bans: 0, start_at, max_players: 2, min_players: 2, deck_reveal: false, spectators: false, status: "open".into(), reason: String::new(),
        created: now, ended: 0,
    };
    apply(&mut t, v)?;
    let _g = app.tour.lock.lock().await;
    let not_over = tour::Entity::find()
        .filter(tour::Column::Creator.eq(me))
        .filter(tour::Column::Status.is_in(ACTIVE))
        .count(&app.db)
        .await?;
    if not_over >= MAX_OPEN {
        return Err(no("You have 3 tournaments that are not over: wait for one to end"));
    }
    let today = tour::Entity::find()
        .filter(Condition::all().add(tour::Column::Creator.eq(me)).add(tour::Column::Created.gt(now - 24 * 60 * MINUTE)))
        .count(&app.db)
        .await?;
    if today >= MAX_PER_DAY {
        return Err(no("10 tournaments a day at most"));
    }
    let mut am = t.into_active_model().reset_all();
    am.id = NotSet;
    let t = am.insert(&app.db).await?;
    let name = crate::db::name_of(&app.db, me).await?;
    app.event(
        Event::new("tournament", format!("{name} created the tournament {} ({}, {})", t.name, t.format, packs::short_name(&rules)))
            .user(me, &name)
            .data(json!({"tournament": t.id})),
    );
    watch(app, t.id, me);
    let t = load(&app.db, t.id).await?;
    send(app, me, json!({"t": "tournament", "tournament": full_json(app, &t, Some(me)).await?}));
    Ok(())
}

/// May `account` see the replay of `game`: a tournament game, when the decks are revealed or the
/// tournament is over, or by its players and the creator. (For `replays::can_view`.)
pub async fn replay_allowed(app: &AppRef, account: i64, game: &str) -> bool {
    let r = async {
        let Some(g) = tgame::Entity::find_by_id(game).one(&app.db).await? else { return Ok::<_, DbErr>(false) };
        let Some(t) = tour::Entity::find_by_id(g.tournament).one(&app.db).await? else { return Ok(false) };
        let m = tmatch::Entity::find_by_id(g.match_id).one(&app.db).await?;
        let player = m.is_some_and(|m| m.a == Some(account) || m.b == Some(account));
        Ok(t.deck_reveal || matches!(t.status.as_str(), "finished" | "cancelled") || t.creator == account || player)
    };
    r.await.unwrap_or(false)
}

// --- the admin panel ---------------------------------------------------------------------------

/// `/admin/api/tournaments?status=`: the list (all statuses when none given), newest first.
pub async fn admin_list(app: &AppRef, status: Option<&str>) -> Result<Value, DbErr> {
    let mut q = tour::Entity::find().order_by_desc(tour::Column::StartAt);
    if let Some(s) = status.filter(|s| !s.is_empty()) {
        q = q.filter(tour::Column::Status.eq(s));
    }
    let rows = q.limit(500).all(&app.db).await?;
    let es = entrant::Entity::find().filter(entrant::Column::Tournament.is_in(rows.iter().map(|r| r.id))).all(&app.db).await?;
    let names = names(&app.db, rows.iter().map(|r| r.creator).chain(es.iter().filter(|e| e.place > 0 && e.place <= 3).map(|e| e.account)))
        .await
        .map_err(|TErr(_, e)| DbErr::Custom(e))?;
    let mut list = vec![];
    for r in &rows {
        let mine: Vec<&entrant::Model> = es.iter().filter(|e| e.tournament == r.id).collect();
        let mut v = summary(r, mine.len(), false, names.get(&r.creator).map_or("?", |s| s), &pack_name(app, &r.pack).await);
        let mut top: Vec<(i64, &str)> = mine.iter().filter(|e| e.place > 0 && e.place <= 3).map(|e| (e.place, names.get(&e.account).map_or("?", |s| s))).collect();
        top.sort();
        v["top"] = json!(top.iter().map(|(p, n)| json!({"place": p, "name": n})).collect::<Vec<_>>());
        v["creator_id"] = json!(r.creator);
        list.push(v);
    }
    Ok(json!({"list": list}))
}

/// `/admin/api/tournaments/{id}`: everything, every deck shown.
pub async fn admin_get(app: &AppRef, id: i64) -> Result<Option<Value>, DbErr> {
    match load(&app.db, id).await {
        Ok(t) => full_json(app, &t, None).await.map(Some).map_err(|TErr(_, e)| DbErr::Custom(e)),
        Err(TErr("server", e)) => Err(DbErr::Custom(e)),
        Err(_) => Ok(None),
    }
}

/// The admin cancels a tournament; false: no such tournament or it is over.
pub async fn admin_cancel(app: &AppRef, id: i64, by: &str) -> Result<bool, DbErr> {
    let _g = app.tour.lock.lock().await;
    let r = async {
        let mut t = load(&app.db, id).await?;
        if !ACTIVE.contains(&t.t.status.as_str()) {
            return Ok(false);
        }
        let orig = t.clone();
        t.t.status = "cancelled".into();
        t.t.ended = now_ms();
        let busy: HashSet<i64> = t.ms.iter().filter(|m| BUSY.contains(&m.status.as_str())).map(|m| m.id).collect();
        save(app, &t, &orig).await?;
        push(app, &t, &busy).await?;
        ev(app, &t.t, format!("{by} (admin) cancelled the tournament {}", t.t.name));
        Ok(true)
    };
    r.await.map_err(|TErr(_, e)| DbErr::Custom(e))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn series(k: usize) -> Series {
        Series { decks: [vec!["ok".into(); k], vec!["ok".into(); k]], ..Default::default() }
    }

    #[test]
    fn conquest_spends_the_winning_deck() {
        let mut s = series(2);
        s.pick = [Some(0), Some(1)];
        let sc = s.record(Some(0), false, true, [0, 0]);
        assert_eq!(sc, [1, 0]);
        assert_eq!(s.decks[0], ["won", "ok"]);
        assert_eq!(s.decks[1], ["ok", "ok"], "the losing deck stays");
        assert_eq!(s.pick, [None, None], "both pick again");
        assert_eq!(s.usable(0), [1]);
        // a forfeit: a point, no deck spent
        let sc = s.record(Some(1), true, true, sc);
        assert_eq!((sc, s.usable(1).len()), ([1, 1], 2));
    }

    #[test]
    fn lhs_the_loser_deck_is_out_the_winner_keeps_its_deck() {
        let mut s = series(3);
        s.pick = [Some(2), Some(0)];
        let sc = s.record(Some(0), false, false, [0, 0]);
        assert_eq!(sc, [1, 0]);
        assert_eq!(s.decks[1], ["lost", "ok", "ok"]);
        assert_eq!(s.decks[0], ["ok", "ok", "ok"]);
        assert_eq!((s.keep, s.pick), (Some(0), [Some(2), None]), "the winner keeps its deck, the loser picks");
        // the keeper loses by forfeit: its kept deck is out, nobody keeps
        let sc = s.record(Some(1), true, false, sc);
        assert_eq!(sc, [1, 1]);
        assert_eq!(s.decks[0], ["ok", "ok", "lost"]);
        assert_eq!((s.keep, s.pick), (None, [None, None]));
        // a game with no winner: played again, nothing changes
        let before = s.clone();
        s.record(None, false, false, sc);
        assert_eq!(s, before);
    }
}
