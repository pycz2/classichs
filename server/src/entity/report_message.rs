//! A message in a problem report's thread after the report itself: the player's or an admin's.
//! Its picture (if any) is `reports/<report>/m<id>.png` in the store.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "report_messages")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub report: i64,
    /// The writer (gone: None) and his name then.
    pub account: Option<i64>,
    pub name: String,
    /// An admin's answer (else the player's).
    pub admin: bool,
    pub text: String,
    pub at: i64,
    pub screen: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
