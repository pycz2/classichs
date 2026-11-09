//! The schema, as sea-orm-migration steps (run at every start: `db::open`).
//! M1 is the schema of 0.26 with IF NOT EXISTS, so databases made before the ORM carry on.

use sea_orm_migration::prelude::*;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(M1), Box::new(M2), Box::new(M3), Box::new(M4), Box::new(M5), Box::new(M6), Box::new(M7), Box::new(M8), Box::new(M9), Box::new(M10)]
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
    SignupKey,
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
    Pack,
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
    Pack,
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
    Hashes,
    IsDefault,
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

#[derive(DeriveIden)]
enum Standings {
    Table,
    Account,
    Pack,
    Season,
    Rank,
    Stars,
    Streak,
    RankedMmr,
    CasualMmr,
}


/// Games on packs (phase D): hashes by docs/packs/format.md (rows of the old scheme are
/// recomputed at start, `packs::migrate_hashes`), the default pack, the pack of a game and
/// of an Arena run, and standings per (account, pack, season): the ranks and MMRs so far were
/// earned in Classic and move there.
struct M4;

impl MigrationName for M4 {
    fn name(&self) -> &str {
        "m20261016_000004_games_on_packs"
    }
}

#[async_trait::async_trait]
impl MigrationTrait for M4 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        m.alter_table(Table::alter().table(Packs::Table).add_column(int(Packs::Hashes).default(0)).to_owned()).await?;
        m.alter_table(Table::alter().table(Packs::Table).add_column(int(Packs::IsDefault).default(0)).to_owned()).await?;
        m.create_index(Index::create().name("packs_rules").table(Packs::Table).col(Packs::RulesHash).to_owned()).await?;
        m.alter_table(Table::alter().table(Games::Table).add_column(ColumnDef::new(Games::Pack).text().not_null().default("")).to_owned()).await?;
        m.alter_table(Table::alter().table(Arena::Table).add_column(ColumnDef::new(Arena::Pack).text().not_null().default("")).to_owned()).await?;
        m.create_table(
            Table::create()
                .table(Standings::Table)
                .col(int(Standings::Account))
                .col(ColumnDef::new(Standings::Pack).text().not_null())
                .col(int(Standings::Season))
                .col(int(Standings::Rank))
                .col(int(Standings::Stars).default(0))
                .col(int(Standings::Streak).default(0))
                .col(ColumnDef::new(Standings::RankedMmr).double().not_null().default(1500.0))
                .col(ColumnDef::new(Standings::CasualMmr).double().not_null().default(1500.0))
                .primary_key(Index::create().col(Standings::Account).col(Standings::Pack).col(Standings::Season))
                .foreign_key(&mut fk(Standings::Table, Standings::Account))
                .to_owned(),
        )
        .await?;
        m.create_index(
            Index::create().name("standings_ladder").table(Standings::Table).col(Standings::Pack).col(Standings::Season).col(Standings::Rank).to_owned(),
        )
        .await?;
        m.get_connection()
            .execute_unprepared(
                "INSERT INTO standings (account, pack, season, rank, stars, streak, ranked_mmr, casual_mmr) \
                 SELECT id, 'classic-2014', season, rank, stars, streak, ranked_mmr, casual_mmr FROM accounts",
            )
            .await?;
        Ok(())
    }
}


/// The server's bots (0.29): their accounts and how and when they play.
struct M5;

impl MigrationName for M5 {
    fn name(&self) -> &str {
        "m20261024_000005_bots"
    }
}

#[derive(DeriveIden)]
enum Bots {
    Table,
    Id,
    Account,
    Level,
    Modes,
    Enabled,
    FromMin,
    ToMin,
    PauseMin,
    PauseMax,
    Created,
}

