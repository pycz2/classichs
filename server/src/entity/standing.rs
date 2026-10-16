//! A player's standing in one game pack (by the manifest id, so a new version keeps it) and
//! one season: the ranked ladder and both MMRs. A new season's row starts from the last one.

use crate::ranked::Rank;
use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "standings")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub account: i64,
    /// The pack's manifest id ("neon", "classic-2014").
    #[sea_orm(primary_key, auto_increment = false)]
    pub pack: String,
    /// Months since year 0.
    #[sea_orm(primary_key, auto_increment = false)]
    pub season: i64,
    /// N..=1; 0 = Legend.
    pub rank: i64,
    pub stars: i64,
    /// Ranked wins in a row.
    pub streak: i64,
    pub ranked_mmr: f64,
    pub casual_mmr: f64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(belongs_to = "super::account::Entity", from = "Column::Account", to = "super::account::Column::Id", on_delete = "Cascade")]
    Account,
}

impl Related<super::account::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Account.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}

impl Model {
    pub fn rank(&self) -> Rank {
        Rank { rank: self.rank, stars: self.stars, streak: self.streak }
    }
}
