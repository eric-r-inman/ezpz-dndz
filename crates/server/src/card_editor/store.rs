//! Per-user file-backed store for named card layouts.
//!
//! `HashMap<UserId, Vec<NamedCardLayout>>` on disk; CRUD by name
//! within the user's slice.  Mirrors `SavedCompendiumStore` —
//! the differences are domain-specific (different record type,
//! different error variants) but the locking + mutate-then-await
//! pattern is identical.

use std::{
  collections::HashMap,
  path::PathBuf,
  sync::Arc,
  time::{SystemTime, UNIX_EPOCH},
};

use ezpz_dndz_lib::{
  card_editor::{NamedCardLayout, NamedCardLayoutMeta},
  json_file_store::JsonFileStore,
  users::UserId,
};
use serde_json::Value;

use super::error::CardLayoutStoreError;

#[derive(Clone)]
pub struct CardLayoutStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<NamedCardLayout>>>>,
}

impl CardLayoutStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, CardLayoutStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Vec<NamedCardLayout>>>::load_or_default(
        path,
      )
      .await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  pub async fn list(&self, user_id: &UserId) -> Vec<NamedCardLayoutMeta> {
    let all = self.inner.read().await;
    let mut metas: Vec<NamedCardLayoutMeta> = all
      .get(user_id)
      .map(|layouts| {
        layouts
          .iter()
          .map(|l| NamedCardLayoutMeta {
            name: l.name.clone(),
            created_at: l.created_at,
            updated_at: l.updated_at,
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
  ) -> Option<NamedCardLayout> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .and_then(|layouts| layouts.iter().find(|l| l.name == name).cloned())
  }

  /// Insert a brand-new record.  Returns `LayoutAlreadyExists`
  /// when the name collides with one of the user's existing
  /// layouts — callers wanting overwrite semantics use
  /// [`replace`](Self::replace).
  pub async fn create(
    &self,
    user_id: &UserId,
    name: String,
    body: Value,
  ) -> Result<NamedCardLayout, CardLayoutStoreError> {
    let now = epoch_millis();
    let record = NamedCardLayout {
      name: name.clone(),
      body,
      created_at: now,
      updated_at: now,
    };
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let layouts = all.entry(user_id_owned).or_default();
        if layouts.iter().any(|l| l.name == name) {
          Err(())
        } else {
          layouts.push(record.clone());
          Ok(record)
        }
      })
      .await?;
    outcome.map_err(|()| CardLayoutStoreError::LayoutAlreadyExists)
  }

  /// Overwrite an existing layout in place, preserving its
  /// `created_at`.  Errors with `LayoutNotFound` if no record
  /// with that name exists for the user.
  pub async fn replace(
    &self,
    user_id: &UserId,
    name: String,
    body: Value,
  ) -> Result<NamedCardLayout, CardLayoutStoreError> {
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let layouts = all.entry(user_id_owned).or_default();
        if let Some(slot) = layouts.iter_mut().find(|l| l.name == name) {
          slot.body = body;
          slot.updated_at = now;
          Ok(slot.clone())
        } else {
          Err(())
        }
      })
      .await?;
    outcome.map_err(|()| CardLayoutStoreError::LayoutNotFound)
  }

  pub async fn delete(
    &self,
    user_id: &UserId,
    name: &str,
  ) -> Result<(), CardLayoutStoreError> {
    let owned = name.to_string();
    let user_id_owned = user_id.clone();
    let removed = self
      .inner
      .mutate(move |all| {
        let layouts = all.entry(user_id_owned).or_default();
        let before = layouts.len();
        layouts.retain(|l| l.name != owned);
        before != layouts.len()
      })
      .await?;
    if removed {
      Ok(())
    } else {
      Err(CardLayoutStoreError::LayoutNotFound)
    }
  }

  pub async fn rename(
    &self,
    user_id: &UserId,
    from: &str,
    to: String,
  ) -> Result<NamedCardLayout, CardLayoutStoreError> {
    let from_owned = from.to_string();
    let now = epoch_millis();
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let layouts = all.entry(user_id_owned).or_default();
        if layouts.iter().any(|l| l.name == to) {
          return Err(CardLayoutStoreError::LayoutAlreadyExists);
        }
        match layouts.iter_mut().find(|l| l.name == from_owned) {
          Some(slot) => {
            slot.name = to;
            slot.updated_at = now;
            Ok(slot.clone())
          }
          None => Err(CardLayoutStoreError::LayoutNotFound),
        }
      })
      .await?;
    outcome
  }
}

/// Validate a user-provided layout name.  Same rules as the
/// compendium-save names so the frontend's input affordances
/// (maxlength, validation patterns) are consistent across modals.
pub fn validate_layout_name(raw: &str) -> Result<String, CardLayoutStoreError> {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return Err(CardLayoutStoreError::LayoutNameInvalid {
      reason: "name must not be empty",
    });
  }
  if trimmed.len() > 120 {
    return Err(CardLayoutStoreError::LayoutNameInvalid {
      reason: "name must be 120 characters or fewer",
    });
  }
  if trimmed
    .chars()
    .any(|c| c == '/' || c == '\\' || c == '\0' || (c.is_control() && c != ' '))
  {
    return Err(CardLayoutStoreError::LayoutNameInvalid {
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
