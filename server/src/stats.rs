//! HSReplay-like statistics (the admin's Statistics page): every finished game with a winner adds
//! to aggregated rows (M11: stats_class, stats_deck, stats_card, stats_decks, stats_names; M12: stats_matchup); the
//! page only reads them. A game's facts come from its replay, played again in the rules engine:
//! the classes, the decks, the cards played and the opening hands kept or replaced.
//! Dimensions: the pack (rules_hash), the mode, the player's bracket at the game's start, whether a
//! bot played, and UTC calendar buckets (hour, day, week from Monday, month, year, all time).
//! Replays kept before the statistics existed are added once in the background (`backfill`).
//! server/README.md, "Statistics".

use crate::bots::auto::is_bot_name;
use crate::bots::cards::Library;
use crate::db::{self, DbResult};
use crate::entity::{arena, pack, replay};
use crate::events::Event;
use crate::packs::{self, GameRules};
use crate::ranked::{self, Mode};
use crate::{replays, AppRef};
use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use classichs_engine::ruleset::Ruleset;
use classichs_engine::Game;
use sea_orm::{ColumnTrait, ConnectionTrait, DbBackend, EntityTrait, QueryFilter, QueryOrder, QueryResult, QuerySelect, Statement, TransactionTrait};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;

pub const PERIODS: [&str; 6] = ["hour", "day", "week", "month", "year", "all"];
/// The bracket of the modes without one, and of ranked and Arena games added by the backfill
/// (a replay has no rank or run record).
pub const ALL: &str = "all";
pub const UNKNOWN: &str = "unknown";
/// Deck and card rows of hours and days older than this are deleted (weeks, months, years and all
/// time stay, and the class and matchup rows of every period: the charts and past views).
pub const KEEP_HOURS: i64 = 48;
pub const KEEP_DAYS: i64 = 400;
/// server_settings: "done", or the backfill's place "until ended game" (it resumes after a restart).
pub const BACKFILL: &str = "stats_backfill";
/// The same for the matchup rows (M12) of the games counted before them.
pub const MATCHUP_BACKFILL: &str = "stats_matchup_backfill";
const BATCH: u64 = 20;

// --- dimensions -----------------------------------------------------------------------------

/// The UTC buckets of a time (seconds), in PERIODS order: "2026-11-10T14", "2026-11-10", the
/// week's Monday "2026-11-09", "2026-11", "2026", "all".
pub fn buckets(t: i64) -> [String; 6] {
    let days = t.div_euclid(86_400);
    let (y, m, d) = civil(days);
    let (wy, wm, wd) = civil(days - (days + 3).rem_euclid(7)); // 1970-01-01 was a Thursday
    [
        format!("{y:04}-{m:02}-{d:02}T{:02}", t.rem_euclid(86_400) / 3600),
        format!("{y:04}-{m:02}-{d:02}"),
        format!("{wy:04}-{wm:02}-{wd:02}"),
        format!("{y:04}-{m:02}"),
        format!("{y:04}"),
        ALL.into(),
    ]
}

/// Days since 1970-01-01 → (year, month, day) (H. Hinnant's civil_from_days).
fn civil(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let (era, doe) = (z.div_euclid(146_097), z.rem_euclid(146_097));
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (d, m) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

/// Ranked: "Legend" (rank 0), "1-5", "6-10", … by the rank at the game's start.
pub fn rank_bracket(rank: i64) -> String {
    if rank <= 0 {
        return "Legend".into();
    }
    let lo = (rank - 1) / 5 * 5 + 1;
    format!("{lo}-{}", lo + 4)
}

/// Arena: by the run's wins before the game.
pub fn arena_bracket(wins: i64) -> &'static str {
    match wins {
        ..=2 => "0-2",
        3..=5 => "3-5",
        _ => "6+",
    }
}

/// Both players' brackets now (before the game's result changes them).
pub async fn brackets(c: &impl ConnectionTrait, mode: Mode, rules: &GameRules, ids: [i64; 2]) -> DbResult<[String; 2]> {
    let mut out = [ALL.to_string(), ALL.to_string()];
    for (p, id) in ids.iter().enumerate() {
        match mode {
            Mode::Ranked => out[p] = rank_bracket(db::standing(c, *id, &rules.id, &rules.ladder).await?.rank),
            Mode::Arena => out[p] = arena_bracket(arena::Entity::find_by_id(*id).one(c).await?.map_or(0, |r| r.wins)).into(),
            _ => {}
        }
    }
    Ok(out)
}

/// A deck's id: the hash of its class and sorted cards.
pub fn deck_id(class: &str, cards: &[String]) -> String {
    let mut v = cards.to_vec();
    v.sort();
    Sha256::digest(format!("{class}:{}", v.join(",")).as_bytes()).iter().take(8).map(|b| format!("{b:02x}")).collect()
}

// --- a game's facts -----------------------------------------------------------------------------

