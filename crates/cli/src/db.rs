//! Shared database plumbing for the data subcommands.
//!
//! Every subcommand that touches persisted state resolves its
//! database exactly like the server does: `--database-url` wins,
//! otherwise the database is the SQLite file inside `--data-dir`
//! (both flags also read the matching `ezpz_dndz_*` env vars, so a
//! single environment covers both binaries).  Opening the database
//! runs the embedded migrations, which is what makes the CLI safe
//! to point at a data dir the server has never booted against.
//!
//! The CLI is otherwise blocking; only database access is async.
//! [`block_on`] builds a single-thread tokio runtime local to the
//! subcommand so no other code path has to become async.

use std::future::Future;
use std::path::PathBuf;

use clap::Args;
use ezpz_dndz_lib::db::{default_sqlite_url, Db, DbError};
use ezpz_dndz_lib::users::{User, UserStore, UserStoreError};
use thiserror::Error;

/// The `--database-url` / `--data-dir` pair shared by every data
/// subcommand, flattened into each variant via `#[command(flatten)]`.
#[derive(Debug, Clone, Args)]
pub struct DbArgs {
  /// Database connection URL (`sqlite:…` or `postgres:…`).
  /// Defaults to `sqlite://<data_dir>/ezpz-dndz.db` resolved from
  /// `--data-dir` or the `ezpz_dndz_data_dir` env var — the same
  /// rule the server applies.
  #[arg(long, env = "ezpz_dndz_database_url")]
  pub database_url: Option<String>,

  /// Root of the runtime data dir.  Used only when
  /// `--database-url` is absent; mirrors the server's `--data-dir`
  /// flag so a single env-var setup covers both binaries.
  #[arg(long, env = "ezpz_dndz_data_dir", default_value = ".")]
  pub data_dir: PathBuf,
}

impl DbArgs {
  /// The connection URL these arguments resolve to.
  pub fn url(&self) -> String {
    self
      .database_url
      .clone()
      .unwrap_or_else(|| default_sqlite_url(&self.data_dir))
  }
}

/// Semantic errors from the shared CLI database plumbing.
#[derive(Debug, Error)]
pub enum DbCliError {
  #[error(
    "Failed to build the tokio runtime for the database subcommand: {0}"
  )]
  RuntimeBuild(#[source] std::io::Error),

  #[error("Failed to open the database at {url}: {source}")]
  Open {
    url: String,
    #[source]
    source: DbError,
  },

  #[error("Failed to look up the user {email}: {source}")]
  UserLookup {
    email: String,
    #[source]
    source: UserStoreError,
  },

  #[error("No user with email {email} exists in this database")]
  UserNotFound { email: String },
}

/// Drive `future` to completion on a fresh current-thread tokio
/// runtime.  Keeping the runtime local to each subcommand avoids
/// forcing `#[tokio::main]` on the file-only paths (harvest,
/// infer-habitats).
pub fn block_on<F, T, E>(future: F) -> Result<T, E>
where
  F: Future<Output = Result<T, E>>,
  E: From<DbCliError>,
{
  tokio::runtime::Builder::new_current_thread()
    .enable_all()
    .build()
    .map_err(|source| E::from(DbCliError::RuntimeBuild(source)))?
    .block_on(future)
}

/// Open (and migrate) the database the arguments resolve to.
pub async fn connect(args: &DbArgs) -> Result<Db, DbCliError> {
  let url = args.url();
  Db::connect(&url)
    .await
    .map_err(|source| DbCliError::Open { url, source })
}

/// Resolve an operator-supplied email address to the owning user,
/// erroring when the account doesn't exist so downstream store
/// calls never run against a phantom user id.
pub async fn user_by_email(db: &Db, email: &str) -> Result<User, DbCliError> {
  UserStore::new(db.clone())
    .find_by_email(email)
    .await
    .map_err(|source| DbCliError::UserLookup {
      email: email.to_string(),
      source,
    })?
    .ok_or_else(|| DbCliError::UserNotFound {
      email: email.to_string(),
    })
}
