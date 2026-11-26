//! The server's integration tests in one test binary (one link instead of one per file: much faster to build).
//! One file per area; `cargo test --release --test all -- flow::` runs one of them.
mod common;
mod admin_extra;
mod admin_players;
mod admin;
mod autobots;
mod bot_levels;
mod bots;
mod chat;
mod brain_search;
mod flow;
mod invites;
mod packs;
mod roles;
mod reports;
mod stats;
mod subserver_mgmt;
mod subservers;
mod tournament;
