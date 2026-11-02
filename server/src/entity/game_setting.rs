//! A player's choices for one game (the client's art and music sets), per account and pack (the
//! manifest id, as decks, so a new version keeps them). `value` is a JSON object of short texts.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "game_settings")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    /// The pack's manifest id ("classic-2014").
    #[sea_orm(primary_key, auto_increment = false)]
    pub pack: String,
    /// JSON object {key: text}.
    pub value: String,
    pub updated: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
