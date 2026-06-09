//! `users` CLI subcommand — admin operations against the
//! file-backed user store.
//!
//! Currently a single operation: `users reset-password
//! --email <email>` resets a forgotten password by writing a fresh
//! Argon2id hash into `users.json`.  No current-password check —
//! this is an operator tool, intended for the case where a friend
//! lost their password and you have direct disk access to the
//! data dir.
//!
//! Lives in the CLI crate (not the server) so it can run while
//! the server is stopped — the same file-backed `UserStore` the
//! server uses is opened directly off disk.  The CLI does **not**
//! go through the HTTP API, so this still works when the server
//! is down.

use std::path::{Path, PathBuf};

use clap::Subcommand;
use ezpz_dndz_lib::users::{UserStore, UserStoreError};
use thiserror::Error;
use tracing::info;

#[derive(Debug, Clone, Subcommand)]
pub enum UsersCommand {
  /// Reset a user's password without knowing the current one.
  /// Operator-only — assumes you have local disk access to the
  /// data dir.  The new password is read from the controlling
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

    /// Path to the users.json file.  Defaults to
    /// `<data_dir>/users.json` resolved from `--data-dir` or the
    /// `ezpz_dndz_data_dir` env var.  Pass explicitly if the
    /// file lives somewhere non-standard.
    #[arg(long, env = "ezpz_dndz_users_path")]
    users_path: Option<PathBuf>,

    /// Root of the runtime data dir.  Used only when
    /// `--users-path` is absent; mirrors the server's
    /// `--data-dir` flag so a single env-var setup covers both
    /// binaries.
    #[arg(long, env = "ezpz_dndz_data_dir", default_value = ".")]
    data_dir: PathBuf,
  },
}

#[derive(Debug, Error)]
pub enum UsersCliError {
  #[error("Failed to load the user store at {path}: {source}")]
  StoreLoad {
    path: PathBuf,
    #[source]
    source: UserStoreError,
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
        users_path,
        data_dir,
      } => {
        let resolved_path =
          users_path.unwrap_or_else(|| data_dir.join("users.json"));
        let password = match new_password {
          Some(p) => p,
          None => prompt_for_password()?,
        };
        if password.is_empty() {
          return Err(UsersCliError::EmptyPassword);
        }
        run_reset(&resolved_path, &email, &password)
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
/// The CLI is otherwise blocking; only the file-backed store
/// needs async.  Keeping the runtime local to the subcommand
/// avoids forcing `#[tokio::main]` on every other path.
fn run_reset(
  users_path: &Path,
  email: &str,
  new_password: &str,
) -> Result<(), UsersCliError> {
  let rt = tokio::runtime::Builder::new_current_thread()
    .enable_all()
    .build()
    .map_err(UsersCliError::Prompt)?;

  rt.block_on(async {
    let store = UserStore::load_or_default(users_path.to_path_buf())
      .await
      .map_err(|source| UsersCliError::StoreLoad {
        path: users_path.to_path_buf(),
        source,
      })?;
    let user = store
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
