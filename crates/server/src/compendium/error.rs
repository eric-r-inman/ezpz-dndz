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
}

impl IntoResponse for CompendiumStoreError {
  fn into_response(self) -> Response {
    let status = match &self {
      Self::CreatureIdNotFoundError { .. } => StatusCode::NOT_FOUND,
      Self::CreatureDuplicateIdError { .. } => StatusCode::CONFLICT,
      Self::CreatureIdMismatchError { .. } => StatusCode::BAD_REQUEST,
      Self::StoreError(_) | Self::BundledParseError { .. } => {
        StatusCode::INTERNAL_SERVER_ERROR
      }
    };
    if status == StatusCode::INTERNAL_SERVER_ERROR {
      warn!(error = %self, "compendium operation failed");
    }
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}
