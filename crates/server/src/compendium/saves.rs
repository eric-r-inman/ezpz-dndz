//! Named-compendium save store.
//!
//! Distinct from the live compendium (`compendium/store.rs`), which
//! holds the single shared bestiary all users edit.  This store
//! holds each user's named compendium snapshots: a list of
//! `{ name, creatures, created_at, updated_at }` records keyed by a
//! user-provided string.  Callers can create / overwrite / list /
//! get / delete / rename these by name, exactly mirroring the
//! `SavedEncounterStore` pattern.
//!
//! Disk shape is `HashMap<UserId, Vec<SavedCompendium>>` — name
//! uniqueness is per-user.  Backed by a single JSON file
//! (`<data_dir>/compendium-saves.json`) through the shared
//! `JsonFileStore` for atomic writes.  The creature list is stored
//! as opaque `serde_json::Value` so the `Creature` shape can evolve
//! without a server-side migration.

use std::{
  collections::HashMap,
  path::PathBuf,
  sync::Arc,
  time::{SystemTime, UNIX_EPOCH},
};

use ezpz_dndz_lib::{json_file_store::JsonFileStore, users::UserId};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::error::CompendiumStoreError;

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

/// File-backed list of named compendium snapshots, keyed by user.
#[derive(Clone)]
pub struct SavedCompendiumStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<SavedCompendium>>>>,
}

impl SavedCompendiumStore {
  /// Open the store at `path`.  Missing file is treated as an
  /// empty map; malformed JSON (including the legacy pre-auth
  /// flat-list shape) drops to an empty map.
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, CompendiumStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Vec<SavedCompendium>>>::load_or_default(
        path,
      )
      .await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Project one user's snapshots down to metadata for the listing
  /// endpoint.  Sorted by `updated_at` descending so the most
  /// recently touched save sits at the top of the modal.
  pub async fn list(&self, user_id: &UserId) -> Vec<SavedCompendiumMeta> {
    let all = self.inner.read().await;
    let mut metas: Vec<SavedCompendiumMeta> = all
      .get(user_id)
      .map(|saves| {
        saves
          .iter()
          .map(|s| SavedCompendiumMeta {
            name: s.name.clone(),
            created_at: s.created_at,
            updated_at: s.updated_at,
          })
          .collect()
      })
      .unwrap_or_default();
    metas.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    metas
  }

  pub async fn get(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Option<SavedCompendium> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .and_then(|saves| saves.iter().find(|s| s.name == name).cloned())
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
    let now = epoch_millis();
    let record = SavedCompendium {
      name: name.clone(),
      creatures,
      created_at: now,
      updated_at: now,
    };
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        if saves.iter().any(|s| s.name == name) {
          Err(())
        } else {
          saves.push(record.clone());
          Ok(record)
        }
      })
      .await?;
    outcome.map_err(|()| CompendiumStoreError::SaveAlreadyExists)
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
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        if let Some(slot) = saves.iter_mut().find(|s| s.name == name) {
          slot.creatures = creatures;
          slot.updated_at = now;
          Ok(slot.clone())
        } else {
          Err(())
        }
      })
      .await?;
    outcome.map_err(|()| CompendiumStoreError::SaveNotFound)
  }

  /// Drop the snapshot with the given name from the user's list.
  pub async fn delete(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<(), CompendiumStoreError> {
    let owned = name.to_string();
    let user_id_owned = user_id.clone();
    let removed = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        let before = saves.len();
        saves.retain(|s| s.name != owned);
        before != saves.len()
      })
      .await?;
    if removed {
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
    let from_owned = from.to_string();
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        if saves.iter().any(|s| s.name == to) {
          return Err(CompendiumStoreError::SaveAlreadyExists);
        }
        match saves.iter_mut().find(|s| s.name == from_owned) {
          Some(slot) => {
            slot.name = to;
            slot.updated_at = now;
            Ok(slot.clone())
          }
          None => Err(CompendiumStoreError::SaveNotFound),
        }
      })
      .await?;
    outcome
  }
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
