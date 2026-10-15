//! A login: the client holds the token, the database only its SHA-256.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "sessions")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub hash: Vec<u8>,
    pub account: i64,
    /// "game" (the game client) | "admin" (the admin panel cookie).
    pub kind: String,
    /// Renewed on use (sliding).
    pub expires: i64,
    /// The admin panel's CSRF token ("" for game sessions).
    pub csrf: String,
    pub created: i64,
    pub last_used: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(belongs_to = "super::account::Entity", from = "Column::Account", to = "super::account::Column::Id", on_delete = "Cascade")]
    Account,
}

impl Related<super::account::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Account.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
