//! Per-user user-authored Lore groups for the Random Encounter
//! generator.
//!
//! Lore groups are themed clusters of compendium creatures the
//! GM curates ("Goblin warband", "Wizards of Saruman") so the
//! random-encounter roller has something narratively coherent to
//! pull from.  Pre-Tier-3 the groups lived only in
//! `localStorage.userLoreGroups`, which kept them out of sync
//! across browsers.  This module persists them on the server,
//! per user, so signing in on a second device gets the same
//! groups back.
//!
//! Disk shape mirrors [`EncounterStore`](crate::encounters::EncounterStore):
//! `HashMap<UserId, Value>` where the value is an opaque JSON
//! payload (whatever the frontend serializes).  The server
//! doesn't model the schema — `Encounter.RandomEncounter.Lore`
//! on the Elm side owns it, and the wire format follows the
//! frontend rather than the other way around.
//!
//! Anonymous users continue to write to localStorage; on sign-in
//! the existing migration pipeline in `Update.Auth` PUTs the
//! local snapshot up here as a one-shot, then switches the
//! persistence target.

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
pub struct LoreGroupStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl LoreGroupStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, LoreGroupStoreError> {
    let inner = JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path)
      .await
      .map_err(LoreGroupStoreError::Store)?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Return the user's saved Lore-group list, or `Value::Null`
  /// when they haven't persisted one yet.  The frontend treats
  /// null as "use the empty default" — no migration step needed.
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
  ) -> Result<(), LoreGroupStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await
      .map_err(LoreGroupStoreError::Store)?;
    Ok(())
  }
}

#[derive(Debug, Error)]
pub enum LoreGroupStoreError {
  #[error("Lore-group persistence failed: {0}")]
  Store(#[source] ezpz_dndz_lib::json_file_store::JsonFileStoreError),
}

impl IntoResponse for LoreGroupStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "lore-group store error");
    (
      axum::http::StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn get_lore_groups(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.lore_groups.read(&user.id).await).into_response()
}

async fn put_lore_groups(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(body): Json<Value>,
) -> Response {
  match state.lore_groups.replace(&user.id, body.clone()).await {
    Ok(()) => Json(body).into_response(),
    Err(e) => e.into_response(),
  }
}

pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/lore-groups",
      get_with(get_lore_groups, |op: TransformOperation| {
        op.description(
          "Return the caller's saved user-authored Lore groups as \
           opaque JSON.  Returns `null` when the user hasn't saved \
           any groups yet — the frontend treats that as the empty \
           default.",
        )
      }),
    )
    .api_route(
      "/api/lore-groups",
      put_with(put_lore_groups, |op: TransformOperation| {
        op.description(
          "Replace the caller's saved Lore groups with the supplied \
           JSON.  Body is opaque to the server — the frontend \
           defines the shape.",
        )
      }),
    )
}
