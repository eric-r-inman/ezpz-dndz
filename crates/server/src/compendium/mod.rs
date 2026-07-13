//! Compendium HTTP routes + stores.
//!
//! - Storage: the relational per-user tables from migration 0003
//!   (`user_creatures`, `compendium_groups`, `compendium_saves` and
//!   their children) through the codecs in [`creature_rows`] and
//!   [`save_body`].  The bundled SRD set stays embedded in the
//!   binary ([`bundled`]); the legacy shared JSON file survives
//!   only as input to the one-shot split migration ([`migrate`]).
//! - Routes: REST CRUD on `/api/compendium/creatures[/:id]` plus
//!   bulk `import` / `export` / `reset` endpoints, per-user groups,
//!   and named snapshot saves.
//! - Errors: semantic `CompendiumStoreError` with descriptive
//!   variants per the project's CLAUDE.md conventions.

pub mod bundled;
pub mod creature_rows;
pub mod error;
pub mod groups;
pub mod migrate;
pub mod save_body;
pub mod saves;
pub mod store;
pub mod user_store;

pub use bundled::BundledCompendium;
pub use error::CompendiumStoreError;
pub use groups::CompendiumGroupStore;
pub use migrate::MigrationError;
pub use saves::{SavedCompendium, SavedCompendiumMeta, SavedCompendiumStore};
pub use store::CompendiumStore;
pub use user_store::UserCompendiumStore;

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

/// Merge the read-only bundled creatures with the caller's per-
/// user creatures, stamping the `is_bundled` flag so the frontend
/// can branch Edit/Delete vs Duplicate on each row.  Bundled
/// creatures come first to match the legacy ordering; user
/// creatures append.
async fn list_creatures(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  let bundled = state
    .bundled_compendium
    .list()
    .iter()
    .cloned()
    .map(|mut c| {
      c.is_bundled = true;
      c
    });
  match state.user_compendium.list(&user.id).await {
    Ok(user_owned) => Json(
      bundled
        .chain(user_owned.into_iter().map(|mut c| {
          c.is_bundled = false;
          c
        }))
        .collect::<Vec<_>>(),
    )
    .into_response(),
    Err(e) => e.into_response(),
  }
}

async fn get_creature(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  if let Some(canonical) = state.bundled_compendium.get(&id) {
    let mut copy = canonical.clone();
    copy.is_bundled = true;
    return Json(copy).into_response();
  }
  match state.user_compendium.get(&user.id, &id).await {
    Ok(Some(mut c)) => {
      c.is_bundled = false;
      Json(c).into_response()
    }
    Ok(None) => StatusCode::NOT_FOUND.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn create_creature(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(draft): Json<CreatureDraft>,
) -> Response {
  match state.user_compendium.insert(&user.id, draft).await {
    Ok(mut c) => {
      c.is_bundled = false;
      (StatusCode::CREATED, Json(c)).into_response()
    }
    Err(e) => e.into_response(),
  }
}

async fn update_creature(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
  Json(creature): Json<Creature>,
) -> Response {
  if state.bundled_compendium.contains(&id) {
    return CompendiumStoreError::BundledNotEditable { id }.into_response();
  }
  match state.user_compendium.update(&user.id, &id, creature).await {
    Ok(mut c) => {
      c.is_bundled = false;
      Json(c).into_response()
    }
    Err(e) => e.into_response(),
  }
}

async fn delete_creature(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  if state.bundled_compendium.contains(&id) {
    return CompendiumStoreError::BundledNotEditable { id }.into_response();
  }
  match state.user_compendium.remove(&user.id, &id).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(e) => e.into_response(),
  }
}

/// `POST /api/compendium/creatures/{id}/duplicate` — clone the
/// creature at `id` (bundled OR the caller's own) into the
/// caller's per-user store with a fresh UUIDv4 and a "Copy of …"
/// name prefix.  Returns the new per-user creature with
/// `is_bundled = false` and `201 Created`.
///
/// This is the only path that lets a user "edit" a bundled
/// creature: duplicate first, then edit the user-owned copy.
/// Bundled originals are never mutated.
///
/// 404 when neither bundle nor per-user store carries `id` —
/// duplicating another user's creature is not possible, since
/// the read paths only ever see the caller's own per-user list.
async fn duplicate_creature(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  let source = if let Some(c) = state.bundled_compendium.get(&id) {
    c.clone()
  } else {
    match state.user_compendium.get(&user.id, &id).await {
      Ok(Some(c)) => c,
      Ok(None) => {
        return CompendiumStoreError::CreatureIdNotFoundError { id }
          .into_response()
      }
      Err(e) => return e.into_response(),
    }
  };

  let mut copy = source;
  copy.id = uuid::Uuid::new_v4().to_string();
  copy.name = format!("Copy of {}", copy.name);
  copy.is_bundled = false;
  let now = std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0);
  copy.created_at = now;
  copy.updated_at = now;

  match state
    .user_compendium
    .insert_raw(&user.id, copy.clone())
    .await
  {
    Ok(()) => (StatusCode::CREATED, Json(copy)).into_response(),
    Err(e) => e.into_response(),
  }
}

