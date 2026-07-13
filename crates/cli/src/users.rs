//! `users` CLI subcommand — admin operations against the user store.
//!
//! Currently a single operation: `users reset-password
//! --email <email>` resets a forgotten password by writing a fresh
//! Argon2id hash into the database.  No current-password check —
//! this is an operator tool, intended for the case where a friend
//! lost their password and you have direct access to the data dir.
//!
//! Lives in the CLI crate (not the server) so it can run while the
//! server is stopped — the same SQL-backed `UserStore` the server
//! uses is opened directly against the database.  The CLI does
//! **not** go through the HTTP API, so this still works when the
//! server is down.  The database is resolved exactly like the
//! server's: `--database-url` wins, otherwise
//! `sqlite://<data_dir>/ezpz-dndz.db`.

use std::path::PathBuf;

use clap::Subcommand;
use ezpz_dndz_lib::db::{default_sqlite_url, Db, DbError};
use ezpz_dndz_lib::users::{UserStore, UserStoreError};
use thiserror::Error;
use tracing::info;

#[derive(Debug, Clone, Subcommand)]
pub enum UsersCommand {
  /// Reset a user's password without knowing the current one.
  /// Operator-only — assumes you have local access to the
  /// database.  The new password is read from the controlling
  /// TTY by default so it never lands in `ps` output or shell
  /// history; pass `--new-password` to script the reset against
  /// a piped value instead.
  ResetPassword {
    /// Email address of the account to reset (case-insensitive).
    #[arg(long)]
    email: String,

    /// Optional pre-supplied password.  When absent, the CLI
    /// reads the new password from the controlling TTY twice
    /// (with confirmation) using a hidden prompt.
    ///
    /// Avoid this flag for interactive use: the value will be
    /// visible in `history`, `ps`, and any auditing process
    /// list.  Useful for scripted rotations where stdin is
    /// already secured.
    #[arg(long)]
    new_password: Option<String>,

    /// Database connection URL (`sqlite:…` or `postgres:…`).
    /// Defaults to `sqlite://<data_dir>/ezpz-dndz.db` resolved
    /// from `--data-dir` or the `ezpz_dndz_data_dir` env var —
    /// the same rule the server applies.
    #[arg(long, env = "ezpz_dndz_database_url")]
    database_url: Option<String>,

    /// Root of the runtime data dir.  Used only when
    /// `--database-url` is absent; mirrors the server's
    /// `--data-dir` flag so a single env-var setup covers both
    /// binaries.
    #[arg(long, env = "ezpz_dndz_data_dir", default_value = ".")]
    data_dir: PathBuf,
  },
}

#[derive(Debug, Error)]
pub enum UsersCliError {
  #[error("Failed to open the database at {url}: {source}")]
  DbOpen {
    url: String,
    #[source]
    source: DbError,
  },

  #[error("Failed to reset the password: {0}")]
  Reset(#[source] UserStoreError),

  #[error("Failed to read password from the terminal: {0}")]
  Prompt(#[source] std::io::Error),

  #[error("Password confirmation did not match the original entry")]
  ConfirmationMismatch,

  #[error("New password must not be empty")]
  EmptyPassword,
}

impl UsersCommand {
  pub fn run(self) -> Result<(), UsersCliError> {
    match self {
      Self::ResetPassword {
        email,
        new_password,
        database_url,
        data_dir,
      } => {
        let url = database_url.unwrap_or_else(|| default_sqlite_url(&data_dir));
        let password = match new_password {
          Some(p) => p,
          None => prompt_for_password()?,
        };
        if password.is_empty() {
          return Err(UsersCliError::EmptyPassword);
        }
        run_reset(&url, &email, &password)
      }
    }
  }
}

/// Prompt twice for the new password (with confirmation), echoing
/// nothing to the terminal.  Returns an error if either read fails
/// or the two entries disagree.
fn prompt_for_password() -> Result<String, UsersCliError> {
  let first = rpassword::prompt_password("New password: ")
    .map_err(UsersCliError::Prompt)?;
  let confirm = rpassword::prompt_password("Confirm new password: ")
    .map_err(UsersCliError::Prompt)?;
  if first != confirm {
    return Err(UsersCliError::ConfirmationMismatch);
  }
  Ok(first)
}

/// Spin up a single-thread tokio runtime just for this command.
/// The CLI is otherwise blocking; only the database access needs
/// async.  Keeping the runtime local to the subcommand avoids
/// forcing `#[tokio::main]` on every other path.
fn run_reset(
  url: &str,
  email: &str,
  new_password: &str,
) -> Result<(), UsersCliError> {
  let rt = tokio::runtime::Builder::new_current_thread()
    .enable_all()
    .build()
    .map_err(UsersCliError::Prompt)?;

  rt.block_on(async {
    let db =
      Db::connect(url)
        .await
        .map_err(|source| UsersCliError::DbOpen {
          url: url.to_string(),
          source,
        })?;
    let user = UserStore::new(db)
      .admin_reset_password(email, new_password)
      .await
      .map_err(UsersCliError::Reset)?;
    info!(
      user_id = user.id.as_str(),
      email = %user.email,
      display_name = %user.display_name,
      "Password reset"
    );
    println!("Reset password for {} <{}>", user.display_name, user.email);
    Ok(())
  })
}
