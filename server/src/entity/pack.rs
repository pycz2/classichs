//! A game pack (`.cardpack`) known to the server: a server pack (no owner, the admin's) or a
//! player's own. The file itself is in the storage under its content hash.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "packs")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,
    /// The manifest's id, e.g. "org.classichs.neon".
    pub pack_id: String,
    pub version: String,
    /// The manifest's name by language, as JSON: {"en": "…", "ru": "…"}.
    pub name: String,
    /// SHA-256 (hex) of what affects play; games are tied to it.
    pub rules_hash: String,
    /// SHA-256 (hex) of the whole file: its storage key.
    pub content_hash: String,
    pub size: i64,
    /// The uploading player; null = a server pack.
    pub owner: Option<i64>,
    pub enabled: bool,
    pub created: i64,
    pub downloads: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(belongs_to = "super::account::Entity", from = "Column::Owner", to = "super::account::Column::Id", on_delete = "Cascade")]
    Account,
}

impl Related<super::account::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Account.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
