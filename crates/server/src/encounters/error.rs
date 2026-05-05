//! Semantic errors for the live-encounter store and the named
//! save-file store.

use axum::{
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use ezpz_dndz_lib::json_file_store::JsonFileStoreError;
use thiserror::Error;
use tracing::warn;

#[derive(Debug, Error)]
pub enum EncounterStoreError {
  /// File IO / serde failure from the shared JsonFileStore.
  #[error("Live-encounter persistence failed: {0}")]
  StoreError(#[from] JsonFileStoreError),

  /// A `create` or `rename` collided with an existing save name.
  #[error("A saved encounter with that name already exists")]
  SaveAlreadyExists,

  /// `get` / `replace` / `delete` / `rename` referenced a save
  /// name that doesn't exist.
  #[error("No saved encounter with that name was found")]
  SaveNotFound,

  /// Save name validation failed.  `reason` is a static slice
  /// describing the rule that fired.
  #[error("Saved encounter name is invalid: {reason}")]
  SaveNameInvalid { reason: &'static str },
}

impl IntoResponse for EncounterStoreError {
  fn into_response(self) -> Response {
    let status = match &self {
      EncounterStoreError::StoreError(_) => StatusCode::INTERNAL_SERVER_ERROR,
      EncounterStoreError::SaveAlreadyExists => StatusCode::CONFLICT,
      EncounterStoreError::SaveNotFound => StatusCode::NOT_FOUND,
      EncounterStoreError::SaveNameInvalid { .. } => StatusCode::BAD_REQUEST,
    };
    if matches!(status, StatusCode::INTERNAL_SERVER_ERROR) {
      warn!(error = %self, "live-encounter operation failed");
    }
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}
