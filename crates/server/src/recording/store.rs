//! Recording store: a small in-memory index over per-user audio
//! files on disk.
//!
//! Per-user metadata lives in a single JSON file
//! `<recordings_dir>/index.json` of shape
//! `HashMap<UserId, Vec<RecordingMeta>>`.  Audio bytes themselves
//! live at `<recordings_dir>/<user-id>/<recording-id>`.
//!
//! The store owns the `JsonFileStore` for the index, plus the
//! base directory it writes audio bytes into.  Mutations
//! serialize through the index's underlying async mutex; writes
//! to individual audio files are append-only by construction
//! (each upload gets a fresh UUID).

use std::{
  collections::HashMap,
  path::PathBuf,
  sync::Arc,
  time::{SystemTime, UNIX_EPOCH},
};

use axum::{
  extract::multipart::Field,
  http::StatusCode,
  response::{IntoResponse, Response},
  Json,
};
use ezpz_dndz_lib::{
  json_file_store::{JsonFileStore, JsonFileStoreError},
  users::UserId,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::{fs, io::AsyncWriteExt};
use tracing::warn;
use uuid::Uuid;

use super::MAX_UPLOAD_BYTES;

const RECORDINGS_INDEX_FILE: &str = "index.json";

/// Cap on stored recordings per user.  Older entries past the
/// cap are pruned (oldest first) on every successful upload.
pub const MAX_RECORDINGS_PER_USER: usize = 64;

/// Metadata for one stored recording.  Persisted in the index;
/// served back over the wire so the GM can browse / download /
/// delete from the frontend.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct RecordingMeta {
  pub id: String,
  pub filename: String,
  pub mime: String,
  pub size_bytes: u64,
  /// Milliseconds since the unix epoch.
  pub created_at_ms: u64,
}

