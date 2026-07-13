//! Relational storage core: one [`Db`] handle over two
//! interchangeable backends.
//!
//! SQLite is the zero-ops default (`sqlite://<data_dir>/ezpz-dndz.db`)
//! and PostgreSQL (`postgres://…`) covers hosted scale.  Both are
//! served through `sqlx`'s `Any` driver so every store issues one set
//! of queries; portability rests on the DDL rules documented in the
//! migration files (TEXT ids, BIGINT integers, `$n` placeholders,
//! which SQLite accepts natively).
//!
//! Migrations are plain `.sql` files under `crates/lib/migrations/`,
//! embedded at compile time and applied on connect.  sqlx 0.8
//! implements `Migrate` for `AnyConnection`, so the embedded migrator
//! runs directly over the pool for either backend.
//!
//! # SQLite specifics
//!
//! `connect` normalizes SQLite URLs: the parent directory of the
//! database file is created if missing, and `mode=rwc` is appended so
//! the file itself is created on first boot.  The pool is capped at a
//! single connection for SQLite — the file only supports one writer
//! at a time, and a singleton connection turns `SQLITE_BUSY` retry
//! loops into simple in-process queueing.  Note that `sqlite::memory:`
//! databases are per-connection under the `Any` driver: with the
//! single-connection pool they work for short-lived tests, but prefer
//! a temp-file database for anything pool-shaped.

use std::path::Path;

use sqlx::any::AnyPoolOptions;
use sqlx::migrate::Migrator;
use sqlx::AnyPool;
use thiserror::Error;

/// The embedded migrations, shared verbatim by both backends.
pub static MIGRATOR: Migrator = sqlx::migrate!();

