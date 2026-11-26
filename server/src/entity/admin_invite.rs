//! An admin invite (`crate::subservers`): registering or logging in with it makes a new sub-server owned by that
//! account, with the built-in Admin role there. One use.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "admin_invite")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// A uuid v4.
    pub key: String,
    pub note: Option<String>,
    pub created: i64,
    pub created_by: Option<i64>,
    pub created_by_name: String,
    pub revoked: bool,
    /// The account that took it, when, and the sub-server it made.
    pub used_by: Option<i64>,
    pub used_at: Option<i64>,
    pub subserver: Option<i64>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
