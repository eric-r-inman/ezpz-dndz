//! Named-compendium save store, relational edition.
//!
//! Distinct from the live per-user compendium (`user_store.rs`).
//! This store holds each user's named compendium snapshots: a list
//! of `{ name, creatures, created_at, updated_at }` records keyed
//! by a user-provided string.  Callers can create / overwrite /
//! list / get / delete / rename these by name, exactly mirroring
//! the `SavedEncounterStore` pattern.
//!
//! Storage is the `compendium_saves` table plus the
//! `compendium_save_nodes` JSON tree (migration 0003).  The
//! snapshot body stays an **opaque** `serde_json::Value` on the
//! wire — that has always been the contract (the frontend can
//! evolve the exported shape without a server migration, and
//! callers may PUT bodies that don't decode as `Creature`), so the
//! body is normalized structurally (one row per JSON node, no JSON
//! columns) rather than through the typed creature tables; see
//! [`super::save_body`] for the codec and migration 0003 for the
//! full rationale.  Name uniqueness is per-user, enforced both in
//! code (for the 409 contract) and by a unique index.
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

use super::error::CompendiumStoreError;
use super::save_body;

/// One named compendium-snapshot record.  The body is stored
/// opaquely as the JSON the frontend exports — this keeps the
/// server out of the business of validating every field on a
/// creature.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SavedCompendium {
  pub name: String,
  pub creatures: Value,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Listing-row shape: just the metadata, no body.  Used by
/// `GET /api/compendium/saves` to keep the response cheap when a
/// user has many snapshots and the modal only needs names.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SavedCompendiumMeta {
  pub name: String,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Wire body for the rename endpoint.
#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct RenameBody {
  pub new_name: String,
}

fn read_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::SaveRowsRead { source }
}

fn write_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::SaveRowsWrite { source }
}

fn begin_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::TransactionBegin {
    store: "save",
    source,
  }
}

fn commit_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::TransactionCommit {
    store: "save",
    source,
  }
}

/// Relational list of named compendium snapshots, keyed by user.
#[derive(Clone)]
pub struct SavedCompendiumStore {
  db: Db,
}

/// The metadata row for one snapshot, including its surrogate id.
struct SaveRow {
  id: String,
  name: String,
  created_at: i64,
  updated_at: i64,
}

fn save_from_row(row: &AnyRow) -> Result<SaveRow, CompendiumStoreError> {
  Ok(SaveRow {
    id: row.try_get("id").map_err(read_error)?,
    name: row.try_get("name").map_err(read_error)?,
    created_at: row.try_get("created_at").map_err(read_error)?,
    updated_at: row.try_get("updated_at").map_err(read_error)?,
  })
}