#[derive(Debug, Default)]
pub struct Side {
    pub name: String,
    pub class: String,
    pub hero: String,
    pub cards: Vec<String>,
    pub won: bool,
    /// Times each card of the deck was played.
    pub played: HashMap<String, i64>,
    /// The deck's cards in the opening hand, by copies kept and replaced.
    pub kept: HashMap<String, i64>,
    pub replaced: HashMap<String, i64>,
}

#[derive(Debug)]
pub struct Facts {
    pub pack: String,
    pub mode: String,
    pub ended: i64,
    pub sides: [Side; 2],
}

impl Facts {
    pub fn bots(&self) -> bool {
        self.sides.iter().any(|s| is_bot_name(&s.name))
    }
}

pub const NO_WINNER: &str = "no winner";

/// Plays a replay (replays.rs) again: who played what, and the mulligans.
pub fn facts(rs: &'static Ruleset, r: &Value) -> Result<Facts, String> {
    let winner = r["result"]["winner"].as_i64().unwrap_or(-1);
    if !(0..=1).contains(&winner) {
        return Err(NO_WINNER.into());
    }
    let mut sides: [Side; 2] = Default::default();
    for (p, s) in sides.iter_mut().enumerate() {
        let pl = &r["players"][p];
        s.name = pl["name"].as_str().unwrap_or_default().into();
        s.hero = pl["hero"].as_str().unwrap_or_default().into();
        s.cards = pl["cards"].as_array().into_iter().flatten().filter_map(|c| c.as_str().map(String::from)).collect();
        if !rs.has(&s.hero) || !s.cards.iter().all(|c| rs.has(c)) {
            return Err(format!("player {p}: a card this pack does not have"));
        }
        s.class = rs.card(&s.hero).card_class.clone();
        s.won = winner == p as i64;
    }
    let (seed, first) = (r["seed"].as_i64().unwrap_or(0), r["first"].as_i64().unwrap_or(-1));
    let mut g = catch_unwind(|| Game::new_in(rs, &sides[0].hero, &sides[0].cards, &sides[1].hero, &sides[1].cards, seed, first, true))
        .map_err(|_| "the game does not start".to_string())?;
    let deck: [HashSet<String>; 2] = std::array::from_fn(|p| sides[p].cards.iter().cloned().collect());
    for (n, a) in r["actions"].as_array().into_iter().flatten().enumerate() {
        let p = a["player"].as_u64().unwrap_or(9) as usize;
        if p < 2 {
            let card = |e: Option<i64>| e.and_then(|e| g.ent(e)).map(|e| e.card_id.to_string()).filter(|c| deck[p].contains(c));
            match a["type"].as_str() {
                Some("mulligan") => {
                    let out: HashSet<i64> = a["replace"].as_array().into_iter().flatten().filter_map(Value::as_i64).collect();
                    for &e in &g.players[p].hand {
                        if let Some(c) = card(Some(e)) {
                            let m = if out.contains(&e) { &mut sides[p].replaced } else { &mut sides[p].kept };
                            *m.entry(c).or_default() += 1;
                        }
                    }
                }
                Some("play") => {
                    if let Some(c) = card(a["entity"].as_i64()) {
                        *sides[p].played.entry(c).or_default() += 1;
                    }
                }
                _ => {}
            }
        }
        if !catch_unwind(AssertUnwindSafe(|| g.apply(a).ok)).unwrap_or(false) {
            return Err(format!("action {n} does not apply: {a}"));
        }
    }
    Ok(Facts { pack: r["pack"].as_str().unwrap_or_default().into(), mode: r["mode"].as_str().unwrap_or_default().into(), ended: r["ended"].as_i64().unwrap_or(0), sides })
}

// --- writing ---------------------------------------------------------------------------------------

/// Rows to add to one table: key values → counts (summed when both players share a row).
struct Rows {
    table: &'static str,
    keys: &'static [&'static str],
    vals: &'static [&'static str],
    rows: Vec<(Vec<sea_orm::Value>, Vec<i64>)>,
    at: HashMap<String, usize>,
}

impl Rows {
    fn new(table: &'static str, keys: &'static [&'static str], vals: &'static [&'static str]) -> Rows {
        Rows { table, keys, vals, rows: vec![], at: HashMap::new() }
    }

    fn add(&mut self, key: Vec<sea_orm::Value>, v: &[i64]) {
        match self.at.get(&format!("{key:?}")) {
            Some(&i) => self.rows[i].1.iter_mut().zip(v).for_each(|(a, b)| *a += b),
            None => {
                self.at.insert(format!("{key:?}"), self.rows.len());
                self.rows.push((key, v.to_vec()));
            }
        }
    }

    async fn write(self, c: &impl ConnectionTrait) -> DbResult<()> {
        let n = self.keys.len() + self.vals.len();
        let cols = self.keys.iter().chain(self.vals).copied().collect::<Vec<_>>().join(", ");
        let set = self.vals.iter().map(|v| format!("{v} = {v} + excluded.{v}")).collect::<Vec<_>>().join(", ");
        let one = format!("({})", vec!["?"; n].join(", "));
        for chunk in self.rows.chunks(30_000 / n) {
            let sql = format!(
                "INSERT INTO {} ({cols}) VALUES {} ON CONFLICT ({}) DO UPDATE SET {set}",
                self.table,
                vec![one.as_str(); chunk.len()].join(", "),
                self.keys.join(", ")
            );
            let values = chunk.iter().flat_map(|(k, v)| k.iter().cloned().chain(v.iter().map(|x| (*x).into())));
            c.execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite, sql, values)).await?;
        }
        Ok(())
    }
}

