// FOUNDATION: a verbatim copy of the foundation agent's file, a stand-in until it lands (take theirs at merge).
//! The audit log: every change of roles, permissions, bans, settings, limits, quotas and sub-server states.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "audit")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// Unix ms.
    pub at: i64,
    /// Who did it.
    pub account: i64,
    pub subserver: i64,
    pub action: String,
    pub target: String,
    /// JSON.
    pub before: String,
    /// JSON.
    pub after: String,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
