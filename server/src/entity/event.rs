//! The server's event log: logins, social, chat, queues, every game action, admin actions,
//! errors. Names are copied in, so the log outlives deleted accounts.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "events")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// Unix milliseconds.
    pub at: i64,
    /// e.g. "login", "msg", "game_action" (the list: README, Admin panel).
    pub kind: String,
    /// Who did it.
    pub account: Option<i64>,
    pub user: Option<String>,
    /// The other side: a friend, a message's recipient, an admin action's target.
    pub other: Option<String>,
    pub game: Option<String>,
    /// One human line.
    pub text: String,
    /// Details as JSON (an action, a message's text, an address…).
    pub data: Option<String>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
