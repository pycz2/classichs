//! SQLite (WAL) behind one mutex; every call runs on the blocking pool.

use crate::ranked::{self, Rank};
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::sync::{Arc, Mutex};

pub use rusqlite::Error as DbError;
pub type DbResult<T> = Result<T, DbError>;

#[derive(Clone)]
pub struct Db(Arc<Mutex<Connection>>);

const SCHEMA: &str = "
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
CREATE TABLE IF NOT EXISTS accounts (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE,
  pass TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',          -- user | admin | super
  tag TEXT,
  tag_key TEXT UNIQUE,                        -- lower(tag): unique case-insensitively
  created INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  suspended INTEGER NOT NULL DEFAULT 0,
  casual_mmr REAL NOT NULL DEFAULT 1500,
  ranked_mmr REAL NOT NULL DEFAULT 1500,
  rank INTEGER NOT NULL DEFAULT 25,           -- 0 = Legend
  stars INTEGER NOT NULL DEFAULT 0,
  streak INTEGER NOT NULL DEFAULT 0,
  season INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
  hash BLOB PRIMARY KEY,
  account INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,                         -- game | admin
  expires INTEGER NOT NULL,
  csrf TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS friends (
  a INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  b INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  PRIMARY KEY (a, b)
);
CREATE TABLE IF NOT EXISTS requests (
  src INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  dst INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  at INTEGER NOT NULL,
  PRIMARY KEY (src, dst)
);
CREATE TABLE IF NOT EXISTS blocks (
  who INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  whom INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  PRIMARY KEY (who, whom)
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY,
  lo INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  hi INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  src INTEGER NOT NULL,
  text TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS messages_pair ON messages(lo, hi, id);
CREATE TABLE IF NOT EXISTS arena (
  account INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  seed INTEGER NOT NULL,
  hero INTEGER NOT NULL DEFAULT -1,
  picks TEXT NOT NULL DEFAULT '[]',
  draft TEXT NOT NULL DEFAULT '{}',           -- the referee's last draft reply
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  p0 INTEGER, p1 INTEGER,
  started INTEGER NOT NULL,
  ended INTEGER NOT NULL,
  winner INTEGER NOT NULL,
  reason TEXT NOT NULL
);
";

impl Db {
    pub fn open(path: &str) -> DbResult<Db> {
        let c = Connection::open(path)?;
        c.execute_batch(SCHEMA)?;
        Ok(Db(Arc::new(Mutex::new(c))))
    }

    /// Runs `f` with the connection on the blocking pool.
    // ponytail: one connection behind a mutex; a reader pool if the panel or chat ever gets busy.
    pub async fn run<T, F>(&self, f: F) -> DbResult<T>
    where
        T: Send + 'static,
        F: FnOnce(&mut Connection) -> DbResult<T> + Send + 'static,
    {
        let db = self.0.clone();
        tokio::task::spawn_blocking(move || f(&mut db.lock().unwrap_or_else(|e| e.into_inner())))
            .await
            .expect("db task panicked")
    }
}

#[derive(Clone, Debug)]
pub struct Account {
    pub id: i64,
    pub name: String,
    pub role: String,
    pub tag: Option<String>,
    pub created: i64,
    pub last_seen: i64,
    pub suspended: bool,
    pub casual_mmr: f64,
    pub ranked_mmr: f64,
    pub rank: Rank,
    pub season: i64,
}

pub const ACCOUNT_COLS: &str =
    "id, name, role, tag, created, last_seen, suspended, casual_mmr, ranked_mmr, rank, stars, streak, season";

pub fn account_row(r: &Row) -> rusqlite::Result<Account> {
    Ok(Account {
        id: r.get(0)?,
        name: r.get(1)?,
        role: r.get(2)?,
        tag: r.get(3)?,
        created: r.get(4)?,
        last_seen: r.get(5)?,
        suspended: r.get::<_, i64>(6)? != 0,
        casual_mmr: r.get(7)?,
        ranked_mmr: r.get(8)?,
        rank: Rank { rank: r.get(9)?, stars: r.get(10)?, streak: r.get(11)? },
        season: r.get(12)?,
    })
}

pub fn account_by_id(c: &Connection, id: i64) -> DbResult<Option<Account>> {
    c.query_row(&format!("SELECT {ACCOUNT_COLS} FROM accounts WHERE id = ?1"), [id], account_row).optional()
}

pub fn account_by_name(c: &Connection, name: &str) -> DbResult<Option<(Account, String)>> {
    c.query_row(
        &format!("SELECT {ACCOUNT_COLS}, pass FROM accounts WHERE name = ?1"),
        [name],
        |r| Ok((account_row(r)?, r.get(13)?)),
    )
    .optional()
}

/// Creates an account (the password is already hashed). None = the name is taken.
pub fn create_account(c: &Connection, name: &str, pass_hash: &str, role: &str) -> DbResult<Option<i64>> {
    let now = ranked::now();
    let n = c.execute(
        "INSERT INTO accounts (name, pass, role, created, last_seen, season) VALUES (?1, ?2, ?3, ?4, ?4, ?5)
         ON CONFLICT(name) DO NOTHING",
        params![name, pass_hash, role, now, ranked::season_of(now)],
    )?;
    Ok((n == 1).then(|| c.last_insert_rowid()))
}

/// Brings an account's rank into the current season (the monthly reset) and saves it.
pub fn refresh_season(c: &Connection, a: &mut Account) -> DbResult<()> {
    let s = ranked::season_of(ranked::now());
    if a.season != s {
        a.rank = ranked::advance(a.rank, a.season, s);
        a.season = s;
        c.execute(
            "UPDATE accounts SET rank = ?1, stars = ?2, streak = ?3, season = ?4 WHERE id = ?5",
            params![a.rank.rank, a.rank.stars, a.rank.streak, s, a.id],
        )?;
    }
    Ok(())
}

/// The Legend number: 1 + Legends of this season with a higher ranked MMR.
pub fn legend_number(c: &Connection, a: &Account) -> DbResult<Option<i64>> {
    if !a.rank.legend() {
        return Ok(None);
    }
    let n: i64 = c.query_row(
        "SELECT COUNT(*) FROM accounts WHERE rank = 0 AND season = ?1 AND ranked_mmr > ?2",
        params![a.season, a.ranked_mmr],
        |r| r.get(0),
    )?;
    Ok(Some(n + 1))
}

pub fn new_session(c: &Connection, account: i64, kind: &str, secs: i64, csrf: &str) -> DbResult<String> {
    let (token, hash) = crate::auth::new_token();
    c.execute("DELETE FROM sessions WHERE expires < ?1", [ranked::now()])?;
    c.execute(
        "INSERT INTO sessions (hash, account, kind, expires, csrf) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![hash, account, kind, ranked::now() + secs, csrf],
    )?;
    Ok(token)
}

/// The live, unsuspended account of a session token: (account, csrf).
pub fn session(c: &Connection, token: &str, kind: &str) -> DbResult<Option<(Account, String)>> {
    let hash = crate::auth::token_hash(token);
    let cols = ACCOUNT_COLS.split(", ").map(|x| format!("a.{x}")).collect::<Vec<_>>().join(", ");
    c.query_row(
        &format!(
            "SELECT {cols}, s.csrf FROM sessions s JOIN accounts a ON a.id = s.account
             WHERE s.hash = ?1 AND s.kind = ?2 AND s.expires > ?3 AND a.suspended = 0"
        ),
        params![hash, kind, ranked::now()],
        |r| Ok((account_row(r)?, r.get(13)?)),
    )
    .optional()
}

pub fn drop_session(c: &Connection, token: &str) -> DbResult<()> {
    c.execute("DELETE FROM sessions WHERE hash = ?1", [crate::auth::token_hash(token)])?;
    Ok(())
}

pub fn set_password(c: &Connection, id: i64, pass_hash: &str) -> DbResult<()> {
    c.execute("UPDATE accounts SET pass = ?1 WHERE id = ?2", params![pass_hash, id])?;
    c.execute("DELETE FROM sessions WHERE account = ?1", [id])?;
    Ok(())
}

/// `classichs-server admin <name>`: creates or resets the superuser.
pub fn make_superuser(c: &Connection, name: &str, pass_hash: &str) -> DbResult<bool> {
    if create_account(c, name, pass_hash, "super")?.is_some() {
        return Ok(true);
    }
    let id: i64 = c.query_row("SELECT id FROM accounts WHERE name = ?1", [name], |r| r.get(0))?;
    c.execute("UPDATE accounts SET role = 'super', suspended = 0 WHERE id = ?1", [id])?;
    set_password(c, id, pass_hash)?;
    Ok(false)
}
