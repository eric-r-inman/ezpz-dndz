//! Per-user compendium **group** store, relational edition.
//!
//! Each user owns their own set of groups; storage is the
//! `compendium_groups` / `compendium_group_entries` tables
//! (migration 0003), with the legacy `HashMap<UserId, Vec<Group>>`
//! JSON file now only read by the one-shot boot import.  Groups are
//! addressed by their server-issued wire UUID like creatures, but
//! the tables key on a surrogate `row_id` because group ids travel
//! inside export files and are only unique per user.  List order
//! round-trips through the per-user `position` column.

use std::time::{SystemTime, UNIX_EPOCH};

use ezpz_dndz_lib::{
  compendium::{Group, GroupDraft, GroupEntry, InitiativeMode, MinionType},
  db::Db,
  users::UserId,
};
use sqlx::{any::AnyRow, AnyConnection, Row};
use uuid::Uuid;

use super::error::CompendiumStoreError;

fn read_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::GroupRowsRead { source }
}

fn write_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::GroupRowsWrite { source }
}

fn decode_error(detail: String) -> CompendiumStoreError {
  CompendiumStoreError::GroupRowDecode { detail }
}

fn begin_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::TransactionBegin {
    store: "group",
    source,
  }
}

fn commit_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::TransactionCommit {
    store: "group",
    source,
  }
}

#[derive(Clone)]
pub struct CompendiumGroupStore {
  db: Db,
}

/// One reassembled group plus its row bookkeeping.
struct GroupRow {
  row_id: String,
  position: i64,
  group: Group,
}

