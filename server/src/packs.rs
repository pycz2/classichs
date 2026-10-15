//! Game packs (`.cardpack`, a zip): the check of an uploaded file (`validate_pack`, the hook
//! the rules engine extends in phase D), the registry (`packs` table), players' uploads and
//! downloads over HTTP, and the bundled packs imported at start.
//!
//! HTTP (the game's session token as `Authorization: Bearer <token>` or `?token=`):
//! - `GET /packs/<content_hash>.cardpack` → the file (ETag = the hash, immutable).
//! - `POST /packs` (the zip as the body) → `201 {pack}`; a player's own pack.

use crate::db::{self, Account, Db};
use crate::entity::{friend, pack, pack_import};
use crate::events::Event;
use crate::{ranked, AppRef};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use futures_util::StreamExt;
use sea_orm::sea_query::{Expr, ExprTrait};
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, DbErr, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, TransactionTrait};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Seek};
use std::path::{Path as FsPath, PathBuf};
use tokio::io::AsyncWriteExt;

/// A player's pack, at most.
pub const MAX_PLAYER_PACK: u64 = 100 << 20;
/// A server pack (the admin's), at most.
pub const MAX_SERVER_PACK: u64 = 1 << 30;
/// Own packs per player.
pub const MAX_PER_PLAYER: u64 = 10;
/// Pack formats this server understands.
pub const FORMATS: [i64; 1] = [1];
const MAX_ENTRIES: usize = 20_000;
const MAX_MANIFEST: u64 = 64 << 10;
/// The rules files read for the rules hash, together.
const MAX_RULES: u64 = 64 << 20;

/// What `validate_pack` learned from a pack.
#[derive(Clone, Debug, PartialEq)]
pub struct PackInfo {
    pub id: String,
    pub version: String,
    /// {"en": "…", …}
    pub name: Value,
    pub rules_hash: String,
}

fn hex(d: impl AsRef<[u8]>) -> String {
    d.as_ref().iter().map(|b| format!("{b:02x}")).collect()
}

/// Does this file affect play (D8: rules, cards, mechanics, scripts)? Those make the rules hash.
fn rules_file(path: &str) -> bool {
    matches!(path, "rules.json" | "cards.json") || path.starts_with("scripts/") || path.starts_with("rules/")
}

