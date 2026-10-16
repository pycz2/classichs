//! Game packs (`.cardpack`, a zip): the check of an uploaded file (`inspect` and `trial`: the
//! rules engine loads it, compiles its scripts and plays a bot game with it), the registry
//! (`packs` table), the rules of the packs games are played in (`rules_for`, `playable`),
//! players' uploads and downloads over HTTP, and the bundled packs imported at start.
//!
//! HTTP (the game's session token as `Authorization: Bearer <token>` or `?token=`):
//! - `GET /packs/<content_hash>.cardpack` → the file (ETag = the hash, immutable).
//! - `POST /packs` (the zip as the body) → `201 {pack}`; a player's own pack.

use crate::db::{self, Account, Db};
use crate::entity::{friend, pack, pack_import};
use crate::events::Event;
use crate::ranked::Ladder;
use crate::{ranked, AppRef, Timers};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use classichs_engine::deck::{self, Deck};
use classichs_engine::pack::{self as engine_pack, Files};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, Game};
use futures_util::StreamExt;
use sea_orm::sea_query::{Expr, ExprTrait};
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, DbErr, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, TransactionTrait, Unchanged};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::Read;
use std::path::{Path as FsPath, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;

/// A player's pack, at most.
pub const MAX_PLAYER_PACK: u64 = 100 << 20;
/// A server pack (the admin's), at most: the format's limit (docs/packs/format.md §1).
pub const MAX_SERVER_PACK: u64 = 128 << 20;
/// Own packs per player.
pub const MAX_PER_PLAYER: u64 = 10;
/// Pack formats this server understands.
pub const FORMATS: [i64; 1] = [1];
/// Different rule sets the engine of this process may hold (they are never freed: games point
/// into them). An upload or a game of a new one beyond this is refused until a restart.
// ponytail: keep-all with a limit; Arc'd rulesets in the engine would allow an LRU.
pub const MAX_RULESETS: usize = 48;
/// The trial game of a pack: actions and time at most.
const TRIAL_ACTIONS: usize = 600;
const TRIAL_TIME: Duration = Duration::from_secs(20);
/// Decks read from a pack for the trial game.
const TRIAL_DECKS: usize = 8;
/// The hash scheme of docs/packs/format.md §3 (`packs.hashes`).
pub const HASHES: i64 = 1;

/// What `inspect` learned from a pack.
#[derive(Clone, Debug, PartialEq)]
pub struct PackInfo {
    pub id: String,
    pub version: String,
    /// {"en": "…", …}
    pub name: Value,
    /// docs/packs/format.md §3, computed by the engine (`classichs_engine::pack::rules_hash`).
    pub rules_hash: String,
    /// docs/packs/format.md §3: every file, path + SHA-256 of its bytes.
    pub content_hash: String,
}

/// A pack read by `inspect`: what it is, the files the engine reads and its ready decks.
pub struct Inspected {
    pub info: PackInfo,
    pub files: Files,
    pub decks: Vec<Value>,
}

fn hex(d: impl AsRef<[u8]>) -> String {
    d.as_ref().iter().map(|b| format!("{b:02x}")).collect()
}

/// `content_hash` of docs/packs/format.md §3 over every file of the zip (directories ignored).
pub fn content_hash(bytes: &[u8]) -> Result<String, String> {
    let mut z = zip::ZipArchive::new(std::io::Cursor::new(bytes)).map_err(|e| format!("not a zip file: {e}"))?;
    let mut items: Vec<(String, String)> = Vec::with_capacity(z.len());
    for i in 0..z.len() {
        let mut f = z.by_index(i).map_err(|e| format!("bad zip entry: {e}"))?;
        if f.is_dir() {
            continue;
        }
        let mut h = Sha256::new();
        let name = f.name().map_err(|e| format!("bad file name: {e}"))?.to_string();
        std::io::copy(&mut f, &mut h).map_err(|e| format!("{name}: {e}"))?;
        items.push((name, hex(h.finalize())));
    }
    items.sort();
    let mut all = Sha256::new();
    all.update(b"cardpack-content/1\n");
    for (p, h) in items {
        all.update(format!("{p}:{h}\n").as_bytes());
    }
    Ok(hex(all.finalize()))
}

/// The first check of a pack (cheap; no engine run): the zip, its paths and limits
/// (`classichs_engine::pack::read_zip`, format.md §1), the manifest, both hashes (the
/// manifest's `rules_hash` must be the files'), and the ready decks.
pub fn inspect(bytes: &[u8]) -> Result<Inspected, String> {
    let files = engine_pack::read_zip(bytes)?;
    let manifest = engine_pack::strict_json(files.get("manifest.json").ok_or("no manifest.json at the top of the zip")?, "manifest.json")?;
    let format = manifest["format"].as_i64().ok_or("manifest.json: format must be a whole number")?;
    if !FORMATS.contains(&format) {
        return Err(format!("pack format {format} is not supported (this server knows {FORMATS:?})"));
    }
    let id = manifest["id"].as_str().unwrap_or_default();
    let id_ok = (1..=64).contains(&id.len())
        && id.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
        && id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "._-".contains(c));
    if !id_ok {
        return Err("manifest.json: id must be 1 to 64 of a-z 0-9 . _ - (like org.example.starter)".into());
    }
    let version = manifest["version"].as_str().unwrap_or_default();
    if !(1..=32).contains(&version.len()) || !version.chars().all(|c| c.is_ascii_graphic()) {
        return Err("manifest.json: version must be 1 to 32 characters without spaces (like 1.2.0)".into());
    }
    let name = manifest["name"].as_object().filter(|n| (1..=32).contains(&n.len())).ok_or("manifest.json: name must be {\"en\": \"…\", …}")?;
    for (lang, v) in name {
        let lang_ok = (2..=10).contains(&lang.len()) && lang.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
        let text_ok = v.as_str().is_some_and(|s| !s.trim().is_empty() && s.chars().count() <= 100);
        if !lang_ok || !text_ok {
            return Err(format!("manifest.json: name.{lang} must be 1 to 100 characters"));
        }
    }
    let rules_hash = engine_pack::rules_hash(&files)?;
    match manifest["rules_hash"].as_str() {
        Some(h) if h == rules_hash => {}
        Some(_) => return Err("manifest.json: rules_hash does not match the rules files (build the pack again)".into()),
        None => return Err("manifest.json: no rules_hash (build the pack with tools/pack.py)".into()),
    }
    let content_hash = content_hash(bytes)?;
    let mut decks = vec![];
    let mut z = zip::ZipArchive::new(std::io::Cursor::new(bytes)).map_err(|e| format!("not a zip file: {e}"))?;
    let mut names: Vec<String> =
        z.file_names().flatten().filter(|n| n.starts_with("decks/") && n.ends_with(".json") && n.matches('/').count() == 1).map(|n| n.to_string()).collect();
    names.sort();
    for n in names.into_iter().take(TRIAL_DECKS) {
        let mut b = vec![];
        let f = z.by_name(&n).map_err(|e| format!("{n}: {e}"))?;
        f.take(64 << 10).read_to_end(&mut b).map_err(|e| format!("{n}: {e}"))?;
        decks.push(engine_pack::strict_json(&b, &n)?);
    }
    let info = PackInfo { id: id.into(), version: version.into(), name: Value::Object(name.clone()), rules_hash, content_hash };
    Ok(Inspected { info, files, decks })
}

