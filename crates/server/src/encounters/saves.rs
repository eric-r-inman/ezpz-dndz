//! Named-encounter save store, relational edition.
//!
//! Distinct from the live-encounter store (`encounters/store.rs`),
//! which holds the single auto-saved current combat.  This store
//! holds the user's named save files: a list of
//! `{ name, encounter, created_at, updated_at }` records keyed by a
//! user-provided string.  Callers can create / overwrite / list /
//! get / delete / rename these by name, exactly mirroring the
//! compendium's `SavedCompendiumStore`.
//!
//! Storage is the `encounter_saves` table plus the
//! `encounter_save_nodes` JSON tree (migration 0004).  The save body
//! stays an **opaque** `serde_json::Value` on the wire — that has
//! always been the contract (callers may PUT bodies that don't
//! decode as an `Encounter`, and the integration suite pins 200 OK
//! for exactly such bodies), so it is normalized structurally (one
//! row per JSON node, no JSON columns) rather than through the typed
//! live-encounter tables; see [`super::save_nodes`] for the codec
//! and migration 0004 for the full rationale.  Name uniqueness is
//! per-user, enforced both in code (for the 409 contract) and by a
//! unique index.
//!
//! The listing sorts by `updated_at` descending with the per-user
//! insertion sequence (`position`) as tiebreak, matching the legacy
//! Vec's stable sort.

use ezpz_dndz_lib::{db::Db, users::UserId};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{any::AnyRow, Row};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use super::error::EncounterStoreError;
use super::save_nodes;

/// One named save record.  The body is stored opaquely.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SavedEncounter {
  pub name: String,
  pub encounter: Value,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Listing-row shape: just the metadata, no body.  Used by the
/// `GET /api/encounter/saves` endpoint to keep the response cheap
/// when a user has dozens of saves and the modal only needs names.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SavedEncounterMeta {
  pub name: String,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Wire body for the rename endpoint.
#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct RenameBody {
  pub new_name: String,
}

fn read_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::SaveRowsRead { source }
}

fn write_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::SaveRowsWrite { source }
}

fn begin_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::TransactionBegin {
    store: "encounter-save",
    source,
  }
}

fn commit_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::TransactionCommit {
    store: "encounter-save",
    source,
  }
}

/// Relational list of named saves, keyed by user.
#[derive(Clone)]
pub struct SavedEncounterStore {
  db: Db,
}

/// The metadata row for one save, including its surrogate id.
struct SaveRow {
  id: String,
  name: String,
  created_at: i64,
  updated_at: i64,
}

fn save_from_row(row: &AnyRow) -> Result<SaveRow, EncounterStoreError> {
  Ok(SaveRow {
    id: row.try_get("id").map_err(read_error)?,
    name: row.try_get("name").map_err(read_error)?,
    created_at: row.try_get("created_at").map_err(read_error)?,
    updated_at: row.try_get("updated_at").map_err(read_error)?,
  })
}

