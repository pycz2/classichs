//! A player (or admin) account with its ladder standing.

use crate::ranked::Rank;
use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "accounts")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// 3–20 `[A-Za-z0-9_]`, unique ignoring case (COLLATE NOCASE).
    pub name: String,
    /// The argon2id hash; never leaves the server.
    pub pass: String,
    /// "user" | "admin" | "super".
    pub role: String,
    /// The public tag friends add each other by.
    pub tag: Option<String>,
    /// lower(tag): unique case-insensitively.
    pub tag_key: Option<String>,
    pub created: i64,
    pub last_seen: i64,
    pub suspended: bool,
    pub casual_mmr: f64,
    pub ranked_mmr: f64,
    /// 25..=1; 0 = Legend.
    pub rank: i64,
    pub stars: i64,
    /// Ranked wins in a row.
    pub streak: i64,
    /// The season the rank belongs to (months since year 0).
    pub season: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}

impl Model {
    pub fn rank(&self) -> Rank {
        Rank { rank: self.rank, stars: self.stars, streak: self.streak }
    }
}