/// Loads a pack's rules into the engine (once per rules_hash for the whole process), within
/// the limit of different rule sets.
fn load_rules(files: &Files) -> Result<&'static Ruleset, String> {
    let h = engine_pack::rules_hash(files)?;
    if let Some(rs) = ruleset::get(&h) {
        return Ok(rs);
    }
    let loaded = classichs_engine::Engine::new().handle(&json!({"op": "packs"}))["packs"].as_array().map_or(0, Vec::len);
    if loaded >= MAX_RULESETS {
        return Err(format!("the server holds {MAX_RULESETS} different games already: try again after its restart"));
    }
    ruleset::load(files).map_err(|e| format!("the rules engine refused it: {e}"))
}

/// The full check (D11): the engine loads the rules and compiles every script, then the bot
/// plays a trial game with the pack's first two legal ready decks (else starter decks) for
/// up to TRIAL_ACTIONS actions or TRIAL_TIME, trying every legal move on a copy at each step.
/// A script error, an engine failure, a game that gets stuck or runs too long refuses the
/// pack. Blocking: call it off the async workers.
pub fn trial(p: &Inspected) -> Result<(), String> {
    let rs = load_rules(&p.files)?;
    let mut decks: Vec<Deck> = p
        .decks
        .iter()
        .filter_map(|d| {
            let hero = d.get("champion").or_else(|| d.get("hero"))?;
            Deck::from_value_in(rs, &json!({"hero": hero, "cards": d.get("cards")?}))
        })
        .filter(|d| d.validate_in(rs).is_empty())
        .collect();
    for c in rs.classes.iter().filter(|c| c.playable && !c.champion.is_empty()) {
        if decks.len() >= 2 {
            break;
        }
        let d = Deck { hero: c.champion.clone(), cards: deck::basic_in(rs, &c.id), arena: false };
        if d.validate_in(rs).is_empty() {
            decks.push(d);
        }
    }
    let (Some(a), Some(b)) = (decks.first(), decks.get(1).or(decks.first())) else {
        return Err("no legal deck to try the pack with (its ready decks and starter decks break its rules)".into());
    };
    let (a, b) = (a.clone(), b.clone());
    let played = std::panic::catch_unwind(move || -> Result<(), String> {
        let started = Instant::now();
        let mut g = Game::new_in(rs, &a.hero, &a.cards, &b.hero, &b.cards, 1, -1, true);
        for _ in 0..TRIAL_ACTIONS {
            if let Some(e) = g.script_error.get() {
                return Err(format!("a card script failed in the trial game: {e}"));
            }
            if g.game_over {
                return Ok(());
            }
            if started.elapsed() > TRIAL_TIME {
                return Err(format!("the trial game took more than {} s", TRIAL_TIME.as_secs()));
            }
            // Every move that could be made now, on a copy: a card the bot avoids because its
            // script fails is found too.
            for a in g.legal_actions().into_iter().filter(|a| a["type"] != "concede") {
                let mut c = g.clone_state();
                c.apply(&Value::Object(a.clone()));
                if let Some(e) = c.script_error.get() {
                    return Err(format!("a card script failed in the trial game ({}): {e}", Value::Object(a)));
                }
            }
            let who = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap_or(g.current) } else { g.current };
            let Some(act) = bot::choose(&g, who) else { return Err("the trial game got stuck: nobody can move".into()) };
            let r = g.apply(&Value::Object(act.clone()));
            if !r.ok {
                return Err(format!("the engine refused its own bot's move {}: {}", Value::Object(act), r.error));
            }
        }
        match g.script_error.get() {
            Some(e) => Err(format!("a card script failed in the trial game: {e}")),
            None => Ok(()),
        }
    });
    played.unwrap_or_else(|_| Err("the rules engine failed in the trial game".into()))
}

// --- the rules of games --------------------------------------------------------------------

/// What the server needs of a pack to run its games: the engine's ruleset and, from
/// rules.json, the timers, the ladder and the Arena's end.
pub struct GameRules {
    pub rs: &'static Ruleset,
    pub rules_hash: String,
    /// The manifest's id (ranks are kept per id, so a new version keeps them).
    pub id: String,
    pub version: String,
    /// The manifest's name ({lang: text}).
    pub name: Value,
    pub timers: Timers,
    /// The ranked ladder (the 2014 one when the pack has none: casual games keep MMRs in it).
    pub ladder: Ladder,
    /// The pack has a ranked ladder (rules.json `ranked`).
    pub ranked: bool,
    pub arena_wins: i64,
    pub arena_losses: i64,
}

