//! A finished game (its moves are in the event log, `events.game`).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "games")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: String,
    /// "casual" | "ranked" | "arena" | "friendly".
    pub mode: String,
    /// The host's account (null once deleted).
    pub p0: Option<i64>,
    pub p1: Option<i64>,
    pub started: i64,
    pub ended: i64,
    /// 0 or 1 (the player number); −1 = nobody.
    pub winner: i64,
    /// over | illegal | desync | cheat | protocol | left | disconnect | aborted.
    pub reason: String,
    /// The pack's rules_hash ("" = the built-in Classic rules, before packs).
    pub pack: String,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
