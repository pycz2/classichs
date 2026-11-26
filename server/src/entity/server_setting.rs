//! A server-wide setting the admin panel changes (`crate::settings`): key → text.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "server_settings")]
pub struct Model {
    /// The sub-server (`crate::scope`).
    #[sea_orm(primary_key, auto_increment = false)]
    pub subserver: i64,
    #[sea_orm(primary_key, auto_increment = false)]
    pub key: String,
    pub value: String,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
