//! SQLite through SeaORM: opening (with the migrations) and the account and session helpers.

use crate::entity::{account, session, standing};
use crate::ranked::Ladder;
use crate::migration::Migrator;
use crate::ranked;
use sea_orm::sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions};
use sea_orm::{
    ActiveModelTrait, ColumnTrait, ConnectionTrait, DatabaseConnection, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, Unchanged,
    SqlxSqliteConnector, TryInsertResult,
};
use sea_orm_migration::MigratorTrait;
use std::str::FromStr;

pub use sea_orm::DbErr as DbError;
pub type DbResult<T> = Result<T, DbError>;
pub type Db = DatabaseConnection;
pub type Account = account::Model;
pub type Standing = standing::Model;

/// Opens (or creates) the database and brings its schema up to date. ":memory:" for tests.
// ponytail: one connection, as before the ORM (SQLite writes one at a time anyway);
// a separate reader pool if the admin panel's searches ever slow the game down.
pub async fn open(path: &str) -> DbResult<Db> {
    let opts = if path == ":memory:" {
        SqliteConnectOptions::from_str("sqlite::memory:").map_err(|e| DbError::Custom(e.to_string()))?
    } else {
        SqliteConnectOptions::new().filename(path).create_if_missing(true).journal_mode(SqliteJournalMode::Wal)
    };
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .idle_timeout(None)
        .max_lifetime(None) // an in-memory database lives as long as its connection
        .connect_with(opts.foreign_keys(true))
        .await
        .map_err(|e| DbError::Custom(e.to_string()))?;
    let db = SqlxSqliteConnector::from_sqlx_sqlite_pool(pool);
    Migrator::up(&db, None).await?;
    Ok(db)
}

pub async fn account_by_id(c: &impl ConnectionTrait, id: i64) -> DbResult<Option<Account>> {
    account::Entity::find_by_id(id).one(c).await
}

/// By name, ignoring case.
pub async fn account_by_name(c: &impl ConnectionTrait, name: &str) -> DbResult<Option<Account>> {
    account::Entity::find().filter(account::Column::Name.eq(name)).one(c).await
}

pub async fn id_by_name(c: &impl ConnectionTrait, name: &str) -> DbResult<Option<i64>> {
    Ok(account_by_name(c, name).await?.map(|a| a.id))
}

pub async fn name_of(c: &impl ConnectionTrait, id: i64) -> DbResult<String> {
    Ok(account_by_id(c, id).await?.map(|a| a.name).unwrap_or_default())
}

/// Creates an account (the password is already hashed). None = the name is taken.
pub async fn create_account(c: &impl ConnectionTrait, name: &str, pass_hash: &str, role: &str) -> DbResult<Option<i64>> {
    let now = ranked::now();
    let a = account::ActiveModel {
        name: Set(name.into()),
        pass: Set(pass_hash.into()),
        role: Set(role.into()),
        created: Set(now),
        last_seen: Set(now),
        season: Set(ranked::season_of(now)),
        ..Default::default()
    };
    match account::Entity::insert(a).on_conflict_do_nothing_on([account::Column::Name]).exec(c).await? {
        TryInsertResult::Inserted(r) => Ok(Some(r.last_insert_id)),
        _ => Ok(None),
    }
}

pub async fn touch(c: &impl ConnectionTrait, id: i64) -> DbResult<()> {
    account::Entity::update_many().col_expr(account::Column::LastSeen, ranked::now().into()).filter(account::Column::Id.eq(id)).exec(c).await?;
    Ok(())
}

/// A player's standing in a pack (by manifest id) this season: made from the last season's
/// (its rank carried over by the ladder's resets, the MMRs kept) or the ladder's start.
pub async fn standing(c: &impl ConnectionTrait, account: i64, pack: &str, ladder: &Ladder) -> DbResult<Standing> {
    let season = ranked::season_of(ranked::now());
    if let Some(s) = standing::Entity::find_by_id((account, pack.to_string(), season)).one(c).await? {
        return Ok(s);
    }
    let last = standing::Entity::find()
        .filter(standing::Column::Account.eq(account))
        .filter(standing::Column::Pack.eq(pack))
        .filter(standing::Column::Season.lt(season))
        .order_by_desc(standing::Column::Season)
        .one(c)
        .await?;
    let s = match last {
        Some(l) => {
            let r = ranked::advance(ladder, l.rank(), l.season, season);
            Standing { season, rank: r.rank, stars: r.stars, streak: r.streak, ..l }
        }
        None => Standing {
            account,
            pack: pack.to_string(),
            season,
            rank: ladder.start.rank,
            stars: ladder.start.stars,
            streak: 0,
            ranked_mmr: 1500.0,
            casual_mmr: 1500.0,
        },
    };
    let row = standing::ActiveModel {
        account: Set(s.account),
        pack: Set(s.pack.clone()),
        season: Set(s.season),
        rank: Set(s.rank),
        stars: Set(s.stars),
        streak: Set(s.streak),
        ranked_mmr: Set(s.ranked_mmr),
        casual_mmr: Set(s.casual_mmr),
    };
    standing::Entity::insert(row).on_conflict_do_nothing().exec_without_returning(c).await?;
    Ok(s)
}