const CLASS_KEY: &[&str] = &["pack", "period", "bucket", "mode", "bracket", "bots", "class"];
const DECK_KEY: &[&str] = &["pack", "period", "bucket", "mode", "bracket", "bots", "class", "deck"];
const CARD_KEY: &[&str] = &["pack", "period", "bucket", "mode", "bracket", "bots", "class", "card"];
const MATCHUP_KEY: &[&str] = &["pack", "period", "bucket", "mode", "bracket", "bots", "class", "opp"];
const CARD_VALS: &[&str] =&["decks", "copies", "deck_wins", "played", "played_wins", "plays", "kept", "replaced", "kept_wins"];

/// Whether deck and card rows of this bucket are still kept (`prune`).
fn fresh(period: &str, bucket: &str, now: i64) -> bool {
    match period {
        "hour" => bucket >= buckets(now - KEEP_HOURS * 3600)[0].as_str(),
        "day" => bucket >= buckets(now - KEEP_DAYS * 86_400)[1].as_str(),
        _ => true,
    }
}

/// Adds one game (both players) to the statistics.
pub async fn write(c: &impl ConnectionTrait, f: &Facts, brackets: &[String; 2]) -> DbResult<()> {
    add(c, f, brackets, true).await
}

/// The matchup rows of one game only (the matchup backfill).
async fn write_matchups(c: &impl ConnectionTrait, f: &Facts, brackets: &[String; 2]) -> DbResult<()> {
    let mut m = Rows::new("stats_matchup", MATCHUP_KEY, &["games", "wins"]);
    let (mirror, bots) = (f.sides[0].class == f.sides[1].class, i64::from(f.bots()));
    for (period, bucket) in PERIODS.iter().zip(buckets(f.ended)) {
        for (p, s) in f.sides.iter().enumerate() {
            let key = vec![f.pack.clone().into(), (*period).into(), bucket.clone().into(), f.mode.clone().into(), brackets[p].clone().into(), bots.into(),
                           s.class.clone().into(), f.sides[1 - p].class.clone().into()];
            m.add(key, &[1, if mirror { 0 } else { i64::from(s.won) }]);
        }
    }
    m.write(c).await
}

async fn add(c: &impl ConnectionTrait, f: &Facts, brackets: &[String; 2], matchups: bool) -> DbResult<()> {
    let now = ranked::now();
    let (mut class, mut deck, mut card) =
        (Rows::new("stats_class", CLASS_KEY, &["games", "wins", "mirrors"]), Rows::new("stats_deck", DECK_KEY, &["games", "wins"]), Rows::new("stats_card", CARD_KEY, CARD_VALS));
    if matchups {
        write_matchups(c, f, brackets).await?;
    }
    let mirror = f.sides[0].class == f.sides[1].class;
    let bots = i64::from(f.bots());
    let ids: Vec<String> = f.sides.iter().map(|s| deck_id(&s.class, &s.cards)).collect();
    for (period, bucket) in PERIODS.iter().zip(buckets(f.ended)) {
        let keep = fresh(period, &bucket, now);
        for (p, s) in f.sides.iter().enumerate() {
            let dims = || -> Vec<sea_orm::Value> {
                vec![f.pack.clone().into(), (*period).into(), bucket.clone().into(), f.mode.clone().into(), brackets[p].clone().into(), bots.into(), s.class.clone().into()]
            };
            let won = i64::from(s.won);
            class.add(dims(), &[1, if mirror { 0 } else { won }, i64::from(mirror)]);
            if !keep {
                continue;
            }
            deck.add([dims(), vec![ids[p].clone().into()]].concat(), &[1, won]);
            let mut copies: BTreeMap<&str, i64> = BTreeMap::new();
            for c in &s.cards {
                *copies.entry(c).or_default() += 1;
            }
            for (c, n) in copies {
                let get = |m: &HashMap<String, i64>| m.get(c).copied().unwrap_or(0);
                let (plays, kept, replaced) = (get(&s.played), get(&s.kept), get(&s.replaced));
                let played = i64::from(plays > 0);
                card.add([dims(), vec![c.to_string().into()]].concat(), &[1, n, won, played, played * won, plays, kept, replaced, kept * won]);
            }
        }
    }
    class.write(c).await?;
    deck.write(c).await?;
    card.write(c).await?;
    for (p, s) in f.sides.iter().enumerate() {
        let mut cards = s.cards.clone();
        cards.sort();
        c.execute_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "INSERT OR IGNORE INTO stats_decks (pack, deck, class, hero, cards) VALUES (?, ?, ?, ?, ?)",
            [f.pack.clone().into(), ids[p].clone().into(), s.class.clone().into(), s.hero.clone().into(), json!(cards).to_string().into()],
        ))
        .await?;
    }
    Ok(())
}

