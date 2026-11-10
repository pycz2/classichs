//! More of the admin panel, beside admin.rs and behind its guard: how much space the database
//! and the pack store take, a pack file by its content or rules hash, and the replay player
//! (the "Replay viewer" web build of the client, ui/replay_app.gd) under /admin/replay/.

use crate::entity::pack;
use crate::AppRef;
use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use sea_orm::{ColumnTrait, Condition, ConnectionTrait, EntityTrait, QueryFilter, QueryOrder, Statement};
use serde_json::json;
use std::path::PathBuf;
use std::sync::OnceLock;

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/storage", get(storage))
        .route("/admin/api/pack_files/{hash}", get(pack_file))
        .route("/admin/replay/{*path}", get(viewer_file))
}

fn err(status: StatusCode, text: &str) -> Response {
    (status, Json(json!({"error": text}))).into_response()
}

// --- sizes -----------------------------------------------------------------------------

/// `{db: {path, file, wal, total}, packs: {bytes, files, what}}` (bytes; an in-memory
/// database has no path and 0 bytes).
async fn storage(State(app): State<AppRef>) -> Response {
    let path = app
        .db
        .query_one_raw(Statement::from_string(app.db.get_database_backend(), "PRAGMA database_list"))
        .await
        .ok()
        .flatten()
        .and_then(|r| r.try_get::<String>("", "file").ok())
        .unwrap_or_default();
    let len = |p: String| std::fs::metadata(p).map_or(0, |m| m.len());
    let (file, wal) = if path.is_empty() { (0, 0) } else { (len(path.clone()), len(format!("{path}-wal"))) };
    let packs = match app.store.usage().await {
        Ok((bytes, files)) => json!({"bytes": bytes, "files": files, "what": app.store.what}),
        Err(e) => {
            tracing::error!("admin: the pack store's size: {e}");
            json!({"error": "Cannot list the pack store", "what": app.store.what})
        }
    };
    Json(json!({"db": {"path": path, "file": file, "wal": wal, "total": file + wal}, "packs": packs})).into_response()
}

// --- a pack file --------------------------------------------------------------------------

/// The newest stored pack with this content hash or rules hash (the replay player has a
/// replay's rules hash), any owner, enabled or not.
async fn pack_file(State(app): State<AppRef>, Path(hash): Path<String>) -> Response {
    if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) {
        return err(StatusCode::NOT_FOUND, "No such pack");
    }
    let row = pack::Entity::find()
        .filter(Condition::any().add(pack::Column::ContentHash.eq(&hash)).add(pack::Column::RulesHash.eq(&hash)))
        .order_by_desc(pack::Column::Id)
        .one(&app.db)
        .await;
    let p = match row {
        Ok(Some(p)) => p,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such pack"),
        Err(e) => {
            tracing::error!("admin: {e}");
            return err(StatusCode::INTERNAL_SERVER_ERROR, "Database error");
        }
    };
    match app.store.get(&p.content_hash).await {
        Ok((size, stream)) => (
            [
                (header::CONTENT_TYPE, "application/zip".to_string()),
                (header::CONTENT_LENGTH, size.to_string()),
                (header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}.cardpack\"", p.content_hash)),
                (header::CACHE_CONTROL, "private, max-age=86400".into()),
            ],
            Body::from_stream(stream),
        )
            .into_response(),
        Err(e) => {
            tracing::error!("admin: pack {}: {e}", p.content_hash);
            err(StatusCode::NOT_FOUND, "The pack's file is not in the store")
        }
    }
}

// --- the replay player ----------------------------------------------------------------------

static REPLAY_DIR: OnceLock<PathBuf> = OnceLock::new();

/// --replay-dir (once, at start).
pub fn set_replay_dir(dir: PathBuf) {
    let _ = REPLAY_DIR.set(dir);
}

/// --replay-dir, else replay-viewer/ next to the binary, else ../share/classichs/replay-viewer
/// above it (the Docker image: /usr/local/share/classichs/replay-viewer).
fn replay_dir() -> PathBuf {
    REPLAY_DIR
        .get_or_init(|| {
            let bin = std::env::current_exe().ok().and_then(|p| Some(p.parent()?.to_path_buf())).unwrap_or_default();
            let near = bin.join("replay-viewer");
            if near.is_dir() { near } else { bin.join("../share/classichs/replay-viewer") }
        })
        .clone()
}

/// What a Godot web build needs: WebAssembly (the engine and the rules), blob: workers
/// (rules.js's bot worker), inline styles; its inline scripts by hash. Framed by the panel only.
fn viewer_csp(index: &str) -> String {
    format!(
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'{}; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; \
         img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; \
         frame-ancestors 'self'",
        crate::admin::script_hashes(index)
    )
}

/// A file of the replay player; an empty path is its index.html.
async fn viewer_file(Path(path): Path<String>, headers: HeaderMap) -> Response {
    let path = if path.is_empty() || path.ends_with('/') { format!("{path}index.html") } else { path };
    let safe = path.split('/').all(|c| !c.is_empty() && !c.starts_with('.') && c.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b)));
    if !safe {
        return err(StatusCode::NOT_FOUND, "No such file");
    }
    let file = replay_dir().join(&path);
    let Ok(meta) = tokio::fs::metadata(&file).await.and_then(|m| if m.is_file() { Ok(m) } else { Err(std::io::ErrorKind::NotFound.into()) }) else {
        return err(StatusCode::NOT_FOUND, "The replay player is not installed on this server (--replay-dir)");
    };
    let mime = match path.rsplit('.').next() {
        Some("html") => "text/html; charset=utf-8",
        Some("js") => "text/javascript; charset=utf-8",
        Some("wasm") => "application/wasm",
        Some("png") => "image/png",
        Some("svg") => "image/svg+xml",
        Some("json") => "application/json",
        _ => "application/octet-stream",
    };
    let mtime = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_secs());
    let etag = format!("\"{:x}-{mtime:x}\"", meta.len());
    let mut res = if headers.get(header::IF_NONE_MATCH).is_some_and(|v| v.as_bytes() == etag.as_bytes()) {
        StatusCode::NOT_MODIFIED.into_response()
    } else if mime.starts_with("text/html") {
        let Ok(html) = tokio::fs::read_to_string(&file).await else { return err(StatusCode::NOT_FOUND, "No such file") };
        let csp = viewer_csp(&html);
        ([(header::CONTENT_SECURITY_POLICY, csp)], html).into_response()
    } else {
        let Ok(f) = tokio::fs::File::open(&file).await else { return err(StatusCode::NOT_FOUND, "No such file") };
        ([(header::CONTENT_LENGTH, meta.len().to_string())], Body::from_stream(tokio_util::io::ReaderStream::new(f))).into_response()
    };
    let h = res.headers_mut();
    h.insert(header::CONTENT_TYPE, mime.parse().unwrap());
    h.insert(header::ETAG, etag.parse().unwrap());
    h.insert(header::CACHE_CONTROL, "no-cache".parse().unwrap()); // (a new build: the ETag differs)
    h.insert(header::X_FRAME_OPTIONS, "SAMEORIGIN".parse().unwrap());
    res
}