impl SavedEncounterStore {
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  async fn row_by_name(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<Option<SaveRow>, EncounterStoreError> {
    sqlx::query(
      "SELECT id, name, created_at, updated_at FROM encounter_saves \
       WHERE user_id = $1 AND name = $2",
    )
    .bind(user_id.as_str())
    .bind(name)
    .fetch_optional(self.db.pool())
    .await
    .map_err(read_error)?
    .as_ref()
    .map(save_from_row)
    .transpose()
  }

  /// Project one user's saves down to metadata for the listing
  /// endpoint.  Sorted by `updated_at` descending so the most
  /// recently touched save sits at the top of the modal.
  pub async fn list(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<SavedEncounterMeta>, EncounterStoreError> {
    sqlx::query(
      "SELECT id, name, created_at, updated_at FROM encounter_saves \
       WHERE user_id = $1 ORDER BY updated_at DESC, position",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(read_error)?
    .iter()
    .map(|row| {
      save_from_row(row).map(|r| SavedEncounterMeta {
        name: r.name,
        created_at: r.created_at,
        updated_at: r.updated_at,
      })
    })
    .collect()
  }

  pub async fn get(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<Option<SavedEncounter>, EncounterStoreError> {
    let Some(row) = self.row_by_name(user_id, name).await? else {
      return Ok(None);
    };
    let mut conn = self.db.pool().acquire().await.map_err(read_error)?;
    Ok(Some(SavedEncounter {
      name: row.name,
      encounter: save_nodes::fetch_body(&mut conn, &row.id).await?,
      created_at: row.created_at,
      updated_at: row.updated_at,
    }))
  }

  /// Insert a brand new save for the given user.  Errors if a save
  /// with this name already exists for that user — callers wanting
  /// overwrite semantics use [`replace`](Self::replace).
  pub async fn create(
    &self,
    user_id: &UserId,
    name: String,
    encounter: Value,
  ) -> Result<SavedEncounter, EncounterStoreError> {
    if self.row_by_name(user_id, &name).await?.is_some() {
      return Err(EncounterStoreError::SaveAlreadyExists);
    }
    let now = epoch_millis();
    let save_id = Uuid::new_v4().to_string();

    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    let position = sqlx::query_scalar::<_, i64>(
      "SELECT COALESCE(MAX(position) + 1, 0) FROM encounter_saves \
       WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(read_error)?;
    sqlx::query(
      "INSERT INTO encounter_saves (id, user_id, position, name, \
       created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(&save_id)
    .bind(user_id.as_str())
    .bind(position)
    .bind(&name)
    .bind(now)
    .bind(now)
    .execute(&mut *tx)
    .await
    .map_err(write_error)?;
    save_nodes::insert_body(&mut tx, &save_id, &encounter).await?;
    tx.commit().await.map_err(commit_error)?;

    Ok(SavedEncounter {
      name,
      encounter,
      created_at: now,
      updated_at: now,
    })
  }

  /// Overwrite an existing save by name; preserves the original
  /// `created_at`.  Errors if no save with this name exists for the
  /// given user.
  pub async fn replace(
    &self,
    user_id: &UserId,
    name: String,
    encounter: Value,
  ) -> Result<SavedEncounter, EncounterStoreError> {
    let row = self
      .row_by_name(user_id, &name)
      .await?
      .ok_or(EncounterStoreError::SaveNotFound)?;
    let now = epoch_millis();

    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    sqlx::query("DELETE FROM encounter_save_nodes WHERE save_id = $1")
      .bind(&row.id)
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    save_nodes::insert_body(&mut tx, &row.id, &encounter).await?;
    sqlx::query("UPDATE encounter_saves SET updated_at = $1 WHERE id = $2")
      .bind(now)
      .bind(&row.id)
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    tx.commit().await.map_err(commit_error)?;

    Ok(SavedEncounter {
      name,
      encounter,
      created_at: row.created_at,
      updated_at: now,
    })
  }

  /// Drop the save with the given name from the user's list.
  pub async fn delete(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<(), EncounterStoreError> {
    let result = sqlx::query(
      "DELETE FROM encounter_saves WHERE user_id = $1 AND name = $2",
    )
    .bind(user_id.as_str())
    .bind(name)
    .execute(self.db.pool())
    .await
    .map_err(write_error)?;
    if result.rows_affected() > 0 {
      Ok(())
    } else {
      Err(EncounterStoreError::SaveNotFound)
    }
  }

  /// Rename a save in place.  Errors if the source name is missing
  /// in the user's list or the destination name already exists for
  /// that user (no implicit overwrite — the frontend prompts).
  /// `updated_at` is bumped to reflect the user-visible change.
  pub async fn rename(
    &self,
    user_id: &UserId,
    from: &str,
    to: String,
  ) -> Result<SavedEncounter, EncounterStoreError> {
    if self.row_by_name(user_id, &to).await?.is_some() {
      return Err(EncounterStoreError::SaveAlreadyExists);
    }
    let row = self
      .row_by_name(user_id, from)
      .await?
      .ok_or(EncounterStoreError::SaveNotFound)?;
    let now = epoch_millis();

    sqlx::query(
      "UPDATE encounter_saves SET name = $1, updated_at = $2 WHERE id = $3",
    )
    .bind(&to)
    .bind(now)
    .bind(&row.id)
    .execute(self.db.pool())
    .await
    .map_err(write_error)?;

    let mut conn = self.db.pool().acquire().await.map_err(read_error)?;
    Ok(SavedEncounter {
      name: to,
      encounter: save_nodes::fetch_body(&mut conn, &row.id).await?,
      created_at: row.created_at,
      updated_at: now,
    })
  }
}

/// Insert one fully-formed save (metadata row + body tree) at
/// `position`, preserving its timestamps.  Takes a bare connection
/// so the one-shot JSON boot import can replay a legacy store
/// inside a single transaction.
pub(crate) async fn insert_save(
  conn: &mut sqlx::AnyConnection,
  user_id: &UserId,
  position: i64,
  save: &SavedEncounter,
) -> Result<(), EncounterStoreError> {
  let save_id = Uuid::new_v4().to_string();
  sqlx::query(
    "INSERT INTO encounter_saves (id, user_id, position, name, \
     created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6)",
  )
  .bind(&save_id)
  .bind(user_id.as_str())
  .bind(position)
  .bind(&save.name)
  .bind(save.created_at)
  .bind(save.updated_at)
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;
  save_nodes::insert_body(conn, &save_id, &save.encounter).await
}

/// Validate a user-provided save name.  Disallow path separators,
/// control characters, and the empty string; cap length to a
/// generous-but-finite limit so a runaway client can't fill the
/// store with megabyte-long names.  Returned `Ok` is the
/// trimmed-and-canonical form to actually store.
pub fn validate_save_name(raw: &str) -> Result<String, EncounterStoreError> {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return Err(EncounterStoreError::SaveNameInvalid {
      reason: "name must not be empty",
    });
  }
  if trimmed.len() > 120 {
    return Err(EncounterStoreError::SaveNameInvalid {
      reason: "name must be 120 characters or fewer",
    });
  }
  if trimmed
    .chars()
    .any(|c| c == '/' || c == '\\' || c == '\0' || (c.is_control() && c != ' '))
  {
    return Err(EncounterStoreError::SaveNameInvalid {
      reason: "name must not contain path separators or control characters",
    });
  }
  Ok(trimmed.to_string())
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}
