//! Generic per-user preset router over the relational store.
//!
//! Five features persist one payload per user and expose it through
//! an identical authenticated GET/PUT pair:
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
//! Historically each payload was an opaque JSON blob in a
//! `JsonFileStore`; it is now normalized into real tables (migration
//! 0002) through the per-feature codecs in [`crate::presets`], which
//! mirror the Elm `*.Wire` modules — including their legacy-shape
//! leniency, since the one-shot boot import feeds them payloads
//! written by any historical frontend version.  A payload that fails
//! its wire decoder is rejected with a 400 (unreachable from the
//! current frontend; it protects the schema).
//!
//! The HTTP contract is tri-state and unchanged from the JSON era:
//! `GET` returns `null` when the user has never persisted the feature
//! (no presence-parent row), and the canonical re-encoding of the
//! persisted structure otherwise — including a persisted-but-empty
//! collection.  The frontend's `Update.UserSync` migration pipeline
//! depends on that distinction.  `PUT` is a full transactional swap:
//! delete the presence row (children cascade), insert the decoded
//! replacement.
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
use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::Value;
use sqlx::AnyConnection;
use std::future::Future;
use thiserror::Error;
use tracing::warn;

use crate::presets::{
  condition_presets::ConditionPresets, lore_groups::LoreGroups,
  save_chains::SaveChains, treasure_profiles::TreasureProfiles,
  treasure_table::TreasureTable,
};
use crate::users::CurrentUser;
use crate::web_base::AppState;

/// One per-user preset feature: the wire codec (mirroring the Elm
/// `*.Wire` module) plus the SQL that maps the decoded value onto the
/// feature's tables.  Implementations are stateless unit structs; the
/// generic [`read_payload`] / [`replace_payload`] pair and the shared
/// router are the only callers besides the one-shot JSON import.
pub trait PerUserFeature: 'static {
  /// Feature name for errors and logs ("save-chain-presets payload
  /// does not match …").
  const LABEL: &'static str;

  /// The presence-parent table.  Deleting a user's row here cascades
  /// to every child table, which is how `replace` swaps the whole
  /// structure atomically.
  const PARENT_TABLE: &'static str;

  /// The decoded, validated payload.
  type Data: Send + Sync;

  /// Decode the wire payload, exactly as leniently as the Elm
  /// decoder (plus any documented server-side extras).  The error is
  /// a human-readable description of the first mismatch.
  fn decode(payload: &Value) -> Result<Self::Data, String>;

  /// Re-encode in the canonical current wire shape, exactly as the
  /// Elm encoder would emit it.
  fn encode(data: &Self::Data) -> Value;

  /// Insert the presence-parent row and all children.  Takes a bare
  /// connection so callers control the transaction — `replace` pairs
  /// it with the cascade delete, and the one-shot JSON import replays
  /// a whole legacy store inside a single transaction.
  fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    data: &Self::Data,
  ) -> impl Future<Output = Result<(), sqlx::Error>> + Send;

  /// Reassemble the user's persisted structure from the tables, or
  /// `None` when the user has never persisted one (no parent row).
  fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> impl Future<Output = Result<Option<Self::Data>, sqlx::Error>> + Send;
}

/// Semantic errors from the per-user preset stores.  Every variant
/// carries the feature label so the messages stay as pointed as the
/// per-store error enums this module replaced.
#[derive(Debug, Error)]
pub enum PerUserStoreError {
  #[error("{label} payload does not match the {label} wire schema: {detail}")]
  PayloadDecode { label: &'static str, detail: String },

  #[error("Failed to read the {label} store: {source}")]
  Read {
    label: &'static str,
    source: sqlx::Error,
  },

  #[error("Failed to replace the {label} store contents: {source}")]
  Replace {
    label: &'static str,
    source: sqlx::Error,
  },

  #[error("Failed to begin a {label} store transaction: {source}")]
  TransactionBegin {
    label: &'static str,
    source: sqlx::Error,
  },

  #[error("Failed to commit a {label} store transaction: {source}")]
  TransactionCommit {
    label: &'static str,
    source: sqlx::Error,
  },
}

impl IntoResponse for PerUserStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "per-user store error");
    let status = match &self {
      Self::PayloadDecode { .. } => axum::http::StatusCode::BAD_REQUEST,
      _ => axum::http::StatusCode::INTERNAL_SERVER_ERROR,
    };
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}

/// The user's saved payload in canonical wire form, or `Value::Null`
/// when they have never persisted one.  The frontend reads null as
/// "use the default" (empty, or the bundled catalog, depending on the
/// feature).
pub async fn read_payload<F: PerUserFeature>(
  db: &Db,
  user_id: &UserId,
) -> Result<Value, PerUserStoreError> {
  F::fetch(db, user_id)
    .await
    .map(|data| data.as_ref().map_or(Value::Null, F::encode))
    .map_err(|source| PerUserStoreError::Read {
      label: F::LABEL,
      source,
    })
}

