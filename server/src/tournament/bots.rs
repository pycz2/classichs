//! Tournament bots (0.66): a pool of accounts "TBot_<Level>_<n>" (`State::bot_pool` a level, 2 by
//! default, made when first needed) that a tournament's creator adds as entrants (`t_add_bots`).
//! They never queue and are not the admin's or the auto-bots: they live only in tournaments. A bot
//! is busy while it is an entrant of a tournament that is not over (open … running), free again
//! once it is finished, cancelled or closed. The scheduler does their match steps at once
//! (`steps`); a connection of their own in this process (`bots::runtime::tournament`, started by
//! `supervise` for every running tournament, also after a restart) plays their games. A match
//! with a bot starts when a slot is free (`State::slots`) and the bots think in their own places
//! (`State::think`), so bot games leave a small host's CPU to the human games.

use super::{deck_count, no, ACTIVE, Res, Series, T};
use crate::bots::brain::Level;
use crate::bots::cards::{class_of, Library};
use crate::bots::runtime::{self, Auth, Ctx};
use crate::bots::transport::Transport;
use crate::bots::LEVELS;
use crate::entity::tournament::{self as tour, entrant};
use crate::packs::GameRules;
use crate::AppRef;
use rand::seq::SliceRandom;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::sync::Arc;

pub const PREFIX: &str = "TBot_";

/// The level of a pool account by its name ("TBot_Hard_2": hard).
pub fn level_of(name: &str) -> Option<Level> {
    Level::parse(&name.strip_prefix(PREFIX)?.split('_').next()?.to_lowercase())
}

fn cap(s: &str) -> String {
    s[..1].to_uppercase() + &s[1..]
}

/// The pool: (account, name, level), made when missing.
pub async fn pool(app: &AppRef) -> Res<Vec<(i64, String, Level)>> {
    let per = app.tour.bot_pool.load(std::sync::atomic::Ordering::Relaxed);
    {
        let p = app.tour.pool.lock().unwrap_or_else(|e| e.into_inner());
        if p.len() == per * LEVELS.len() {
            return Ok(p.clone());
        }
    }
    let mut out = vec![];
    for l in LEVELS {
        for n in 1..=per {
            let name = format!("{PREFIX}{}_{n}", cap(l));
            let id = match crate::db::id_by_name(&app.db, &name).await? {
                Some(id) => id,
                // (made by a call at the same time: then it is there)
                None => match crate::bots::auto::make(app, &name).await {
                    Some(id) => id,
                    None => crate::db::id_by_name(&app.db, &name).await?.ok_or_else(|| no("A tournament bot could not be made"))?,
                },
            };
            out.push((id, name, Level::parse(l).unwrap_or(Level::Medium)));
        }
    }
    *app.tour.pool.lock().unwrap_or_else(|e| e.into_inner()) = out.clone();
    Ok(out)
}

/// The pool's accounts that are entrants of a tournament not over.
async fn busy(app: &AppRef, ids: &[i64]) -> Res<HashSet<i64>> {
    let es = entrant::Entity::find().filter(entrant::Column::Account.is_in(ids.iter().copied())).all(&app.db).await?;
    let active: HashSet<i64> = tour::Entity::find()
        .filter(tour::Column::Id.is_in(es.iter().map(|e| e.tournament)))
        .filter(tour::Column::Status.is_in(ACTIVE))
        .all(&app.db)
        .await?
        .into_iter()
        .map(|t| t.id)
        .collect();
    Ok(es.iter().filter(|e| active.contains(&e.tournament)).map(|e| e.account).collect())
}

/// The free bots of each level, in the pool's order.
pub async fn free(app: &AppRef) -> Res<Vec<(i64, String, Level)>> {
    let p = pool(app).await?;
    let b = busy(app, &p.iter().map(|x| x.0).collect::<Vec<_>>()).await?;
    Ok(p.into_iter().filter(|x| !b.contains(&x.0)).collect())
}

