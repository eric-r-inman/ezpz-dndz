//! Semantic errors for the live-encounter store and the named
//! save-file store, relational edition.

use axum::{
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use thiserror::Error;
use tracing::warn;

#[derive(Debug, Error)]
pub enum EncounterStoreError {
  /// A PUT body did not decode through the lenient wire codec
  /// (`encounters/wire.rs`).  Unreachable from the current
  /// frontend, whose encoder always emits the canonical shape; it
  /// protects the typed schema from hand-shaped payloads.
  #[error("Encounter body does not match the wire schema: {detail}")]
  LiveEncounterDecode { detail: String },

  /// Reading the live-encounter tables failed at the SQL layer.
  #[error("Failed to read the live-encounter rows: {source}")]
  LiveRowsRead { source: sqlx::Error },

  /// Writing the live-encounter tables failed at the SQL layer.
  #[error("Failed to write the live-encounter rows: {source}")]
  LiveRowsWrite { source: sqlx::Error },

  /// A persisted live-encounter row didn't decode back into the
  /// wire model.  The rows are only ever written by the codec in
  /// `rows.rs`, so this indicates schema corruption.
  #[error("Corrupt live-encounter row: {detail}")]
  LiveRowDecode { detail: String },

  /// Reading the saved-encounter tables failed at the SQL layer.
  #[error("Failed to read the saved-encounter rows: {source}")]
  SaveRowsRead { source: sqlx::Error },

  /// Writing the saved-encounter tables failed at the SQL layer.
  #[error("Failed to write the saved-encounter rows: {source}")]
  SaveRowsWrite { source: sqlx::Error },

  /// A persisted save-body node tree didn't reassemble.  The nodes
  /// are only ever written by `save_nodes.rs`, so this indicates
  /// schema corruption.
  #[error("Corrupt saved-encounter body: {detail}")]
  SaveRowDecode { detail: String },

  /// Failed to open a write transaction.
  #[error("Failed to begin the {store} transaction: {source}")]
  TransactionBegin {
    store: &'static str,
    source: sqlx::Error,
  },

  /// Failed to commit a write transaction.
  #[error("Failed to commit the {store} transaction: {source}")]
  TransactionCommit {
    store: &'static str,
    source: sqlx::Error,
  },

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
      EncounterStoreError::LiveEncounterDecode { .. } => {
        StatusCode::BAD_REQUEST
      }
      EncounterStoreError::SaveAlreadyExists => StatusCode::CONFLICT,
      EncounterStoreError::SaveNotFound => StatusCode::NOT_FOUND,
      EncounterStoreError::SaveNameInvalid { .. } => StatusCode::BAD_REQUEST,
      EncounterStoreError::LiveRowsRead { .. }
      | EncounterStoreError::LiveRowsWrite { .. }
      | EncounterStoreError::LiveRowDecode { .. }
      | EncounterStoreError::SaveRowsRead { .. }
      | EncounterStoreError::SaveRowsWrite { .. }
      | EncounterStoreError::SaveRowDecode { .. }
      | EncounterStoreError::TransactionBegin { .. }
      | EncounterStoreError::TransactionCommit { .. } => {
        StatusCode::INTERNAL_SERVER_ERROR
      }
    };
    if matches!(status, StatusCode::INTERNAL_SERVER_ERROR) {
      warn!(error = %self, "encounter-store operation failed");
    }
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}
