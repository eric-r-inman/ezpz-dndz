//! Card-editor HTTP routes + per-user file-backed store for named
//! creature-card layouts.
//!
//! - Storage: `HashMap<UserId, Vec<NamedCardLayout>>` in a single
//!   JSON file (`<data_dir>/card-layouts.json`) via the shared
//!   `JsonFileStore`.  Mirrors `SavedCompendiumStore`'s disk shape
//!   and locking discipline.
//! - Routes: REST CRUD on `/api/card-layouts[/{name}]` plus a
//!   rename endpoint.
//! - Bodies are opaque `serde_json::Value` so the layout schema
//!   (rows / widgets / alignments) can evolve frontend-only.

pub mod error;
pub mod store;

pub use error::CardLayoutStoreError;
pub use store::CardLayoutStore;

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
  Extension, Json,
};
use ezpz_dndz_lib::card_editor::RenameBody;
use serde::Deserialize;
use serde_json::Value;

use crate::users::CurrentUser;
use crate::web_base::AppState;

async fn list_layouts(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.card_layouts.list(&user.id).await).into_response()
}

async fn get_layout(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
) -> Response {
  state.card_layouts.get(&user.id, &name).await.map_or_else(
    || CardLayoutStoreError::LayoutNotFound.into_response(),
    |record| Json(record).into_response(),
  )
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct PutLayoutQuery {
  /// When `true`, replace the existing layout with this name.
  /// When `false` (the default), creating against an existing
  /// name returns `409 Conflict` so the frontend can prompt
  /// for overwrite.
  #[serde(default)]
  overwrite: bool,
}

async fn put_layout(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(raw_name): Path<String>,
  Query(query): Query<PutLayoutQuery>,
  Json(body): Json<Value>,
) -> Response {
  let name = match store::validate_layout_name(&raw_name) {
    Ok(n) => n,
    Err(e) => return e.into_response(),
  };
  let result = if query.overwrite {
    // Try replace first; fall back to create if the name doesn't
    // exist yet (so a single PUT?overwrite=true upserts).
    match state
      .card_layouts
      .replace(&user.id, name.clone(), body.clone())
      .await
    {
      Ok(record) => Ok(record),
      Err(CardLayoutStoreError::LayoutNotFound) => {
        state.card_layouts.create(&user.id, name, body).await
      }
      Err(other) => Err(other),
    }
  } else {
    state.card_layouts.create(&user.id, name, body).await
  };
  match result {
    Ok(record) => (StatusCode::OK, Json(record)).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn delete_layout(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
) -> Response {
  match state.card_layouts.delete(&user.id, &name).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn rename_layout(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
  Json(body): Json<RenameBody>,
) -> Response {
  let new_name = match store::validate_layout_name(&body.new_name) {
    Ok(n) => n,
    Err(e) => return e.into_response(),
  };
  match state.card_layouts.rename(&user.id, &name, new_name).await {
    Ok(record) => Json(record).into_response(),
    Err(e) => e.into_response(),
  }
}

/// Build the card-editor subrouter.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/card-layouts",
      get_with(list_layouts, |op: TransformOperation| {
        op.description(
          "List the calling user's saved card layouts (metadata only). \
           Sorted by most-recently-updated first.",
        )
      }),
    )
    .api_route(
      "/api/card-layouts/{name}",
      get_with(get_layout, |op: TransformOperation| {
        op.description("Fetch one saved card layout, including its full body.")
      }),
    )
    .api_route(
      "/api/card-layouts/{name}",
      put_with(put_layout, |op: TransformOperation| {
        op.description(
          "Create or overwrite a named card layout.  Without \
           `?overwrite=true`, saving against an existing name \
           returns 409 so the frontend can confirm.",
        )
      }),
    )
    .api_route(
      "/api/card-layouts/{name}",
      delete_with(delete_layout, |op: TransformOperation| {
        op.description("Delete a saved card layout.")
      }),
    )
    .api_route(
      "/api/card-layouts/{name}/rename",
      post_with(rename_layout, |op: TransformOperation| {
        op.description(
          "Rename a saved card layout.  Body: `{ \"new_name\": \"…\" }`.  \
           Errors if the destination name already exists.",
        )
      }),
    )
}
