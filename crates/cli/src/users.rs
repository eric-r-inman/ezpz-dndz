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
//! server is down.  The database is resolved through the shared
//! [`DbArgs`], exactly like the server's.

use clap::Subcommand;
use ezpz_dndz_lib::users::{validate_new_password, UserStore, UserStoreError};
use thiserror::Error;
use tracing::info;

use crate::db::{self, DbArgs, DbCliError};

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

    #[command(flatten)]
    db: DbArgs,
  },
}

#[derive(Debug, Error)]
pub enum UsersCliError {
  #[error("Database access failed: {0}")]
  Db(#[from] DbCliError),

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
        db,
      } => {
        let password = match new_password {
          Some(p) => p,
          None => prompt_for_password()?,
        };
        if password.is_empty() {
          return Err(UsersCliError::EmptyPassword);
        }
        validate_new_password(&password).map_err(UsersCliError::Reset)?;
        db::block_on(run_reset(&db, &email, &password))
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

/// Reset the password of an account that must already exist.  The
/// lookup names an unknown email.  The store's own error would
/// blame a password instead.
async fn run_reset(
  args: &DbArgs,
  email: &str,
  new_password: &str,
) -> Result<(), UsersCliError> {
  let db = db::connect(args).await?;
  let account = db::user_by_email(&db, email).await?;
  let user = UserStore::new(db)
    .admin_reset_password(&account.email, new_password)
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
}