impl GameRules {
    pub fn of(rs: &'static Ruleset, files: &Files) -> GameRules {
        let json = |f: &str| files.get(f).and_then(|b| serde_json::from_slice::<Value>(b).ok()).unwrap_or(Value::Null);
        let (rules, manifest) = (json("rules.json"), json("manifest.json"));
        let t = &rules["timers"];
        let secs = |k: &str, d: u64| Duration::from_secs(t[k].as_u64().unwrap_or(d).clamp(1, 3600));
        let arena = &rules["modes"]["arena"];
        GameRules {
            rs,
            rules_hash: rs.rules_hash.clone(),
            id: rs.id.clone(),
            version: rs.version.clone(),
            name: manifest["name"].clone(),
            timers: Timers {
                turn: secs("turn", 75),
                mulligan: secs("mulligan", 45),
                slack: Duration::from_secs(Ord::min(t["grace"].as_u64().unwrap_or(5), 600)),
                away: secs("away", 30),
            },
            ladder: Ladder::from_rules(&rules["ranked"]).unwrap_or_else(Ladder::classic),
            ranked: Ladder::from_rules(&rules["ranked"]).is_some(),
            arena_wins: Ord::max(arena["wins"].as_i64().unwrap_or(12), 1),
            arena_losses: Ord::max(arena["losses"].as_i64().unwrap_or(3), 1),
        }
    }

    /// The built-in Classic rules (the default when the server has no default pack).
    pub fn classic() -> Arc<GameRules> {
        static C: std::sync::OnceLock<Arc<GameRules>> = std::sync::OnceLock::new();
        C.get_or_init(|| Arc::new(GameRules::of(ruleset::classic(), &ruleset::classic_files()))).clone()
    }
}

/// "Neonfall 1.0.0": a pack's English (else any) name and version, for logs and the admin panel.
pub fn short_name(r: &GameRules) -> String {
    let n = r.name["en"].as_str().or_else(|| r.name.as_object().and_then(|o| o.values().next()).and_then(Value::as_str)).unwrap_or(&r.id);
    format!("{n} {}", r.version)
}

/// The game rules of a rules_hash: the built-in Classic ones, or a stored pack with these
/// rules loaded into the engine (once; cached in the app).
pub async fn rules_for(app: &AppRef, rules_hash: &str) -> Result<Arc<GameRules>, String> {
    let classic = GameRules::classic();
    if rules_hash.is_empty() || rules_hash == classic.rules_hash {
        return Ok(classic);
    }
    if let Some(r) = app.rules.lock().unwrap_or_else(|e| e.into_inner()).get(rules_hash) {
        return Ok(r.clone());
    }
    let _one = app.loading.lock().await; // one load at a time: a pack is read once
    if let Some(r) = app.rules.lock().unwrap_or_else(|e| e.into_inner()).get(rules_hash) {
        return Ok(r.clone());
    }
    let row = pack::Entity::find()
        .filter(pack::Column::RulesHash.eq(rules_hash))
        .filter(pack::Column::Hashes.eq(HASHES))
        .order_by_asc(pack::Column::Owner)
        .one(&app.db)
        .await
        .map_err(|e| format!("database: {e}"))?
        .ok_or("no such pack")?;
    let bytes = app.store.read(&row.content_hash, MAX_SERVER_PACK).await.map_err(|e| format!("storage: {e}"))?;
    let r = tokio::task::spawn_blocking(move || -> Result<GameRules, String> {
        let files = engine_pack::read_zip(&bytes)?;
        Ok(GameRules::of(load_rules(&files)?, &files))
    })
    .await
    .map_err(|_| "the rules engine failed".to_string())??;
    let r = Arc::new(r);
    app.rules.lock().unwrap_or_else(|e| e.into_inner()).insert(rules_hash.to_string(), r.clone());
    Ok(r)
}

/// The rules_hash games are played in when a request names none: the default server pack,
/// else the built-in Classic rules.
pub async fn default_hash(db: &Db) -> Result<String, DbErr> {
    let d = pack::Entity::find()
        .filter(pack::Column::Owner.is_null())
        .filter(pack::Column::Enabled.eq(true))
        .filter(pack::Column::IsDefault.eq(true))
        .one(db)
        .await?;
    Ok(d.map_or_else(|| GameRules::classic().rules_hash.clone(), |p| p.rules_hash))
}

/// The game a request asks for (`pack`: a rules_hash; None = the default), if `me` may play
/// it here: the default, an enabled server pack, or (friendly games: `own` = the inviter) the
/// inviter's own enabled pack. Returns the rules and the pack as the game sees it.
pub async fn playable(app: &AppRef, pack: Option<&str>, own: Option<i64>) -> Result<(Arc<GameRules>, Value), (&'static str, String)> {
    let server = |e: DbErr| ("server", format!("database: {e}"));
    let h = match pack {
        Some(h) => h.to_string(),
        None => default_hash(&app.db).await.map_err(server)?,
    };
    if h.len() > 64 {
        return Err(("pack", "This server does not have this game".into()));
    }
    let rows = pack::Entity::find()
        .filter(pack::Column::RulesHash.eq(&h))
        .filter(pack::Column::Enabled.eq(true))
        .order_by_asc(pack::Column::Id)
        .all(&app.db)
        .await
        .map_err(server)?;
    let row = rows.iter().find(|p| p.owner.is_none()).or_else(|| rows.iter().find(|p| own.is_some() && p.owner == own));
    let default = default_hash(&app.db).await.map_err(server)?;
    if row.is_none() && h != default {
        return Err(("pack", "This server does not have this game".into()));
    }
    let rules = rules_for(app, &h).await.map_err(|e| ("pack", format!("This game cannot be played here: {e}")))?;
    let entry = row.map_or_else(|| json!({"id": rules.id, "name": rules.name, "version": rules.version, "rules_hash": h}), pack_json);
    Ok((rules, entry))
}

