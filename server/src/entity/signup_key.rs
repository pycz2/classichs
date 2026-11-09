//! An invite key a player registers with (made in the admin panel; `register {key}`).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "signup_keys")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// A uuid v4.
    pub key: String,
    pub note: Option<String>,
    pub uses_total: i64,
    /// Taken in the same transaction as the account's insert (`db::register`).
    pub uses_left: i64,
    pub created: i64,
    /// The admin's account (it may be gone since); its name is kept in `created_by_name`.
    pub created_by: Option<i64>,
    pub created_by_name: String,
    pub revoked: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
