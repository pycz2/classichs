//! The schema, as sea-orm-migration steps (run at every start: `db::open`).
//! M1 is the schema of 0.26 with IF NOT EXISTS, so databases made before the ORM carry on.

use sea_orm_migration::prelude::*;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(M1), Box::new(M2), Box::new(M3)]
    }
}

#[derive(DeriveIden)]
enum Accounts {
    Table,
    Id,
    Name,
    Pass,
    Role,
    Tag,
    TagKey,
    Created,
    LastSeen,
    Suspended,
    CasualMmr,
    RankedMmr,
    Rank,
    Stars,
    Streak,
    Season,
}

#[derive(DeriveIden)]
enum Sessions {
    Table,
    Hash,
    Account,
    Kind,
    Expires,
    Csrf,
    Created,
    LastUsed,
}

#[derive(DeriveIden)]
enum Friends {
    Table,
    A,
    B,
}

#[derive(DeriveIden)]
enum Requests {
    Table,
    Src,
    Dst,
    At,
}

#[derive(DeriveIden)]
enum Blocks {
    Table,
    Who,
    Whom,
}

#[derive(DeriveIden)]
enum Messages {
    Table,
    Id,
    Lo,
    Hi,
    Src,
    Text,
    At,
    Seen,
}

#[derive(DeriveIden)]
enum Arena {
    Table,
    Account,
    Seed,
    Hero,
    Picks,
    Draft,
    Wins,
    Losses,
}

#[derive(DeriveIden)]
enum Games {
    Table,
    Id,
    Mode,
    P0,
    P1,
    Started,
    Ended,
    Winner,
    Reason,
}

#[derive(DeriveIden)]
enum Events {
    Table,
    Id,
    At,
    Kind,
    Account,
    User,
    Other,
    Game,
    Text,
    Data,
}

fn int<T: IntoIden>(c: T) -> ColumnDef {
    ColumnDef::new(c).integer().not_null().to_owned()
}

fn fk<T: IntoIden, C: IntoIden>(table: T, col: C) -> ForeignKeyCreateStatement {
    ForeignKey::create().from(table, col).to(Accounts::Table, Accounts::Id).on_delete(ForeignKeyAction::Cascade).to_owned()
}

/// The 0.26 schema.
struct M1;

impl MigrationName for M1 {
    fn name(&self) -> &str {
        "m20261015_000001_initial"
    }
}

#[async_trait::async_trait]
impl MigrationTrait for M1 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        m.create_table(
            Table::create()
                .table(Accounts::Table)
                .if_not_exists()
                .col(ColumnDef::new(Accounts::Id).integer().not_null().primary_key())
                .col(ColumnDef::new(Accounts::Name).text().not_null().unique_key().extra("COLLATE NOCASE"))
                .col(ColumnDef::new(Accounts::Pass).text().not_null())
                .col(ColumnDef::new(Accounts::Role).text().not_null().default("user"))
                .col(ColumnDef::new(Accounts::Tag).text())
                .col(ColumnDef::new(Accounts::TagKey).text().unique_key())
                .col(int(Accounts::Created))
                .col(int(Accounts::LastSeen))
                .col(int(Accounts::Suspended).default(0))
                .col(ColumnDef::new(Accounts::CasualMmr).double().not_null().default(1500.0))
                .col(ColumnDef::new(Accounts::RankedMmr).double().not_null().default(1500.0))
                .col(int(Accounts::Rank).default(25))
                .col(int(Accounts::Stars).default(0))
                .col(int(Accounts::Streak).default(0))
                .col(int(Accounts::Season).default(0))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Sessions::Table)
                .if_not_exists()
                .col(ColumnDef::new(Sessions::Hash).blob().not_null().primary_key())
                .col(int(Sessions::Account))
                .col(ColumnDef::new(Sessions::Kind).text().not_null())
                .col(int(Sessions::Expires))
                .col(ColumnDef::new(Sessions::Csrf).text().not_null().default(""))
                .foreign_key(&mut fk(Sessions::Table, Sessions::Account))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Friends::Table)
                .if_not_exists()
                .col(int(Friends::A))
                .col(int(Friends::B))
                .primary_key(Index::create().col(Friends::A).col(Friends::B))
                .foreign_key(&mut fk(Friends::Table, Friends::A))
                .foreign_key(&mut fk(Friends::Table, Friends::B))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Requests::Table)
                .if_not_exists()
                .col(int(Requests::Src))
                .col(int(Requests::Dst))
                .col(int(Requests::At))
                .primary_key(Index::create().col(Requests::Src).col(Requests::Dst))
                .foreign_key(&mut fk(Requests::Table, Requests::Src))
                .foreign_key(&mut fk(Requests::Table, Requests::Dst))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Blocks::Table)
                .if_not_exists()
                .col(int(Blocks::Who))
                .col(int(Blocks::Whom))
                .primary_key(Index::create().col(Blocks::Who).col(Blocks::Whom))
                .foreign_key(&mut fk(Blocks::Table, Blocks::Who))
                .foreign_key(&mut fk(Blocks::Table, Blocks::Whom))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Messages::Table)
                .if_not_exists()
                .col(ColumnDef::new(Messages::Id).integer().not_null().primary_key())
                .col(int(Messages::Lo))
                .col(int(Messages::Hi))
                .col(int(Messages::Src))
                .col(ColumnDef::new(Messages::Text).text().not_null())
                .col(int(Messages::At))
                .foreign_key(&mut fk(Messages::Table, Messages::Lo))
                .foreign_key(&mut fk(Messages::Table, Messages::Hi))
                .to_owned(),
        )
        .await?;
        m.create_index(
            Index::create().if_not_exists().name("messages_pair").table(Messages::Table).col(Messages::Lo).col(Messages::Hi).col(Messages::Id).to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Arena::Table)
                .if_not_exists()
                .col(ColumnDef::new(Arena::Account).integer().not_null().primary_key())
                .col(int(Arena::Seed))
                .col(int(Arena::Hero).default(-1))
                .col(ColumnDef::new(Arena::Picks).text().not_null().default("[]"))
                .col(ColumnDef::new(Arena::Draft).text().not_null().default("{}"))
                .col(int(Arena::Wins).default(0))
                .col(int(Arena::Losses).default(0))
                .foreign_key(&mut fk(Arena::Table, Arena::Account))
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(Games::Table)
                .if_not_exists()
                .col(ColumnDef::new(Games::Id).text().not_null().primary_key())
                .col(ColumnDef::new(Games::Mode).text().not_null())
                .col(ColumnDef::new(Games::P0).integer())
                .col(ColumnDef::new(Games::P1).integer())
                .col(int(Games::Started))
                .col(int(Games::Ended))
                .col(int(Games::Winner))
                .col(ColumnDef::new(Games::Reason).text().not_null())
                .to_owned(),
        )
        .await
    }
}