// --- errors ------------------------------------------------------------------------------

/// A refusal: HTTP status, a code for programs, a text for people.
#[derive(Debug)]
pub struct PackErr(pub StatusCode, pub &'static str, pub String);

impl PackErr {
    fn new(s: StatusCode, code: &'static str, text: impl Into<String>) -> PackErr {
        PackErr(s, code, text.into())
    }
}

impl From<DbErr> for PackErr {
    fn from(e: DbErr) -> PackErr {
        tracing::error!("packs: database: {e}");
        PackErr::new(StatusCode::INTERNAL_SERVER_ERROR, "server", "Server error")
    }
}

impl IntoResponse for PackErr {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error": self.2, "code": self.1}))).into_response()
    }
}

fn store_err(e: impl std::fmt::Display) -> PackErr {
    tracing::error!("packs: storage: {e}");
    PackErr::new(StatusCode::INTERNAL_SERVER_ERROR, "storage", "The pack storage failed")
}

// --- receiving a file ----------------------------------------------------------------------

/// An uploaded file in the temp directory (removed when dropped), with its hash and size.
pub struct Upload {
    pub path: PathBuf,
    pub hash: String,
    pub size: u64,
}

impl Drop for Upload {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Streams a request body to a temp file, hashing it; refuses more than `limit` bytes.
pub async fn receive(headers: &HeaderMap, body: Body, limit: u64) -> Result<Upload, PackErr> {
    let too_big = || PackErr::new(StatusCode::PAYLOAD_TOO_LARGE, "too_large", format!("A pack is {} MB at most", limit >> 20));
    let declared = headers.get(header::CONTENT_LENGTH).and_then(|v| v.to_str().ok()).and_then(|v| v.parse::<u64>().ok());
    if declared.is_some_and(|n| n > limit) {
        return Err(too_big());
    }
    let mut name = [0u8; 12];
    rand::RngCore::fill_bytes(&mut rand::rngs::OsRng, &mut name);
    let path = std::env::temp_dir().join(format!("chs-pack-{}.part", hex(name)));
    let mut file = tokio::fs::File::create(&path).await.map_err(store_err)?;
    let mut up = Upload { path, hash: String::new(), size: 0 };
    let mut h = Sha256::new();
    let mut stream = body.into_data_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| PackErr::new(StatusCode::BAD_REQUEST, "bad_body", format!("The upload broke off: {e}")))?;
        up.size += chunk.len() as u64;
        if up.size > limit {
            return Err(too_big());
        }
        h.update(&chunk);
        file.write_all(&chunk).await.map_err(store_err)?;
    }
    file.flush().await.map_err(store_err)?;
    if up.size == 0 {
        return Err(PackErr::new(StatusCode::BAD_REQUEST, "empty", "Send the .cardpack file as the request body"));
    }
    up.hash = hex(h.finalize());
    Ok(up)
}

fn hash_file(path: &FsPath) -> std::io::Result<(String, u64)> {
    let mut h = Sha256::new();
    let n = std::io::copy(&mut std::fs::File::open(path)?, &mut h)?;
    Ok((hex(h.finalize()), n))
}

/// The whole check of a pack file (`inspect`, then `trial` unless a pack with the same rules
/// passed it before), off the async workers, within TRIAL_TIME and a bit.
pub async fn check_file(app: &AppRef, path: &FsPath) -> Result<PackInfo, PackErr> {
    let bytes = tokio::fs::read(path).await.map_err(store_err)?;
    let invalid = |e: String| PackErr::new(StatusCode::UNPROCESSABLE_ENTITY, "invalid", e);
    let p = tokio::task::spawn_blocking(move || inspect(&bytes))
        .await
        .map_err(|_| PackErr::new(StatusCode::INTERNAL_SERVER_ERROR, "server", "Server error"))?
        .map_err(invalid)?;
    let known = pack::Entity::find()
        .filter(pack::Column::RulesHash.eq(&p.info.rules_hash))
        .filter(pack::Column::Hashes.eq(HASHES))
        .count(&app.db)
        .await?
        > 0;
    if known {
        return Ok(p.info);
    }
    let _one = app.loading.lock().await; // trials one at a time
    let job = tokio::task::spawn_blocking(move || trial(&p).map(|_| p.info));
    match tokio::time::timeout(TRIAL_TIME + Duration::from_secs(10), job).await {
        Ok(Ok(r)) => r.map_err(invalid),
        Ok(Err(_)) => Err(invalid("the rules engine failed on it".into())),
        Err(_) => Err(invalid(format!("the check took more than {} s", TRIAL_TIME.as_secs() + 10))),
    }
}

