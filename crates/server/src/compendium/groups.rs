//! Per-user compendium **group** store.
//!
//! Each user owns their own set of groups; the on-disk shape is
//! `HashMap<UserId, Vec<Group>>` in a single JSON file backed by
//! [`JsonFileStore`].  Mirrors [`SavedCompendiumStore`](super::saves::SavedCompendiumStore)
//! in disk layout and locking discipline, but with id-based
//! lookup rather than name-based (groups are addressed by their
//! server-issued UUID, like creatures).

use std::{
  collections::HashMap,
  path::PathBuf,
  sync::Arc,
  time::{SystemTime, UNIX_EPOCH},
};

use ezpz_dndz_lib::{
  compendium::{Group, GroupDraft},
  json_file_store::JsonFileStore,
  users::UserId,
};
use uuid::Uuid;

use super::error::CompendiumStoreError;

#[derive(Clone)]
pub struct CompendiumGroupStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<Group>>>>,
}

impl CompendiumGroupStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, CompendiumStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Vec<Group>>>::load_or_default(path)
        .await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  pub async fn list(&self, user_id: &UserId) -> Vec<Group> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .cloned()
      .unwrap_or_default()
  }

  pub async fn get(&self, user_id: &UserId, id: &str) -> Option<Group> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .and_then(|groups| groups.iter().find(|g| g.id == id).cloned())
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
    let user_id_owned = user_id.clone();
    let to_return = group.clone();
    self
      .inner
      .mutate(move |all| {
        all.entry(user_id_owned).or_default().push(group);
      })
      .await?;
    Ok(to_return)
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
    let id_owned = id.to_string();
    let user_id_owned = user_id.clone();
    // Return the slot's CONTENTS after the mutate so the response
    // reflects the server-preserved `created_at` rather than
    // whatever the client round-tripped.
    let outcome = self
      .inner
      .mutate(move |all| {
        let groups = all.entry(user_id_owned).or_default();
        match groups.iter_mut().find(|g| g.id == id_owned) {
          Some(slot) => {
            let preserved_created_at = slot.created_at;
            *slot = group;
            slot.created_at = preserved_created_at;
            Some(slot.clone())
          }
          None => None,
        }
      })
      .await?;
    outcome.ok_or_else(|| CompendiumStoreError::GroupIdNotFoundError {
      id: id.to_string(),
    })
  }

  /// Replace this user's entire group list with `groups`.  Used by
  /// the reset-to-bundled path (empty `groups`) and by full-
  /// compendium import (groups bundled with the creature list in
  /// the export file).  Server preserves nothing — what you send
  /// is what's on disk for this user.
  pub async fn replace_for_user(
    &self,
    user_id: &UserId,
    groups: Vec<Group>,
  ) -> Result<(), CompendiumStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, groups);
      })
      .await?;
    Ok(())
  }

  pub async fn remove(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<(), CompendiumStoreError> {
    let id_owned = id.to_string();
    let user_id_owned = user_id.clone();
    let removed = self
      .inner
      .mutate(move |all| {
        let groups = all.entry(user_id_owned).or_default();
        let before = groups.len();
        groups.retain(|g| g.id != id_owned);
        before != groups.len()
      })
      .await?;
    if removed {
      Ok(())
    } else {
      Err(CompendiumStoreError::GroupIdNotFoundError { id: id.to_string() })
    }
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}