/// `{easy: n, medium: n, hard: n, superhard: n}`: the free bots a level.
pub async fn free_json(app: &AppRef) -> Res<Value> {
    let f = free(app).await?;
    Ok(Value::Object(LEVELS.iter().map(|l| (l.to_string(), json!(f.iter().filter(|x| x.2.name() == *l).count()))).collect()))
}

/// The library of a tournament's game (Classic's own decks, or the pack's).
fn library(pack: &str) -> &'static Library {
    Library::of_pack(Some(pack))
}

/// A bot's decks for a tournament: its count, each of another class, picked at random from the
/// game's bot decks (templates), else starter decks; checked and copied as a player's.
pub fn decks(rules: &GameRules, t: &tour::Model) -> Res<String> {
    let k = deck_count(t);
    let lib = library(&rules.rules_hash);
    let rs = rules.rs;
    let mut all = lib.decks.clone();
    all.shuffle(&mut rand::thread_rng());
    let mut classes = HashSet::new();
    let mut out = vec![];
    for d in &all {
        if out.len() < k && classes.insert(class_of(rs, &d.hero)) {
            out.push(json!({"name": d.name, "hero": d.hero, "cards": d.cards}));
        }
    }
    let mut starters: Vec<_> = rs.classes.iter().filter(|c| c.playable && !c.champion.is_empty() && !classes.contains(&c.id)).collect();
    starters.shuffle(&mut rand::thread_rng());
    for c in starters {
        if out.len() < k {
            out.push(json!({"name": format!("{} starter", cap(&c.id.to_lowercase())), "hero": c.champion, "cards": classichs_engine::deck::basic_in(rs, &c.id)}));
        }
    }
    if out.len() < k {
        return Err(no("This game has too few decks of different classes for bots"));
    }
    super::check_decks(rules, &Value::Array(out), k)
}

/// How a level rates a deck: the mean draft score of its cards.
fn rating(lib: &Library, d: &Value) -> f64 {
    let class = class_of(lib.rs, d["hero"].as_str().unwrap_or(""));
    let cards = d["cards"].as_array().cloned().unwrap_or_default();
    cards.iter().map(|c| lib.tier(c.as_str().unwrap_or(""), &class)).sum::<f64>() / cards.len().max(1) as f64
}

/// The bots of a match do their steps at once: accept, ban (Easy: a random deck; the others the
/// opponent's deck they rate strongest), pick (a random usable deck).
pub(super) fn steps(t: &mut T, i: usize, now: i64) {
    let lib = library(&t.t.pack);
    let bans = t.t.bans;
    for _ in 0..4 {
        let m = &t.ms[i];
        if !matches!(m.status.as_str(), "accept" | "ban" | "pick") {
            return;
        }
        let p = [m.a, m.b];
        let mut s = Series::of(m);
        let mut acted = false;
        for side in 0..2 {
            let Some(level) = p[side].and_then(|a| t.bots.get(&a).copied()) else { continue };
            let m = &t.ms[i];
            let (kind, deck) = match m.status.as_str() {
                "accept" if !s.acc[side] => ("t_accept", None),
                "ban" if s.ban[side].is_none() => {
                    let theirs = t.decks_of(p[1 - side]);
                    let usable = s.usable(1 - side);
                    let d = if level == Level::Easy {
                        usable.choose(&mut rand::thread_rng()).copied()
                    } else {
                        let r = |x: usize| theirs.get(x).map_or(0.0, |d| rating(lib, d));
                        usable.iter().copied().max_by(|&x, &y| r(x).total_cmp(&r(y)))
                    };
                    ("t_ban", d)
                }
                "pick" if s.pick[side].is_none() => ("t_pick", s.usable(side).choose(&mut rand::thread_rng()).copied()),
                _ => continue,
            };
            let m = &mut t.ms[i];
            if super::act(m, &mut s, side, kind, deck, bans, now).is_ok() {
                m.state = serde_json::to_string(&s).unwrap_or_default();
                acted = true;
            }
        }
        if !acted {
            return;
        }
    }
}