/// Checks a received file and registers it (server pack: `owner` None). Stores the file
/// under its content hash unless the storage has it already.
pub async fn add(app: &AppRef, file: &FsPath, size: u64, owner: Option<i64>) -> Result<pack::Model, PackErr> {
    let info = check_file(app, file).await?;
    let hash = info.content_hash.clone();
    let mine = |owner: Option<i64>| match owner {
        Some(o) => Condition::all().add(pack::Column::Owner.eq(o)),
        None => Condition::all().add(pack::Column::Owner.is_null()),
    };
    let dup = pack::Entity::find().filter(mine(owner)).filter(pack::Column::ContentHash.eq(&hash)).one(&app.db).await?;
    if dup.is_some() {
        return Err(PackErr::new(StatusCode::CONFLICT, "exists", "This pack is uploaded already"));
    }
    if !app.store.exists(&hash).await.map_err(store_err)? {
        app.store.put_file(&hash, file).await.map_err(store_err)?;
    }
    let tx = app.db.begin().await?;
    if let Some(o) = owner {
        if pack::Entity::find().filter(pack::Column::Owner.eq(o)).count(&tx).await? >= MAX_PER_PLAYER {
            return Err(PackErr::new(StatusCode::CONFLICT, "too_many", format!("{MAX_PER_PLAYER} packs at most: delete one first")));
        }
    }
    let row = pack::ActiveModel {
        pack_id: Set(info.id),
        version: Set(info.version),
        name: Set(info.name.to_string()),
        rules_hash: Set(info.rules_hash),
        content_hash: Set(hash),
        size: Set(size as i64),
        owner: Set(owner),
        enabled: Set(true),
        created: Set(ranked::now()),
        downloads: Set(0),
        hashes: Set(HASHES),
        is_default: Set(false),
        ..Default::default()
    }
    .insert(&tx)
    .await?;
    tx.commit().await?;
    Ok(row)
}

/// Rows stored before the hashes of docs/packs/format.md (`hashes` 0): reads each file once,
/// stores it under its new content hash and rewrites both hashes. A file that is gone or no
/// longer a valid pack turns its rows off (an event says why).
pub async fn migrate_hashes(app: &AppRef) -> usize {
    let old = match pack::Entity::find().filter(pack::Column::Hashes.ne(HASHES)).all(&app.db).await {
        Ok(v) => v,
        Err(e) => {
            tracing::error!("packs: {e}");
            return 0;
        }
    };
    let mut files: Vec<String> = old.iter().map(|p| p.content_hash.clone()).collect();
    files.sort();
    files.dedup();
    let mut done = 0;
    for file in files {
        let r = async {
            let bytes = app.store.read(&file, MAX_SERVER_PACK).await.map_err(|e| format!("storage: {e}"))?;
            let (info, bytes) = tokio::task::spawn_blocking(move || inspect(&bytes).map(|p| (p.info, bytes)))
                .await
                .map_err(|_| "the check failed".to_string())??;
            if !app.store.exists(&info.content_hash).await.map_err(|e| e.to_string())? {
                app.store.put_bytes(&info.content_hash, bytes).await.map_err(|e| e.to_string())?;
            }
            Ok::<_, String>(info)
        }
        .await;
        let rows = old.iter().filter(|p| p.content_hash == file);
        for p in rows {
            let m = match &r {
                Ok(info) => pack::ActiveModel {
                    id: Unchanged(p.id),
                    rules_hash: Set(info.rules_hash.clone()),
                    content_hash: Set(info.content_hash.clone()),
                    hashes: Set(HASHES),
                    ..Default::default()
                },
                Err(why) => {
                    app.event(Event::new("pack_rejected", format!("The pack {} was turned off: {why}", label(p))).data(event_data(p)));
                    pack::ActiveModel { id: Unchanged(p.id), enabled: Set(false), hashes: Set(HASHES), ..Default::default() }
                }
            };
            if let Err(e) = m.update(&app.db).await {
                tracing::error!("packs: {e}");
            }
            done += 1;
        }
        if r.as_ref().is_ok_and(|i| i.content_hash != file) {
            gc(app, &file).await;
        }
        match r {
            Ok(i) => tracing::info!("pack file {file}: new hashes {} / {}", i.content_hash, i.rules_hash),
            Err(e) => tracing::error!("pack file {file}: {e}"),
        }
    }
    done
}

/// Makes a server pack the default game (`id`), or, with None, the newest enabled server pack
/// with the manifest id `want` when there is no default yet (the bundled Neonfall).
pub async fn set_default(app: &AppRef, id: Option<i64>, want: &str) -> Result<Option<pack::Model>, DbErr> {
    let db = &app.db;
    let target = match id {
        Some(id) => pack::Entity::find_by_id(id).filter(pack::Column::Owner.is_null()).one(db).await?,
        None => {
            let has = pack::Entity::find()
                .filter(pack::Column::Owner.is_null())
                .filter(pack::Column::Enabled.eq(true))
                .filter(pack::Column::IsDefault.eq(true))
                .count(db)
                .await?;
            if has > 0 {
                return Ok(None);
            }
            pack::Entity::find()
                .filter(pack::Column::Owner.is_null())
                .filter(pack::Column::Enabled.eq(true))
                .filter(pack::Column::PackId.eq(want))
                .order_by_desc(pack::Column::Id)
                .one(db)
                .await?
        }
    };
    let Some(t) = target else { return Ok(None) };
    let tx = db.begin().await?;
    pack::Entity::update_many().col_expr(pack::Column::IsDefault, Expr::value(false)).exec(&tx).await?;
    pack::Entity::update_many().col_expr(pack::Column::IsDefault, Expr::value(true)).filter(pack::Column::Id.eq(t.id)).exec(&tx).await?;
    tx.commit().await?;
    Ok(Some(t))
}

/// Removes the stored file when no pack row uses it any more.
pub async fn gc(app: &AppRef, hash: &str) {
    match pack::Entity::find().filter(pack::Column::ContentHash.eq(hash)).count(&app.db).await {
        Ok(0) => {
            if let Err(e) = app.store.delete(hash).await {
                tracing::error!("packs: deleting {hash}: {e}");
            }
        }
        Ok(_) => {}
        Err(e) => tracing::error!("packs: gc {hash}: {e}"),
    }
}

/// The file name a pack downloads as.
fn file_name(p: &pack::Model) -> String {
    format!("{}-{}.cardpack", p.pack_id, p.version).chars().filter(|c| c.is_ascii_alphanumeric() || "._-".contains(*c)).collect()
}

