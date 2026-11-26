//! The admin panel's roles and the audit log (beside admin.rs, behind its guard): the roles of this sub-server
//! and the global ones with their members, making and changing a sub-server's own roles, giving and taking them,
//! and the audit rows (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §2). One may only put in a
//! role, or give, the permissions one has; built-in roles are read-only; the last Super admin keeps the role.

use crate::admin::{db_err, err, forbidden, need, Admin};
use crate::db;
use crate::entity::{account_role, audit, role};
use crate::perm;
use crate::ws::accounts_in_order;
use crate::AppRef;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, Unchanged};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/roles", need("roles.view", get(list)).merge(need("roles.edit", post(create))))
        .route("/admin/api/roles/{id}", need("roles.edit", post(edit)))
        .route("/admin/api/roles/{id}/delete", need("roles.edit", post(delete)))
        .route("/admin/api/roles/{id}/assign", need("roles.assign", post(assign)))
        .route("/admin/api/roles/{id}/unassign", need("roles.assign", post(unassign)))
        .route("/admin/api/accounts/{id}/roles", get(account_roles)) // players.view or roles.view
        .route("/admin/api/audit", need("audit.view", get(audit_list)))
}

type Res<T> = Result<T, Response>;

fn bad(text: &str) -> Response {
    err(StatusCode::BAD_REQUEST, text)
}

fn role_json(r: &role::Model, members: Vec<Value>) -> Value {
    json!({"id": r.id, "name": r.name, "subserver": r.subserver, "perms": perm::perms_of(r), "builtin": r.builtin, "members": members})
}

/// The roles one sees here: this sub-server's and the global ones.
fn here(a: &Admin) -> Condition {
    Condition::any().add(role::Column::Subserver.is_null()).add(role::Column::Subserver.eq(a.scope.id))
}

async fn list(State(app): State<AppRef>, Extension(a): Extension<Admin>) -> Response {
    let r = async {
        let roles = role::Entity::find().filter(here(&a)).order_by_asc(role::Column::Id).all(&app.db).await?;
        let rows = account_role::Entity::find().filter(account_role::Column::Role.is_in(roles.iter().map(|r| r.id))).all(&app.db).await?;
        let mut ids: Vec<i64> = rows.iter().map(|r| r.account).collect();
        ids.sort_unstable();
        ids.dedup();
        let names: HashMap<i64, String> = accounts_in_order(&app.db, &ids).await?.into_iter().map(|x| (x.id, x.name)).collect();
        let list: Vec<Value> = roles
            .iter()
            .map(|r| {
                let members = rows.iter().filter(|m| m.role == r.id).filter_map(|m| Some(json!({"id": m.account, "user": names.get(&m.account)?})));
                role_json(r, members.collect())
            })
            .collect();
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "all_perms": perm::ALL, "super": perm::SUPER, "mine": a.perms}))
    }
    .await;
    match r {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}

/// A role of this sub-server or a global one, by id.
async fn find(app: &AppRef, a: &Admin, id: i64) -> Res<role::Model> {
    match role::Entity::find_by_id(id).filter(here(a)).one(&app.db).await {
        Ok(Some(r)) => Ok(r),
        Ok(None) => Err(err(StatusCode::NOT_FOUND, "No such role")),
        Err(e) => Err(db_err(e)),
    }
}

/// May this admin change or give the role: a global one only with superadmins.manage, and only with every
/// permission it gives.
fn may_handle(a: &Admin, r: &role::Model) -> Res<()> {
    if r.subserver.is_none() {
        a.need("superadmins.manage")?;
    }
    match perm::expand(&perm::perms_of(r)).into_iter().find(|p| !a.can(p)) {
        Some(p) => Err(forbidden(&p)),
        None => Ok(()),
    }
}

#[derive(Deserialize)]
struct RoleIn {
    name: String,
    perms: Vec<String>,
}

