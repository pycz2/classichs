//! The database tables as SeaORM entities (schema: `crate::migration`).
//! Times are unix seconds, except `events.at` (milliseconds).

pub mod account;
pub mod admin_invite;
pub mod arena;
pub mod block;
pub mod bot;
pub mod deck;
pub mod event;
pub mod friend;
pub mod game;
pub mod game_setting;
pub mod message;
pub mod pack;
pub mod pack_import;
pub mod pack_version;
pub mod replay;
pub mod request;
pub mod server_setting;
pub mod session;
pub mod signup_key;
pub mod standing;
pub mod subserver_quota;
pub mod tournament;
// FOUNDATION: the stand-ins below (account_role, audit, member, role, subserver)
pub mod account_role;
pub mod audit;
pub mod member;
pub mod role;
pub mod subserver;