/// Semantic errors from opening and preparing the database.
#[derive(Debug, Error)]
pub enum DbError {
  #[error("Failed to create the SQLite database directory {path}: {source}")]
  SqliteDirCreate {
    path: std::path::PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to connect to the database at {url}: {source}")]
  Connect { url: String, source: sqlx::Error },

  #[error("Failed to run database migrations: {0}")]
  Migrate(#[source] sqlx::migrate::MigrateError),

  #[error("Failed to read schema metadata for key {key:?}: {source}")]
  SchemaMetaRead { key: String, source: sqlx::Error },
}

/// Handle to the relational database: a cloneable pool plus the
/// helpers every store shares.  Construct once in `main` via
/// [`Db::connect`] and hand clones to each store.
#[derive(Debug, Clone)]
pub struct Db {
  pool: AnyPool,
}

impl Db {
  /// Connect to `url` (either `sqlite:…` or `postgres:…`) and bring
  /// the schema up to date.  SQLite URLs get create-if-missing
  /// semantics and their parent directory created; see the module
  /// docs for the single-connection rationale.
  pub async fn connect(url: &str) -> Result<Self, DbError> {
    // Idempotent: sqlx guards the driver registry with a `Once`.
    sqlx::any::install_default_drivers();

    let url = prepared_url(url).await?;
    let pool = pool_options(&url).connect(&url).await.map_err(|source| {
      DbError::Connect {
        url: url.clone(),
        source,
      }
    })?;
    MIGRATOR.run(&pool).await.map_err(DbError::Migrate)?;
    Ok(Self { pool })
  }

  /// Borrow the underlying pool.  Stores issue their queries through
  /// this; transactions begin here too.
  pub fn pool(&self) -> &AnyPool {
    &self.pool
  }

  /// Read one `schema_meta` value.  One-shot migrations use this
  /// table to record completion markers.
  pub async fn schema_meta(
    &self,
    key: &str,
  ) -> Result<Option<String>, DbError> {
    sqlx::query_scalar::<_, String>(
      "SELECT value FROM schema_meta WHERE key = $1",
    )
    .bind(key)
    .fetch_optional(&self.pool)
    .await
    .map_err(|source| DbError::SchemaMetaRead {
      key: key.to_string(),
      source,
    })
  }
}

/// The default on-disk database location for a given data directory,
/// as a SQLite URL.  Shared by the server and the CLI so both
/// binaries resolve `--data-dir` to the same file.
pub fn default_sqlite_url(data_dir: &Path) -> String {
  format!("sqlite://{}", data_dir.join("ezpz-dndz.db").display())
}

/// For SQLite URLs: create the database file's parent directory and
/// append `mode=rwc` (create if missing) unless a mode is already
/// specified.  Non-SQLite URLs pass through untouched.
async fn prepared_url(url: &str) -> Result<String, DbError> {
  let Some(db_path) = sqlite_database_path(url) else {
    return Ok(url.to_string());
  };

  // In-memory databases (`sqlite::memory:` or `?mode=memory`) have
  // no file to create and must not gain a conflicting mode.
  if db_path == ":memory:" || db_path.is_empty() {
    return Ok(url.to_string());
  }

  if let Some(parent) = Path::new(db_path).parent() {
    if !parent.as_os_str().is_empty() {
      tokio::fs::create_dir_all(parent).await.map_err(|source| {
        DbError::SqliteDirCreate {
          path: parent.to_path_buf(),
          source,
        }
      })?;
    }
  }

  if url.contains("mode=") {
    Ok(url.to_string())
  } else if url.contains('?') {
    Ok(format!("{url}&mode=rwc"))
  } else {
    Ok(format!("{url}?mode=rwc"))
  }
}

/// Extract the database path from a SQLite URL, or `None` for other
/// schemes.  Both `sqlite:path` and `sqlite://path` are accepted —
/// sqlx itself strips the two prefixes identically, so the server's
/// `sqlite:///abs/path` and a bare `sqlite:relative.db` both work.
fn sqlite_database_path(url: &str) -> Option<&str> {
  url
    .strip_prefix("sqlite://")
    .or_else(|| url.strip_prefix("sqlite:"))
    .map(|rest| rest.split('?').next().unwrap_or(rest))
}

/// Pool sizing per backend; see the module docs for why SQLite gets
/// exactly one connection.
fn pool_options(url: &str) -> AnyPoolOptions {
  AnyPoolOptions::new().max_connections(if url.starts_with("sqlite:") {
    1
  } else {
    10
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use tempfile::TempDir;

  #[test]
  fn sqlite_database_path_handles_both_prefix_forms() {
    assert_eq!(
      sqlite_database_path("sqlite:///abs/path/db.sqlite"),
      Some("/abs/path/db.sqlite")
    );
    assert_eq!(sqlite_database_path("sqlite:relative.db"), Some("relative.db"));
    assert_eq!(
      sqlite_database_path("sqlite://relative.db?mode=ro"),
      Some("relative.db")
    );
    assert_eq!(sqlite_database_path("sqlite::memory:"), Some(":memory:"));
    assert_eq!(sqlite_database_path("postgres://localhost/db"), None);
  }

  #[tokio::test]
  async fn connect_creates_missing_file_and_directories() {
    let dir = TempDir::new().unwrap();
    let db_file = dir.path().join("nested").join("deeper").join("app.db");
    let url = format!("sqlite://{}", db_file.display());

    let db = Db::connect(&url).await.expect("connect");
    assert!(db_file.exists(), "database file should have been created");

    // Migrations ran: the users table answers a count query.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
      .fetch_one(db.pool())
      .await
      .expect("count users");
    assert_eq!(count, 0);
  }

  #[tokio::test]
  async fn connect_accepts_single_colon_absolute_form() {
    let dir = TempDir::new().unwrap();
    let db_file = dir.path().join("single-colon.db");
    let url = format!("sqlite:{}", db_file.display());

    Db::connect(&url).await.expect("connect via sqlite:<abs>");
    assert!(db_file.exists());
  }

  #[tokio::test]
  async fn connect_migrates_in_memory_database() {
    // The single-connection pool keeps `:memory:` coherent for the
    // lifetime of this test; see the module docs for the caveat.
    let db = Db::connect("sqlite::memory:").await.expect("connect");
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM schema_meta")
      .fetch_one(db.pool())
      .await
      .expect("count schema_meta");
    assert_eq!(count, 0);
  }

  #[tokio::test]
  async fn schema_meta_round_trips() {
    let dir = TempDir::new().unwrap();
    let db = Db::connect(&default_sqlite_url(dir.path()))
      .await
      .expect("connect");

    assert_eq!(db.schema_meta("absent").await.expect("read"), None);

    sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
      .bind("marker")
      .bind("done")
      .execute(db.pool())
      .await
      .expect("insert marker");

    assert_eq!(
      db.schema_meta("marker").await.expect("read"),
      Some("done".to_string())
    );
  }

  #[tokio::test]
  async fn migrations_are_idempotent_across_reconnects() {
    let dir = TempDir::new().unwrap();
    let url = default_sqlite_url(dir.path());
    Db::connect(&url).await.expect("first connect");
    Db::connect(&url).await.expect("second connect");
  }
}
