//! The sub-server a request or a connection belongs to (docs/superpowers/specs/2026-11-26-roles-subservers-design.md
//! §1): `/s/<name>/…` is the sub-server `name` (its path without the prefix is routed as usual), every other path
//! the main one (id 0). Every query of a sub-server's data filters by `Scope::id`.

use crate::entity::subserver;
use crate::AppRef;
use axum::extract::{FromRequestParts, Request, State};
use axum::http::request::Parts;
use axum::http::{StatusCode, Uri};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use std::convert::Infallible;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Scope {
    pub id: i64,
}

impl Scope {
    pub const MAIN: Scope = Scope { id: 0 };
}

/// The path prefix of the request's sub-server: "" for main, "/s/<name>" for the others.
#[derive(Clone, Debug, Default)]
pub struct Prefix(pub String);

impl<S: Send + Sync> FromRequestParts<S> for Scope {
    type Rejection = Infallible;

    async fn from_request_parts(parts: &mut Parts, _: &S) -> Result<Scope, Infallible> {
        Ok(parts.extensions.get::<Scope>().copied().unwrap_or(Scope::MAIN))
    }
}

/// Splits `/s/<name>/rest` into ("name", "/rest").
pub fn split(path: &str) -> Option<(&str, String)> {
    let rest = path.strip_prefix("/s/")?;
    let (name, tail) = rest.split_once('/').unwrap_or((rest, ""));
    Some((name, format!("/{tail}")))
}

/// The middleware in front of every route: finds the sub-server, strips its prefix, puts `Scope` and `Prefix`
/// into the request. An unknown sub-server: 404.
pub async fn route(State(app): State<AppRef>, mut req: Request, next: Next) -> Response {
    let Some((name, tail)) = split(req.uri().path()) else {
        req.extensions_mut().insert(Scope::MAIN);
        req.extensions_mut().insert(Prefix::default());
        return next.run(req).await;
    };
    let name = name.to_string();
    let found = subserver::Entity::find().filter(subserver::Column::Name.eq(&name)).one(&app.db).await;
    let Ok(Some(s)) = found else { return (StatusCode::NOT_FOUND, "No such server").into_response() };
    if let Some(r) = crate::subservers::closed(&s, &tail) {
        return r;
    }
    let pq = match req.uri().query() {
        Some(q) => format!("{tail}?{q}"),
        None => tail,
    };
    let mut parts = req.uri().clone().into_parts();
    parts.path_and_query = pq.parse().ok();
    let Ok(uri) = Uri::from_parts(parts) else { return StatusCode::BAD_REQUEST.into_response() };
    *req.uri_mut() = uri;
    req.extensions_mut().insert(Scope { id: s.id });
    req.extensions_mut().insert(Prefix(format!("/s/{name}")));
    next.run(req).await
}

#[cfg(test)]
mod tests {
    #[test]
    fn split() {
        assert_eq!(super::split("/s/abc/admin/api/me"), Some(("abc", "/admin/api/me".into())));
        assert_eq!(super::split("/s/abc"), Some(("abc", "/".into())));
        assert_eq!(super::split("/s/abc/"), Some(("abc", "/".into())));
        assert_eq!(super::split("/admin"), None);
    }
}
