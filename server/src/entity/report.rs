//! A problem report a player sent from the game (`crate::reports`): a thread the player and the
//! admins write in (`report_message`). Its picture and voice message are files in the store
//! (`reports/<id>/screen.png`, `reports/<id>/voice.ogg`).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "reports")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The sub-server it was sent to (0 = the main one).
    pub subserver: i64,
    pub account: i64,
    /// The time on the player's device as he wrote it; the time the server got it; the thread's
    /// last message or change.
    pub written_at: i64,
    pub received_at: i64,
    pub last_at: i64,
    pub text: String,
    /// The game's version (also in `context`; a column for the filter).
    pub version: String,
    /// JSON: version, platform, screen, language, pack {id, version, rules_hash}, game.
    pub context: String,
    /// JSON: the game ids (the current one first, then the last 5 finished).
    pub games: String,
    /// Has a picture, a voice message (in the store).
    pub screen: bool,
    pub voice: bool,
    /// "open" | "resolved" | "rejected" (the player sees open or closed).
    pub state: String,
    /// The admins' own note.
    pub note: String,
    /// A duplicate merged into another report: the admins see the thread there; the player still
    /// sees his own.
    pub merged_into: Option<i64>,
    /// An admin has opened it; something new for the admins (the report, a player's answer); for
    /// the player (an answer, a state change).
    pub admin_opened: bool,
    pub admin_unread: bool,
    pub player_unread: bool,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
