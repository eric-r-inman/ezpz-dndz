//! Dice-history subcommands for the CLI.
//!
//! The roll log is relational and per-user (`dice_rolls` and its
//! child tables); these subcommands open the same database the
//! server uses — resolved via the shared `--database-url` /
//! `--data-dir` rules — and go through the server crate's
//! [`DiceStore`] so the JSON printed here is byte-compatible with
//! what `GET /api/dice/history` serves.  Works while the server is
//! stopped, e.g. for inspecting a restored backup.

use clap::Subcommand;
use ezpz_dndz_server::dice::{DiceHistoryError, DiceStore};
use thiserror::Error;
use tracing::info;

use crate::db::{self, DbArgs, DbCliError};

#[derive(Debug, Error)]
pub enum DiceCliError {
  #[error("Database access failed: {0}")]
  Db(#[from] DbCliError),

  #[error("Failed to count the stored dice rolls: {0}")]
  CountQuery(#[source] sqlx::Error),

  #[error("Failed to read the dice-roll history: {0}")]
  HistoryRead(#[source] DiceHistoryError),

  #[error("Failed to clear the dice-roll history: {0}")]
  HistoryClear(#[source] DiceHistoryError),

  #[error("Failed to serialize the dice-roll history to JSON: {0}")]
  SerializeError(#[source] serde_json::Error),
}

/// Subcommands grouped under `ezpz-dndz-cli dice <...>`.
#[derive(Debug, Clone, Subcommand)]
pub enum DiceCommand {
  /// Count the recorded rolls.  With `--email` the count covers one
  /// user's log; without it, every user's rolls are counted
  /// together.
  Count {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose log to count (case-insensitive).
    #[arg(long)]
    email: Option<String>,
  },

  /// Print one user's most recent N rolls (defaults to 10) as
  /// pretty JSON, newest first — the same shape the HTTP history
  /// endpoint serves.
  Tail {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose log to read (case-insensitive).
    #[arg(long)]
    email: String,

    /// How many of the most recent rolls to show.
    #[arg(short, long, default_value_t = 10)]
    n: usize,
  },

  /// Wipe one user's roll history.  This is destructive; pass
  /// `--yes` to bypass the confirmation prompt (the only "ask" the
  /// CLI does, since you very rarely mean to nuke a roll log).
  Clear {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose log to wipe (case-insensitive).
    #[arg(long)]
    email: String,

    /// Skip the interactive confirmation.
    #[arg(long)]
    yes: bool,
  },
}

impl DiceCommand {
  pub fn run(&self) -> Result<(), DiceCliError> {
    match self {
      DiceCommand::Count { db, email } => {
        db::block_on(count(db, email.as_deref()))
      }
      DiceCommand::Tail { db, email, n } => db::block_on(tail(db, email, *n)),
      DiceCommand::Clear { db, email, yes } => {
        if !*yes {
          eprintln!(
            "About to wipe the dice history for {email}.  \
             Pass --yes to confirm."
          );
          return Ok(());
        }
        db::block_on(clear(db, email))
      }
    }
  }
}

async fn count(args: &DbArgs, email: Option<&str>) -> Result<(), DiceCliError> {
  let db = db::connect(args).await?;
  let total = match email {
    Some(email) => {
      let user = db::user_by_email(&db, email).await?;
      DiceStore::new(db)
        .load(&user.id)
        .await
        .map_err(DiceCliError::HistoryRead)?
        .len() as i64
    }
    // Admin-wide aggregate: no store API exists for cross-user
    // reads on purpose, so the CLI asks the parent table directly.
    None => sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM dice_rolls")
      .fetch_one(db.pool())
      .await
      .map_err(DiceCliError::CountQuery)?,
  };
  info!(count = total, email = ?email, "Counted dice rolls");
  println!("{total}");
  Ok(())
}

async fn tail(
  args: &DbArgs,
  email: &str,
  n: usize,
) -> Result<(), DiceCliError> {
  let db = db::connect(args).await?;
  let user = db::user_by_email(&db, email).await?;
  let rolls = DiceStore::new(db)
    .load(&user.id)
    .await
    .map_err(DiceCliError::HistoryRead)?;
  // The store returns newest-first; "tail" semantically means
  // "most-recent N", so we slice from the front.
  let pretty =
    serde_json::to_string_pretty(&rolls.iter().take(n).collect::<Vec<_>>())
      .map_err(DiceCliError::SerializeError)?;
  println!("{pretty}");
  Ok(())
}

async fn clear(args: &DbArgs, email: &str) -> Result<(), DiceCliError> {
  let db = db::connect(args).await?;
  let user = db::user_by_email(&db, email).await?;
  DiceStore::new(db)
    .clear(&user.id)
    .await
    .map_err(DiceCliError::HistoryClear)?;
  info!(email, "Cleared dice history");
  println!("Cleared.");
  Ok(())
}
