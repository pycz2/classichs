//! A chat message between two friends; the pair is (lo, hi) = (smaller id, larger id).
//! The last 200 of a pair are kept.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "messages")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub lo: i64,
    pub hi: i64,
    /// The sender (lo or hi).
    pub src: i64,
    pub text: String,
    pub at: i64,
    /// The recipient has read it.
    pub seen: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
