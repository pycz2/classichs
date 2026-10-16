//! The rules engine of Classic HS: general card-game mechanics with no game
//! content of its own. A game pack (docs/packs/) gives the rules, cards, mechanic
//! names and Lua card scripts; the built-in ruleset is the Classic pack.
//! Hosts use the JSON API in `api` (see README.md).

pub mod api;
pub mod arena_draft;
pub mod bot;
pub mod card_db;
pub mod deck;
pub mod entity;
pub mod game;
pub mod hooks;
pub mod json;
pub mod lua;
pub mod missions;
pub mod pack;
pub mod player;
pub mod rng;
pub mod ruleset;
pub mod scenario;
pub mod state;
pub mod view;

pub use api::Engine;
pub use state::Game;
