//! Session recorder plugin: stores binary audio uploads per user.
//!
//! Wire shape:
//!
//! - `POST   /api/recording/upload` — multipart/form-data with one
//!   `audio` field carrying the recorded blob.  Returns
//!   `RecordingMeta` for the freshly-created entry.
//! - `GET    /api/recording`         — list this user's recordings,
//!   newest-first.
//! - `GET    /api/recording/{id}`    — stream the audio file back to
//!   the browser with its stored MIME type.
//! - `DELETE /api/recording/{id}`    — remove file + index entry.
//!
//! On disk the layout is intentionally boring:
//!
//! ```text
//! <data_dir>/recordings/
//! ├── index.json                       # HashMap<UserId, Vec<RecordingMeta>>
//! └── <user-id>/
//!     └── <recording-id>               # raw blob (Opus/WebM by default)
//! ```
//!
//! The whole module is gated behind the `recording` cargo feature.
//! Disabling it removes the routes, the `RecordingStore` field on
//! `AppState`, and the entire `axum/multipart` cost; the rest of
//! the server compiles and runs unchanged.

mod store;

use aide::axum::ApiRouter;
use axum::{
  body::Body,
  extract::{DefaultBodyLimit, Multipart, Path, State},
  http::{header, StatusCode},
  response::{IntoResponse, Response},
  routing::{get, post},
  Extension, Json,
};
use tracing::warn;

use crate::users::CurrentUser;
use crate::web_base::AppState;

pub use store::{RecordingMeta, RecordingStore, RecordingStoreError};

/// Hard cap on a single upload: 200 MB.  Comfortable for ~8h of
/// Opus @ 32 kbps with headroom; rejects anything pathological
/// before we burn disk.
const MAX_UPLOAD_BYTES: usize = 200 * 1024 * 1024;

/// Build the `/api/recording/*` subrouter.  Merged into the
/// auth-gated protected router in `main.rs` so every handler can
/// assume `Extension<CurrentUser>` is present.
///
/// Uses plain `axum::routing` rather than the aide `_with`
/// variants because the upload/fetch endpoints traffic in
/// `Multipart` / `Body` types that don't have `JsonSchema`
/// impls.  These routes won't surface in `/scalar`; that's fine
/// for a binary-blob plugin.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .route("/api/recording", get(list))
    .route("/api/recording/upload", post(upload))
    .route("/api/recording/{id}", get(fetch).delete(delete_one))
    .layer(DefaultBodyLimit::max(MAX_UPLOAD_BYTES))
}

// ── handlers ─────────────────────────────────────────────────────────────

async fn list(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Json<Vec<RecordingMeta>> {
  Json(state.recording_store.list(&user.id).await)
}

async fn upload(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  mut multipart: Multipart,
) -> Response {
  // Single multipart pass — we expect one `audio` field and stop
  // reading at the first one (extra fields are silently dropped).
  loop {
    let field = match multipart.next_field().await {
      Ok(Some(field)) => field,
      Ok(None) => break,
      Err(err) => {
        warn!(error = %err, "recording upload: multipart read failed");
        return (
          StatusCode::BAD_REQUEST,
          Json(serde_json::json!({ "error": "Malformed multipart body" })),
        )
          .into_response();
      }
    };

    if field.name() != Some("audio") {
      // Drop other fields; we don't care about extra form parts.
      continue;
    }

    let filename = field.file_name().map(|s| s.to_string());
    let mime = field
      .content_type()
      .map(|s| s.to_string())
      .unwrap_or_else(|| "audio/webm".to_string());

    return match state
      .recording_store
      .save(&user.id, filename, mime, field)
      .await
    {
      Ok(meta) => (StatusCode::CREATED, Json(meta)).into_response(),
      Err(err) => err.into_response(),
    };
  }

  (
    StatusCode::BAD_REQUEST,
    Json(serde_json::json!({
      "error": "Missing `audio` field in multipart upload"
    })),
  )
    .into_response()
}

async fn fetch(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  let (meta, path) = match state.recording_store.locate(&user.id, &id).await {
    Some(pair) => pair,
    None => return StatusCode::NOT_FOUND.into_response(),
  };

  // v0: whole-file read.  At homelab scale (recordings ≤ ~50 MB),
  // the memory cost is acceptable.  Switch to ReaderStream-based
  // chunked streaming when the first user actually parks a 4h
  // session here.
  let bytes = match tokio::fs::read(&path).await {
    Ok(b) => b,
    Err(err) => {
      warn!(?path, error = %err, "recording fetch: read failed");
      return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
  };

  (
    [
      (header::CONTENT_TYPE, meta.mime.clone()),
      (
        header::CONTENT_DISPOSITION,
        format!("attachment; filename=\"{}\"", meta.filename),
      ),
      (header::CACHE_CONTROL, "no-store".to_string()),
    ],
    Body::from(bytes),
  )
    .into_response()
}

async fn delete_one(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Path(id): Path<String>,
) -> Response {
  match state.recording_store.delete(&user.id, &id).await {
    Ok(true) => StatusCode::NO_CONTENT.into_response(),
    Ok(false) => StatusCode::NOT_FOUND.into_response(),
    Err(err) => err.into_response(),
  }
}
