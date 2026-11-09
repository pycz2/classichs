//! A finished game's replay (`crate::replays`): enough to play it again in the rules engine.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "replays")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub game: String,
    /// The pack's rules_hash.
    pub pack: String,
    /// The players' accounts by seat (as `games`).
    pub p0: Option<i64>,
    pub p1: Option<i64>,
    pub ended: i64,
    /// The replay JSON (`replays::build`), deflate-compressed.
    pub data: Vec<u8>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
