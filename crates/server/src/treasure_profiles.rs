//! Per-user saved profiles for the Treasure roller's
//! "Tune your rolls" settings.
//!
//! A profile captures one full `TreasureSettings` record (per-Kind
//! toggles, count + value knobs, magic-scroll chance) under a
//! GM-supplied name so common encounter archetypes — "Dragon
//! hoard with x2 art objects", "Wizard's library", "Bounty board"
//! — can be reapplied with one click.
//!
//! Disk shape mirrors the sibling user-store modules
//! (`condition_presets`, `lore_groups`, etc.): a
//! `HashMap<UserId, Value>` where the value is the opaque JSON
//! the frontend serializes (a name → settings dict).  The server
//! doesn't model the profile schema — the Elm side owns it, and
//! the wire format follows the frontend.
//!
//! Anonymous sessions write to `localStorage.userTreasureProfiles`
//! and PUT a snapshot up on sign-in, same as the other user-store
//! features.

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
pub struct TreasureProfileStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl TreasureProfileStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, TreasureProfileStoreError> {
    let inner = JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path)
      .await
      .map_err(TreasureProfileStoreError::Store)?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Return the caller's saved profile dict, or `Value::Null`
  /// when they haven't persisted any yet.  Frontend reads null
  /// as "use the empty default".
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
  ) -> Result<(), TreasureProfileStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await
      .map_err(TreasureProfileStoreError::Store)?;
    Ok(())
  }
}

#[derive(Debug, Error)]
pub enum TreasureProfileStoreError {
  #[error("Treasure-profile persistence failed: {0}")]
  Store(#[source] ezpz_dndz_lib::json_file_store::JsonFileStoreError),
}

impl IntoResponse for TreasureProfileStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "treasure-profile store error");
    (
      axum::http::StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn get_treasure_profiles(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.treasure_profiles.read(&user.id).await).into_response()
}

async fn put_treasure_profiles(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(body): Json<Value>,
) -> Response {
  match state
    .treasure_profiles
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
      "/api/treasure-profiles",
      get_with(get_treasure_profiles, |op: TransformOperation| {
        op.description(
          "Return the caller's saved Treasure-roller settings \
           profiles as opaque JSON.  Returns `null` when the user \
           hasn't saved any yet — the frontend treats that as the \
           empty default.",
        )
      }),
    )
    .api_route(
      "/api/treasure-profiles",
      put_with(put_treasure_profiles, |op: TransformOperation| {
        op.description(
          "Replace the caller's saved Treasure-roller settings \
           profiles with the supplied JSON.  Body is opaque to the \
           server.",
        )
      }),
    )
}
