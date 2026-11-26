//! A version of a pack (docs/packs/format.md §13): games of it are played in its view
//! (`classichs_engine::pack::version_view`), tied to its rules_hash.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "pack_version")]
pub struct Model {
    /// The pack row (`packs.id`).
    #[sea_orm(primary_key, auto_increment = false)]
    pub pack: i64,
    /// The version's id in the manifest, e.g. "4944".
    #[sea_orm(primary_key, auto_increment = false)]
    pub version: String,
    pub rules_hash: String,
    /// JSON list: ["standard", "wild"], or [] for one format.
    pub formats: String,
    /// JSON {lang: text}.
    pub name: String,
    pub date: String,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
