//! A message in a tournament chat (0.74, `crate::chat`): the tournaments list's common chat
//! (channel `tournaments`) or a tournament's own (`t:<tournament id>`). A deleted message keeps
//! its row: everyone sees "deleted by <moderator>" instead of the text.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "chat_message")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The sub-server (0 = the main one).
    pub subserver: i64,
    pub channel: String,
    pub account: i64,
    pub text: String,
    pub at: i64,
    /// The moderator who deleted it (None: not deleted) and when.
    pub deleted_by: Option<i64>,
    pub deleted_at: Option<i64>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