/// The English names of a pack, its classes and cards, the first time a game of it is counted:
/// the pack's locales/en.json, else the built-in card names (data/cards.json), else the id.
pub async fn names(app: &AppRef, rules: &GameRules) -> DbResult<()> {
    let have = query(&app.db, "SELECT 1 AS x FROM stats_names WHERE pack = ? AND kind = 'pack'", vec![rules.rules_hash.clone().into()]).await?;
    if !have.is_empty() {
        return Ok(());
    }
    let en = locale(app, &rules.rules_hash).await.unwrap_or(Value::Null);
    let rs = rules.rs;
    let lib = Library::get();
    let title = |s: &str| s.split('_').map(|w| w[..1.min(w.len())].to_uppercase() + &w[1.min(w.len())..].to_lowercase()).collect::<Vec<_>>().join(" ");
    let mut rows: Vec<(&str, String, String)> = vec![("pack", String::new(), packs::short_name(rules))];
    for c in &rs.classes {
        rows.push(("class", c.id.clone(), en["classes"][&c.id].as_str().map_or_else(|| title(&c.id), String::from)));
    }
    for (id, _) in rs.cards.iter().filter(|(_, c)| c.collectible) {
        rows.push(("card", id.clone(), en["cards"][id]["name"].as_str().map_or_else(|| lib.name(id), String::from)));
    }
    for chunk in rows.chunks(5000) {
        let sql = format!("INSERT OR IGNORE INTO stats_names (pack, kind, id, name) VALUES {}", vec!["(?, ?, ?, ?)"; chunk.len()].join(", "));
        let values = chunk.iter().flat_map(|(k, id, n)| [rules.rules_hash.clone().into(), (*k).into(), id.clone().into(), n.clone().into()]);
        app.db.execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite, sql, values.collect::<Vec<sea_orm::Value>>())).await?;
    }
    Ok(())
}

/// A stored pack's locales/en.json.
async fn locale(app: &AppRef, rules_hash: &str) -> Option<Value> {
    let row = pack::Entity::find().filter(pack::Column::RulesHash.eq(rules_hash)).order_by_asc(pack::Column::Owner).one(&app.db).await.ok()??;
    let bytes = app.store.read(&row.content_hash, packs::MAX_SERVER_PACK).await.ok()?;
    tokio::task::spawn_blocking(move || {
        let mut z = zip::ZipArchive::new(std::io::Cursor::new(bytes)).ok()?;
        let en = serde_json::from_reader(z.by_name("locales/en.json").ok()?).ok();
        en
    })
    .await
    .ok()?
}

/// `prune` at most once an hour.
async fn prune_hourly(c: &impl ConnectionTrait) {
    static LAST: AtomicI64 = AtomicI64::new(-1);
    let now = ranked::now();
    if LAST.swap(now / 3600, Ordering::Relaxed) != now / 3600 {
        prune(c, now).await;
    }
}

/// Deletes the deck and card rows of hours and days older than kept at `now`.
pub async fn prune(c: &impl ConnectionTrait, now: i64) {
    let (h, d) = (buckets(now - KEEP_HOURS * 3600)[0].clone(), buckets(now - KEEP_DAYS * 86_400)[1].clone());
    for t in ["stats_deck", "stats_card"] {
        let sql = format!("DELETE FROM {t} WHERE (period = 'hour' AND bucket < ?) OR (period = 'day' AND bucket < ?)");
        if let Err(e) = c.execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite, sql, [h.clone().into(), d.clone().into()])).await {
            tracing::error!("stats: pruning {t}: {e}");
        }
    }
}

/// A finished game (game.rs `finish`): its facts from the replay, then its rows.
pub async fn record(app: AppRef, rules: Arc<GameRules>, replay: Value, brackets: [String; 2]) {
    let rs = rules.rs;
    let game = replay["game"].as_str().unwrap_or_default().to_string();
    let f = match tokio::task::spawn_blocking(move || facts(rs, &replay)).await {
        Ok(Ok(f)) => f,
        Ok(Err(e)) if e == NO_WINNER => return,
        Ok(Err(e)) => return failed(&app, &game, &e),
        Err(_) => return failed(&app, &game, "the rules engine failed"),
    };
    let saved = async {
        names(&app, &rules).await?;
        let tx = app.db.begin().await?;
        write(&tx, &f, &brackets).await?;
        tx.commit().await
    };
    if let Err(e) = saved.await {
        failed(&app, &game, &e.to_string());
    }
    prune_hourly(&app.db).await;
}

