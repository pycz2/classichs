//! A bundled pack (from `--packs-dir`) already imported once: deleting it in the admin
//! panel keeps it deleted after a restart.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "pack_imports")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub content_hash: String,
    pub at: i64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
