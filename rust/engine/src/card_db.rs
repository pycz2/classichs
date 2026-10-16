//! Card data of the built-in Classic ruleset (`ruleset::classic()`), for hosts
//! and the Rust card hooks. Games read cards through their own ruleset.

use crate::ruleset;

pub use crate::ruleset::Card;

/// The card; panics on an unknown id (GDScript asserts). Check `has` at trust boundaries.
pub fn card(id: &str) -> &'static Card {
    ruleset::classic().card(id)
}

pub fn has(id: &str) -> bool {
    ruleset::classic().has(id)
}

/// Collectible VANILLA cards, sorted by id.
pub fn collectible() -> &'static [String] {
    &ruleset::classic().collectible
}

/// SHA-256 of data/cards.json: both sides of a game must have the same card data.
pub fn data_hash() -> &'static str {
    &ruleset::classic().data_hash
}
