//! Semantic errors for the live-encounter store.

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
}

impl IntoResponse for EncounterStoreError {
  fn into_response(self) -> Response {
    warn!(error = %self, "live-encounter operation failed");
    (
      StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}
