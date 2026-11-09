//! stub: part B (replays). Only the access check tournaments extend; the integrator replaces this
//! file and keeps the tournament line in `can_view`.

use crate::AppRef;

/// May `account` see the replay of `game`? (B: the game's players; D: tournament games.)
// stub: part B
pub async fn can_view(app: &AppRef, account: i64, game: &str) -> bool {
    crate::tournament::replay_allowed(app, account, game).await
}