/// The check of an uploaded pack. For now: a sane zip (entry count, safe paths) with a
/// `manifest.json` that has the basic fields; the rules hash is SHA-256 over
/// `path:sha256(bytes)\n` of the rules files sorted by path.
// ponytail: manifest-only check until the engine loads packs (phase D: load, compile the
// scripts, a trial bot game); extend here, every upload path goes through this function.
pub fn validate_pack<R: Read + Seek>(r: R) -> Result<PackInfo, String> {
    let mut z = zip::ZipArchive::new(r).map_err(|e| format!("not a zip file: {e}"))?;
    if z.len() > MAX_ENTRIES {
        return Err(format!("too many files: {} (at most {MAX_ENTRIES})", z.len()));
    }
    let mut rules = vec![];
    for name in z.file_names() {
        let name = name.map_err(|e| format!("bad file name: {e}"))?;
        let bad = name.is_empty()
            || name.len() > 255
            || name.starts_with('/')
            || name.contains('\\')
            || name.contains('\0')
            || name.contains(':')
            || name.split('/').any(|p| p == ".." || p == ".");
        if bad {
            return Err(format!("unsafe path in the zip: {:?}", name.chars().take(80).collect::<String>()));
        }
        if rules_file(&name) && !name.ends_with('/') {
            rules.push(name.into_owned());
        }
    }
    let manifest: Value = {
        let f = z.by_name("manifest.json").map_err(|_| "no manifest.json at the top of the zip".to_string())?;
        if f.size() > MAX_MANIFEST {
            return Err("manifest.json is over 64 KB".into());
        }
        let mut s = String::new();
        f.take(MAX_MANIFEST + 1).read_to_string(&mut s).map_err(|e| format!("manifest.json: {e}"))?;
        serde_json::from_str(&s).map_err(|e| format!("manifest.json is not valid JSON: {e}"))?
    };
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
    rules.sort();
    let mut all = Sha256::new();
    let mut budget = MAX_RULES;
    for path in rules {
        let f = z.by_name(&path).map_err(|e| format!("{path}: {e}"))?;
        let mut h = Sha256::new();
        let n = std::io::copy(&mut f.take(budget + 1), &mut h).map_err(|e| format!("{path}: {e}"))?;
        if n > budget {
            return Err("the rules files are over 64 MB together".into());
        }
        budget -= n;
        all.update(format!("{path}:{}\n", hex(h.finalize())));
    }
    Ok(PackInfo { id: id.into(), version: version.into(), name: Value::Object(name.clone()), rules_hash: hex(all.finalize()) })
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

async fn validate_file(path: &FsPath) -> Result<PackInfo, PackErr> {
    let p = path.to_path_buf();
    tokio::task::spawn_blocking(move || validate_pack(std::fs::File::open(p).map_err(|e| e.to_string())?))
        .await
        .map_err(|_| PackErr::new(StatusCode::INTERNAL_SERVER_ERROR, "server", "Server error"))?
        .map_err(|e| PackErr::new(StatusCode::UNPROCESSABLE_ENTITY, "invalid", e))
}

/// Checks a received file and registers it (server pack: `owner` None). Stores the file
/// unless the storage has it already.
pub async fn add(app: &AppRef, file: &FsPath, hash: &str, size: u64, owner: Option<i64>) -> Result<pack::Model, PackErr> {
    let info = validate_file(file).await?;
    let mine = |owner: Option<i64>| match owner {
        Some(o) => Condition::all().add(pack::Column::Owner.eq(o)),
        None => Condition::all().add(pack::Column::Owner.is_null()),
    };
    let dup = pack::Entity::find().filter(mine(owner)).filter(pack::Column::ContentHash.eq(hash)).one(&app.db).await?;
    if dup.is_some() {
        return Err(PackErr::new(StatusCode::CONFLICT, "exists", "This pack is uploaded already"));
    }
    if !app.store.exists(hash).await.map_err(store_err)? {
        app.store.put_file(hash, file).await.map_err(store_err)?;
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
        content_hash: Set(hash.into()),
        size: Set(size as i64),
        owner: Set(owner),
        enabled: Set(true),
        created: Set(ranked::now()),
        downloads: Set(0),
        ..Default::default()
    }
    .insert(&tx)
    .await?;
    tx.commit().await?;
    Ok(row)
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
           "rules_hash": p.rules_hash, "content_hash": p.content_hash, "size": p.size,
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
    let p = match add(&app, &up.path, &up.hash, up.size, Some(a.id)).await {
        Ok(p) => p,
        Err(e) => {
            if e.1 == "invalid" {
                app.event(Event::new("pack_rejected", format!("{}'s pack was refused: {}", a.name, e.2)).user(a.id, &a.name)
                    .data(json!({"reason": e.2, "content_hash": up.hash, "size": up.size})));
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

/// Imports every `*.cardpack` in `dir` not imported before, as an enabled server pack (so
/// a pack the admin deleted stays deleted). Returns how many were added.
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
        let r = match add(app, &f, &hash, size, None).await {
            Ok(p) => {
                app.event(Event::new("pack_import", format!("Bundled pack {} installed", label(&p))).data(event_data(&p)));
                tracing::info!("bundled pack {} installed: {}", f.display(), label(&p));
                added += 1;
                true
            }
            Err(PackErr(_, "exists", _)) => true,
            Err(PackErr(_, "invalid", why)) => {
                app.event(Event::new("pack_rejected", format!("Bundled pack {} refused: {why}", f.display())).data(json!({"reason": why, "content_hash": hash})));
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
           "downloads": p.downloads, "owner": p.owner.map(|o| json!({"id": o, "user": names.get(&o)}))})
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

    const MANIFEST: &str = r#"{"format": 1, "id": "org.test.neon", "version": "1.0.0", "name": {"en": "Neon", "ru": "Неон"}}"#;

    #[test]
    fn validates_manifest_and_hashes_rules() {
        let a = zip_of(&[("manifest.json", MANIFEST), ("rules.json", "{}"), ("cards.json", "[]"), ("art/x.webp", "1")]);
        let info = validate_pack(Cursor::new(&a)).unwrap();
        assert_eq!((info.id.as_str(), info.version.as_str()), ("org.test.neon", "1.0.0"));
        assert_eq!(info.name["ru"], "Неон");
        // Art does not change the rules hash; a card does; the order in the zip does not.
        let b = zip_of(&[("cards.json", "[]"), ("manifest.json", MANIFEST), ("rules.json", "{}"), ("art/x.webp", "2")]);
        assert_eq!(validate_pack(Cursor::new(&b)).unwrap().rules_hash, info.rules_hash);
        let c = zip_of(&[("manifest.json", MANIFEST), ("rules.json", "{}"), ("cards.json", "[1]")]);
        assert_ne!(validate_pack(Cursor::new(&c)).unwrap().rules_hash, info.rules_hash);
        let lines = format!("cards.json:{}\nrules.json:{}\n", hex(Sha256::digest(b"[]")), hex(Sha256::digest(b"{}")));
        assert_eq!(info.rules_hash, hex(Sha256::digest(lines.as_bytes())));
    }

    #[test]
    fn refuses_bad_packs() {
        let bad = |files: &[(&str, &str)]| validate_pack(Cursor::new(zip_of(files))).unwrap_err();
        assert!(validate_pack(Cursor::new(b"not a zip")).unwrap_err().contains("not a zip"));
        assert!(bad(&[("rules.json", "{}")]).contains("no manifest.json"));
        assert!(bad(&[("manifest.json", "{")]).contains("not valid JSON"));
        assert!(bad(&[("manifest.json", r#"{"format": 2, "id": "a", "version": "1", "name": {"en": "A"}}"#)]).contains("format 2"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "Bad Id", "version": "1", "name": {"en": "A"}}"#)]).contains("id must"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "", "name": {"en": "A"}}"#)]).contains("version"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "1", "name": "A"}"#)]).contains("name"));
        assert!(bad(&[("manifest.json", r#"{"format": 1, "id": "a", "version": "1", "name": {"en": " "}}"#)]).contains("name.en"));
        assert!(bad(&[("manifest.json", MANIFEST), ("../evil.lua", "x")]).contains("unsafe path"));
        assert!(bad(&[("manifest.json", MANIFEST), ("scripts\\a.lua", "x")]).contains("unsafe path"));
        let big = format!(r#"{{"format": 1, "id": "a", "version": "1", "name": {{"en": "A"}}, "pad": "{}"}}"#, "x".repeat(70_000));
        assert!(bad(&[("manifest.json", &big)]).contains("64 KB"));
    }
}