impl CompendiumGroupStore {
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  async fn rows(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<GroupRow>, CompendiumStoreError> {
    let mut conn = self.db.pool().acquire().await.map_err(read_error)?;
    fetch_groups(&mut conn, user_id).await
  }

  pub async fn list(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<Group>, CompendiumStoreError> {
    Ok(
      self
        .rows(user_id)
        .await?
        .into_iter()
        .map(|r| r.group)
        .collect(),
    )
  }

  pub async fn get(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<Option<Group>, CompendiumStoreError> {
    Ok(
      self
        .rows(user_id)
        .await?
        .into_iter()
        .find(|r| r.group.id == id)
        .map(|r| r.group),
    )
  }

  /// Allocate a fresh id + timestamps, append, return the
  /// materialised `Group` so the client doesn't have to GET to
  /// learn what the server picked.
  pub async fn insert(
    &self,
    user_id: &UserId,
    draft: GroupDraft,
  ) -> Result<Group, CompendiumStoreError> {
    let now = epoch_millis();
    let group = Group {
      id: Uuid::new_v4().to_string(),
      name: draft.name,
      initiative_mode: draft.initiative_mode,
      entries: draft.entries,
      created_at: now,
      updated_at: now,
    };
    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    let position = sqlx::query_scalar::<_, i64>(
      "SELECT COALESCE(MAX(position) + 1, 0) FROM compendium_groups \
       WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(read_error)?;
    insert_group(&mut tx, user_id, position, &group).await?;
    tx.commit().await.map_err(commit_error)?;
    Ok(group)
  }

  /// Replace the existing group at `id` with the supplied record.
  /// `created_at` is preserved server-side; `updated_at` is
  /// bumped.  Errors with `GroupIdMismatchError` if the body id
  /// disagrees with the path id, and `GroupIdNotFoundError` if no
  /// such group exists for this user.
  pub async fn update(
    &self,
    user_id: &UserId,
    id: &str,
    mut group: Group,
  ) -> Result<Group, CompendiumStoreError> {
    if group.id != id {
      return Err(CompendiumStoreError::GroupIdMismatchError {
        path_id: id.to_string(),
        body_id: group.id.clone(),
      });
    }
    group.updated_at = epoch_millis();

    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    let existing = fetch_groups(&mut tx, user_id)
      .await?
      .into_iter()
      .find(|r| r.group.id == id)
      .ok_or_else(|| CompendiumStoreError::GroupIdNotFoundError {
        id: id.to_string(),
      })?;

    // The response reflects the server-preserved created_at rather
    // than whatever the client round-tripped.
    group.created_at = existing.group.created_at;

    sqlx::query("DELETE FROM compendium_groups WHERE row_id = $1")
      .bind(&existing.row_id)
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    insert_group(&mut tx, user_id, existing.position, &group).await?;
    tx.commit().await.map_err(commit_error)?;
    Ok(group)
  }

  /// Replace this user's entire group list with `groups`.  Used by
  /// the reset-to-bundled path (empty `groups`) and by full-
  /// compendium import (groups bundled with the creature list in
  /// the export file).  Server preserves nothing — what you send
  /// is what's persisted for this user.
  pub async fn replace_for_user(
    &self,
    user_id: &UserId,
    groups: Vec<Group>,
  ) -> Result<(), CompendiumStoreError> {
    let mut tx = self.db.pool().begin().await.map_err(begin_error)?;
    sqlx::query("DELETE FROM compendium_groups WHERE user_id = $1")
      .bind(user_id.as_str())
      .execute(&mut *tx)
      .await
      .map_err(write_error)?;
    for (i, group) in groups.iter().enumerate() {
      insert_group(&mut tx, user_id, i as i64, group).await?;
    }
    tx.commit().await.map_err(commit_error)
  }

  pub async fn remove(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<(), CompendiumStoreError> {
    let result = sqlx::query(
      "DELETE FROM compendium_groups WHERE user_id = $1 AND group_id = $2",
    )
    .bind(user_id.as_str())
    .bind(id)
    .execute(self.db.pool())
    .await
    .map_err(write_error)?;
    if result.rows_affected() > 0 {
      Ok(())
    } else {
      Err(CompendiumStoreError::GroupIdNotFoundError { id: id.to_string() })
    }
  }
}

/// Insert one group (parent row + ordered entries) at `position`.
/// Takes a bare connection so the store's transactions and the
/// one-shot JSON boot import can both drive it.
pub(crate) async fn insert_group(
  conn: &mut AnyConnection,
  user_id: &UserId,
  position: i64,
  group: &Group,
) -> Result<(), CompendiumStoreError> {
  let row_id = Uuid::new_v4().to_string();
  let (initiative_kind, initiative_value) = match &group.initiative_mode {
    InitiativeMode::EachRolls => ("each_rolls", None),
    InitiativeMode::SharedRolled => ("shared_rolled", None),
    InitiativeMode::SharedManual { value } => {
      ("shared_manual", Some(i64::from(*value)))
    }
  };
  sqlx::query(
    "INSERT INTO compendium_groups (row_id, user_id, position, group_id, \
     name, initiative_kind, initiative_value, created_at, updated_at) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
  )
  .bind(&row_id)
  .bind(user_id.as_str())
  .bind(position)
  .bind(&group.id)
  .bind(&group.name)
  .bind(initiative_kind)
  .bind(initiative_value)
  .bind(group.created_at)
  .bind(group.updated_at)
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;

  for (i, entry) in group.entries.iter().enumerate() {
    sqlx::query(
      "INSERT INTO compendium_group_entries (group_row_id, position, \
       creature_id, spawn_count, minion_type) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(&entry.creature_id)
    .bind(i64::from(entry.count))
    .bind(minion_token(entry.minion_type))
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }
  Ok(())
}

/// Reassemble every group `user_id` owns, in list order.
async fn fetch_groups(
  conn: &mut AnyConnection,
  user_id: &UserId,
) -> Result<Vec<GroupRow>, CompendiumStoreError> {
  let parents = sqlx::query(
    "SELECT row_id, position, group_id, name, initiative_kind, \
     initiative_value, created_at, updated_at FROM compendium_groups \
     WHERE user_id = $1 ORDER BY position",
  )
  .bind(user_id.as_str())
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?;

  let mut rows = parents
    .iter()
    .map(group_from_row)
    .collect::<Result<Vec<_>, _>>()?;
  if rows.is_empty() {
    return Ok(rows);
  }

  for row in sqlx::query(
    "SELECT e.group_row_id, e.creature_id, e.spawn_count, e.minion_type \
     FROM compendium_group_entries e \
     JOIN compendium_groups g ON g.row_id = e.group_row_id \
     WHERE g.user_id = $1 ORDER BY e.position",
  )
  .bind(user_id.as_str())
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?
  {
    let owner: String = row.try_get("group_row_id").map_err(read_error)?;
    if let Some(slot) = rows.iter_mut().find(|r| r.row_id == owner) {
      slot.group.entries.push(GroupEntry {
        creature_id: row.try_get("creature_id").map_err(read_error)?,
        count: row.try_get::<i64, _>("spawn_count").map_err(read_error)? as i32,
        minion_type: parse_minion(
          &row
            .try_get::<String, _>("minion_type")
            .map_err(read_error)?,
        )?,
      });
    }
  }

  Ok(rows)
}

fn group_from_row(row: &AnyRow) -> Result<GroupRow, CompendiumStoreError> {
  let initiative_kind: String =
    row.try_get("initiative_kind").map_err(read_error)?;
  let initiative_value: Option<i64> =
    row.try_get("initiative_value").map_err(read_error)?;
  let initiative_mode = match initiative_kind.as_str() {
    "each_rolls" => InitiativeMode::EachRolls,
    "shared_rolled" => InitiativeMode::SharedRolled,
    "shared_manual" => InitiativeMode::SharedManual {
      value: initiative_value.unwrap_or_default() as i32,
    },
    other => {
      return Err(decode_error(format!("unknown initiative kind {other:?}")))
    }
  };
  Ok(GroupRow {
    row_id: row.try_get("row_id").map_err(read_error)?,
    position: row.try_get("position").map_err(read_error)?,
    group: Group {
      id: row.try_get("group_id").map_err(read_error)?,
      name: row.try_get("name").map_err(read_error)?,
      initiative_mode,
      entries: Vec::new(),
      created_at: row.try_get("created_at").map_err(read_error)?,
      updated_at: row.try_get("updated_at").map_err(read_error)?,
    },
  })
}

fn minion_token(minion: MinionType) -> &'static str {
  match minion {
    MinionType::None => "none",
    MinionType::Half => "half",
    MinionType::One => "one",
  }
}

fn parse_minion(token: &str) -> Result<MinionType, CompendiumStoreError> {
  match token {
    "none" => Ok(MinionType::None),
    "half" => Ok(MinionType::Half),
    "one" => Ok(MinionType::One),
    other => Err(decode_error(format!("unknown minion type {other:?}"))),
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}
