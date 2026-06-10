//! Per-user user-authored treasure tables for the Treasure
//! generator's _Custom_ section.
//!
//! A user treasure table is a weighted list of named entries
//! ("Iridescent Pearl" / "Silver Crown" / "Smoking Censer of
//! Bahamut") that the GM rolls on alongside the bundled SRD
//! tables.  Pre-Tier-4 these would live only in
//! `localStorage.userTreasureTables`, but persisting them
//! server-side keeps the same table available across browsers
//! — the same pattern as
//! [`LoreGroupStore`](crate::lore_groups::LoreGroupStore) and
//! [`ConditionPresetStore`](crate::condition_presets::ConditionPresetStore).
//!
//! Disk shape: `HashMap<UserId, Value>` where the value is an
//! opaque JSON payload defined by
//! `Encounter.Treasure.UserTable.Wire` on the Elm side.  The
//! server doesn't model the schema — the frontend owns it,
//! and the wire format follows the frontend.
//!
//! Anonymous users persist to `localStorage` instead; on
//! sign-in the existing migration pipeline in `Update.Auth`
//! PUTs the local snapshot up here once.

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
pub struct TreasureTableStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl TreasureTableStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, TreasureTableStoreError> {
    let inner = JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path)
      .await
      .map_err(TreasureTableStoreError::Store)?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Return the user's saved treasure-table list, or
  /// `Value::Null` when they haven't persisted one yet.  The
  /// frontend treats null as "use the empty default" — no
  /// migration step needed.
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
  ) -> Result<(), TreasureTableStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await
      .map_err(TreasureTableStoreError::Store)?;
    Ok(())
  }
}

#[derive(Debug, Error)]
pub enum TreasureTableStoreError {
  #[error("Treasure-table persistence failed: {0}")]
  Store(#[source] ezpz_dndz_lib::json_file_store::JsonFileStoreError),
}

impl IntoResponse for TreasureTableStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "treasure-table store error");
    (
      axum::http::StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn get_treasure_tables(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.treasure_tables.read(&user.id).await).into_response()
}

async fn put_treasure_tables(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(body): Json<Value>,
) -> Response {
  match state.treasure_tables.replace(&user.id, body.clone()).await {
    Ok(()) => Json(body).into_response(),
    Err(e) => e.into_response(),
  }
}

pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/treasure-tables",
      get_with(get_treasure_tables, |op: TransformOperation| {
        op.description(
          "Return the caller's saved user-authored treasure tables \
           as opaque JSON.  Returns `null` when the user hasn't \
           saved any tables yet — the frontend treats that as the \
           empty default.",
        )
      }),
    )
    .api_route(
      "/api/treasure-tables",
      put_with(put_treasure_tables, |op: TransformOperation| {
        op.description(
          "Replace the caller's saved treasure tables with the \
           supplied JSON.  Body is opaque to the server — the \
           frontend defines the shape.",
        )
      }),
    )
}
