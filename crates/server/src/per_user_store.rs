//! Generic per-user opaque-JSON store and its GET/PUT router.
//!
//! Five features persist one JSON payload per user and expose it
//! through an identical authenticated GET/PUT pair — the payload's
//! schema is owned entirely by the Elm side, and the server just
//! round-trips it:
//!
//! - **Lore groups** — themed clusters of compendium creatures the GM
//!   curates ("Goblin warband") so the random-encounter roller has
//!   something narratively coherent to pull from.
//! - **Condition presets** — saved Add-Condition forms ("Stun, DC 15
//!   CON, ends end-of-next-turn") reapplied with one click.
//! - **Save Chain presets** — reusable "creature makes a save;
//!   something happens" recipes (Hold Person, Fireball, …).
//! - **Treasure table** — the user's singular treasure table; bundled
//!   SRD defaults out of the box, mutated through the editor modal.
//! - **Treasure profiles** — named "Tune your rolls" presets for the
//!   Treasure generator.
//!
//! Each was born as its own module with a copy-pasted store struct,
//! error enum, handler pair, and router; the five differed only in
//! label strings and route paths, so they now share this one
//! implementation.  [`routers`](routers) is the single registration
//! point — adding a sixth store is one line there plus an
//! [`AppState`](crate::web_base::AppState) field.
//!
//! Disk shape: `HashMap<UserId, Value>` where the value is an opaque
//! JSON payload (whatever the frontend serializes).  `GET` returns
//! `Value::Null` when the user hasn't persisted anything yet — the
//! frontend treats that as "use the default" (empty, or the bundled
//! catalog, depending on the feature).
//!
//! Anonymous users persist to localStorage instead; on sign-in the
//! migration pipeline in the frontend's `Update.UserSync` PUTs the
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

/// One per-user opaque-JSON store.  `label` names the owning feature
/// in errors and logs ("save-chain-preset store persistence failed:
/// …"), so the shared error type stays semantic.
#[derive(Clone)]
pub struct PerUserStore {
  label: &'static str,
  inner: Arc<JsonFileStore<HashMap<UserId, Value>>>,
}

impl PerUserStore {
  pub async fn load_or_default(
    label: &'static str,
    path: PathBuf,
  ) -> Result<Self, PerUserStoreError> {
    let inner = JsonFileStore::<HashMap<UserId, Value>>::load_or_default(path)
      .await
      .map_err(|source| PerUserStoreError { label, source })?;
    Ok(Self {
      label,
      inner: Arc::new(inner),
    })
  }

  /// Return the user's saved payload, or `Value::Null` when they
  /// haven't persisted one yet.  The frontend reads null as "use the
  /// default" — no migration step needed.
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
  ) -> Result<(), PerUserStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, next);
      })
      .await
      .map_err(|source| PerUserStoreError {
        label: self.label,
        source,
      })?;
    Ok(())
  }
}

/// Persistence failure in one of the per-user stores.  `label` names
/// the feature so the message stays as semantic as the per-store
/// error enums this type replaced.
#[derive(Debug, Error)]
#[error("{label} store persistence failed: {source}")]
pub struct PerUserStoreError {
  pub label: &'static str,
  #[source]
  pub source: ezpz_dndz_lib::json_file_store::JsonFileStoreError,
}

impl IntoResponse for PerUserStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, store = self.label, "per-user store error");
    (
      axum::http::StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

// ── routers ──────────────────────────────────────────────────────────────────

/// The authenticated GET/PUT pair for one store, mounted at `path`.
/// The handlers capture their `PerUserStore` clone directly, so no
/// state extraction or per-store handler code is needed.
fn router(
  path: &'static str,
  store: PerUserStore,
  get_description: &'static str,
  put_description: &'static str,
) -> ApiRouter<AppState> {
  let read_store = store.clone();
  ApiRouter::new()
    .api_route(
      path,
      get_with(
        move |Extension(CurrentUser(user)): Extension<CurrentUser>| {
          let store = read_store.clone();
          async move { Json(store.read(&user.id).await).into_response() }
        },
        move |op: TransformOperation| op.description(get_description),
      ),
    )
    .api_route(
      path,
      put_with(
        move |Extension(CurrentUser(user)): Extension<CurrentUser>,
              Json(body): Json<Value>| {
          let store = store.clone();
          async move {
            match store.replace(&user.id, body.clone()).await {
              Ok(()) => Json(body).into_response(),
              Err(e) => e.into_response(),
            }
          }
        },
        move |op: TransformOperation| op.description(put_description),
      ),
    )
}

/// Every per-user store route, in one place.  Payloads are opaque to
/// the server throughout — the frontend defines each shape.
pub fn routers(state: &AppState) -> ApiRouter<AppState> {
  ApiRouter::new()
    .merge(router(
      "/api/lore-groups",
      state.lore_groups.clone(),
      "Return the caller's saved user-authored Lore groups as opaque \
       JSON.  Returns `null` when the user hasn't saved any groups \
       yet — the frontend treats that as the empty default.",
      "Replace the caller's saved Lore groups with the supplied JSON.",
    ))
    .merge(router(
      "/api/condition-presets",
      state.condition_presets.clone(),
      "Return the caller's saved condition presets as opaque JSON.  \
       Returns `null` when the user hasn't saved any presets yet — \
       the frontend treats that as the empty default.",
      "Replace the caller's saved condition presets with the supplied \
       JSON.",
    ))
    .merge(router(
      "/api/save-chain-presets",
      state.save_chain_presets.clone(),
      "Return the caller's saved Save Chain presets as opaque JSON.  \
       Returns `null` when the user hasn't saved any presets yet — \
       the frontend treats that as the empty default and falls back \
       to the bundled Save Chain catalog.",
      "Replace the caller's saved Save Chain presets with the \
       supplied JSON.",
    ))
    .merge(router(
      "/api/treasure-table",
      state.treasure_table.clone(),
      "Return the caller's saved singular treasure table as opaque \
       JSON.  Returns `null` when the user hasn't saved one yet — \
       the frontend then falls back to the bundled SRD default.",
      "Replace the caller's saved treasure table with the supplied \
       JSON.",
    ))
    .merge(router(
      "/api/treasure-profiles",
      state.treasure_profiles.clone(),
      "Return the caller's saved treasure profiles as opaque JSON.  \
       Returns `null` when the user hasn't saved any profiles yet — \
       the frontend treats that as the empty default.",
      "Replace the caller's saved treasure profiles with the supplied \
       JSON.",
    ))
}