/// Replace the user's persisted structure with `payload`: decode (400
/// on a wire-schema mismatch), then swap the rows in one transaction
/// (cascade-delete the presence row, insert the replacement).
/// Returns the canonical re-encoding, which the PUT handler echoes.
pub async fn replace_payload<F: PerUserFeature>(
  db: &Db,
  user_id: &UserId,
  payload: &Value,
) -> Result<Value, PerUserStoreError> {
  let data =
    F::decode(payload).map_err(|detail| PerUserStoreError::PayloadDecode {
      label: F::LABEL,
      detail,
    })?;

  let mut tx = db.pool().begin().await.map_err(|source| {
    PerUserStoreError::TransactionBegin {
      label: F::LABEL,
      source,
    }
  })?;

  // PARENT_TABLE is a compile-time constant, so the format! is not
  // an injection surface; sqlx's Any driver has no placeholder for
  // identifiers.
  sqlx::query(&format!("DELETE FROM {} WHERE user_id = $1", F::PARENT_TABLE))
    .bind(user_id.as_str())
    .execute(&mut *tx)
    .await
    .map_err(|source| PerUserStoreError::Replace {
      label: F::LABEL,
      source,
    })?;

  F::insert(&mut tx, user_id, &data).await.map_err(|source| {
    PerUserStoreError::Replace {
      label: F::LABEL,
      source,
    }
  })?;

  tx.commit()
    .await
    .map_err(|source| PerUserStoreError::TransactionCommit {
      label: F::LABEL,
      source,
    })?;

  Ok(F::encode(&data))
}

// ── routers ──────────────────────────────────────────────────────────────────

/// The authenticated GET/PUT pair for one feature, mounted at `path`.
/// The handlers capture a `Db` clone directly, so no state extraction
/// or per-feature handler code is needed.
fn router<F: PerUserFeature>(
  path: &'static str,
  db: Db,
  get_description: &'static str,
  put_description: &'static str,
) -> ApiRouter<AppState> {
  let read_db = db.clone();
  ApiRouter::new()
    .api_route(
      path,
      get_with(
        move |Extension(CurrentUser(user)): Extension<CurrentUser>| {
          let db = read_db.clone();
          async move {
            match read_payload::<F>(&db, &user.id).await {
              Ok(payload) => Json(payload).into_response(),
              Err(e) => e.into_response(),
            }
          }
        },
        move |op: TransformOperation| op.description(get_description),
      ),
    )
    .api_route(
      path,
      put_with(
        move |Extension(CurrentUser(user)): Extension<CurrentUser>,
              Json(body): Json<Value>| {
          let db = db.clone();
          async move {
            match replace_payload::<F>(&db, &user.id, &body).await {
              Ok(canonical) => Json(canonical).into_response(),
              Err(e) => e.into_response(),
            }
          }
        },
        move |op: TransformOperation| op.description(put_description),
      ),
    )
}

/// Every per-user preset route, in one place.  Adding a sixth store
/// is one `.merge` here plus a `PerUserFeature` impl in
/// [`crate::presets`].
pub fn routers(state: &AppState) -> ApiRouter<AppState> {
  ApiRouter::new()
    .merge(router::<LoreGroups>(
      "/api/lore-groups",
      state.db.clone(),
      "Return the caller's saved user-authored Lore groups.  Returns \
       `null` when the user hasn't saved any groups yet — the \
       frontend treats that as the empty default.",
      "Replace the caller's saved Lore groups with the supplied JSON.",
    ))
    .merge(router::<ConditionPresets>(
      "/api/condition-presets",
      state.db.clone(),
      "Return the caller's saved condition presets.  Returns `null` \
       when the user hasn't saved any presets yet — the frontend \
       treats that as the empty default.",
      "Replace the caller's saved condition presets with the supplied \
       JSON.",
    ))
    .merge(router::<SaveChains>(
      "/api/save-chain-presets",
      state.db.clone(),
      "Return the caller's saved Save Chain presets.  Returns `null` \
       when the user hasn't saved any presets yet — the frontend \
       treats that as the empty default and falls back to the bundled \
       Save Chain catalog.",
      "Replace the caller's saved Save Chain presets with the \
       supplied JSON.",
    ))
    .merge(router::<TreasureTable>(
      "/api/treasure-table",
      state.db.clone(),
      "Return the caller's saved singular treasure table.  Returns \
       `null` when the user hasn't saved one yet — the frontend then \
       falls back to the bundled SRD default.",
      "Replace the caller's saved treasure table with the supplied \
       JSON.",
    ))
    .merge(router::<TreasureProfiles>(
      "/api/treasure-profiles",
      state.db.clone(),
      "Return the caller's saved treasure profiles.  Returns `null` \
       when the user hasn't saved any profiles yet — the frontend \
       treats that as the empty default.",
      "Replace the caller's saved treasure profiles with the supplied \
       JSON.",
    ))
}
