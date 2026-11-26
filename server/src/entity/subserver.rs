// FOUNDATION: a verbatim copy of the foundation agent's file, a stand-in until it lands (take theirs at merge).
//! A sub-server (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §1): one of the game servers this
//! server hosts, at `/s/<name>/…`. Row 0 is "main", today's server at the bare paths.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "subserver")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The path part: `[a-z0-9-]{3,32}`, unique.
    pub name: String,
    pub title: String,
    /// The owner's account (None: main).
    pub owner: Option<i64>,
    /// "active" | "suspended" | "unavailable".
    pub state: String,
    /// JSON: the limits the super admin set ({} = the defaults).
    pub limits: String,
    pub created: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