#[async_trait::async_trait]
impl MigrationTrait for M5 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        let text = |c: Bots| ColumnDef::new(c).text().not_null().to_owned();
        m.create_table(
            Table::create()
                .table(Bots::Table)
                .col(ColumnDef::new(Bots::Id).integer().not_null().primary_key())
                .col(int(Bots::Account).unique_key())
                .col(text(Bots::Level))
                .col(text(Bots::Modes))
                .col(int(Bots::Enabled).default(1))
                .col(int(Bots::FromMin).default(0))
                .col(int(Bots::ToMin).default(0))
                .col(int(Bots::PauseMin).default(5))
                .col(int(Bots::PauseMax).default(15))
                .col(int(Bots::Created))
                .foreign_key(&mut fk(Bots::Table, Bots::Account))
                .to_owned(),
        )
        .await
    }
}


/// Players' decks kept on the server (0.32): per account and pack (the manifest id, as standings).
struct M6;

impl MigrationName for M6 {
    fn name(&self) -> &str {
        "m20261102_000006_decks"
    }
}

#[derive(DeriveIden)]
enum Decks {
    Table,
    Id,
    Account,
    Pack,
    Name,
    Hero,
    Cards,
    Created,
    Updated,
}

#[async_trait::async_trait]
impl MigrationTrait for M6 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        let text = |c: Decks| ColumnDef::new(c).text().not_null().to_owned();
        m.create_table(
            Table::create()
                .table(Decks::Table)
                .col(ColumnDef::new(Decks::Id).integer().not_null().primary_key())
                .col(int(Decks::Account))
                .col(text(Decks::Pack))
                .col(text(Decks::Name))
                .col(text(Decks::Hero))
                .col(text(Decks::Cards))
                .col(int(Decks::Created))
                .col(int(Decks::Updated))
                .foreign_key(&mut fk(Decks::Table, Decks::Account))
                .to_owned(),
        )
        .await?;
        m.create_index(Index::create().name("decks_account").table(Decks::Table).col(Decks::Account).to_owned()).await
    }
}

/// A player's choices per game (0.40: the art and music sets), per account and pack (the manifest id).
struct M7;

impl MigrationName for M7 {
    fn name(&self) -> &str {
        "m20261102_000007_game_settings"
    }
}

#[derive(DeriveIden)]
enum GameSettings {
    Table,
    Account,
    Pack,
    Value,
    Updated,
}

#[async_trait::async_trait]
impl MigrationTrait for M7 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        m.create_table(
            Table::create()
                .table(GameSettings::Table)
                .col(int(GameSettings::Account))
                .col(ColumnDef::new(GameSettings::Pack).text().not_null())
                .col(ColumnDef::new(GameSettings::Value).text().not_null())
                .col(int(GameSettings::Updated))
                .primary_key(Index::create().col(GameSettings::Account).col(GameSettings::Pack))
                .foreign_key(&mut fk(GameSettings::Table, GameSettings::Account))
                .to_owned(),
        )
        .await
    }
}

/// Admin settings and invite keys (0.50): the server's settings (key → text), the keys a player
/// registers with, and the key each account registered with (NULL: none, as every older account).
struct M8;

impl MigrationName for M8 {
    fn name(&self) -> &str {
        "m20261109_000008_settings_and_signup_keys"
    }
}

#[derive(DeriveIden)]
enum ServerSettings {
    Table,
    Key,
    Value,
}

#[derive(DeriveIden)]
enum SignupKeys {
    Table,
    Id,
    Key,
    Note,
    UsesTotal,
    UsesLeft,
    Created,
    CreatedBy,
    CreatedByName,
    Revoked,
}

