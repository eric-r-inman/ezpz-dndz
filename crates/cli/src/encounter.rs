//! Encounter subcommands for the CLI.
//!
//! Each user's live encounter is relational (the `encounters` table
//! family); these subcommands open the same database the server
//! uses and read through the server crate's [`EncounterStore`], so
//! what prints here is the canonical wire encoding that
//! `GET /api/encounter` serves — `null` for a user who has never
//! persisted an encounter.  Works while the server is stopped,
//! e.g. for inspecting a restored backup.

use clap::Subcommand;
use ezpz_dndz_server::encounters::{EncounterStore, EncounterStoreError};
use serde_json::Value;
use thiserror::Error;
use tracing::info;

use crate::db::{self, DbArgs, DbCliError};

#[derive(Debug, Error)]
pub enum EncounterCliError {
  #[error("Database access failed: {0}")]
  Db(#[from] DbCliError),

  #[error("Failed to read the live encounter: {0}")]
  EncounterRead(#[source] EncounterStoreError),

  #[error("Failed to serialize the encounter to JSON: {0}")]
  Serialize(#[source] serde_json::Error),
}

/// Subcommands grouped under `ezpz-dndz-cli encounter <...>`.
#[derive(Debug, Clone, Subcommand)]
pub enum EncounterCommand {
  /// Pretty-print one user's live encounter as its wire JSON
  /// (`null` when the user has never persisted one).
  Show {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose encounter to read
    /// (case-insensitive).
    #[arg(long)]
    email: String,
  },

  /// Count the creatures in one user's live encounter queue.
  Count {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose encounter to count
    /// (case-insensitive).
    #[arg(long)]
    email: String,
  },
}

impl EncounterCommand {
  pub fn run(&self) -> Result<(), EncounterCliError> {
    match self {
      EncounterCommand::Show { db, email } => db::block_on(show(db, email)),
      EncounterCommand::Count { db, email } => db::block_on(count(db, email)),
    }
  }
}

async fn read_value(
  args: &DbArgs,
  email: &str,
) -> Result<Value, EncounterCliError> {
  let db = db::connect(args).await?;
  let user = db::user_by_email(&db, email).await?;
  EncounterStore::new(db)
    .read(&user.id)
    .await
    .map_err(EncounterCliError::EncounterRead)
}

async fn show(args: &DbArgs, email: &str) -> Result<(), EncounterCliError> {
  let value = read_value(args, email).await?;
  let pretty = serde_json::to_string_pretty(&value)
    .map_err(EncounterCliError::Serialize)?;
  println!("{pretty}");
  Ok(())
}

async fn count(args: &DbArgs, email: &str) -> Result<(), EncounterCliError> {
  let value = read_value(args, email).await?;
  let n = value
    .get("creatures")
    .and_then(|v| v.as_array())
    .map_or(0, |a| a.len());
  info!(count = n, email, "Counted creatures");
  println!("{n}");
  Ok(())
}
