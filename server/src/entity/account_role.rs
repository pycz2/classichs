// FOUNDATION: a verbatim copy of the foundation agent's file, a stand-in until it lands (take theirs at merge).
//! A role given to an account, in the role's sub-server (None: a global role, every sub-server).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "account_role")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    #[sea_orm(primary_key, auto_increment = false)]
    pub role: i64,
    pub subserver: Option<i64>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
