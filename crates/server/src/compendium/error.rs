//! Semantic errors for the compendium subsystem.

use axum::{
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use ezpz_dndz_lib::json_file_store::JsonFileStoreError;
use thiserror::Error;
use tracing::warn;

#[derive(Debug, Error)]
pub enum CompendiumStoreError {
  /// Underlying file IO / serde failure from the shared store.
  #[error("Compendium persistence failed: {0}")]
  StoreError(#[from] JsonFileStoreError),

  /// The bundled creature JSON embedded at build time failed to
  /// parse.  This shouldn't happen in production (the JSON is
  /// validated as part of the build), but we surface it
  /// explicitly rather than panicking so a misconfigured
  /// development env gets a clean error message.
  #[error("Failed to parse bundled creature JSON at compile time: {source}")]
  BundledParseError { source: serde_json::Error },

  /// Lookup-by-id missed.  Used by GET / PUT / DELETE
  /// `/api/compendium/creatures/{id}`.
  #[error("Compendium creature with id {id} was not found")]
  CreatureIdNotFoundError { id: String },

  /// Insert collided with an existing creature id.  In normal
  /// flow the server allocates fresh UUIDs so this shouldn't
  /// fire; defensively handled in case a client posts a Creature
  /// with an id field set.
  #[error("A compendium creature with id {id} already exists")]
  CreatureDuplicateIdError { id: String },

  /// PUT was sent to a path that doesn't match the creature's id.
  #[error(
    "Path id {path_id} does not match body id {body_id} on compendium update"
  )]
  CreatureIdMismatchError { path_id: String, body_id: String },

  /// PUT or DELETE targeted a bundled (read-only) creature.  Users
  /// who want to modify a bundled creature must duplicate it first
  /// via `POST /api/compendium/creatures/{id}/duplicate`, which
  /// returns a per-user copy with a fresh UUIDv4 id.
  #[error(
    "Bundled creature {id} is read-only — duplicate it first if you \
     want an editable copy"
  )]
  BundledNotEditable { id: String },

  /// Failed to write the bundle-seed sidecar file that records
  /// "the highest BUNDLED_VERSION we've ever applied to this
  /// store".  Non-fatal at the data level (the creatures
  /// themselves are unaffected) but we log + surface anyway —
  /// without the seed file, the next boot will redundantly re-
  /// run the bundle merge.
  #[error("Failed to write the compendium bundle-seed file: {source}")]
  BundleSeedWriteError {
    #[from]
    source: std::io::Error,
  },

  /// The bundle-seed sidecar file was malformed.  Treated as
  /// "unknown seed version" upstream (i.e., the boot code
  /// proceeds as if no merge had ever happened); we still
  /// surface the error variant so a misconfigured deploy gets
  /// a clean log line instead of silently re-merging on every
  /// startup.
  #[error("Failed to parse the compendium bundle-seed file: {source}")]
  BundleSeedParseError { source: serde_json::Error },

  /// A `create` or `rename` collided with an existing
  /// compendium-save name.
  #[error("A saved compendium with that name already exists")]
  SaveAlreadyExists,

  /// `get` / `replace` / `delete` / `rename` referenced a
  /// compendium-save name that doesn't exist.
  #[error("No saved compendium with that name was found")]
  SaveNotFound,

  /// Compendium-save name validation failed.  `reason` is a
  /// static slice describing the rule that fired.
  #[error("Saved compendium name is invalid: {reason}")]
  SaveNameInvalid { reason: &'static str },

  /// Lookup-by-id missed on the groups store.  Used by GET / PUT
  /// / DELETE `/api/compendium/groups/{id}`.
  #[error("Compendium group with id {id} was not found")]
  GroupIdNotFoundError { id: String },

  /// PUT was sent to a path that doesn't match the group's id.
  #[error(
    "Path id {path_id} does not match body id {body_id} on compendium group update"
  )]
  GroupIdMismatchError { path_id: String, body_id: String },

  /// Reading the per-user creature tables failed at the SQL layer.
  #[error("Failed to read the per-user compendium creature rows: {source}")]
  CreatureRowsRead { source: sqlx::Error },

  /// Writing the per-user creature tables failed at the SQL layer.
  #[error("Failed to write the per-user compendium creature rows: {source}")]
  CreatureRowsWrite { source: sqlx::Error },

  /// A persisted creature row didn't decode back into a `Creature`.
  /// The rows are only ever written by the codec in
  /// `creature_rows.rs`, so this indicates schema corruption.
  #[error("Corrupt per-user compendium creature row: {detail}")]
  CreatureRowDecode { detail: String },

  /// Reading the compendium group tables failed at the SQL layer.
  #[error("Failed to read the compendium group rows: {source}")]
  GroupRowsRead { source: sqlx::Error },

  /// Writing the compendium group tables failed at the SQL layer.
  #[error("Failed to write the compendium group rows: {source}")]
  GroupRowsWrite { source: sqlx::Error },

  /// A persisted group row didn't decode back into a `Group`.
  #[error("Corrupt compendium group row: {detail}")]
  GroupRowDecode { detail: String },

  /// Reading the compendium-save tables failed at the SQL layer.
  #[error("Failed to read the saved-compendium rows: {source}")]
  SaveRowsRead { source: sqlx::Error },

  /// Writing the compendium-save tables failed at the SQL layer.
  #[error("Failed to write the saved-compendium rows: {source}")]
  SaveRowsWrite { source: sqlx::Error },

  /// A persisted snapshot-body node didn't reassemble into JSON.
  /// The node tree is only ever written by `save_body.rs`, so this
  /// indicates schema corruption.
  #[error("Corrupt saved-compendium body row: {detail}")]
  SaveRowDecode { detail: String },

  /// Beginning a compendium store transaction failed.
  #[error("Failed to begin a compendium {store} transaction: {source}")]
  TransactionBegin {
    store: &'static str,
    source: sqlx::Error,
  },

  /// Committing a compendium store transaction failed.
  #[error("Failed to commit a compendium {store} transaction: {source}")]
  TransactionCommit {
    store: &'static str,
    source: sqlx::Error,
  },
}

impl IntoResponse for CompendiumStoreError {
  fn into_response(self) -> Response {
    let status = match &self {
      Self::CreatureIdNotFoundError { .. }
      | Self::SaveNotFound
      | Self::GroupIdNotFoundError { .. } => StatusCode::NOT_FOUND,
      Self::CreatureDuplicateIdError { .. } | Self::SaveAlreadyExists => {
        StatusCode::CONFLICT
      }
      Self::CreatureIdMismatchError { .. }
      | Self::GroupIdMismatchError { .. }
      | Self::SaveNameInvalid { .. } => StatusCode::BAD_REQUEST,
      Self::BundledNotEditable { .. } => StatusCode::FORBIDDEN,
      Self::StoreError(_)
      | Self::BundledParseError { .. }
      | Self::BundleSeedWriteError { .. }
      | Self::BundleSeedParseError { .. }
      | Self::CreatureRowsRead { .. }
      | Self::CreatureRowsWrite { .. }
      | Self::CreatureRowDecode { .. }
      | Self::GroupRowsRead { .. }
      | Self::GroupRowsWrite { .. }
      | Self::GroupRowDecode { .. }
      | Self::SaveRowsRead { .. }
      | Self::SaveRowsWrite { .. }
      | Self::SaveRowDecode { .. }
      | Self::TransactionBegin { .. }
      | Self::TransactionCommit { .. } => StatusCode::INTERNAL_SERVER_ERROR,
    };
    if status == StatusCode::INTERNAL_SERVER_ERROR {
      warn!(error = %self, "compendium operation failed");
    }
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}