#[async_trait::async_trait]
impl MigrationTrait for M8 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        m.create_table(
            Table::create()
                .table(ServerSettings::Table)
                .col(ColumnDef::new(ServerSettings::Key).text().not_null().primary_key())
                .col(ColumnDef::new(ServerSettings::Value).text().not_null())
                .to_owned(),
        )
        .await?;
        m.create_table(
            Table::create()
                .table(SignupKeys::Table)
                .col(ColumnDef::new(SignupKeys::Id).integer().not_null().primary_key())
                .col(ColumnDef::new(SignupKeys::Key).text().not_null().unique_key())
                .col(ColumnDef::new(SignupKeys::Note).text())
                .col(int(SignupKeys::UsesTotal))
                .col(int(SignupKeys::UsesLeft))
                .col(int(SignupKeys::Created))
                .col(ColumnDef::new(SignupKeys::CreatedBy).integer())
                .col(ColumnDef::new(SignupKeys::CreatedByName).text().not_null().default(""))
                .col(int(SignupKeys::Revoked).default(0))
                .to_owned(),
        )
        .await?;
        m.alter_table(Table::alter().table(Accounts::Table).add_column(ColumnDef::new(Accounts::SignupKey).integer()).to_owned()).await?;
        m.create_index(Index::create().name("accounts_signup_key").table(Accounts::Table).col(Accounts::SignupKey).to_owned()).await
    }
}

/// Tournaments (0.50): the tournament, its entrants (decks copied), its matches and their games.
struct M10;

impl MigrationName for M10 {
    fn name(&self) -> &str {
        "m20261109_000010_tournaments"
    }
}

#[derive(DeriveIden)]
enum Tournaments {
    Table,
    Id,
    Name,
    Creator,
    Pack,
    Format,
    Options,
    Series,
    BestOf,
    Bans,
    StartAt,
    MaxPlayers,
    MinPlayers,
    DeckReveal,
    Spectators,
    Status,
    Reason,
    Created,
    Ended,
}

#[derive(DeriveIden)]
enum TEntrants {
    Table,
    Tournament,
    Account,
    Decks,
    Seed,
    Team,
    Place,
    Joined,
}

#[derive(DeriveIden)]
enum TMatches {
    Table,
    Id,
    Tournament,
    N,
    Round,
    Bracket,
    Slot,
    Out,
    A,
    B,
    Src,
    Status,
    Deadline,
    ScoreA,
    ScoreB,
    Winner,
    State,
}

#[derive(DeriveIden)]
enum TGames {
    Table,
    Game,
    Tournament,
    MatchId,
    N,
    DeckA,
    DeckB,
    Winner,
    Reason,
}

/// A foreign key to tournaments (deleted with it).
fn of_tournament<T: IntoIden, C: IntoIden>(table: T, col: C) -> ForeignKeyCreateStatement {
    ForeignKey::create().from(table, col).to(Tournaments::Table, Tournaments::Id).on_delete(ForeignKeyAction::Cascade).to_owned()
}

