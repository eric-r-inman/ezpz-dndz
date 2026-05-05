//! Live-encounter persistence.
//!
//! Stores the single active combat queue + active marker + round
//! counter as opaque JSON.  Mirrors the `Encounter` shape on the
//! Elm side; the server doesn't re-model the schema because the
//! frontend is the source of truth for combat semantics.
//!
//! This is the v1 of the "save / load encounter" feature: one
//! persistent live encounter per deployment, auto-saved on every
//! mutation by the frontend, auto-loaded on app boot.  The
//! per-user multi-encounter system described in the parent
//! module's docstring is a follow-up that waits on the `users`
//! table.

use std::{path::PathBuf, sync::Arc};

use ezpz_dndz_lib::json_file_store::JsonFileStore;
use serde_json::Value;

use super::error::EncounterStoreError;

#[derive(Clone)]
pub struct EncounterStore {
  inner: Arc<JsonFileStore<Value>>,
}

impl EncounterStore {
  /// Open the store at `path`.  No bootstrap — an absent file
  /// reads as `Value::Null`, which the frontend treats as
  /// "no persisted encounter, use the empty default".
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, EncounterStoreError> {
    let inner = JsonFileStore::<Value>::load_or_default(path).await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  pub async fn read(&self) -> Value {
    self.inner.read().await
  }

  pub async fn replace(&self, next: Value) -> Result<(), EncounterStoreError> {
    self.inner.replace(next).await?;
    Ok(())
  }
}
