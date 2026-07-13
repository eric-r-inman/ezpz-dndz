//! One-shot boot import of the legacy JSON stores into the database.
//!
//! Before the relational migration, users lived in `users.json` (a
//! flat `Vec<User>`) and dice history in `dice-history.json` (a
//! `HashMap<UserId, Vec<Value>>`, newest roll first).  On the first
//! boot against a fresh database this module replays both files into
//! the `users` and `dice_rolls` tables inside a single transaction,
//! then records a marker in `schema_meta` so the import never runs
//! twice.  The JSON files are left untouched on disk as the rollback
//! copy.
//!
//! Defensive rules: nothing happens when the marker is present or
//! when neither legacy file exists, and a database that already
//! contains users is never imported into (the marker is written with
//! an explanatory value instead, so the skip is deliberate and
//! permanent rather than re-warned on every boot).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use ezpz_dndz_lib::db::{Db, DbError};
use ezpz_dndz_lib::users::{insert_user, User, UserId};
use serde_json::Value;
use thiserror::Error;
use tracing::{info, warn};

use crate::config::RuntimePaths;
use crate::dice::{insert_roll, DiceHistoryError, RollEntry};

/// `schema_meta` key marking that the users + dice import has run
/// (or was deliberately skipped).
pub const IMPORT_MARKER_KEY: &str = "json_import_users_dice";

#[derive(Debug, Error)]
pub enum JsonImportError {
  #[error("Failed to read the import marker: {0}")]
  MarkerRead(#[source] DbError),

  #[error("Failed to write the import marker: {0}")]
  MarkerWrite(#[source] sqlx::Error),

  #[error("Failed to count existing users before the import: {0}")]
  UserCount(#[source] sqlx::Error),

  #[error("Failed to read the legacy JSON file at {path}: {source}")]
  LegacyFileRead {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse the legacy JSON file at {path}: {source}")]
  LegacyFileParse {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Failed to begin the import transaction: {0}")]
  TransactionBegin(#[source] sqlx::Error),

  #[error("Failed to commit the import transaction: {0}")]
  TransactionCommit(#[source] sqlx::Error),

  #[error("Failed to import legacy user {email}: {source}")]
  UserInsert { email: String, source: sqlx::Error },

  #[error("Failed to import a legacy dice roll for user {user_id}: {source}")]
  RollInsert {
    user_id: String,
    source: DiceHistoryError,
  },
}

/// Run the one-shot import.  Called from `AppState::assemble` after
/// migrations (via `Db::connect`) and before anything that needs the
/// imported users, such as the compendium split migration's claim-
/// user lookup.
pub async fn run(db: &Db, paths: &RuntimePaths) -> Result<(), JsonImportError> {
  if db
    .schema_meta(IMPORT_MARKER_KEY)
    .await
    .map_err(JsonImportError::MarkerRead)?
    .is_some()
  {
    return Ok(());
  }

  if !paths.users.exists() && !paths.dice_history.exists() {
    return Ok(());
  }

  let existing_users: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
    .fetch_one(db.pool())
    .await
    .map_err(JsonImportError::UserCount)?;
  if existing_users > 0 {
    warn!(
      existing_users,
      "legacy JSON files present but the database already has users; \
       skipping the one-shot import permanently"
    );
    sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
      .bind(IMPORT_MARKER_KEY)
      .bind("skipped: database already contained users")
      .execute(db.pool())
      .await
      .map_err(JsonImportError::MarkerWrite)?;
    return Ok(());
  }

  let users: Vec<User> = read_json_or_default(&paths.users).await?;
  let dice: HashMap<UserId, Vec<Value>> =
    read_json_or_default(&paths.dice_history).await?;

  let mut tx = db
    .pool()
    .begin()
    .await
    .map_err(JsonImportError::TransactionBegin)?;

  for user in &users {
    insert_user(&mut tx, user).await.map_err(|source| {
      JsonImportError::UserInsert {
        email: user.email.clone(),
        source,
      }
    })?;
  }

  let known_ids: std::collections::HashSet<&str> =
    users.iter().map(|u| u.id.as_str()).collect();
  let mut imported_rolls = 0usize;
  let mut skipped_rolls = 0usize;
  for (user_id, entries) in &dice {
    if !known_ids.contains(user_id.as_str()) {
      warn!(
        user_id = user_id.as_str(),
        entries = entries.len(),
        "legacy dice history references a user missing from \
         users.json; skipping those rolls"
      );
      skipped_rolls += entries.len();
      continue;
    }
    // The legacy file stores each user's log newest-first; positions
    // count down so the newest entry keeps the highest position.
    let total = entries.len() as i64;
    for (i, raw) in entries.iter().enumerate() {
      match serde_json::from_value::<RollEntry>(raw.clone()) {
        Ok(entry) => {
          insert_roll(&mut tx, user_id, total - i as i64, &entry)
            .await
            .map_err(|source| JsonImportError::RollInsert {
              user_id: user_id.as_str().to_string(),
              source,
            })?;
          imported_rolls += 1;
        }
        Err(error) => {
          warn!(
            user_id = user_id.as_str(),
            %error,
            "legacy dice entry does not match the roll schema; skipping"
          );
          skipped_rolls += 1;
        }
      }
    }
  }

  sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
    .bind(IMPORT_MARKER_KEY)
    .bind("done")
    .execute(&mut *tx)
    .await
    .map_err(JsonImportError::MarkerWrite)?;

  tx.commit()
    .await
    .map_err(JsonImportError::TransactionCommit)?;

  info!(
    users = users.len(),
    rolls = imported_rolls,
    skipped_rolls,
    "imported legacy JSON stores into the database"
  );
  Ok(())
}

/// Read + parse a legacy JSON file, treating a missing file as the
/// type's default so "users.json exists but dice-history.json does
/// not" (and vice versa) imports cleanly.
async fn read_json_or_default<T>(path: &Path) -> Result<T, JsonImportError>
where
  T: serde::de::DeserializeOwned + Default,
{
  match tokio::fs::read(path).await {
    Ok(bytes) => serde_json::from_slice(&bytes).map_err(|source| {
      JsonImportError::LegacyFileParse {
        path: path.to_path_buf(),
        source,
      }
    }),
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
    Err(source) => Err(JsonImportError::LegacyFileRead {
      path: path.to_path_buf(),
      source,
    }),
  }
}
