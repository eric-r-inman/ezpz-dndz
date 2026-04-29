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

use axum::{
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
  routing::{delete, get, post},
  Json, Router,
};
use serde_json::Value;
use std::{path::PathBuf, sync::Arc};
use tokio::{
  fs,
  io::{AsyncReadExt, AsyncWriteExt},
  sync::Mutex,
};
use tracing::warn;

/// Hard cap on persisted rolls.  Matches the in-memory cap on the
/// frontend (`Dice.maxHistoryEntries`) so the two stay in lockstep.
pub const MAX_ENTRIES: usize = 30;

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
  pub async fn append(&self, roll: Value) -> std::io::Result<Vec<Value>> {
    let _guard = self.mutex.lock().await;
    let mut entries = read_file(&self.path).await.unwrap_or_default();
    entries.insert(0, roll);
    entries.truncate(MAX_ENTRIES);
    write_file(&self.path, &entries).await?;
    Ok(entries)
  }

  /// Delete the history file.  No-op if it doesn't exist.
  pub async fn clear(&self) -> std::io::Result<()> {
    let _guard = self.mutex.lock().await;
    match fs::remove_file(&self.path).await {
      Ok(()) => Ok(()),
      Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
      Err(e) => Err(e),
    }
  }
}

/// Read + parse the history file, swallowing the not-found case.
/// Other IO errors propagate as `Err`; serde failures are logged and
/// downgraded to an empty history so a corrupt file doesn't brick
/// the page.
async fn read_file(path: &PathBuf) -> std::io::Result<Vec<Value>> {
  let mut file = match fs::File::open(path).await {
    Ok(f) => f,
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
    Err(e) => return Err(e),
  };

  let mut bytes = Vec::new();
  file.read_to_end(&mut bytes).await?;

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
async fn write_file(path: &PathBuf, entries: &[Value]) -> std::io::Result<()> {
  if let Some(parent) = path.parent() {
    if !parent.as_os_str().is_empty() {
      fs::create_dir_all(parent).await.ok();
    }
  }

  let tmp = path.with_extension("tmp");
  {
    let mut file = fs::File::create(&tmp).await?;
    let bytes = serde_json::to_vec_pretty(&entries)
      .expect("serializing Vec<Value> never fails");
    file.write_all(&bytes).await?;
    file.sync_data().await.ok();
  }
  fs::rename(&tmp, path).await
}

// ── HTTP handlers ────────────────────────────────────────────────────────────

async fn get_history(State(store): State<DiceStore>) -> Json<Vec<Value>> {
  Json(store.load().await)
}

async fn post_roll(
  State(store): State<DiceStore>,
  Json(roll): Json<Value>,
) -> Response {
  match store.append(roll).await {
    Ok(entries) => Json(entries).into_response(),
    Err(err) => {
      warn!(%err, "failed to persist dice roll");
      (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(serde_json::json!({
          "error": format!("Failed to persist roll: {err}"),
        })),
      )
        .into_response()
    }
  }
}

async fn delete_history(State(store): State<DiceStore>) -> Response {
  match store.clear().await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(err) => {
      warn!(%err, "failed to clear dice history");
      (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(serde_json::json!({
          "error": format!("Failed to clear history: {err}"),
        })),
      )
        .into_response()
    }
  }
}

/// Build the `/api/dice/*` subrouter, ready to be `.merge()`d into
/// the base router.  All three handlers share the same `DiceStore`
/// state — the frontend talks to a single endpoint.
pub fn router(store: DiceStore) -> Router {
  Router::new()
    .route("/api/dice/history", get(get_history))
    .route("/api/dice/history", post(post_roll))
    .route("/api/dice/history", delete(delete_history))
    .with_state(store)
}
