//! Compendium HTTP routes + file-backed store.
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
//!   variants per the project's CLAUDE.md conventions.

pub mod error;
pub mod groups;
pub mod saves;
pub mod store;

pub use error::CompendiumStoreError;
pub use groups::CompendiumGroupStore;
pub use saves::{SavedCompendium, SavedCompendiumMeta, SavedCompendiumStore};
pub use store::CompendiumStore;

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
use ezpz_dndz_lib::compendium::{Creature, CreatureDraft, Group, GroupDraft};
use serde::Deserialize;
use serde_json::Value;

use crate::users::CurrentUser;
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

// ── named-save handlers ──────────────────────────────────────────────────────
//
// Mirrors the encounter-saves endpoints under `/api/encounter/saves`.
// The save body is the full creature list, stored opaquely as
// `serde_json::Value` so frontend-only schema changes don't need a
// server migration.

async fn list_compendium_saves(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.compendium_saves.list(&user.id).await).into_response()
}

async fn get_compendium_save(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
) -> Response {
  match state.compendium_saves.get(&user.id, &name).await {
    Some(record) => Json(record).into_response(),
    None => CompendiumStoreError::SaveNotFound.into_response(),
  }
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct PutCompendiumSaveQuery {
  /// When `true`, replace the existing save with this name.  When
  /// `false` (the default), creating against an existing name
  /// returns `409 Conflict` so the frontend can prompt the user
  /// to confirm the overwrite.
  #[serde(default)]
  overwrite: bool,
}

async fn put_compendium_save(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(raw_name): Path<String>,
  Query(query): Query<PutCompendiumSaveQuery>,
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
      .compendium_saves
      .replace(&user.id, name.clone(), body.clone())
      .await
    {
      Ok(record) => Ok(record),
      Err(CompendiumStoreError::SaveNotFound) => {
        state.compendium_saves.create(&user.id, name, body).await
      }
      Err(other) => Err(other),
    }
  } else {
    state.compendium_saves.create(&user.id, name, body).await
  };
  match result {
    Ok(record) => (StatusCode::OK, Json(record)).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn delete_compendium_save(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
) -> Response {
  match state.compendium_saves.delete(&user.id, &name).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn rename_compendium_save(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
  Json(body): Json<saves::RenameBody>,
) -> Response {
  let new_name = match saves::validate_save_name(&body.new_name) {
    Ok(n) => n,
    Err(e) => return e.into_response(),
  };
  match state
    .compendium_saves
    .rename(&user.id, &name, new_name)
    .await
  {
    Ok(record) => Json(record).into_response(),
    Err(e) => e.into_response(),
  }
}

// ── group handlers ───────────────────────────────────────────────────────────
//
// Per-user CRUD on `/api/compendium/groups`.  Mirrors the creature endpoints
// in shape (list / get / create / update / delete) but with `CurrentUser`
// scoping every operation so the on-disk shape is `HashMap<UserId, Vec<Group>>`.

async fn list_groups(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  Json(state.compendium_groups.list(&user.id).await).into_response()
}

async fn get_group(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  match state.compendium_groups.get(&user.id, &id).await {
    Some(g) => Json(g).into_response(),
    None => CompendiumStoreError::GroupIdNotFoundError { id }.into_response(),
  }
}

async fn create_group(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(draft): Json<GroupDraft>,
) -> Response {
  match state.compendium_groups.insert(&user.id, draft).await {
    Ok(g) => (StatusCode::CREATED, Json(g)).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn update_group(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
  Json(group): Json<Group>,
) -> Response {
  match state.compendium_groups.update(&user.id, &id, group).await {
    Ok(g) => Json(g).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn delete_group(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  match state.compendium_groups.remove(&user.id, &id).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
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
    .api_route(
      "/api/compendium/saves",
      get_with(list_compendium_saves, |op: TransformOperation| {
        op.description(
          "List named compendium snapshots (metadata only — no bodies). \
           Sorted by most-recently-updated first.",
        )
      }),
    )
    .api_route(
      "/api/compendium/saves/{name}",
      get_with(get_compendium_save, |op: TransformOperation| {
        op.description(
          "Fetch one named compendium snapshot, including its full \
           creature list.",
        )
      }),
    )
    .api_route(
      "/api/compendium/saves/{name}",
      put_with(put_compendium_save, |op: TransformOperation| {
        op.description(
          "Create or overwrite a named compendium snapshot. \
           Without `?overwrite=true`, attempting to save under an \
           existing name returns 409 so the frontend can prompt.",
        )
      }),
    )
    .api_route(
      "/api/compendium/saves/{name}",
      delete_with(delete_compendium_save, |op: TransformOperation| {
        op.description("Delete a named compendium snapshot.")
      }),
    )
    .api_route(
      "/api/compendium/saves/{name}/rename",
      post_with(rename_compendium_save, |op: TransformOperation| {
        op.description(
          "Rename a compendium snapshot.  Body: `{ \"new_name\": \"...\" }`. \
           Errors if the destination name already exists.",
        )
      }),
    )
    .api_route(
      "/api/compendium/groups",
      get_with(list_groups, |op: TransformOperation| {
        op.description("List the calling user's compendium groups.")
      }),
    )
    .api_route(
      "/api/compendium/groups",
      post_with(create_group, |op: TransformOperation| {
        op.description(
          "Create a group.  Server allocates the id and timestamps; \
           client provides a GroupDraft.",
        )
      }),
    )
    .api_route(
      "/api/compendium/groups/{id}",
      get_with(get_group, |op: TransformOperation| {
        op.description("Fetch one group by id.")
      }),
    )
    .api_route(
      "/api/compendium/groups/{id}",
      put_with(update_group, |op: TransformOperation| {
        op.description(
          "Replace a group's full record.  Body must be a Group with \
           the matching id; created_at is preserved server-side.",
        )
      }),
    )
    .api_route(
      "/api/compendium/groups/{id}",
      delete_with(delete_group, |op: TransformOperation| {
        op.description("Delete one of the user's groups.")
      }),
    )
}
