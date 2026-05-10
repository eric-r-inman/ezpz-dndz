//! Named-encounter save store.
//!
//! Distinct from the live-encounter store (`encounters/store.rs`),
//! which holds the single auto-saved current combat.  This store
//! holds the user's named save files: a list of
//! `{ name, encounter, created_at, updated_at }` records keyed by
//! a user-provided string.  Callers can create / overwrite / list /
//! get / delete / rename these by name.
//!
//! Disk shape is `HashMap<UserId, Vec<SavedEncounter>>` — each user
//! sees only their own saves and name uniqueness is per-user (Alice
//! and Bob can both have a "Goblin ambush" without collision).
//!
//! Backed by a single JSON file (`<data_dir>/encounter-saves.json`)
//! through the shared `JsonFileStore` for atomic writes.  The
//! encounter body is stored as opaque `serde_json::Value` so the
//! shape of `Encounter.elm` can evolve without a server-side
//! migration.

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

use super::error::EncounterStoreError;

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

/// File-backed list of named saves, keyed by user.
#[derive(Clone)]
pub struct SavedEncounterStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<SavedEncounter>>>>,
}

impl SavedEncounterStore {
  /// Open the store at `path`.  Missing file is treated as an empty
  /// map; malformed JSON (including the legacy pre-auth flat-list
  /// shape) is logged at WARN by the underlying `JsonFileStore` and
  /// also drops to an empty map.
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, EncounterStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Vec<SavedEncounter>>>::load_or_default(
        path,
      )
      .await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Project one user's saves down to metadata for the listing
  /// endpoint.  Sorted by `updated_at` descending so the most
  /// recently touched save sits at the top of the modal.
  pub async fn list(&self, user_id: &UserId) -> Vec<SavedEncounterMeta> {
    let all = self.inner.read().await;
    let mut metas: Vec<SavedEncounterMeta> = all
      .get(user_id)
      .map(|saves| {
        saves
          .iter()
          .map(|s| SavedEncounterMeta {
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
  ) -> Option<SavedEncounter> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .and_then(|saves| saves.iter().find(|s| s.name == name).cloned())
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
    let now = epoch_millis();
    let record = SavedEncounter {
      name: name.clone(),
      encounter,
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
    outcome.map_err(|()| EncounterStoreError::SaveAlreadyExists)
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
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        if let Some(slot) = saves.iter_mut().find(|s| s.name == name) {
          slot.encounter = encounter;
          slot.updated_at = now;
          Ok(slot.clone())
        } else {
          Err(())
        }
      })
      .await?;
    outcome.map_err(|()| EncounterStoreError::SaveNotFound)
  }

  /// Drop the save with the given name from the user's list.
  pub async fn delete(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<(), EncounterStoreError> {
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
    let from_owned = from.to_string();
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let saves = all.entry(user_id_owned).or_default();
        if saves.iter().any(|s| s.name == to) {
          return Err(EncounterStoreError::SaveAlreadyExists);
        }
        match saves.iter_mut().find(|s| s.name == from_owned) {
          Some(slot) => {
            slot.name = to;
            slot.updated_at = now;
            Ok(slot.clone())
          }
          None => Err(EncounterStoreError::SaveNotFound),
        }
      })
      .await?;
    outcome
  }
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
