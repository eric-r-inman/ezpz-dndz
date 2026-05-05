//! Live-encounter persistence + HTTP routes.
//!
//! Two stores live here:
//!
//! - The single auto-saved live encounter (`store.rs` /
//!   [`EncounterStore`]).  Auto-saved by the frontend on every
//!   mutation, auto-loaded on app boot so a page reload doesn't
//!   lose combat state.
//! - The user's named save files (`saves.rs` /
//!   [`SavedEncounterStore`]).  Explicit user-initiated saves and
//!   loads via the Save / Load buttons in Encounter Controls.
//!
//! HTTP routes:
//!
//! - `GET /api/encounter` — read the live encounter as opaque JSON.
//!   Returns `null` when no encounter has been persisted yet.
//! - `PUT /api/encounter` — replace the persisted live encounter.
//! - `GET /api/encounter/saves` — list named saves (metadata only).
//! - `GET /api/encounter/saves/:name` — read a single save's body.
//! - `PUT /api/encounter/saves/:name` (?overwrite=true) — create or
//!   overwrite a named save.
//! - `DELETE /api/encounter/saves/:name` — drop a named save.
//! - `POST /api/encounter/saves/:name/rename` — rename a save.
//!
//! The schema for the encounter body is whatever the frontend's
//! `Encounter.elm` serializes; the server stores it opaquely so
//! frontend-only schema changes don't require a migration.

pub mod error;
pub mod saves;
pub mod store;

pub use error::EncounterStoreError;
pub use saves::{SavedEncounter, SavedEncounterMeta, SavedEncounterStore};
pub use store::EncounterStore;

use aide::{
  axum::{
    routing::{delete_with, get_with, post_with, put_with},
    ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::{Path, Query, State},
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use serde::Deserialize;
use serde_json::Value;

use crate::web_base::AppState;

async fn get_encounter(State(state): State<AppState>) -> Response {
  Json(state.encounter_store.read().await).into_response()
}

async fn put_encounter(
  State(state): State<AppState>,
  Json(body): Json<Value>,
) -> Response {
  match state.encounter_store.replace(body.clone()).await {
    Ok(()) => Json(body).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn list_saves(State(state): State<AppState>) -> Response {
  Json(state.encounter_saves.list().await).into_response()
}

async fn get_save(
  State(state): State<AppState>,
  Path(name): Path<String>,
) -> Response {
  match state.encounter_saves.get(&name).await {
    Some(record) => Json(record).into_response(),
    None => EncounterStoreError::SaveNotFound.into_response(),
  }
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct PutSaveQuery {
  /// When `true`, replace the existing save with this name.  When
  /// `false` (the default), creating against an existing name
  /// returns `409 Conflict` so the frontend can prompt the user
  /// to confirm the overwrite.
  #[serde(default)]
  overwrite: bool,
}

async fn put_save(
  State(state): State<AppState>,
  Path(raw_name): Path<String>,
  Query(query): Query<PutSaveQuery>,
  Json(body): Json<Value>,
) -> Response {
  let name = match saves::validate_save_name(&raw_name) {
    Ok(n) => n,
    Err(e) => return e.into_response(),
  };
  let result = if query.overwrite {
    // Try replace; if missing, fall back to create so a single
    // PUT?overwrite=true call upserts.
    match state
      .encounter_saves
      .replace(name.clone(), body.clone())
      .await
    {
      Ok(record) => Ok(record),
      Err(EncounterStoreError::SaveNotFound) => {
        state.encounter_saves.create(name, body).await
      }
      Err(other) => Err(other),
    }
  } else {
    state.encounter_saves.create(name, body).await
  };
  match result {
    Ok(record) => (StatusCode::OK, Json(record)).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn delete_save(
  State(state): State<AppState>,
  Path(name): Path<String>,
) -> Response {
  match state.encounter_saves.delete(&name).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn rename_save(
  State(state): State<AppState>,
  Path(name): Path<String>,
  Json(body): Json<saves::RenameBody>,
) -> Response {
  let new_name = match saves::validate_save_name(&body.new_name) {
    Ok(n) => n,
    Err(e) => return e.into_response(),
  };
  match state.encounter_saves.rename(&name, new_name).await {
    Ok(record) => Json(record).into_response(),
    Err(e) => e.into_response(),
  }
}

/// Build the live-encounter subrouter.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/encounter",
      get_with(get_encounter, |op: TransformOperation| {
        op.description(
          "Read the persisted live encounter as opaque JSON. \
           Returns `null` when no encounter has been saved.",
        )
      }),
    )
    .api_route(
      "/api/encounter",
      put_with(put_encounter, |op: TransformOperation| {
        op.description(
          "Replace the persisted live encounter with the supplied \
           JSON.  The shape is whatever the frontend serializes; \
           the server doesn't validate it.",
        )
      }),
    )
    .api_route(
      "/api/encounter/saves",
      get_with(list_saves, |op: TransformOperation| {
        op.description(
          "List named saved encounters (metadata only — no bodies). \
           Sorted by most-recently-updated first.",
        )
      }),
    )
    .api_route(
      "/api/encounter/saves/{name}",
      get_with(get_save, |op: TransformOperation| {
        op.description("Fetch one named saved encounter, including its body.")
      }),
    )
    .api_route(
      "/api/encounter/saves/{name}",
      put_with(put_save, |op: TransformOperation| {
        op.description(
          "Create or overwrite a named saved encounter. \
           Without `?overwrite=true`, attempting to save under an \
           existing name returns 409 so the frontend can prompt.",
        )
      }),
    )
    .api_route(
      "/api/encounter/saves/{name}",
      delete_with(delete_save, |op: TransformOperation| {
        op.description("Delete a named saved encounter.")
      }),
    )
    .api_route(
      "/api/encounter/saves/{name}/rename",
      post_with(rename_save, |op: TransformOperation| {
        op.description(
          "Rename a saved encounter.  Body: `{ \"new_name\": \"...\" }`. \
           Errors if the destination name already exists.",
        )
      }),
    )
}
