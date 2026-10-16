//! An account's Arena run (one at a time, in one pack): the engine recomputes heroes and
//! offers from seed + picks.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "arena")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    pub seed: i64,
    /// The chosen hero's index; −1 = not chosen yet.
    pub hero: i64,
    /// JSON array of the offer indexes picked.
    pub picks: String,
    /// The engine's last draft reply (JSON).
    pub draft: String,
    pub wins: i64,
    pub losses: i64,
    /// The pack's rules_hash the run is drafted and played in ("" = the built-in Classic rules).
    pub pack: String,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
