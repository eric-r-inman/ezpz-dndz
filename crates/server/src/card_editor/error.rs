//! Semantic errors for the card-editor subsystem.

use axum::{
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use ezpz_dndz_lib::json_file_store::JsonFileStoreError;
use thiserror::Error;
use tracing::warn;

#[derive(Debug, Error)]
pub enum CardLayoutStoreError {
  #[error("Card-layout persistence failed: {0}")]
  StoreError(#[from] JsonFileStoreError),

  /// A `create` or `rename` collided with an existing layout
  /// name for this user.
  #[error("A saved card layout with that name already exists")]
  LayoutAlreadyExists,

  /// `get` / `replace` / `delete` / `rename` referenced a name
  /// that doesn't exist for this user.
  #[error("No saved card layout with that name was found")]
  LayoutNotFound,

  /// User-supplied name failed validation (empty, too long,
  /// path separator, control character).
  #[error("Card-layout name is invalid: {reason}")]
  LayoutNameInvalid { reason: &'static str },
}

impl IntoResponse for CardLayoutStoreError {
  fn into_response(self) -> Response {
    let status = match &self {
      Self::LayoutNotFound => StatusCode::NOT_FOUND,
      Self::LayoutAlreadyExists => StatusCode::CONFLICT,
      Self::LayoutNameInvalid { .. } => StatusCode::BAD_REQUEST,
      Self::StoreError(_) => StatusCode::INTERNAL_SERVER_ERROR,
    };
    if status == StatusCode::INTERNAL_SERVER_ERROR {
      warn!(error = %self, "card-layout operation failed");
    }
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}
