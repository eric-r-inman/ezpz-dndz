//! Live-encounter persistence + HTTP routes.
//!
//! v1 scope: a single persistent live encounter per deployment.
//! Auto-saved by the frontend on every mutation, auto-loaded on
//! app boot so a page reload doesn't lose combat state.  The
//! schema is whatever the frontend's `Encounter.elm` serializes;
//! the server stores the JSON opaquely (`serde_json::Value`).
//!
//! HTTP routes:
//!
//!   - `GET /api/encounter` — 200 JSON, or `null` when no
//!     encounter has been persisted yet.
//!   - `PUT /api/encounter` — 200 JSON, replaces the persisted
//!     encounter with the supplied body.
//!
//! The per-user multi-encounter API (`GET / POST / PUT / DELETE
//! /api/me/encounters[/:id]`) is a planned follow-up that waits
//! on the `users` table and the OIDC session plumbing.  The route
//! shape in this file deliberately stays at the unauth,
//! single-encounter tier so it works in dev / homelab modes.

pub mod error;
pub mod store;

pub use error::EncounterStoreError;
pub use store::EncounterStore;

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
  Json,
};
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
}