fn failed(app: &AppRef, game: &str, why: &str) {
    tracing::error!("stats: game {game} not counted: {why}");
    app.event(Event::new("error", format!("The statistics did not count game {game}: {why}")).game(game));
}

// --- the backfill ----------------------------------------------------------------------------------

async fn setting(c: &impl ConnectionTrait, key: &str) -> DbResult<Option<String>> {
    let r = query(c, "SELECT value FROM server_settings WHERE key = ?", vec![key.into()]).await?;
    Ok(r.first().map(|r| s(r, "value")))
}

async fn set_setting(c: &impl ConnectionTrait, key: &str, value: &str) -> DbResult<()> {
    let sql = "INSERT INTO server_settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value";
    c.execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite, sql, [key.into(), value.into()])).await?;
    Ok(())
}

async fn empty(c: &impl ConnectionTrait, table: &str) -> DbResult<bool> {
    Ok(query(c, &format!("SELECT 1 AS x FROM {table} LIMIT 1"), vec![]).await?.is_empty())
}

/// Counts the replays kept before the statistics existed, once (at start, when the stats tables
/// are empty): those that ended before the first run of it, oldest first, BATCH at a time, each
/// batch with its place in one transaction (a restart resumes there). Ranked and Arena games get
/// the bracket "unknown". Then the same for the matchup rows alone (M12), once, when the matchup
/// table is empty but the others are not. Returns the games counted (by both).
pub async fn backfill(app: &AppRef) -> DbResult<usize> {
    // the matchups' mark first, before this start's games add matchup rows
    if setting(&app.db, MATCHUP_BACKFILL).await?.is_none() {
        let start = empty(&app.db, "stats_matchup").await? && !empty(&app.db, "stats_class").await?;
        set_setting(&app.db, MATCHUP_BACKFILL, &if start { format!("{} 0 ", ranked::now()) } else { "done".into() }).await?;
    }
    if setting(&app.db, BACKFILL).await?.is_none() {
        let start = empty(&app.db, "stats_class").await?;
        set_setting(&app.db, BACKFILL, &if start { format!("{} 0 ", ranked::now()) } else { "done".into() }).await?;
    }
    // a backfill stopped before M12 leaves its games' matchups to the matchup backfill
    let matchups = setting(&app.db, MATCHUP_BACKFILL).await?.as_deref() == Some("done");
    Ok(run_backfill(app, BACKFILL, matchups).await? + run_backfill(app, MATCHUP_BACKFILL, true).await?)
}

/// One backfill from its mark `key` ("done" or "until ended game"): all the rows (`matchups`:
/// with the matchup rows), or for MATCHUP_BACKFILL the matchup rows alone.
async fn run_backfill(app: &AppRef, key: &str, matchups: bool) -> DbResult<usize> {
    let v = setting(&app.db, key).await?.unwrap_or_else(|| "done".into());
    if v == "done" {
        return Ok(0);
    }
    let mut it = v.splitn(3, ' ');
    let mut next = || it.next().unwrap_or_default().to_string();
    let (until, mut ended, mut game): (i64, i64, String) = (next().parse().unwrap_or(0), next().parse().unwrap_or(0), next());
    let mut counted = 0;
    loop {
        let rows = replay::Entity::find()
            .filter(replay::Column::Ended.lt(until))
            .filter(
                sea_orm::Condition::any()
                    .add(replay::Column::Ended.gt(ended))
                    .add(sea_orm::Condition::all().add(replay::Column::Ended.eq(ended)).add(replay::Column::Game.gt(game.as_str()))),
            )
            .order_by_asc(replay::Column::Ended)
            .order_by_asc(replay::Column::Game)
            .limit(BATCH)
            .all(&app.db)
            .await?;
        let Some(last) = rows.last() else {
            set_setting(&app.db, key, "done").await?;
            if counted > 0 {
                tracing::info!("stats: {counted} earlier game(s) counted ({key})");
            }
            return Ok(counted);
        };
        (ended, game) = (last.ended, last.game.clone());
        let mut batch = vec![];
        for r in rows {
            let Ok(rules) = packs::rules_for(app, &r.pack).await else { continue }; // a pack no longer here
            let rs = rules.rs;
            let f = tokio::task::spawn_blocking(move || replays::decompress(&r.data).ok_or("unreadable".to_string()).and_then(|d| facts(rs, &d))).await;
            if let Ok(Ok(f)) = f {
                names(app, &rules).await?;
                let b = if matches!(f.mode.as_str(), "ranked" | "arena") { UNKNOWN } else { ALL };
                batch.push((f, [b.to_string(), b.to_string()]));
            }
        }
        let tx = app.db.begin().await?;
        for (f, b) in &batch {
            if key == MATCHUP_BACKFILL { write_matchups(&tx, f, b).await? } else { add(&tx, f, b, matchups).await? }
        }
        set_setting(&tx, key, &format!("{until} {ended} {game}")).await?;
        tx.commit().await?;
        counted += batch.len();
        tokio::time::sleep(std::time::Duration::from_millis(20)).await; // the games' writes first
    }
}

