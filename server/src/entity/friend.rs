//! A friendship, stored both ways: (a, b) and (b, a).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "friends")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub a: i64,
    #[sea_orm(primary_key, auto_increment = false)]
    pub b: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