/// Saves the rank and MMRs of a standing.
pub async fn save_standing(c: &impl ConnectionTrait, s: &Standing) -> DbResult<()> {
    standing::ActiveModel {
        account: Unchanged(s.account),
        pack: Unchanged(s.pack.clone()),
        season: Unchanged(s.season),
        rank: Set(s.rank),
        stars: Set(s.stars),
        streak: Set(s.streak),
        ranked_mmr: Set(s.ranked_mmr),
        casual_mmr: Set(s.casual_mmr),
    }
    .update(c)
    .await?;
    Ok(())
}

/// The Legend number: 1 + Legends of this pack and season with a higher ranked MMR.
pub async fn legend_number(c: &impl ConnectionTrait, s: &Standing) -> DbResult<Option<i64>> {
    if !s.rank().legend() {
        return Ok(None);
    }
    let n = standing::Entity::find()
        .filter(standing::Column::Pack.eq(&s.pack))
        .filter(standing::Column::Season.eq(s.season))
        .filter(standing::Column::Rank.eq(ranked::LEGEND))
        .filter(standing::Column::RankedMmr.gt(s.ranked_mmr))
        .count(c)
        .await?;
    Ok(Some(n as i64 + 1))
}

pub async fn new_session(c: &impl ConnectionTrait, account: i64, kind: &str, secs: i64, csrf: &str) -> DbResult<String> {
    let (token, hash) = crate::auth::new_token();
    let now = ranked::now();
    session::Entity::delete_many().filter(session::Column::Expires.lt(now)).exec(c).await?;
    let s = session::ActiveModel {
        hash: Set(hash),
        account: Set(account),
        kind: Set(kind.into()),
        expires: Set(now + secs),
        csrf: Set(csrf.into()),
        created: Set(now),
        last_used: Set(now),
    };
    session::Entity::insert(s).exec_without_returning(c).await?;
    Ok(token)
}

/// The live, unsuspended account of a session token, with the session.
pub async fn session(c: &impl ConnectionTrait, token: &str, kind: &str) -> DbResult<Option<(Account, session::Model)>> {
    let found = session::Entity::find_by_id(crate::auth::token_hash(token))
        .filter(session::Column::Kind.eq(kind))
        .filter(session::Column::Expires.gt(ranked::now()))
        .find_also_related(account::Entity)
        .one(c)
        .await?;
    Ok(match found {
        Some((s, Some(a))) if !a.suspended => Some((a, s)),
        _ => None,
    })
}

/// Sliding sessions: `secs` more from now.
pub async fn renew_session(c: &impl ConnectionTrait, hash: Vec<u8>, secs: i64) -> DbResult<()> {
    let now = ranked::now();
    session::Entity::update_many()
        .col_expr(session::Column::Expires, (now + secs).into())
        .col_expr(session::Column::LastUsed, now.into())
        .filter(session::Column::Hash.eq(hash))
        .exec(c)
        .await?;
    Ok(())
}

pub async fn drop_session(c: &impl ConnectionTrait, token: &str) -> DbResult<()> {
    session::Entity::delete_by_id(crate::auth::token_hash(token)).exec(c).await?;
    Ok(())
}

/// Every session of an account (of one kind, or all).
pub async fn drop_sessions(c: &impl ConnectionTrait, account: i64, kind: Option<&str>) -> DbResult<()> {
    let mut q = session::Entity::delete_many().filter(session::Column::Account.eq(account));
    if let Some(k) = kind {
        q = q.filter(session::Column::Kind.eq(k));
    }
    q.exec(c).await?;
    Ok(())
}

/// A new password logs the account out everywhere.
pub async fn set_password(c: &impl ConnectionTrait, id: i64, pass_hash: &str) -> DbResult<()> {
    account::ActiveModel { id: Unchanged(id), pass: Set(pass_hash.into()), ..Default::default() }.update(c).await?;
    drop_sessions(c, id, None).await
}

/// `classichs-server admin <name>`: creates or resets the superuser. true = created.
pub async fn make_superuser(c: &impl ConnectionTrait, name: &str, pass_hash: &str) -> DbResult<bool> {
    if create_account(c, name, pass_hash, "super").await?.is_some() {
        return Ok(true);
    }
    let a = account_by_name(c, name).await?.ok_or(DbError::RecordNotFound(name.into()))?;
    account::ActiveModel { id: Unchanged(a.id), role: Set("super".into()), suspended: Set(false), ..Default::default() }
        
        .update(c)
        .await?;
    set_password(c, a.id, pass_hash).await?;
    Ok(false)
}
