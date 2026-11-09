//! stub: part C (spectators). Only the function tournaments call; the integrator replaces this file.

use crate::AppRef;

/// Lets `account` watch the live `game` (`full`: both hands open).
// stub: part C
pub fn add(_app: &AppRef, _game: &str, _account: i64, _full: bool) -> Result<(), &'static str> {
    Err("Watching games is not available on this server yet")
}