/// Checks a sub-server role's name and permission list: known names (or `*`, `x.*`), none of the super level,
/// none the editor lacks. The name is unique here.
async fn checked(app: &AppRef, a: &Admin, f: RoleIn, id: Option<i64>) -> Res<(String, Vec<String>)> {
    let name = f.name.trim().to_string();
    if name.is_empty() || name.chars().count() > 40 {
        return Err(bad("A role's name is 1 to 40 characters"));
    }
    let known = |p: &str| p == "*" || perm::ALL.contains(&p) || p.strip_suffix('*').is_some_and(|pre| pre.ends_with('.') && perm::ALL.iter().any(|x| x.starts_with(pre)));
    if let Some(p) = f.perms.iter().find(|p| !known(p)) {
        return Err(bad(&format!("No such permission: {p}")));
    }
    let mut perms = f.perms;
    perms.sort();
    perms.dedup();
    let all = perm::expand(&perms);
    if let Some(p) = all.iter().find(|p| perm::SUPER.contains(&p.as_str())) {
        return Err(bad(&format!("{p} is a super admin permission: a server's role can't have it")));
    }
    if let Some(p) = all.iter().find(|p| !a.can(p)) {
        return Err(forbidden(p));
    }
    let mut taken = role::Entity::find().filter(here(a)).filter(role::Column::Name.eq(&name));
    if let Some(id) = id {
        taken = taken.filter(role::Column::Id.ne(id));
    }
    match taken.count(&app.db).await {
        Ok(0) => Ok((name, perms)),
        Ok(_) => Err(err(StatusCode::CONFLICT, "A role with this name exists")),
        Err(e) => Err(db_err(e)),
    }
}

/// Logs the change twice: the audit row and the admin event (the event log, the live feed).
async fn record(app: &AppRef, a: &Admin, action: &str, target: &str, before: Value, after: Value, text: String) {
    perm::audit(&app.db, a.me.id, a.scope.id, action, target, before, after).await;
    tracing::info!("admin: {text}");
    app.event(a.ev(text).data(json!({"action": action, "target": target})));
}

async fn create(State(app): State<AppRef>, Extension(a): Extension<Admin>, Json(f): Json<RoleIn>) -> Response {
    let (name, perms) = match checked(&app, &a, f, None).await {
        Ok(v) => v,
        Err(r) => return r,
    };
    let row = role::ActiveModel { subserver: Set(Some(a.scope.id)), name: Set(name.clone()), perms: Set(json!(perms).to_string()), builtin: Set(false), ..Default::default() };
    match row.insert(&app.db).await {
        Ok(r) => {
            record(&app, &a, "role.create", &name, Value::Null, json!({"name": name, "perms": perms}), format!("{} made the role {name}", a.me.name)).await;
            Json(json!({"id": r.id})).into_response()
        }
        Err(e) => db_err(e),
    }
}

/// A role this admin may change: here, not built-in, and every permission it has now his too.
async fn own(app: &AppRef, a: &Admin, id: i64) -> Res<role::Model> {
    let r = find(app, a, id).await?;
    if r.builtin {
        return Err(err(StatusCode::FORBIDDEN, "Built-in roles can't be changed"));
    }
    may_handle(a, &r)?;
    Ok(r)
}

async fn edit(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<RoleIn>) -> Response {
    let r = match own(&app, &a, id).await {
        Ok(r) => r,
        Err(r) => return r,
    };
    let (name, perms) = match checked(&app, &a, f, Some(id)).await {
        Ok(v) => v,
        Err(r) => return r,
    };
    let row = role::ActiveModel { id: Unchanged(id), name: Set(name.clone()), perms: Set(json!(perms).to_string()), ..Default::default() };
    if let Err(e) = row.update(&app.db).await {
        return db_err(e);
    }
    let before = json!({"name": r.name, "perms": perm::perms_of(&r)});
    record(&app, &a, "role.edit", &name, before, json!({"name": name, "perms": perms}), format!("{} changed the role {name}", a.me.name)).await;
    Json(json!({"ok": true})).into_response()
}

async fn delete(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    let r = match own(&app, &a, id).await {
        Ok(r) => r,
        Err(r) => return r,
    };
    // (its account_role rows go with it: ON DELETE CASCADE)
    if let Err(e) = role::Entity::delete_by_id(id).exec(&app.db).await {
        return db_err(e);
    }
    let before = json!({"name": r.name, "perms": perm::perms_of(&r)});
    record(&app, &a, "role.delete", &r.name, before, Value::Null, format!("{} deleted the role {}", a.me.name, r.name)).await;
    Json(json!({"ok": true})).into_response()
}

#[derive(Deserialize)]
struct AssignIn {
    account: i64,
}

async fn assign(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<AssignIn>) -> Response {
    give(app, a, id, f.account, true).await
}

async fn unassign(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<AssignIn>) -> Response {
    give(app, a, id, f.account, false).await
}

