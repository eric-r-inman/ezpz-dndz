//! Live-encounter persistence, scoped per user.
//!
//! Stores each user's single active combat queue + active marker +
//! round counter as opaque JSON, keyed by `UserId`.  Mirrors the
//! `Encounter` shape on the Elm side; the server doesn't re-model
//! the schema because the frontend is the source of truth for
//! combat semantics.
//!
//! Disk shape is `HashMap<UserId, Value>`.  Two users running
//! simultaneous combats don't trample each other; a user with no
//! persisted encounter yet reads as `Value::Null`, which the
//! frontend treats as "use the empty default".

use std::{collections::HashMap, path::PathBuf, sync::Arc};

use ezpz_dndz_lib::{json_file_store::JsonFileStore, users::UserId};
use serde_json::Value;

use super::error::EncounterStoreError;

#[derive(Clone)]
pub struct EncounterStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl EncounterStore {
  /// Open the store at `path`.  No bootstrap — an absent file is an
  /// empty map; users without an entry read `Value::Null`.
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, EncounterStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path).await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Return the given user's encounter, or `Value::Null` when they
  /// haven't auto-saved one yet.
  pub async fn read(&self, user_id: &UserId) -> Value {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .cloned()
      .unwrap_or(Value::Null)
  }

  pub async fn replace(
    &self,
    user_id: &UserId,
    next: Value,
  ) -> Result<(), EncounterStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await?;
    Ok(())
  }
}
