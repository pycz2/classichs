// FOUNDATION: a verbatim copy of the foundation agent's file, a stand-in until it lands (take theirs at merge).
//! A role: a named set of permissions (`crate::perm`), of a sub-server or global (subserver None: the super level).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "role")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub subserver: Option<i64>,
    pub name: String,
    /// JSON list of permission names; `*` = all, `chats.*` = every `chats.…`.
    pub perms: String,
    /// Made by the migration (Super admin, Admin, Moderator, Viewer).
    pub builtin: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
