//! Classic HS rules engine: the whole game logic of the Godot remake of
//! Hearthstone Classic (June 2014), behaving exactly as the GDScript engine.
//! Hosts use the JSON API in `api` (see README.md).

pub mod api;
pub mod arena_draft;
pub mod bot;
pub mod card_db;
pub mod cards;
pub mod deck;
pub mod entity;
pub mod game;
pub mod json;
pub mod missions;
pub mod player;
pub mod rng;
pub mod scenario;
pub mod state;

pub use api::Engine;
pub use state::Game;
