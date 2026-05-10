//! Dice-roll history persistence.
//!
//! The Elm dice roller is a pure rules engine that produces a `Roll`
//! JSON blob per click.  The frontend can't reach `localStorage`
//! without hand-written JS glue, which the project explicitly avoids,
//! so persistence rides through this crate instead: a small
//! file-backed JSON store with three HTTP endpoints.
//!
//! Endpoints:
//!
//! - `GET    /api/dice/history`  — return the stored roll log
//!   (newest first; bounded by `MAX_ENTRIES`).
//! - `POST   /api/dice/history`  — append one roll, truncate to
//!   `MAX_ENTRIES`, and return the updated log.
//! - `DELETE /api/dice/history`  — clear the log.
//!
//! Each `Roll` is treated as opaque JSON.  The server intentionally
//! does NOT validate the rolls' shape — the frontend defines the
//! schema and round-trips it.  This keeps the rules layer entirely
//! in Elm and lets us extend the schema without changing this file.
//!
//! Concurrency: a single async mutex serializes file IO so concurrent
//! POSTs can't lose updates from a read-modify-write race.  This is
//! cheap because the typical load is a handful of rolls per second
//! at the table.

use std::{collections::HashMap, sync::Arc};

use aide::{
  axum::{
    routing::delete_with, routing::get_with, routing::post_with, ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
  Extension, Json,
};
use ezpz_dndz_lib::{
  json_file_store::{JsonFileStore, JsonFileStoreError},
  users::UserId,
};
use serde_json::Value;
use thiserror::Error;
use tracing::warn;

use crate::users::CurrentUser;
use crate::web_base::AppState;

/// Hard cap on persisted rolls.  Matches the in-memory cap on the
/// frontend (`Dice.maxHistoryEntries`) so the two stay in lockstep.
pub const MAX_ENTRIES: usize = 30;

/// Semantic errors from dice-history persistence.  Wraps the
/// generic `JsonFileStoreError` from the lib crate so the dice
/// surface keeps its own typed error vocabulary; future variants
/// can describe dice-specific failure modes (e.g. malformed roll
/// payload) without leaking storage internals to callers.
#[derive(Debug, Error)]
pub enum DiceHistoryError {
  #[error("Dice history persistence failed: {0}")]
  StoreError(#[from] JsonFileStoreError),
}

impl IntoResponse for DiceHistoryError {
  fn into_response(self) -> Response {
    warn!(error = %self, "dice history operation failed");
    (
      StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

/// File-backed dice history store, scoped per user.  Disk shape is
/// `HashMap<UserId, Vec<Value>>`: each user has their own log,
/// independently capped at `MAX_ENTRIES`.
#[derive(Clone)]
pub struct DiceStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<Value>>>>,
}

impl DiceStore {
  /// Open a store backed by `path`.  Loads the file (or initializes
  /// to an empty map) eagerly so the first request doesn't pay
  /// the file-IO cost.
  pub async fn load_or_default(
    path: std::path::PathBuf,
  ) -> Result<Self, DiceHistoryError> {
    let inner = JsonFileStore::load_or_default(path).await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  /// Read the given user's history.  Returns an empty `Vec` for
  /// users who haven't rolled anything yet.
  pub async fn load(&self, user_id: &UserId) -> Vec<Value> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .cloned()
      .unwrap_or_default()
  }

  /// Prepend `roll` to the user's history, truncate to
  /// `MAX_ENTRIES`, and persist the result.  Returns the user's
  /// updated history.
  pub async fn append(
    &self,
    user_id: &UserId,
    roll: Value,
  ) -> Result<Vec<Value>, DiceHistoryError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        let entries = all.entry(user_id_owned).or_default();
        entries.insert(0, roll);
        entries.truncate(MAX_ENTRIES);
        entries.clone()
      })
      .await
      .map_err(DiceHistoryError::from)
  }

  /// Clear the user's history (drops their entry from the map).
  pub async fn clear(&self, user_id: &UserId) -> Result<(), DiceHistoryError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.remove(&user_id_owned);
      })
      .await?;
    Ok(())
  }
}

// ── HTTP handlers ────────────────────────────────────────────────────────────
//
// Handlers return `Response` directly (rather than `Result<T, E>`) because
// aide's `OperationHandler` trait requires `OperationOutput` on the return
// type, and we don't want to commit to an aide-specific trait impl on our
// own error enum.  The error → response mapping rides on
// `impl IntoResponse for DiceHistoryError` so the handler bodies stay
// tight: success path picks one branch, error path picks the other.

async fn get_history(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Json<Vec<Value>> {
  Json(state.dice_store.load(&user.id).await)
}

async fn post_roll(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(roll): Json<Value>,
) -> Response {
  match state.dice_store.append(&user.id, roll).await {
    Ok(entries) => Json(entries).into_response(),
    Err(err) => err.into_response(),
  }
}

async fn delete_history(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  match state.dice_store.clear(&user.id).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(err) => err.into_response(),
  }
}

/// Build the `/api/dice/*` subrouter, ready to be merged into the
/// base `ApiRouter`.  Returning `ApiRouter<AppState>` (rather than a
/// plain `axum::Router`) lets the three endpoints participate in the
/// OpenAPI schema served at `/api-docs/openapi.json` and browsable
/// at `/scalar`.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/dice/history",
      get_with(get_history, |op: TransformOperation| {
        op.description("Return the persisted dice-roll history (newest first).")
      }),
    )
    .api_route(
      "/api/dice/history",
      post_with(post_roll, |op: TransformOperation| {
        op.description(
          "Append one roll to the history, truncating older entries past MAX_ENTRIES.",
        )
      }),
    )
    .api_route(
      "/api/dice/history",
      delete_with(delete_history, |op: TransformOperation| {
        op.description("Clear the persisted dice-roll history.")
      }),
    )
}