/// A short human label: "Neon 1.0.0 (org.classichs.neon)".
pub fn label(p: &pack::Model) -> String {
    let name: Value = serde_json::from_str(&p.name).unwrap_or(Value::Null);
    let shown = name["en"].as_str().or_else(|| name.as_object().and_then(|o| o.values().next()).and_then(|v| v.as_str())).unwrap_or(&p.pack_id);
    format!("{shown} {} ({})", p.version, p.pack_id)
}

pub fn event_data(p: &pack::Model) -> Value {
    json!({"pack": p.id, "pack_id": p.pack_id, "version": p.version, "content_hash": p.content_hash, "rules_hash": p.rules_hash,
           "size": p.size, "owner": p.owner})
}

// --- the game's view ----------------------------------------------------------------------

/// A pack as the game sees it.
pub fn pack_json(p: &pack::Model) -> Value {
    json!({"id": p.pack_id, "name": serde_json::from_str::<Value>(&p.name).unwrap_or(Value::Null), "version": p.version,
           "rules_hash": p.rules_hash, "content_hash": p.content_hash, "size": p.size, "default": p.is_default,
           "url": format!("/packs/{}.cardpack", p.content_hash)})
}

/// `packs {server, mine}`: the enabled server packs and the player's own (with `enabled`).
pub async fn packs_msg(db: &Db, me: i64) -> Result<Value, DbErr> {
    let server = pack::Entity::find()
        .filter(pack::Column::Owner.is_null())
        .filter(pack::Column::Enabled.eq(true))
        .order_by_asc(pack::Column::PackId)
        .order_by_asc(pack::Column::Id)
        .all(db)
        .await?;
    let mine = pack::Entity::find().filter(pack::Column::Owner.eq(me)).order_by_desc(pack::Column::Id).all(db).await?;
    let mine: Vec<Value> = mine
        .iter()
        .map(|p| {
            let mut v = pack_json(p);
            v["enabled"] = json!(p.enabled);
            v
        })
        .collect();
    Ok(json!({"t": "packs", "server": server.iter().map(pack_json).collect::<Vec<_>>(), "mine": mine}))
}

/// `pack_delete {content_hash}`: the player's own pack. false = no such pack of theirs.
pub async fn delete_own(app: &AppRef, me: i64, my_name: &str, hash: &str) -> Result<bool, DbErr> {
    let Some(p) = pack::Entity::find().filter(pack::Column::Owner.eq(me)).filter(pack::Column::ContentHash.eq(hash)).one(&app.db).await? else {
        return Ok(false);
    };
    pack::Entity::delete_by_id(p.id).exec(&app.db).await?;
    gc(app, hash).await;
    app.event(Event::new("pack_delete", format!("{my_name} deleted the pack {}", label(&p))).user(me, my_name).data(event_data(&p)));
    Ok(true)
}

// --- HTTP ------------------------------------------------------------------------------------

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/packs", post(upload).options(preflight))
        .route("/packs/{file}", get(download).options(preflight))
        .layer(axum::middleware::map_response(cors))
}

/// The web build of the game runs on another origin; the token, not a cookie, authenticates.
async fn cors(mut res: Response) -> Response {
    let h = res.headers_mut();
    h.insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
    h.insert(header::ACCESS_CONTROL_EXPOSE_HEADERS, HeaderValue::from_static("etag, content-length, content-disposition"));
    res
}

async fn preflight() -> Response {
    (
        StatusCode::NO_CONTENT,
        [
            (header::ACCESS_CONTROL_ALLOW_METHODS, "GET, POST, OPTIONS"),
            (header::ACCESS_CONTROL_ALLOW_HEADERS, "authorization, content-type, if-none-match"),
            (header::ACCESS_CONTROL_MAX_AGE, "86400"),
        ],
    )
        .into_response()
}

#[derive(Deserialize)]
struct TokenQ {
    token: Option<String>,
}

/// The player of a game session token (Authorization: Bearer, else ?token=).
async fn player(app: &AppRef, headers: &HeaderMap, q: &TokenQ) -> Result<Account, PackErr> {
    let bearer = headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer "));
    let token = bearer.map(str::trim).or(q.token.as_deref()).unwrap_or_default();
    if token.is_empty() || token.len() > 200 {
        return Err(PackErr::new(StatusCode::UNAUTHORIZED, "auth_required", "Log in first: send the session token"));
    }
    match db::session(&app.db, token, "game").await? {
        Some((a, _)) => Ok(a),
        None => Err(PackErr::new(StatusCode::UNAUTHORIZED, "bad_token", "The session expired: log in again")),
    }
}

async fn upload(State(app): State<AppRef>, Query(q): Query<TokenQ>, headers: HeaderMap, body: Body) -> Result<Response, PackErr> {
    let a = player(&app, &headers, &q).await?;
    if pack::Entity::find().filter(pack::Column::Owner.eq(a.id)).count(&app.db).await? >= MAX_PER_PLAYER {
        return Err(PackErr::new(StatusCode::CONFLICT, "too_many", format!("{MAX_PER_PLAYER} packs at most: delete one first")));
    }
    let up = receive(&headers, body, MAX_PLAYER_PACK).await?;
    let p = match add(&app, &up.path, up.size, Some(a.id)).await {
        Ok(p) => p,
        Err(e) => {
            if e.1 == "invalid" {
                app.event(Event::new("pack_rejected", format!("{}'s pack was refused: {}", a.name, e.2)).user(a.id, &a.name)
                    .data(json!({"reason": e.2, "sha256": up.hash, "size": up.size})));
            }
            return Err(e);
        }
    };
    app.event(Event::new("pack_upload", format!("{} uploaded the pack {}", a.name, label(&p))).user(a.id, &a.name).data(event_data(&p)));
    if let Ok(m) = packs_msg(&app.db, a.id).await {
        app.hub().send(a.id, &m);
    }
    Ok((StatusCode::CREATED, Json(json!({"pack": pack_json(&p)}))).into_response())
}