/// Full-compendium export payload: the caller's per-user creatures
/// plus the caller's per-user groups.  Wire shape is
/// `{ "creatures": [...], "groups": [...] }`.  Bundled creatures
/// are intentionally omitted — every server runs the same bundle
/// in its binary, and a user re-importing this file on another
/// deployment shouldn't accidentally shadow the receiver's
/// bundled set with stale copies.  The bare `Vec<Creature>`
/// shape that earlier exports produced is still accepted on
/// import as a legacy fallback so older download files keep
/// working — see `import_compendium`.
async fn export_compendium(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  let creatures = match state.user_compendium.list(&user.id).await {
    Ok(creatures) => creatures,
    Err(e) => return e.into_response(),
  };
  match state.compendium_groups.list(&user.id).await {
    Ok(groups) => Json(serde_json::json!({
      "creatures": creatures,
      "groups": groups,
    }))
    .into_response(),
    Err(e) => e.into_response(),
  }
}

/// Import a compendium into the caller's per-user store.  Accepts
/// two body shapes:
///
/// - **Legacy** (`[creature, creature, ...]`) — bare array of
///   creatures.  Replaces the caller's per-user creature list;
///   does not touch groups.  Pre-split exports stored the shared
///   compendium this way; we still accept it so older download
///   files keep importing into a single user's per-user store.
/// - **Full** (`{ "creatures": [...], "groups": [...]? }`) —
///   replaces both the caller's per-user creatures and their
///   group list.  Used when the user uploads a JSON export that
///   `export_compendium` produced.  `groups` is optional; absent
///   keeps existing groups in place.
///
/// Bundled creature ids in the body are silently dropped — the
/// shared bundled set is the source of truth and per-user
/// creatures must have unique (user-owned) ids.  This protects
/// against an import that would otherwise shadow bundled rows
/// with stale forks of them.
async fn import_compendium(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(body): Json<serde_json::Value>,
) -> Response {
  #[derive(serde::Deserialize)]
  struct FullBody {
    creatures: Vec<Creature>,
    #[serde(default)]
    groups: Option<Vec<ezpz_dndz_lib::compendium::Group>>,
  }

  let (creatures, groups) = match body {
    serde_json::Value::Array(_) => {
      match serde_json::from_value::<Vec<Creature>>(body) {
        Ok(c) => (c, None),
        Err(_) => return import_bad_body(),
      }
    }
    serde_json::Value::Object(_) => {
      match serde_json::from_value::<FullBody>(body) {
        Ok(b) => (b.creatures, b.groups),
        Err(_) => return import_bad_body(),
      }
    }
    _ => return import_bad_body(),
  };

  // Drop any creature whose id collides with a bundled id — those
  // belong to the read-only bundle, not the per-user store.
  let creatures: Vec<Creature> = creatures
    .into_iter()
    .filter(|c| !state.bundled_compendium.contains(&c.id))
    .collect();
  let count = creatures.len();
  if let Err(e) = state
    .user_compendium
    .replace_for_user(&user.id, creatures)
    .await
  {
    return e.into_response();
  }
  if let Some(g) = groups {
    if let Err(e) = state.compendium_groups.replace_for_user(&user.id, g).await
    {
      return e.into_response();
    }
  }
  Json(serde_json::json!({
    "imported": count,
    "replaced": true,
  }))
  .into_response()
}

fn import_bad_body() -> Response {
  (
    StatusCode::BAD_REQUEST,
    Json(serde_json::json!({
      "error":
        "Import body must be either a JSON array of creatures \
         or an object with \"creatures\" (and optional \"groups\")."
    })),
  )
    .into_response()
}

/// Reset the caller's per-user compendium to empty AND wipe their
/// groups.  Bundled creatures are always present (in-binary), so
/// "reset" only has to drop the user's own creatures + groups —
/// the bundled rows reappear automatically the next time the
/// merged list is read.  Other users are untouched.
///
/// Groups reference creature ids that may have been removed by
/// the reset, so leaving them behind would orphan references;
/// clearing them is the safer baseline.
async fn reset_compendium(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  if let Err(e) = state
    .user_compendium
    .replace_for_user(&user.id, Vec::new())
    .await
  {
    return e.into_response();
  }
  if let Err(e) = state
    .compendium_groups
    .replace_for_user(&user.id, Vec::new())
    .await
  {
    return e.into_response();
  }
  // Return the merged view (bundled + the now-empty per-user
  // list) so the client can update its in-memory DB without a
  // separate GET round-trip.
  let bundled = state
    .bundled_compendium
    .list()
    .iter()
    .cloned()
    .map(|mut c| {
      c.is_bundled = true;
      c
    });
  Json(bundled.collect::<Vec<_>>()).into_response()
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
  match state.compendium_saves.list(&user.id).await {
    Ok(metas) => Json(metas).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn get_compendium_save(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(name): Path<String>,
) -> Response {
  match state.compendium_saves.get(&user.id, &name).await {
    Ok(Some(record)) => Json(record).into_response(),
    Ok(None) => CompendiumStoreError::SaveNotFound.into_response(),
    Err(e) => e.into_response(),
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
  match state.compendium_groups.list(&user.id).await {
    Ok(groups) => Json(groups).into_response(),
    Err(e) => e.into_response(),
  }
}

async fn get_group(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  match state.compendium_groups.get(&user.id, &id).await {
    Ok(Some(g)) => Json(g).into_response(),
    Ok(None) => {
      CompendiumStoreError::GroupIdNotFoundError { id }.into_response()
    }
    Err(e) => e.into_response(),
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
      "/api/compendium/creatures/{id}/duplicate",
      post_with(duplicate_creature, |op: TransformOperation| {
        op.description(
          "Duplicate a creature (bundled or user-owned) into the \
           caller's per-user compendium.  Returns the new copy \
           with a fresh UUID and a 'Copy of …' name prefix.  The \
           only way to obtain an editable version of a bundled \
           creature.",
        )
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