/// `backfill` in the background (main.rs, at start).
pub fn spawn_backfill(app: AppRef) {
    tokio::spawn(async move {
        if let Err(e) = backfill(&app).await {
            tracing::error!("stats: the backfill stopped: {e}");
        }
    });
}

// --- the admin's view: GET /admin/api/stats ----------------------------------------------------------

async fn query(c: &impl ConnectionTrait, sql: &str, values: Vec<sea_orm::Value>) -> DbResult<Vec<QueryResult>> {
    c.query_all_raw(Statement::from_sql_and_values(DbBackend::Sqlite, sql, values)).await
}

fn i(r: &QueryResult, c: &str) -> i64 {
    r.try_get::<i64>("", c).unwrap_or(0)
}

fn s(r: &QueryResult, c: &str) -> String {
    r.try_get::<String>("", c).unwrap_or_default()
}

#[derive(Deserialize, Default)]
pub struct ViewQuery {
    pub pack: Option<String>,
    pub mode: Option<String>,
    pub bracket: Option<String>,
    pub period: Option<String>,
    /// "0": without the games a bot played in.
    pub bots: Option<String>,
    /// The fewest games of a deck shown.
    pub min: Option<i64>,
    /// The cards of one class's decks.
    pub class: Option<String>,
    /// A past bucket of the period ("2026-11-09" of a day); none: the current one.
    pub bucket: Option<String>,
}

pub async fn api(State(app): State<AppRef>, Query(q): Query<ViewQuery>) -> Response {
    match view(&app, q).await {
        Ok(v) => Json(v).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))).into_response(),
    }
}

