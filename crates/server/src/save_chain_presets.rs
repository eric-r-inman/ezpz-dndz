//! Per-user saved presets for the Save Chain modal.
//!
//! A Save Chain preset captures a fully-configured "creature
//! makes a save; something happens" recipe (Save ability, DC,
//! on-fail / on-success HP effect + condition list) under a
//! user-given label so a spell like "Hold Person" or "Fireball"
//! can be reapplied with one click across future encounters.
//! Pre-server-sync these lived only in
//! `localStorage.saveChainPresets`, which kept them stuck in the
//! browser they were authored in and forced a re-import on every
//! new device.  This module persists them on the server, per
//! user, so signing in on a second device gets the same presets
//! back.
//!
//! Disk shape mirrors the sibling
//! [`ConditionPresetStore`](crate::condition_presets::ConditionPresetStore)
//! and [`LoreGroupStore`](crate::lore_groups::LoreGroupStore):
//! `HashMap<UserId, Value>` with the value as an opaque JSON
//! payload (whatever the frontend serializes).  The server
//! doesn't model the Save Chain schema — the Elm side owns it,
//! and the wire format follows the frontend.
//!
//! Anonymous users continue to write to localStorage; on sign-in
//! the migration pipeline in `Update.UserSync` PUTs the local
//! snapshot up here as a one-shot, then switches the persistence
//! target.

use aide::{
  axum::{
    routing::{get_with, put_with},
    ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::State,
  response::{IntoResponse, Response},
  Extension, Json,
};
use ezpz_dndz_lib::{json_file_store::JsonFileStore, users::UserId};
use serde_json::Value;
use std::{collections::HashMap, path::PathBuf, sync::Arc};
use thiserror::Error;
use tracing::warn;

use crate::users::CurrentUser;
use crate::web_base::AppState;

#[derive(Clone)]
pub struct SaveChainPresetStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl SaveChainPresetStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, SaveChainPresetStoreError> {
    let inner = JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path)
      .await
      .map_err(SaveChainPresetStoreError::Store)?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Return the user's saved Save Chain preset map, or
  /// `Value::Null` when they haven't persisted any yet.  Frontend
  /// reads null as "use the empty default".
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
  ) -> Result<(), SaveChainPresetStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await
      .map_err(SaveChainPresetStoreError::Store)?;
    Ok(())
  }
}

#[derive(Debug, Error)]
pub enum SaveChainPresetStoreError {
  #[error("Save-chain-preset persistence failed: {0}")]
  Store(#[source] ezpz_dndz_lib::json_file_store::JsonFileStoreError),
}

impl IntoResponse for SaveChainPresetStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "save-chain-preset store error");
    (
      axum::http::StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn get_save_chain_presets(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.save_chain_presets.read(&user.id).await).into_response()
}

async fn put_save_chain_presets(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(body): Json<Value>,
) -> Response {
  match state
    .save_chain_presets
    .replace(&user.id, body.clone())
    .await
  {
    Ok(()) => Json(body).into_response(),
    Err(e) => e.into_response(),
  }
}

pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/save-chain-presets",
      get_with(get_save_chain_presets, |op: TransformOperation| {
        op.description(
          "Return the caller's saved Save Chain presets as opaque \
           JSON.  Returns `null` when the user hasn't saved any \
           presets yet — the frontend treats that as the empty \
           default and falls back to the bundled Save Chain \
           catalog.",
        )
      }),
    )
    .api_route(
      "/api/save-chain-presets",
      put_with(put_save_chain_presets, |op: TransformOperation| {
        op.description(
          "Replace the caller's saved Save Chain presets with the \
           supplied JSON.  Body is opaque to the server.",
        )
      }),
    )
}
