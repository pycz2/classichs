//! Roles and permissions (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §2): a role is a
//! named set of permissions, given to an account in a sub-server (or globally: then in every one); what
//! the account may do there is the union of its roles. And the audit log of the changes.

use crate::entity::{account_role, audit, role};
use crate::App;
use sea_orm::{ActiveModelTrait, ColumnTrait, Condition, ConnectionTrait, EntityTrait, QueryFilter, Set};
use serde_json::Value;
use std::collections::BTreeSet;

/// Every permission (each one guards an admin API endpoint and the panel's view or button).
pub const ALL: &[&str] = &[
    "panel.open",
    "dashboard.view",
    "players.view",
    "players.edit",
    "players.ban",
    "players.delete",
    "players.decks.view",
    "players.decks.edit",
    "players.sessions.kick",
    "invites.view",
    "invites.create",
    "invites.revoke",
    "roles.view",
    "roles.edit",
    "roles.assign",
    "packs.view",
    "packs.upload",
    "packs.enable",
    "packs.delete",
    "packs.default",
    "settings.view",
    "settings.edit",
    "settings.retention",
    "bots.view",
    "bots.edit",
    "tournaments.view",
    "tournaments.create",
    "tournaments.manage",
    "tournaments.delete",
    "chats.view",
    "chats.write_as_admin",
    "chats.moderate",
    "replays.view",
    "replays.delete",
    "stats.view",
    "server.view",
    "reports.view",
    "reports.manage",
    "reports.export",
    "audit.view",
    "limits.view",
    "subservers.create_own",
    "subservers.view",
    "subservers.create",
    "subservers.suspend",
    "subservers.delete",
    "subservers.enter",
    "admin_invites.create",
    "superadmins.manage",
    "quotas.edit",
    "limits.edit",
];

/// The super level: only a global role (Super admin) gives these.
pub const SUPER: &[&str] = &[
    "settings.retention",
    "subservers.view",
    "subservers.create",
    "subservers.suspend",
    "subservers.delete",
    "subservers.enter",
    "admin_invites.create",
    "superadmins.manage",
    "quotas.edit",
    "limits.edit",
];

/// The built-in roles: (name, permissions). "Super admin" is global; the others are made in every sub-server.
pub const SUPER_ADMIN: &str = "Super admin";

pub fn builtin() -> Vec<(&'static str, Vec<String>)> {
    let admin = ALL.iter().filter(|p| !SUPER.contains(p)).map(|p| p.to_string()).collect();
    let moderator = ["panel.open", "players.view", "players.ban", "chats.*", "tournaments.manage", "replays.view", "reports.view", "reports.manage"];
    let viewer = ALL.iter().filter(|p| p.ends_with(".view") && !SUPER.contains(p)).map(|p| p.to_string());
    vec![
        ("Admin", admin),
        ("Moderator", moderator.iter().map(|p| p.to_string()).collect()),
        ("Viewer", std::iter::once("panel.open".to_string()).chain(viewer).collect()),
    ]
}

/// Does a role's permission list give `p`? `*` gives all, `chats.*` every `chats.…`.
pub fn grants(perms: &[String], p: &str) -> bool {
    perms.iter().any(|g| g == "*" || g == p || g.strip_suffix('*').is_some_and(|pre| pre.ends_with('.') && p.starts_with(pre)))
}

/// The permissions a role's list stands for (wildcards expanded to the known names).
pub fn expand(perms: &[String]) -> BTreeSet<String> {
    ALL.iter().filter(|p| grants(perms, p)).map(|p| p.to_string()).collect()
}

pub fn perms_of(r: &role::Model) -> Vec<String> {
    serde_json::from_str(&r.perms).unwrap_or_default()
}

/// The roles an account has in a sub-server (its global ones included).
pub async fn roles(c: &impl ConnectionTrait, account: i64, subserver: i64) -> Result<Vec<role::Model>, sea_orm::DbErr> {
    let ids: Vec<i64> = account_role::Entity::find()
        .filter(account_role::Column::Account.eq(account))
        .filter(Condition::any().add(account_role::Column::Subserver.is_null()).add(account_role::Column::Subserver.eq(subserver)))
        .all(c)
        .await?
        .into_iter()
        .map(|r| r.role)
        .collect();
    role::Entity::find().filter(role::Column::Id.is_in(ids)).all(c).await
}

/// Everything the account may do in the sub-server (the admin panel shows only that).
pub async fn all(app: &App, account: i64, subserver: i64) -> BTreeSet<String> {
    let roles = roles(&app.db, account, subserver).await.unwrap_or_default();
    // a sub-server's role never gives the super level, whatever its list says
    roles.iter().flat_map(|r| expand(&perms_of(r)).into_iter().filter(|p| r.subserver.is_none() || !SUPER.contains(&p.as_str()))).collect()
}

pub async fn has(app: &App, account: i64, p: &str, subserver: i64) -> bool {
    all(app, account, subserver).await.contains(p)
}

/// Gives the account the global Super admin role (the server's first admin, `db::make_superuser`).
pub async fn make_super(c: &impl ConnectionTrait, account: i64) -> Result<(), sea_orm::DbErr> {
    let Some(r) = role::Entity::find().filter(role::Column::Name.eq(SUPER_ADMIN)).filter(role::Column::Subserver.is_null()).one(c).await? else {
        return Err(sea_orm::DbErr::Custom("no Super admin role".into()));
    };
    let row = account_role::ActiveModel { account: Set(account), role: Set(r.id), subserver: Set(None) };
    account_role::Entity::insert(row).on_conflict_do_nothing().exec_without_returning(c).await?;
    Ok(())
}

/// Gives the account a built-in role of a sub-server ("Admin", "Moderator", "Viewer").
pub async fn give_builtin(c: &impl ConnectionTrait, account: i64, subserver: i64, name: &str) -> Result<(), sea_orm::DbErr> {
    let r = role::Entity::find()
        .filter(role::Column::Subserver.eq(subserver))
        .filter(role::Column::Name.eq(name))
        .filter(role::Column::Builtin.eq(true))
        .one(c)
        .await?
        .ok_or_else(|| sea_orm::DbErr::Custom(format!("no {name} role")))?;
    let row = account_role::ActiveModel { account: Set(account), role: Set(r.id), subserver: Set(Some(subserver)) };
    account_role::Entity::insert(row).on_conflict_do_nothing().exec_without_returning(c).await?;
    Ok(())
}

/// Writes an audit row: who changed what, where, before → after.
pub async fn audit(c: &impl ConnectionTrait, account: i64, subserver: i64, action: &str, target: &str, before: Value, after: Value) {
    let row = audit::ActiveModel {
        at: Set(crate::events::now_ms()),
        account: Set(account),
        subserver: Set(subserver),
        action: Set(action.into()),
        target: Set(target.into()),
        before: Set(before.to_string()),
        after: Set(after.to_string()),
        ..Default::default()
    };
    if let Err(e) = row.insert(c).await {
        tracing::error!("audit: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wildcards() {
        let p = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(grants(&p(&["*"]), "players.ban"));
        assert!(grants(&p(&["chats.*"]), "chats.moderate"));
        assert!(!grants(&p(&["chats.*"]), "chatsx.y"));
        assert!(!grants(&p(&["players.view"]), "players.ban"));
        let b = builtin();
        assert!(!b[0].1.iter().any(|p| SUPER.contains(&p.as_str())), "Admin has no super level permission");
        assert!(b[2].1.iter().all(|p| p.ends_with(".view") || p == "panel.open"));
    }
}
