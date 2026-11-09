//! Tournaments (0.50, `crate::tournament`): the tournament, its entrants (with the decks copied
//! when given), its matches and the games of each match. Times here are unix milliseconds.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "tournaments")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    pub name: String,
    pub creator: i64,
    /// The pack's rules_hash.
    pub pack: String,
    /// round_robin | swiss | elimination | scheveningen
    pub format: String,
    /// JSON: {rounds, drop_after, losses} (what the format uses; rounds filled in at seeding).
    pub options: String,
    /// conquest | lhs
    pub series: String,
    pub best_of: i64,
    pub bans: i64,
    pub start_at: i64,
    pub max_players: i64,
    pub min_players: i64,
    pub deck_reveal: bool,
    pub spectators: bool,
    /// open | locked | seeded | running | finished | cancelled | closed
    pub status: String,
    /// Why it was closed ("not enough players").
    pub reason: String,
    pub created: i64,
    /// When it finished, was cancelled or closed (0 = not yet).
    pub ended: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}

pub mod entrant {
    use sea_orm::entity::prelude::*;

    #[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
    #[sea_orm(table_name = "t_entrants")]
    pub struct Model {
        #[sea_orm(primary_key, auto_increment = false)]
        pub tournament: i64,
        #[sea_orm(primary_key, auto_increment = false)]
        pub account: i64,
        /// JSON [{name, hero, cards}]: copies, so the player's own decks may change.
        pub decks: String,
        /// From 0 at seeding; −1 before.
        pub seed: i64,
        /// Scheveningen: 0 or 1; −1 else.
        pub team: i64,
        /// At the end (0 = none).
        pub place: i64,
        pub joined: i64,
    }

    #[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
    pub enum Relation {}

    impl ActiveModelBehavior for ActiveModel {}
}

pub mod matches {
    use sea_orm::entity::prelude::*;

    #[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
    #[sea_orm(table_name = "t_matches")]
    pub struct Model {
        #[sea_orm(primary_key)]
        pub id: i64,
        pub tournament: i64,
        /// The match's index in its tournament (what `src` refers to).
        pub n: i64,
        pub round: i64,
        /// Elimination: w | l | gf; "" else.
        pub bracket: String,
        pub slot: i64,
        /// Elimination: the loser is out at this stage (0 = not out).
        pub out: i64,
        /// The entrants' accounts (null: not known yet while `src` says where from, else a bye).
        pub a: Option<i64>,
        pub b: Option<i64>,
        /// JSON [src a, src b]: "" (known), "w<n>" / "l<n>" (the winner / loser of match n).
        pub src: String,
        /// pending | accept | ban | pick | playing | done
        pub status: String,
        /// The current step's deadline (0 = none).
        pub deadline: i64,
        pub score_a: i64,
        pub score_b: i64,
        pub winner: Option<i64>,
        /// JSON: the series (`tournament::Series`).
        pub state: String,
    }

    #[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
    pub enum Relation {}

    impl ActiveModelBehavior for ActiveModel {}
}

pub mod games {
    use sea_orm::entity::prelude::*;

    #[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
    #[sea_orm(table_name = "t_games")]
    pub struct Model {
        #[sea_orm(primary_key, auto_increment = false)]
        pub game: String,
        pub tournament: i64,
        pub match_id: i64,
        /// 1, 2, … in the match.
        pub n: i64,
        /// The decks played (indices into each side's decks).
        pub deck_a: i64,
        pub deck_b: i64,
        /// The winner's account (null: none yet, or no winner).
        pub winner: Option<i64>,
        pub reason: String,
    }

    #[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
    pub enum Relation {}

    impl ActiveModelBehavior for ActiveModel {}
}