/// Read marks, session times, the event log.
struct M2;

impl MigrationName for M2 {
    fn name(&self) -> &str {
        "m20261015_000002_events_and_reads"
    }
}

#[async_trait::async_trait]
impl MigrationTrait for M2 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        // Messages from before the read marks count as read.
        m.alter_table(Table::alter().table(Messages::Table).add_column(int(Messages::Seen).default(0)).to_owned()).await?;
        m.exec_stmt(Query::update().table(Messages::Table).value(Messages::Seen, 1).to_owned()).await?;
        m.alter_table(Table::alter().table(Sessions::Table).add_column(int(Sessions::Created).default(0)).to_owned()).await?;
        m.alter_table(Table::alter().table(Sessions::Table).add_column(int(Sessions::LastUsed).default(0)).to_owned()).await?;
        m.create_index(Index::create().name("games_ended").table(Games::Table).col(Games::Ended).to_owned()).await?;
        m.create_table(
            Table::create()
                .table(Events::Table)
                .col(ColumnDef::new(Events::Id).integer().not_null().primary_key())
                .col(int(Events::At))
                .col(ColumnDef::new(Events::Kind).text().not_null())
                .col(ColumnDef::new(Events::Account).integer())
                .col(ColumnDef::new(Events::User).text().extra("COLLATE NOCASE"))
                .col(ColumnDef::new(Events::Other).text().extra("COLLATE NOCASE"))
                .col(ColumnDef::new(Events::Game).text())
                .col(ColumnDef::new(Events::Text).text().not_null())
                .col(ColumnDef::new(Events::Data).text())
                .to_owned(),
        )
        .await?;
        for (name, col) in [("events_at", Events::At), ("events_kind", Events::Kind), ("events_game", Events::Game), ("events_user", Events::User), ("events_other", Events::Other)] {
            let mut i = Index::create().name(name).table(Events::Table).col(col).to_owned();
            if name != "events_at" {
                i.col(Events::Id);
            }
            m.create_index(i).await?;
        }
        Ok(())
    }
}

#[derive(DeriveIden)]
enum Packs {
    Table,
    Id,
    PackId,
    Version,
    Name,
    RulesHash,
    ContentHash,
    Size,
    Owner,
    Enabled,
    Created,
    Downloads,
}

#[derive(DeriveIden)]
enum PackImports {
    Table,
    ContentHash,
    At,
}

/// Game packs.
struct M3;

impl MigrationName for M3 {
    fn name(&self) -> &str {
        "m20261016_000003_packs"
    }
}

#[async_trait::async_trait]
impl MigrationTrait for M3 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        let text = |c: Packs| ColumnDef::new(c).text().not_null().to_owned();
        m.create_table(
            Table::create()
                .table(Packs::Table)
                .col(ColumnDef::new(Packs::Id).integer().not_null().primary_key())
                .col(text(Packs::PackId))
                .col(text(Packs::Version))
                .col(text(Packs::Name))
                .col(text(Packs::RulesHash))
                .col(text(Packs::ContentHash))
                .col(int(Packs::Size))
                .col(ColumnDef::new(Packs::Owner).integer())
                .col(int(Packs::Enabled).default(1))
                .col(int(Packs::Created))
                .col(int(Packs::Downloads).default(0))
                .foreign_key(&mut fk(Packs::Table, Packs::Owner))
                .to_owned(),
        )
        .await?;
        m.create_index(Index::create().name("packs_hash").table(Packs::Table).col(Packs::ContentHash).to_owned()).await?;
        m.create_index(Index::create().name("packs_owner").table(Packs::Table).col(Packs::Owner).to_owned()).await?;
        m.create_table(
            Table::create()
                .table(PackImports::Table)
                .col(ColumnDef::new(PackImports::ContentHash).text().not_null().primary_key())
                .col(int(PackImports::At))
                .to_owned(),
        )
        .await
    }
}