/// Every bot of a running tournament has its connection playing its games (the scheduler's tick:
/// at start, after a restart, after a lost connection). A connection ends with its tournament.
pub async fn supervise(app: &AppRef) {
    let r = async {
        let running: Vec<i64> = tour::Entity::find().filter(tour::Column::Status.eq("running")).all(&app.db).await?.into_iter().map(|t| t.id).collect();
        if running.is_empty() {
            return Ok::<_, super::TErr>(()); // (no accounts made on an idle server)
        }
        let p = pool(app).await?;
        let es = entrant::Entity::find()
            .filter(entrant::Column::Tournament.is_in(running))
            .filter(entrant::Column::Account.is_in(p.iter().map(|x| x.0)))
            .all(&app.db)
            .await?;
        for e in es {
            let Some((id, name, level)) = p.iter().find(|x| x.0 == e.account).cloned() else { continue };
            let mut tasks = app.tour.bot_tasks.lock().unwrap_or_else(|e| e.into_inner());
            if tasks.get(&id).is_some_and(|h| !h.is_finished()) {
                continue;
            }
            let app2 = app.clone();
            let h = tokio::spawn(async move {
                if let Err(e) = play(&app2, id, &name, level).await {
                    tracing::info!("tournament bot {name}: {e}");
                    app2.bots.status.error(-id, e);
                }
            });
            tasks.insert(id, h.abort_handle());
        }
        Ok(())
    };
    if let Err(super::TErr(_, e)) = r.await {
        tracing::error!("tournament bots: {e}");
    }
}

/// Is the account an entrant of a running tournament?
async fn in_running(app: &AppRef, account: i64) -> bool {
    let r = async {
        let ts: Vec<i64> = entrant::Entity::find().filter(entrant::Column::Account.eq(account)).all(&app.db).await?.iter().map(|e| e.tournament).collect();
        Ok::<_, sea_orm::DbErr>(tour::Entity::find().filter(tour::Column::Id.is_in(ts)).filter(tour::Column::Status.eq("running")).one(&app.db).await?.is_some())
    };
    r.await.unwrap_or(true) // (a database hiccup does not end a bot mid-tournament)
}

/// One bot's connection: logs in through this process and plays until its tournament is over.
async fn play(app: &AppRef, account: i64, name: &str, level: Level) -> Result<(), String> {
    let token = crate::db::new_session(&app.db, account, "game", 86400, "").await.map_err(|e| e.to_string())?;
    let ctx = Ctx { id: -account, name: name.to_string(), status: app.bots.status.clone(), think: app.tour.think.clone(), app: Some(app.clone()), pace: false };
    let a = app.clone();
    let connect: runtime::ConnectFn = Arc::new(move || {
        let a = a.clone();
        Box::pin(async move { Ok(Transport::local(&a)) })
    });
    let a = app.clone();
    let keep = Arc::new(move || {
        let a = a.clone();
        Box::pin(async move { in_running(&a, account).await }) as runtime::BoxFut<bool>
    });
    let a = app.clone();
    let cards = Arc::new(move |m: Value| {
        let a = a.clone();
        Box::pin(async move { super::bot_cards(&a, m["match"].as_i64().unwrap_or(-1), account).await }) as runtime::BoxFut<Vec<String>>
    });
    runtime::tournament(&ctx, &connect, &Auth::Token(token), level, keep, cards).await
}

/// The bots a level of the pool that `add` may take now (free ones only), the first `count`.
pub async fn take(app: &AppRef, level: &str, count: usize) -> Res<Vec<(i64, String)>> {
    let f: Vec<(i64, String)> = free(app).await?.into_iter().filter(|x| x.2.name() == level).map(|x| (x.0, x.1)).collect();
    if f.len() < count {
        return Err(super::TErr("tournament", format!("Only {} bots of this level are free now", f.len())));
    }
    Ok(f.into_iter().take(count).collect())
}