/// The page's data: only reads the stats rows (sums over the dimensions not chosen).
pub async fn view(app: &AppRef, q: ViewQuery) -> DbResult<Value> {
    let c = &app.db;
    let packs: Vec<Value> = query(
        c,
        "SELECT n.pack AS pack, n.name AS name, (SELECT COALESCE(SUM(games), 0) FROM stats_class s WHERE s.pack = n.pack AND s.period = 'all') AS sides \
         FROM stats_names n WHERE n.kind = 'pack' ORDER BY sides DESC, name",
        vec![],
    )
    .await?
    .iter()
    .map(|r| json!({"pack": s(r, "pack"), "name": s(r, "name"), "games": i(r, "sides") / 2}))
    .collect();
    let pack = q.pack.filter(|p| packs.iter().any(|x| x["pack"] == *p)).or_else(|| packs.first().and_then(|p| p["pack"].as_str().map(String::from)));
    let backfill = match (setting(c, BACKFILL).await?, setting(c, MATCHUP_BACKFILL).await?) {
        (None, _) => "not started",
        (Some(a), b) if a == "done" && b.as_deref().is_none_or(|b| b == "done") => "done",
        _ => "running",
    };
    let Some(pack) = pack else { return Ok(json!({"packs": [], "backfill": backfill})) };
    let period = q.period.filter(|p| PERIODS.contains(&p.as_str())).unwrap_or_else(|| ALL.into());
    let now = ranked::now();
    let current = buckets(now)[PERIODS.iter().position(|p| *p == period).unwrap_or(5)].clone();
    let bucket = q.bucket.filter(|b| !b.is_empty() && period != ALL).unwrap_or_else(|| current.clone());
    let (mode, bracket) = (q.mode.filter(|m| !m.is_empty()), q.bracket.filter(|b| !b.is_empty()));
    let bots = q.bots.as_deref() != Some("0");
    let class = q.class.filter(|c| !c.is_empty());
    let min = q.min.unwrap_or(20).max(1);

    // the chosen mode, bracket and bots (after pack, period and bucket)
    let filter = |sql: &mut String, v: &mut Vec<sea_orm::Value>| {
        if let Some(m) = &mode {
            sql.push_str(" AND mode = ?");
            v.push(m.clone().into());
        }
        if let Some(b) = &bracket {
            sql.push_str(" AND bracket = ?");
            v.push(b.clone().into());
        }
        if !bots {
            sql.push_str(" AND bots = 0");
        }
    };
    let base = |period: &str, bucket: &str| -> (String, Vec<sea_orm::Value>) {
        let mut sql = " WHERE pack = ? AND period = ? AND bucket = ?".to_string();
        let mut v: Vec<sea_orm::Value> = vec![pack.clone().into(), period.into(), bucket.into()];
        filter(&mut sql, &mut v);
        (sql, v)
    };
    let names_of = |kind: &'static str| {
        let pack = pack.clone();
        async move {
            let r = query(c, "SELECT id, name FROM stats_names WHERE pack = ? AND kind = ?", vec![pack.into(), kind.into()]).await?;
            Ok::<_, sea_orm::DbErr>(r.iter().map(|r| (s(r, "id"), s(r, "name"))).collect::<HashMap<_, _>>())
        }
    };
    let (class_names, card_names) = (names_of("class").await?, names_of("card").await?);
    let rs = packs::rules_for(app, &pack).await.ok().map(|r| r.rs);
    let cost = |id: &str| rs.and_then(|rs| rs.cards.get(id)).map(|c| c.cost);

    let all = query(c, "SELECT DISTINCT mode, bracket FROM stats_class WHERE pack = ? AND period = 'all' ORDER BY mode, bracket", vec![pack.clone().into()]).await?;
    let modes: Vec<String> = all.iter().map(|r| s(r, "mode")).collect::<std::collections::BTreeSet<_>>().into_iter().collect();
    let brackets: Vec<String> = all.iter().filter(|r| mode.as_ref().is_none_or(|m| *m == s(r, "mode"))).map(|r| s(r, "bracket")).collect::<std::collections::BTreeSet<_>>().into_iter().collect();

    let (w, v) = base(&period, &bucket);
    let classes: Vec<Value> = query(c, &format!("SELECT class, SUM(games) AS games, SUM(wins) AS wins, SUM(mirrors) AS mirrors FROM stats_class{w} GROUP BY class ORDER BY class"), v)
        .await?
        .iter()
        .map(|r| {
            let id = s(r, "class");
            json!({"class": id, "name": class_names.get(&id).cloned().unwrap_or_else(|| id.clone()), "games": i(r, "games"), "wins": i(r, "wins"), "mirrors": i(r, "mirrors")})
        })
        .collect();
    let (w, v) = base(&period, &bucket);
    let matchups: Vec<Value> = query(c, &format!("SELECT class, opp, SUM(games) AS games, SUM(wins) AS wins FROM stats_matchup{w} GROUP BY class, opp ORDER BY class, opp"), v)
        .await?
        .iter()
        .map(|r| json!({"class": s(r, "class"), "opp": s(r, "opp"), "games": i(r, "games"), "wins": i(r, "wins")}))
        .collect();

    // the period's buckets with games (newest first), the current and the chosen one always
    let mut sql = " WHERE pack = ? AND period = ?".to_string();
    let mut v: Vec<sea_orm::Value> = vec![pack.clone().into(), period.clone().into()];
    filter(&mut sql, &mut v);
    let mut list: BTreeMap<String, i64> =
        query(c, &format!("SELECT bucket, SUM(games) AS sides FROM stats_class{sql} GROUP BY bucket ORDER BY bucket DESC LIMIT 1000"), v).await?.iter().map(|r| (s(r, "bucket"), i(r, "sides"))).collect();
    list.entry(current.clone()).or_default();
    list.entry(bucket.clone()).or_default();
    let bucket_list: Vec<Value> = list.iter().rev().map(|(b, n)| json!({"bucket": b, "sides": n})).collect();

    // games over time: the last 48 hours and 30 days (sides: two a game)
    let mut series = json!({});
    for (period, n, step, idx) in [("hour", 48, 3600, 0usize), ("day", 30, 86_400, 1usize)] {
        let keys: Vec<String> = (0..n).rev().map(|k| buckets(now - k * step)[idx].clone()).collect();
        let mut sql = " WHERE pack = ? AND period = ? AND bucket >= ?".to_string();
        let mut v: Vec<sea_orm::Value> = vec![pack.clone().into(), period.into(), keys[0].clone().into()];
        filter(&mut sql, &mut v);
        let got: HashMap<String, i64> =
            query(c, &format!("SELECT bucket, SUM(games) AS sides FROM stats_class{sql} GROUP BY bucket"), v).await?.iter().map(|r| (s(r, "bucket"), i(r, "sides"))).collect();
        series[period] = keys.iter().map(|k| json!([k, got.get(k).copied().unwrap_or(0)])).collect();
    }

    // decks: the best 20 and each class's best 5 with at least `min` games
    let (w, mut v) = base(&period, &bucket);
    v.push(min.into());
    let decks_sql = format!("SELECT class, deck, SUM(games) AS games, SUM(wins) AS wins FROM stats_deck{w} GROUP BY class, deck HAVING SUM(games) >= ?");
    let total_decks = i(&query(c, &format!("SELECT COUNT(*) AS n FROM ({decks_sql})"), v.clone()).await?[0], "n");
    let order = "ORDER BY CAST(wins AS REAL) / games DESC, games DESC, deck";
    let top = query(c, &format!("SELECT * FROM ({decks_sql}) {order} LIMIT 20"), v.clone()).await?;
    let per_class = query(c, &format!("SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY class {order}) AS n FROM ({decks_sql})) WHERE n <= 5 {order}"), v).await?;
    let ids: HashSet<String> = top.iter().chain(&per_class).map(|r| s(r, "deck")).collect();
    let mut lists: HashMap<String, (String, Vec<String>)> = HashMap::new();
    for id in ids {
        if let Some(r) = query(c, "SELECT hero, cards FROM stats_decks WHERE pack = ? AND deck = ?", vec![pack.clone().into(), id.clone().into()]).await?.first() {
            lists.insert(id, (s(r, "hero"), serde_json::from_str(&s(r, "cards")).unwrap_or_default()));
        }
    }
    let deck_json = |r: &QueryResult| {
        let id = s(r, "deck");
        let (hero, cards) = lists.get(&id).cloned().unwrap_or_default();
        let mut counted: BTreeMap<&str, i64> = BTreeMap::new();
        for c in &cards {
            *counted.entry(c).or_default() += 1;
        }
        let mut cards: Vec<Value> = counted
            .into_iter()
            .map(|(c, n)| json!({"id": c, "name": card_names.get(c).cloned().unwrap_or_else(|| c.to_string()), "n": n, "cost": cost(c)}))
            .collect();
        cards.sort_by_key(|c| (c["cost"].as_i64().unwrap_or(99), c["name"].as_str().unwrap_or_default().to_string()));
        json!({"deck": id, "class": s(r, "class"), "hero": hero, "games": i(r, "games"), "wins": i(r, "wins"), "cards": cards})
    };
    let top: Vec<Value> = top.iter().map(deck_json).collect();
    let mut by_class: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for r in &per_class {
        by_class.entry(s(r, "class")).or_default().push(deck_json(r));
    }

    // cards (of one class's decks, or all)
    let (mut w, mut v) = base(&period, &bucket);
    if let Some(k) = &class {
        w.push_str(" AND class = ?");
        v.push(k.clone().into());
    }
    let sums = CARD_VALS.iter().map(|c| format!("SUM({c}) AS {c}")).collect::<Vec<_>>().join(", ");
    let cards: Vec<Value> = query(c, &format!("SELECT card, {sums} FROM stats_card{w} GROUP BY card"), v)
        .await?
        .iter()
        .map(|r| {
            let id = s(r, "card");
            let mut o = json!({"card": id, "name": card_names.get(&id).cloned().unwrap_or_else(|| id.clone()), "cost": cost(&id)});
            for k in CARD_VALS {
                o[*k] = json!(i(r, k));
            }
            o
        })
        .collect();
    let (mut w, mut v) = base(&period, &bucket);
    if let Some(k) = &class {
        w.push_str(" AND class = ?");
        v.push(k.clone().into());
    }
    let sides = i(&query(c, &format!("SELECT COALESCE(SUM(games), 0) AS n FROM stats_class{w}"), v).await?[0], "n");
    Ok(json!({
        "packs": packs, "pack": pack, "period": period, "bucket": bucket, "current": current, "buckets": bucket_list, "kept": fresh(&period, &bucket, now),
        "mode": mode, "bracket": bracket, "bots": bots, "min": min, "class": class,
        "modes": modes, "brackets": brackets, "backfill": backfill, "sides": sides, "classes": classes, "matchups": matchups, "series": series,
        "decks": {"total": total_decks, "top": top, "by_class": by_class}, "cards": cards,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calendar_buckets() {
        // 2026-11-10 14:05:00 UTC, a Tuesday
        let t = 1_794_319_500;
        assert_eq!(buckets(t), ["2026-11-10T14", "2026-11-10", "2026-11-09", "2026-11", "2026", "all"].map(String::from));
        assert_eq!(buckets(0)[..3], ["1970-01-01T00", "1970-01-01", "1969-12-29"].map(String::from));
        // a week across a year's end: Thu 2026-01-01 is in the week of Mon 2025-12-29
        assert_eq!(buckets(1_767_225_600)[1..5], ["2026-01-01", "2025-12-29", "2026-01", "2026"].map(String::from));
        assert_eq!(buckets(951_782_400)[1], "2000-02-29"); // a leap day
    }

    #[test]
    fn rank_and_arena_brackets() {
        let r: Vec<String> = [0, 1, 5, 6, 10, 11, 16, 20, 21, 25, 26].iter().map(|r| rank_bracket(*r)).collect();
        assert_eq!(r, ["Legend", "1-5", "1-5", "6-10", "6-10", "11-15", "16-20", "16-20", "21-25", "21-25", "26-30"]);
        assert_eq!([0, 2, 3, 5, 6, 11].map(arena_bracket), ["0-2", "0-2", "3-5", "3-5", "6+", "6+"]);
    }

    #[test]
    fn a_deck_is_its_class_and_sorted_cards() {
        let a = deck_id("MAGE", &["b".into(), "a".into(), "a".into()]);
        assert_eq!(a, deck_id("MAGE", &["a".into(), "b".into(), "a".into()]));
        assert_ne!(a, deck_id("MAGE", &["a".into(), "b".into()]));
        assert_ne!(a, deck_id("PRIEST", &["a".into(), "b".into(), "a".into()]));
        assert_eq!(a.len(), 16);
    }
}