impl SavedCompendiumStore {
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  async fn row_by_name(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<Option<SaveRow>, CompendiumStoreError> {
    sqlx::query(
      "SELECT id, name, created_at, updated_at FROM compendium_saves \
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

  /// One user's snapshot metadata for the listing endpoint.  Sorted
  /// by `updated_at` descending so the most recently touched save
  /// sits at the top of the modal.
  pub async fn list(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<SavedCompendiumMeta>, CompendiumStoreError> {
    sqlx::query(
      "SELECT id, name, created_at, updated_at FROM compendium_saves \
       WHERE user_id = $1 ORDER BY updated_at DESC, position",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(read_error)?
    .iter()
    .map(|row| {
      save_from_row(row).map(|r| SavedCompendiumMeta {
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
  ) -> Result<Option<SavedCompendium>, CompendiumStoreError> {
    let Some(row) = self.row_by_name(user_id, name).await? else {
      return Ok(None);
    };
    let mut conn = self.db.pool().acquire().await.map_err(read_error)?;
    Ok(Some(SavedCompendium {
      name: row.name,
      creatures: save_body::fetch_body(&mut conn, &row.id).await?,
      created_at: row.created_at,
      updated_at: row.updated_at,
    }))
  }

  /// Insert a brand new snapshot for the given user.  Errors if a
  /// save with this name already exists for that user — callers
  /// wanting overwrite semantics use [`replace`](Self::replace).
  pub async fn create(
    &self,
    user_id: &UserId,
    name: String,
    creatures: Value,
  ) -> Result<SavedCompendium, CompendiumStoreError> {
    if self.row_by_name(user_id, &name).await?.is_some() {
      return Err(CompendiumStoreError::SaveAlreadyExists);
    }
    let now = epoch_millis();
    let save_id = Uuid::new_v4().to_string();

    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    let position = sqlx::query_scalar::<_, i64>(
      "SELECT COALESCE(MAX(position) + 1, 0) FROM compendium_saves \
       WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(read_error)?;
    sqlx::query(
      "INSERT INTO compendium_saves (id, user_id, position, name, \
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
    save_body::insert_body(&mut tx, &save_id, &creatures).await?;
    tx.commit().await.map_err(commit_error)?;

    Ok(SavedCompendium {
      name,
      creatures,
      created_at: now,
      updated_at: now,
    })
  }

  /// Overwrite an existing snapshot by name; preserves the
  /// original `created_at`.  Errors if no save with this name
  /// exists for the given user.
  pub async fn replace(
    &self,
    user_id: &UserId,
    name: String,
    creatures: Value,
  ) -> Result<SavedCompendium, CompendiumStoreError> {
    let row = self
      .row_by_name(user_id, &name)
      .await?
      .ok_or(CompendiumStoreError::SaveNotFound)?;
    let now = epoch_millis();

    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    sqlx::query("DELETE FROM compendium_save_nodes WHERE save_id = $1")
      .bind(&row.id)
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    save_body::insert_body(&mut tx, &row.id, &creatures).await?;
    sqlx::query("UPDATE compendium_saves SET updated_at = $1 WHERE id = $2")
      .bind(now)
      .bind(&row.id)
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    tx.commit().await.map_err(commit_error)?;

    Ok(SavedCompendium {
      name,
      creatures,
      created_at: row.created_at,
      updated_at: now,
    })
  }

  /// Drop the snapshot with the given name from the user's list.
  pub async fn delete(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<(), CompendiumStoreError> {
    let result = sqlx::query(
      "DELETE FROM compendium_saves WHERE user_id = $1 AND name = $2",
    )
    .bind(user_id.as_str())
    .bind(name)
    .execute(self.db.pool())
    .await
    .map_err(write_error)?;
    if result.rows_affected() > 0 {
      Ok(())
    } else {
      Err(CompendiumStoreError::SaveNotFound)
    }
  }

  /// Rename a snapshot in place.  Errors if the source name is
  /// missing or the destination name already exists for the user
  /// (no implicit overwrite — the frontend should prompt).
  /// `updated_at` is bumped to reflect the user-visible change.
  pub async fn rename(
    &self,
    user_id: &UserId,
    from: &str,
    to: String,
  ) -> Result<SavedCompendium, CompendiumStoreError> {
    if self.row_by_name(user_id, &to).await?.is_some() {
      return Err(CompendiumStoreError::SaveAlreadyExists);
    }
    let row = self
      .row_by_name(user_id, from)
      .await?
      .ok_or(CompendiumStoreError::SaveNotFound)?;
    let now = epoch_millis();

    sqlx::query(
      "UPDATE compendium_saves SET name = $1, updated_at = $2 WHERE id = $3",
    )
    .bind(&to)
    .bind(now)
    .bind(&row.id)
    .execute(self.db.pool())
    .await
    .map_err(write_error)?;

    let mut conn = self.db.pool().acquire().await.map_err(read_error)?;
    Ok(SavedCompendium {
      name: to,
      creatures: save_body::fetch_body(&mut conn, &row.id).await?,
      created_at: row.created_at,
      updated_at: now,
    })
  }
}

/// Insert one fully-formed snapshot (metadata row + body tree) at
/// `position`, preserving its timestamps.  Takes a bare connection
/// so the one-shot JSON boot import can replay a legacy store
/// inside a single transaction.
pub(crate) async fn insert_snapshot(
  conn: &mut sqlx::AnyConnection,
  user_id: &UserId,
  position: i64,
  snapshot: &SavedCompendium,
) -> Result<(), CompendiumStoreError> {
  let save_id = Uuid::new_v4().to_string();
  sqlx::query(
    "INSERT INTO compendium_saves (id, user_id, position, name, \
     created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6)",
  )
  .bind(&save_id)
  .bind(user_id.as_str())
  .bind(position)
  .bind(&snapshot.name)
  .bind(snapshot.created_at)
  .bind(snapshot.updated_at)
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;
  save_body::insert_body(conn, &save_id, &snapshot.creatures).await
}

/// Validate a user-provided save name.  Disallow path separators,
/// control characters, and the empty string; cap length at 120
/// chars (mirrors the encounter-saves limit so the modal's input
/// `maxlength` is universal client-side).  Returned `Ok` is the
/// trimmed-and-canonical form to actually store.
pub fn validate_save_name(raw: &str) -> Result<String, CompendiumStoreError> {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return Err(CompendiumStoreError::SaveNameInvalid {
      reason: "name must not be empty",
    });
  }
  if trimmed.len() > 120 {
    return Err(CompendiumStoreError::SaveNameInvalid {
      reason: "name must be 120 characters or fewer",
    });
  }
  if trimmed
    .chars()
    .any(|c| c == '/' || c == '\\' || c == '\0' || (c.is_control() && c != ' '))
  {
    return Err(CompendiumStoreError::SaveNameInvalid {
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
