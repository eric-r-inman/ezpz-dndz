//! Compendium HTTP routes + file-backed store.
//!
//! Per [`COMPENDIUM_PLAN.org`](../../../../COMPENDIUM_PLAN.org):
//!
//! - Storage: a single JSON file at
//!   `<data_dir>/compendium/creatures.json` via the shared
//!   `JsonFileStore<Vec<Creature>>` from the lib crate.
//! - Routes: REST CRUD on `/api/compendium/creatures[/:id]` plus
//!   bulk `import` / `export` / `reset` endpoints.
//! - Bootstrap: on first launch, the bundled creatures
//!   (embedded via `include_str!`) are written to disk so the
//!   user has something to browse immediately.
//! - Errors: semantic `CompendiumStoreError` with descriptive
//!   variants per the project's `llms.org` conventions.

pub mod error;
pub mod store;

pub use error::CompendiumStoreError;
pub use store::CompendiumStore;

use aide::{
  axum::{
    routing::{delete_with, get_with, post_with, put_with},
    ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::{Path, State},
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};

use crate::web_base::AppState;

// ── handlers ─────────────────────────────────────────────────────────────────
//
// Handlers return `Response` directly rather than typed bodies because the
// aide+axum integration's `OperationHandler` trait fits `Response` cleanly
// while typed responses occasionally trip over generic-parameter inference.
// Request body / path types DO need `schemars::JsonSchema` for the input-
// side `OperationInput` impl — see the JsonSchema derives in the lib
// `compendium/types.rs`.  Net effect: full OpenAPI for path + body
// schemas; response bodies appear as `application/json` without a typed
// schema (acceptable trade-off for now).

async fn list_creatures(State(state): State<AppState>) -> Response {
  Json(state.compendium_store.list().await).into_response()
}

async fn get_creature(
  State(state): State<AppState>,
  Path(id): Path<String>,
) -> Response {
  match state.compendium_store.get(&id).await {
    Some(c) => Json(c).into_response(),
    None => StatusCode::NOT_FOUND.into_response(),
  }
}

async fn create_creature(
  State(state): State<AppState>,
  Json(draft): Json<CreatureDraft>,
) -> Response {
  match state.compendium_store.insert(draft).await {
    Ok(c) => (StatusCode::CREATED, Json(c)).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn update_creature(
  State(state): State<AppState>,
  Path(id): Path<String>,
  Json(creature): Json<Creature>,
) -> Response {
  match state.compendium_store.update(&id, creature).await {
    Ok(c) => Json(c).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn delete_creature(
  State(state): State<AppState>,
  Path(id): Path<String>,
) -> Response {
  match state.compendium_store.remove(&id).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn export_compendium(State(state): State<AppState>) -> Response {
  Json(state.compendium_store.list().await).into_response()
}

async fn import_compendium(
  State(state): State<AppState>,
  Json(creatures): Json<Vec<Creature>>,
) -> Response {
  let count = creatures.len();
  match state.compendium_store.replace_all(creatures).await {
    Ok(()) => Json(serde_json::json!({
      "imported": count,
      "replaced": true,
    }))
    .into_response(),
    Err(e) => e.into_response(),
  }
}

async fn reset_compendium(State(state): State<AppState>) -> Response {
  match state.compendium_store.reset_to_bundled().await {
    Ok(creatures) => Json(creatures).into_response(),
    Err(e) => e.into_response(),
  }
}

// ── router ───────────────────────────────────────────────────────────────────

/// Build the compendium subrouter.  Returned as `ApiRouter<AppState>`
/// so all routes participate in the OpenAPI schema.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/compendium/creatures",
      get_with(list_creatures, |op: TransformOperation| {
        op.description("List all creatures in the compendium.")
      }),
    )
    .api_route(
      "/api/compendium/creatures",
      post_with(create_creature, |op: TransformOperation| {
        op.description(
          "Create a new creature.  Server allocates the id and \
           timestamps; client provides a CreatureDraft.",
        )
      }),
    )
    .api_route(
      "/api/compendium/creatures/{id}",
      get_with(get_creature, |op: TransformOperation| {
        op.description("Fetch a single creature by id.")
      }),
    )
    .api_route(
      "/api/compendium/creatures/{id}",
      put_with(update_creature, |op: TransformOperation| {
        op.description(
          "Replace a creature's full record.  Body must be a \
           Creature with the matching id and updated fields.",
        )
      }),
    )
    .api_route(
      "/api/compendium/creatures/{id}",
      delete_with(delete_creature, |op: TransformOperation| {
        op.description("Delete a creature from the compendium.")
      }),
    )
    .api_route(
      "/api/compendium/export",
      get_with(export_compendium, |op: TransformOperation| {
        op.description("Return the entire compendium as JSON for download.")
      }),
    )
    .api_route(
      "/api/compendium/import",
      post_with(import_compendium, |op: TransformOperation| {
        op.description(
          "Replace the entire compendium with the supplied list. \
           Body: Vec<Creature> (full records, with ids).",
        )
      }),
    )
    .api_route(
      "/api/compendium/reset",
      post_with(reset_compendium, |op: TransformOperation| {
        op.description(
          "Restore the bundled creature set, discarding user changes.",
        )
      }),
    )
}
