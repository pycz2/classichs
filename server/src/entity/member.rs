//! An account that logged into a sub-server (its players list), with that sub-server's own ban of it (main bans
//! with `accounts.suspended`, everywhere).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "member")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub subserver: i64,
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    pub joined: i64,
    pub suspended: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