/// May this player download that pack? Enabled server packs: everyone; a player's pack: the
/// owner, and (enabled) the owner's friends — friendly games go to friends only.
async fn visible(db: &Db, me: i64, rows: Vec<pack::Model>) -> Result<Option<pack::Model>, DbErr> {
    let mut best = None;
    for p in rows {
        let ok = match p.owner {
            None => p.enabled,
            Some(o) if o == me => true,
            Some(o) => p.enabled && friend::Entity::find_by_id((o, me)).one(db).await?.is_some(),
        };
        if ok && (best.is_none() || p.owner.is_none()) {
            best = Some(p);
        }
    }
    Ok(best)
}

async fn download(State(app): State<AppRef>, Path(file): Path<String>, Query(q): Query<TokenQ>, headers: HeaderMap) -> Result<Response, PackErr> {
    let not_found = || PackErr::new(StatusCode::NOT_FOUND, "not_found", "No such pack");
    let hash = file.strip_suffix(".cardpack").unwrap_or_default().to_string();
    if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) {
        return Err(not_found());
    }
    let a = player(&app, &headers, &q).await?;
    let rows = pack::Entity::find().filter(pack::Column::ContentHash.eq(&hash)).all(&app.db).await?;
    let p = visible(&app.db, a.id, rows).await?.ok_or_else(not_found)?;
    let etag = format!("\"{hash}\"");
    let cache = (header::CACHE_CONTROL, "private, max-age=31536000, immutable");
    let matches = headers.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()).is_some_and(|v| v.split(',').any(|t| t.trim() == etag || t.trim() == "*"));
    if matches {
        return Ok((StatusCode::NOT_MODIFIED, [(header::ETAG, etag.as_str()), cache]).into_response());
    }
    let (size, stream) = app.store.get(&hash).await.map_err(|e| match e {
        crate::storage::Error::NotFound { .. } => {
            tracing::error!("packs: {hash} is registered but not in the storage");
            not_found()
        }
        e => store_err(e),
    })?;
    pack::Entity::update_many()
        .col_expr(pack::Column::Downloads, Expr::col(pack::Column::Downloads).add(1))
        .filter(pack::Column::Id.eq(p.id))
        .exec(&app.db)
        .await?;
    app.event(Event::new("pack_download", format!("{} downloaded the pack {}", a.name, label(&p))).user(a.id, &a.name).data(event_data(&p)));
    let disposition = format!("attachment; filename=\"{}\"", file_name(&p));
    let body = Body::from_stream(stream);
    Ok((
        [
            (header::CONTENT_TYPE, "application/zip".to_string()),
            (header::CONTENT_LENGTH, size.to_string()),
            (header::ETAG, etag),
            (header::CACHE_CONTROL, cache.1.to_string()),
            (header::CONTENT_DISPOSITION, disposition),
        ],
        body,
    )
        .into_response())
}

// --- bundled packs ---------------------------------------------------------------------------

/// Imports every `*.cardpack` in `dir` not imported before (by the file's SHA-256), as an
/// enabled server pack (so a pack the admin deleted stays deleted); a new version of the
/// default game becomes the default. Returns how many were added.
pub async fn import_bundled(app: &AppRef, dir: &FsPath) -> usize {
    let Ok(rd) = std::fs::read_dir(dir) else { return 0 };
    let mut files: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "cardpack")).collect();
    files.sort();
    let mut added = 0;
    for f in files {
        let (hash, size) = match hash_file(&f) {
            Ok(h) => h,
            Err(e) => {
                tracing::error!("bundled pack {}: {e}", f.display());
                continue;
            }
        };
        match pack_import::Entity::find_by_id(&hash).one(&app.db).await {
            Ok(None) => {}
            Ok(Some(_)) => continue,
            Err(e) => {
                tracing::error!("bundled packs: {e}");
                return added;
            }
        }
        let r = match add(app, &f, size, None).await {
            Ok(p) => {
                app.event(Event::new("pack_import", format!("Bundled pack {} installed", label(&p))).data(event_data(&p)));
                // A new version of the default game becomes the default.
                let default_id = pack::Entity::find().filter(pack::Column::IsDefault.eq(true)).one(&app.db).await.ok().flatten().map(|d| d.pack_id);
                if default_id.as_deref() == Some(p.pack_id.as_str()) {
                    let _ = set_default(app, Some(p.id), "").await;
                }
                tracing::info!("bundled pack {} installed: {}", f.display(), label(&p));
                added += 1;
                true
            }
            Err(PackErr(_, "exists", _)) => true,
            Err(PackErr(_, "invalid", why)) => {
                app.event(Event::new("pack_rejected", format!("Bundled pack {} refused: {why}", f.display())).data(json!({"reason": why, "sha256": hash})));
                tracing::error!("bundled pack {} refused: {why}", f.display());
                true
            }
            Err(e) => {
                tracing::error!("bundled pack {}: {}", f.display(), e.2);
                false
            }
        };
        if r {
            let row = pack_import::ActiveModel { content_hash: Set(hash), at: Set(ranked::now()) };
            if let Err(e) = pack_import::Entity::insert(row).on_conflict_do_nothing().exec(&app.db).await {
                tracing::error!("bundled packs: {e}");
            }
        }
    }
    added
}

// --- the admin panel -------------------------------------------------------------------------

