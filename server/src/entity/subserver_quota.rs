//! How many sub-servers an account may own (`crate::subservers`; no row: 0).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "subserver_quota")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    pub quota: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