#[async_trait::async_trait]
impl MigrationTrait for M10 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        let text = |c: Tournaments| ColumnDef::new(c).text().not_null().to_owned();
        m.create_table(
            Table::create()
                .table(Tournaments::Table)
                .col(ColumnDef::new(Tournaments::Id).integer().not_null().primary_key())
                .col(text(Tournaments::Name))
                .col(int(Tournaments::Creator))
                .col(text(Tournaments::Pack))
                .col(text(Tournaments::Format))
                .col(text(Tournaments::Options))
                .col(text(Tournaments::Series))
                .col(int(Tournaments::BestOf))
                .col(int(Tournaments::Bans))
                .col(int(Tournaments::StartAt))
                .col(int(Tournaments::MaxPlayers))
                .col(int(Tournaments::MinPlayers))
                .col(int(Tournaments::DeckReveal))
                .col(int(Tournaments::Spectators))
                .col(text(Tournaments::Status))
                .col(text(Tournaments::Reason).default(""))
                .col(int(Tournaments::Created))
                .col(int(Tournaments::Ended).default(0))
                .foreign_key(&mut fk(Tournaments::Table, Tournaments::Creator))
                .to_owned(),
        )
        .await?;
        m.create_index(Index::create().name("tournaments_status").table(Tournaments::Table).col(Tournaments::Status).to_owned()).await?;
        m.create_index(Index::create().name("tournaments_creator").table(Tournaments::Table).col(Tournaments::Creator).to_owned()).await?;
        m.create_table(
            Table::create()
                .table(TEntrants::Table)
                .col(int(TEntrants::Tournament))
                .col(int(TEntrants::Account))
                .col(ColumnDef::new(TEntrants::Decks).text().not_null())
                .col(int(TEntrants::Seed).default(-1))
                .col(int(TEntrants::Team).default(-1))
                .col(int(TEntrants::Place).default(0))
                .col(int(TEntrants::Joined))
                .primary_key(Index::create().col(TEntrants::Tournament).col(TEntrants::Account))
                .foreign_key(&mut of_tournament(TEntrants::Table, TEntrants::Tournament))
                .foreign_key(&mut fk(TEntrants::Table, TEntrants::Account))
                .to_owned(),
        )
        .await?;
        let text = |c: TMatches| ColumnDef::new(c).text().not_null().to_owned();
        m.create_table(
            Table::create()
                .table(TMatches::Table)
                .col(ColumnDef::new(TMatches::Id).integer().not_null().primary_key())
                .col(int(TMatches::Tournament))
                .col(int(TMatches::N))
                .col(int(TMatches::Round))
                .col(text(TMatches::Bracket))
                .col(int(TMatches::Slot))
                .col(int(TMatches::Out).default(0))
                .col(ColumnDef::new(TMatches::A).integer().null())
                .col(ColumnDef::new(TMatches::B).integer().null())
                .col(text(TMatches::Src))
                .col(text(TMatches::Status))
                .col(int(TMatches::Deadline).default(0))
                .col(int(TMatches::ScoreA).default(0))
                .col(int(TMatches::ScoreB).default(0))
                .col(ColumnDef::new(TMatches::Winner).integer().null())
                .col(text(TMatches::State))
                .foreign_key(&mut of_tournament(TMatches::Table, TMatches::Tournament))
                .to_owned(),
        )
        .await?;
        m.create_index(Index::create().name("t_matches_tournament").table(TMatches::Table).col(TMatches::Tournament).to_owned()).await?;
        m.create_table(
            Table::create()
                .table(TGames::Table)
                .col(ColumnDef::new(TGames::Game).text().not_null().primary_key())
                .col(int(TGames::Tournament))
                .col(int(TGames::MatchId))
                .col(int(TGames::N))
                .col(int(TGames::DeckA))
                .col(int(TGames::DeckB))
                .col(ColumnDef::new(TGames::Winner).integer().null())
                .col(ColumnDef::new(TGames::Reason).text().not_null().default(""))
                .foreign_key(&mut of_tournament(TGames::Table, TGames::Tournament))
                .to_owned(),
        )
        .await?;
        m.create_index(Index::create().name("t_games_match").table(TGames::Table).col(TGames::MatchId).to_owned()).await
    }
}

/// Every finished game's replay (0.50): the setup and the actions, deflated JSON (`crate::replays`).
struct M9;

impl MigrationName for M9 {
    fn name(&self) -> &str {
        "m20261109_000009_replays"
    }
}

#[derive(DeriveIden)]
enum Replays {
    Table,
    Game,
    Pack,
    P0,
    P1,
    Ended,
    Data,
}

#[async_trait::async_trait]
impl MigrationTrait for M9 {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        m.create_table(
            Table::create()
                .table(Replays::Table)
                .col(ColumnDef::new(Replays::Game).text().not_null().primary_key())
                .col(ColumnDef::new(Replays::Pack).text().not_null())
                .col(ColumnDef::new(Replays::P0).integer())
                .col(ColumnDef::new(Replays::P1).integer())
                .col(int(Replays::Ended))
                .col(ColumnDef::new(Replays::Data).blob().not_null())
                .to_owned(),
        )
        .await?;
        for (name, col) in [("replays_p0", Replays::P0), ("replays_p1", Replays::P1)] {
            m.create_index(Index::create().name(name).table(Replays::Table).col(col).to_owned()).await?;
        }
        Ok(())
    }
}
