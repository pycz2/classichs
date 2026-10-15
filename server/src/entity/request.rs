//! A friend request from `src` to `dst`.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "requests")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub src: i64,
    #[sea_orm(primary_key, auto_increment = false)]
    pub dst: i64,
    pub at: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
