//! A bot of the server (the admin's Bots page): it plays Classic as its own account, through the
//! same protocol as a player (`crate::bots`).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "bots")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The bot's account (one bot per account).
    pub account: i64,
    /// "easy" | "medium" | "hard".
    pub level: String,
    /// "ladder" (ranked and casual in turn) | "ranked" | "casual" | "arena".
    pub modes: String,
    pub enabled: bool,
    /// The daily window it plays in, minutes from 00:00 UTC; from = to: all day.
    pub from_min: i64,
    pub to_min: i64,
    /// The pause before each game, seconds (a random one in [min, max]).
    pub pause_min: i64,
    pub pause_max: i64,
    pub created: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
