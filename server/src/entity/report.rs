//! A problem report a player sent from the game (`crate::reports`). Its picture and voice message
//! are files in the store (`reports/<id>/screen.png`, `reports/<id>/voice.ogg`).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "reports")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The sub-server it was sent to (0 = the main one).
    pub subserver: i64,
    pub account: i64,
    /// The time on the player's device as he wrote it; the time the server got it.
    pub written_at: i64,
    pub received_at: i64,
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
    /// "new" | "seen" | "done".
    pub state: String,
    pub note: String,
    /// The private message an admin answered with.
    pub answer_message: Option<i64>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
