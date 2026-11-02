//! A player's deck kept on the server (the client's deck list ticks which): per account and
//! pack (the manifest id, as standings, so a new version keeps them).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "decks")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub account: i64,
    /// The pack's manifest id ("classic-2014").
    pub pack: String,
    pub name: String,
    pub hero: String,
    /// JSON array of card ids.
    pub cards: String,
    pub created: i64,
    pub updated: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