/// Gives (on) or takes (off) a role.
async fn give(app: AppRef, a: Admin, id: i64, account: i64, on: bool) -> Response {
    let r = match find(&app, &a, id).await {
        Ok(r) => r,
        Err(r) => return r,
    };
    if let Err(r) = may_handle(&a, &r) {
        return r;
    }
    let t = match db::account_by_id(&app.db, account).await {
        Ok(Some(t)) => t,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No such account"),
        Err(e) => return db_err(e),
    };
    let db = &app.db;
    let res = if on {
        let row = account_role::ActiveModel { account: Set(account), role: Set(id), subserver: Set(r.subserver) };
        account_role::Entity::insert(row).on_conflict_do_nothing().exec_without_returning(db).await.map(|_| ())
    } else {
        // ponytail: count then delete, not atomic; two super admins taking it from each other at once could both pass
        if r.subserver.is_none() && r.name == perm::SUPER_ADMIN {
            let holders = account_role::Entity::find().filter(account_role::Column::Role.eq(id)).filter(account_role::Column::Account.ne(account)).count(db).await;
            match holders {
                Ok(0) => return err(StatusCode::CONFLICT, "The last Super admin can't lose the role"),
                Ok(_) => {}
                Err(e) => return db_err(e),
            }
        }
        account_role::Entity::delete_many().filter(account_role::Column::Account.eq(account)).filter(account_role::Column::Role.eq(id)).exec(db).await.map(|_| ())
    };
    if let Err(e) = res {
        return db_err(e);
    }
    let (action, before, after, text) = if on {
        ("role.assign", Value::Null, json!(r.name), format!("{} gave {} the role {}", a.me.name, t.name, r.name))
    } else {
        ("role.unassign", json!(r.name), Value::Null, format!("{} took the role {} from {}", a.me.name, r.name, t.name))
    };
    record(&app, &a, action, &format!("role:{id} account:{account}"), before, after, text).await;
    Json(json!({"ok": true})).into_response()
}

async fn account_roles(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>) -> Response {
    if !a.can("players.view") && !a.can("roles.view") {
        return forbidden("players.view");
    }
    match perm::roles(&app.db, id, a.scope.id).await {
        Ok(roles) => Json(json!({"list": roles.iter().map(|r| role_json(r, vec![])).collect::<Vec<_>>()})).into_response(),
        Err(e) => db_err(e),
    }
}

#[derive(Deserialize)]
struct AuditQ {
    /// An action or its start ("role" = every `role.…`).
    action: Option<String>,
    /// Who did it (an account name).
    account: Option<String>,
    page: Option<u64>,
    size: Option<u64>,
}

/// This sub-server's audit rows, newest first: {list, total, page, size}.
async fn audit_list(State(app): State<AppRef>, Extension(a): Extension<Admin>, Query(q): Query<AuditQ>) -> Response {
    let r = async {
        let db = &app.db;
        let mut sel = audit::Entity::find().filter(audit::Column::Subserver.eq(a.scope.id));
        if let Some(act) = q.action.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            sel = sel.filter(audit::Column::Action.starts_with(act));
        }
        if let Some(who) = q.account.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            let id = db::account_by_name(db, who).await?.map_or(-1, |x| x.id);
            sel = sel.filter(audit::Column::Account.eq(id));
        }
        let (page, size) = (q.page.unwrap_or(0).min(1_000_000), q.size.unwrap_or(50).clamp(1, 500));
        let p = sel.order_by_desc(audit::Column::Id).paginate(db, size);
        let total = p.num_items().await?;
        let rows = p.fetch_page(page).await?;
        let mut ids: Vec<i64> = rows.iter().map(|r| r.account).collect();
        ids.sort_unstable();
        ids.dedup();
        let names: HashMap<i64, String> = accounts_in_order(db, &ids).await?.into_iter().map(|x| (x.id, x.name)).collect();
        let parse = |s: &str| serde_json::from_str::<Value>(s).unwrap_or(Value::Null);
        let list: Vec<Value> = rows
            .iter()
            .map(|r| json!({"id": r.id, "at": r.at, "account": r.account, "user": names.get(&r.account), "action": r.action,
                            "target": r.target, "before": parse(&r.before), "after": parse(&r.after)}))
            .collect();
        Ok::<_, sea_orm::DbErr>(json!({"list": list, "total": total, "page": page, "size": size}))
    }
    .await;
    match r {
        Ok(v) => Json(v).into_response(),
        Err(e) => db_err(e),
    }
}
