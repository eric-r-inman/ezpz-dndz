//! Dice-roll history persistence.
//!
//! The Elm dice roller is a pure rules engine that produces a `Roll`
//! JSON blob per click.  The frontend can't reach `localStorage`
//! without hand-written JS glue, which the project explicitly avoids,
//! so persistence rides through this crate instead: a small
//! file-backed JSON store with three HTTP endpoints.
//!
//! Endpoints:
//!
//! - `GET    /api/dice/history`  — return the stored roll log
//!   (newest first; bounded by `MAX_ENTRIES`).
//! - `POST   /api/dice/history`  — append one roll, truncate to
//!   `MAX_ENTRIES`, and return the updated log.
//! - `DELETE /api/dice/history`  — clear the log.
//!
//! Each `Roll` is treated as opaque JSON.  The server intentionally
//! does NOT validate the rolls' shape — the frontend defines the
//! schema and round-trips it.  This keeps the rules layer entirely
//! in Elm and lets us extend the schema without changing this file.
//!
//! Concurrency: a single async mutex serializes file IO so concurrent
//! POSTs can't lose updates from a read-modify-write race.  This is
//! cheap because the typical load is a handful of rolls per second
//! at the table.

use aide::{
  axum::{
    routing::delete_with, routing::get_with, routing::post_with, ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use serde_json::Value;
use std::{path::PathBuf, sync::Arc};
use thiserror::Error;
use tokio::{
  fs,
  io::{AsyncReadExt, AsyncWriteExt},
  sync::Mutex,
};
use tracing::warn;

use crate::web_base::AppState;

/// Hard cap on persisted rolls.  Matches the in-memory cap on the
/// frontend (`Dice.maxHistoryEntries`) so the two stay in lockstep.
pub const MAX_ENTRIES: usize = 30;

/// Semantic errors from dice-history persistence.  Each variant
/// describes both what failed and which file was involved, so a
/// log line or HTTP error message reads as a complete sentence.
#[derive(Debug, Error)]
pub enum DiceHistoryError {
  #[error("Failed to read dice history file at {path}: {source}")]
  ReadError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to write dice history file at {path}: {source}")]
  WriteError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to atomically rename dice history file from {from} to {to}: {source}")]
  RenameError {
    from: PathBuf,
    to: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to remove dice history file at {path}: {source}")]
  RemoveError {
    path: PathBuf,
    source: std::io::Error,
  },
}

impl IntoResponse for DiceHistoryError {
  fn into_response(self) -> Response {
    warn!(error = %self, "dice history operation failed");
    (
      StatusCode::INTERNAL_SERVER_ERROR,
      Json(serde_json::json!({ "error": self.to_string() })),
    )
      .into_response()
  }
}

/// File-backed dice history store.
///
/// `path` is the on-disk location of the JSON file (created on first
/// write; missing == empty history).  `mutex` serializes
/// read-modify-write so concurrent POSTs don't lose updates.
#[derive(Clone)]
pub struct DiceStore {
  path: PathBuf,
  mutex: Arc<Mutex<()>>,
}

impl DiceStore {
  /// Construct a store backed by `path`.  No file IO is performed
  /// here; the path is opened lazily on the first read or write.
  pub fn new(path: PathBuf) -> Self {
    Self {
      path,
      mutex: Arc::new(Mutex::new(())),
    }
  }

  /// Read the current history.  Returns an empty list if the file
  /// doesn't exist or contains malformed JSON; we'd rather hand the
  /// user an empty roll log than fail the page load.
  pub async fn load(&self) -> Vec<Value> {
    let _guard = self.mutex.lock().await;
    read_file(&self.path).await.unwrap_or_default()
  }

  /// Prepend `roll` to the history, truncate to `MAX_ENTRIES`, and
  /// persist the result.  Returns the new history.
  pub async fn append(
    &self,
    roll: Value,
  ) -> Result<Vec<Value>, DiceHistoryError> {
    let _guard = self.mutex.lock().await;
    let mut entries = read_file(&self.path).await.unwrap_or_default();
    entries.insert(0, roll);
    entries.truncate(MAX_ENTRIES);
    write_file(&self.path, &entries).await?;
    Ok(entries)
  }

  /// Delete the history file.  No-op if it doesn't exist.
  pub async fn clear(&self) -> Result<(), DiceHistoryError> {
    let _guard = self.mutex.lock().await;
    match fs::remove_file(&self.path).await {
      Ok(()) => Ok(()),
      Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
      Err(source) => Err(DiceHistoryError::RemoveError {
        path: self.path.clone(),
        source,
      }),
    }
  }
}

/// Read + parse the history file, swallowing the not-found case.
/// Other IO errors propagate as `Err`; serde failures are logged and
/// downgraded to an empty history so a corrupt file doesn't brick
/// the page.
async fn read_file(path: &PathBuf) -> Result<Vec<Value>, DiceHistoryError> {
  let mut file = match fs::File::open(path).await {
    Ok(f) => f,
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
    Err(source) => {
      return Err(DiceHistoryError::ReadError {
        path: path.clone(),
        source,
      })
    }
  };

  let mut bytes = Vec::new();
  file.read_to_end(&mut bytes).await.map_err(|source| {
    DiceHistoryError::ReadError {
      path: path.clone(),
      source,
    }
  })?;

  match serde_json::from_slice(&bytes) {
    Ok(v) => Ok(v),
    Err(err) => {
      warn!(?path, %err, "dice history file is malformed; treating as empty");
      Ok(Vec::new())
    }
  }
}

/// Atomically replace the history file with the new contents.
///
/// Writes to a sibling tempfile and renames over the target so a
/// crash mid-write can't leave a half-truncated JSON behind.
async fn write_file(
  path: &PathBuf,
  entries: &[Value],
) -> Result<(), DiceHistoryError> {
  if let Some(parent) = path.parent() {
    if !parent.as_os_str().is_empty() {
      // Best-effort directory creation; if this fails we'll surface
      // the actual write error below with full context.
      fs::create_dir_all(parent).await.ok();
    }
  }

  let tmp = path.with_extension("tmp");
  {
    let mut file = fs::File::create(&tmp).await.map_err(|source| {
      DiceHistoryError::WriteError {
        path: tmp.clone(),
        source,
      }
    })?;
    let bytes = serde_json::to_vec_pretty(&entries)
      .expect("serializing Vec<Value> never fails");
    file.write_all(&bytes).await.map_err(|source| {
      DiceHistoryError::WriteError {
        path: tmp.clone(),
        source,
      }
    })?;
    file.sync_data().await.ok();
  }
  fs::rename(&tmp, path)
    .await
    .map_err(|source| DiceHistoryError::RenameError {
      from: tmp,
      to: path.clone(),
      source,
    })
}

// ── HTTP handlers ────────────────────────────────────────────────────────────
//
// Handlers return `Response` directly (rather than `Result<T, E>`) because
// aide's `OperationHandler` trait requires `OperationOutput` on the return
// type, and we don't want to commit to an aide-specific trait impl on our
// own error enum.  The error → response mapping rides on
// `impl IntoResponse for DiceHistoryError` so the handler bodies stay
// tight: success path picks one branch, error path picks the other.

async fn get_history(State(state): State<AppState>) -> Json<Vec<Value>> {
  Json(state.dice_store.load().await)
}

async fn post_roll(
  State(state): State<AppState>,
  Json(roll): Json<Value>,
) -> Response {
  match state.dice_store.append(roll).await {
    Ok(entries) => Json(entries).into_response(),
    Err(err) => err.into_response(),
  }
}

async fn delete_history(State(state): State<AppState>) -> Response {
  match state.dice_store.clear().await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(err) => err.into_response(),
  }
}

/// Build the `/api/dice/*` subrouter, ready to be merged into the
/// base `ApiRouter`.  Returning `ApiRouter<AppState>` (rather than a
/// plain `axum::Router`) lets the three endpoints participate in the
/// OpenAPI schema served at `/api-docs/openapi.json` and browsable
/// at `/scalar`.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/dice/history",
      get_with(get_history, |op: TransformOperation| {
        op.description("Return the persisted dice-roll history (newest first).")
      }),
    )
    .api_route(
      "/api/dice/history",
      post_with(post_roll, |op: TransformOperation| {
        op.description(
          "Append one roll to the history, truncating older entries past MAX_ENTRIES.",
        )
      }),
    )
    .api_route(
      "/api/dice/history",
      delete_with(delete_history, |op: TransformOperation| {
        op.description("Clear the persisted dice-roll history.")
      }),
    )
}