/// A pack row for the admin panel (`owner` = {id, user} or null).
pub fn admin_json(p: &pack::Model, names: &HashMap<i64, String>) -> Value {
    json!({"id": p.id, "pack_id": p.pack_id, "version": p.version, "name": serde_json::from_str::<Value>(&p.name).unwrap_or(Value::Null),
           "rules_hash": p.rules_hash, "content_hash": p.content_hash, "size": p.size, "enabled": p.enabled, "created": p.created,
           "downloads": p.downloads, "default": p.is_default, "owner": p.owner.map(|o| json!({"id": o, "user": names.get(&o)}))})
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Cursor, Write};
    use zip::write::SimpleFileOptions;

    pub fn zip_of(files: &[(&str, &str)]) -> Vec<u8> {
        let mut w = zip::ZipWriter::new(Cursor::new(vec![]));
        for (name, body) in files {
            w.start_file(*name, SimpleFileOptions::default()).unwrap();
            w.write_all(body.as_bytes()).unwrap();
        }
        w.finish().unwrap().into_inner()
    }

    /// A zip with the manifest's rules_hash filled in from the other files.
    fn pack_of(manifest: Value, files: &[(&str, &str)]) -> Vec<u8> {
        let mut m = manifest;
        let fs: Files = files.iter().map(|(p, b)| (p.to_string(), b.as_bytes().to_vec())).collect();
        m["rules_hash"] = json!(engine_pack::rules_hash(&fs).unwrap());
        let m = m.to_string();
        let mut all = vec![("manifest.json", m.as_str())];
        all.extend_from_slice(files);
        zip_of(&all)
    }

    fn manifest() -> Value {
        json!({"format": 1, "id": "org.test.neon", "version": "1.0.0", "name": {"en": "Neon", "ru": "Неон"}})
    }

    #[test]
    fn hashes_as_the_format_says() {
        let a = pack_of(manifest(), &[("rules.json", "{}"), ("cards.json", "[]"), ("art/x/a.webp", "1")]);
        let info = inspect(&a).unwrap().info;
        assert_eq!((info.id.as_str(), info.version.as_str()), ("org.test.neon", "1.0.0"));
        assert_eq!(info.name["ru"], "Неон");
        // rules_hash: "cardpack-rules/1\n" + path:sha256(canonical JSON) per rules file, sorted.
        let lines = format!("cardpack-rules/1\ncards.json:{}\nrules.json:{}\n", hex(Sha256::digest(b"[]")), hex(Sha256::digest(b"{}")));
        assert_eq!(info.rules_hash, hex(Sha256::digest(lines.as_bytes())));
        // content_hash: every file's raw bytes, sorted by path; not the zip's bytes.
        let mut z = zip::ZipArchive::new(Cursor::new(&a)).unwrap();
        let mut m = String::new();
        z.by_name("manifest.json").unwrap().read_to_string(&mut m).unwrap();
        let line = |p: &str, b: &[u8]| format!("{p}:{}\n", hex(Sha256::digest(b)));
        let want = format!("cardpack-content/1\n{}{}{}{}", line("art/x/a.webp", b"1"), line("cards.json", b"[]"), line("manifest.json", m.as_bytes()),
            line("rules.json", b"{}"));
        assert_eq!(info.content_hash, hex(Sha256::digest(want.as_bytes())));
        // The order in the zip changes neither; art changes only the content hash.
        let mut files = vec![("cards.json", "[]"), ("art/x/a.webp", "1"), ("rules.json", "{}")];
        files.reverse();
        let mut mm: Value = serde_json::from_str(&m).unwrap();
        mm.as_object_mut().unwrap().remove("rules_hash");
        let b = inspect(&pack_of(mm.clone(), &files)).unwrap().info;
        assert_eq!((b.rules_hash.as_str(), b.content_hash.as_str()), (info.rules_hash.as_str(), info.content_hash.as_str()));
        let c = inspect(&pack_of(mm, &[("rules.json", "{}"), ("cards.json", "[]"), ("art/x/a.webp", "2")])).unwrap().info;
        assert_eq!(c.rules_hash, info.rules_hash);
        assert_ne!(c.content_hash, info.content_hash);
    }

    #[test]
    fn refuses_bad_packs() {
        let bad = |files: &[(&str, &str)]| inspect(&zip_of(files)).err().unwrap();
        assert!(inspect(b"not a zip").err().unwrap().contains("not a zip"));
        assert!(bad(&[("rules.json", "{}")]).contains("no manifest.json"));
        assert!(bad(&[("manifest.json", "{")]).contains("manifest.json"));
        assert!(bad(&[("manifest.json", r#"{"format": 2, "id": "a", "version": "1", "name": {"en": "A"}}"#)]).contains("format 2"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "Bad Id", "version": "1", "name": {"en": "A"}}"#)]).contains("id must"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "", "name": {"en": "A"}}"#)]).contains("version"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "1", "name": "A"}"#)]).contains("name"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "1", "name": {"en": " "}}"#)]).contains("name.en"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "1", "name": {"en": "A"}}"#)]).contains("no rules_hash"));
        let wrong = r#"{"format": 1, "id": "a", "version": "1", "name": {"en": "A"}, "rules_hash": "00"}"#;
        assert!(bad(&[("manifest.json", wrong), ("rules.json", "{}")]).contains("does not match"));
        assert!(bad(&[("manifest.json", wrong), ("../evil.lua", "x")]).contains("may not have"));
        assert!(bad(&[("manifest.json", wrong), ("scripts\\a.lua", "x")]).contains("may not have"));
    }

    /// The built packs of the repository (tools/build_packs.sh) pass the whole check.
    #[test]
    fn built_packs_pass_the_trial() {
        for f in ["classic", "neon"] {
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../packs/{f}.cardpack"));
            let Ok(bytes) = std::fs::read(&path) else {
                eprintln!("{}: not built (tools/build_packs.sh), skipped", path.display());
                continue;
            };
            let p = inspect(&bytes).unwrap_or_else(|e| panic!("{f}: {e}"));
            trial(&p).unwrap_or_else(|e| panic!("{f}: {e}"));
        }
    }
}