/// Semantic errors from the recording store.
#[derive(Debug, Error)]
pub enum RecordingStoreError {
  #[error("Recording index persistence failed: {0}")]
  IndexStore(#[from] JsonFileStoreError),

  #[error("Recording disk IO failed: {0}")]
  Io(#[from] std::io::Error),

  #[error("Multipart read failed: {0}")]
  Multipart(#[from] axum::extract::multipart::MultipartError),

  #[error("Recording too large ({size} bytes exceeds the {limit}-byte limit)")]
  TooLarge { size: u64, limit: u64 },
}

impl IntoResponse for RecordingStoreError {
  fn into_response(self) -> Response {
    let status = match &self {
      Self::TooLarge { .. } => StatusCode::PAYLOAD_TOO_LARGE,
      Self::Multipart(_) => StatusCode::BAD_REQUEST,
      _ => StatusCode::INTERNAL_SERVER_ERROR,
    };
    warn!(error = %self, "recording operation failed");
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}

/// File-backed recording store.  Cheap to clone — the index sits
/// behind `Arc<JsonFileStore<_>>` and the base path is a `PathBuf`.
#[derive(Clone)]
pub struct RecordingStore {
  index: Arc<JsonFileStore<HashMap<UserId, Vec<RecordingMeta>>>>,
  base_dir: PathBuf,
}

impl RecordingStore {
  /// Open the store rooted at `recordings_dir`, creating both the
  /// directory and the index file when they don't exist.
  pub async fn open(
    recordings_dir: PathBuf,
  ) -> Result<Self, RecordingStoreError> {
    fs::create_dir_all(&recordings_dir).await?;

    let index = JsonFileStore::load_or_default(
      recordings_dir.join(RECORDINGS_INDEX_FILE),
    )
    .await?;

    Ok(Self {
      index: Arc::new(index),
      base_dir: recordings_dir,
    })
  }

  /// Return the user's recordings, newest-first.  Cheap clone of
  /// the cached index value; no disk IO on the hot path.
  pub async fn list(&self, user_id: &UserId) -> Vec<RecordingMeta> {
    self
      .index
      .read()
      .await
      .get(user_id)
      .cloned()
      .unwrap_or_default()
  }

  /// Look up one recording's metadata + on-disk path.  `None`
  /// when the id isn't owned by this user (which is the same
  /// thing as "doesn't exist" from this user's perspective —
  /// no cross-user leakage).
  pub async fn locate(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Option<(RecordingMeta, PathBuf)> {
    let meta = self
      .index
      .read()
      .await
      .get(user_id)?
      .iter()
      .find(|m| m.id == id)
      .cloned()?;
    let path = self.audio_path(user_id, &meta.id);
    Some((meta, path))
  }

  /// Stream a multipart field to disk under
  /// `<base_dir>/<user-id>/<uuid>` and append the resulting meta
  /// to the user's index entry.  The upload aborts and the partial
  /// file is removed if `MAX_UPLOAD_BYTES` is exceeded.
  ///
  /// Returns the persisted `RecordingMeta` on success.
  pub async fn save(
    &self,
    user_id: &UserId,
    filename_hint: Option<String>,
    mime: String,
    mut field: Field<'_>,
  ) -> Result<RecordingMeta, RecordingStoreError> {
    let id = Uuid::new_v4().to_string();
    let user_dir = self.user_dir(user_id);
    fs::create_dir_all(&user_dir).await?;
    let audio_path = user_dir.join(&id);

    let mut total: u64 = 0;
    let mut file = fs::File::create(&audio_path).await?;

    while let Some(chunk) = field.chunk().await? {
      total = total.saturating_add(chunk.len() as u64);
      if total > MAX_UPLOAD_BYTES as u64 {
        // Abort: tear the file down so we don't leak a partial.
        drop(file);
        let _ = fs::remove_file(&audio_path).await;
        return Err(RecordingStoreError::TooLarge {
          size: total,
          limit: MAX_UPLOAD_BYTES as u64,
        });
      }
      file.write_all(&chunk).await?;
    }
    file.flush().await?;
    drop(file);

    let created_at_ms = SystemTime::now()
      .duration_since(UNIX_EPOCH)
      .map(|d| d.as_millis() as u64)
      .unwrap_or(0);

    let display_filename =
      pretty_filename(filename_hint.as_deref(), &id, created_at_ms);

    let meta = RecordingMeta {
      id: id.clone(),
      filename: display_filename,
      mime,
      size_bytes: total,
      created_at_ms,
    };

    // Insert into the index, prune past the per-user cap, and
    // persist.  Mutate-then-clone returns the freshly-pruned-and-
    // sorted entry so we surface exactly what's on disk.
    let pruned_paths = self
      .index
      .mutate({
        let user_id = user_id.clone();
        let meta = meta.clone();
        move |index| {
          let entries = index.entry(user_id).or_default();
          entries.insert(0, meta);
          // Keep newest first; trim from the tail.
          let dropped: Vec<RecordingMeta> =
            if entries.len() > MAX_RECORDINGS_PER_USER {
              entries.split_off(MAX_RECORDINGS_PER_USER)
            } else {
              Vec::new()
            };
          dropped
        }
      })
      .await?;

    // Clean up audio files for the recordings pruned by the cap.
    // Best-effort — log and continue on individual removal errors
    // so a single stale file doesn't fail the whole upload.
    for dropped in pruned_paths {
      let path = self.audio_path(user_id, &dropped.id);
      if let Err(err) = fs::remove_file(&path).await {
        warn!(?path, error = %err, "recording prune: failed to delete file");
      }
    }

    Ok(meta)
  }

  /// Remove the index entry + the on-disk file.  Returns `Ok(true)`
  /// when an entry existed and was removed, `Ok(false)` when the
  /// id wasn't found.
  pub async fn delete(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<bool, RecordingStoreError> {
    let removed = self
      .index
      .mutate({
        let user_id = user_id.clone();
        let id = id.to_string();
        move |index| {
          let Some(entries) = index.get_mut(&user_id) else {
            return false;
          };
          let before = entries.len();
          entries.retain(|m| m.id != id);
          before != entries.len()
        }
      })
      .await?;

    if removed {
      let path = self.audio_path(user_id, id);
      if let Err(err) = fs::remove_file(&path).await {
        // Index already updated; log and swallow — the next list
        // call won't see this entry, so an orphan file is harmless.
        warn!(?path, error = %err, "recording delete: file removal failed");
      }
    }

    Ok(removed)
  }

  fn user_dir(&self, user_id: &UserId) -> PathBuf {
    // UserId is a UUID-shaped String — filesystem-safe by
    // construction, no traversal vector to worry about.
    self.base_dir.join(&user_id.0)
  }

  fn audio_path(&self, user_id: &UserId, id: &str) -> PathBuf {
    self.user_dir(user_id).join(id)
  }
}

/// Pick a human-friendly filename for the stored entry.
///
/// Browser MediaRecorder usually leaves the multipart `filename`
/// blank, so we synthesise one from the recording timestamp.
/// When the client does send something useful we keep it (sans
/// path traversal), so a future "session-title" UI tweak works
/// without server changes.
fn pretty_filename(hint: Option<&str>, id: &str, created_at_ms: u64) -> String {
  if let Some(raw) = hint {
    let cleaned: String = raw
      .chars()
      .filter(|c| !matches!(*c, '/' | '\\' | '\0'))
      .collect();
    if !cleaned.trim().is_empty() {
      return cleaned;
    }
  }
  let secs = created_at_ms / 1000;
  // Avoid pulling in chrono just for a date string — secs since
  // epoch + a short id is sufficient and round-trips through any
  // filesystem.
  format!("session-{secs}-{}.webm", &id[..8])
}
