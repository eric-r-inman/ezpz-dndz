//! Generic JSON-file-backed value store with atomic writes and
//! async-mutex serialization.  **Legacy-import machinery only.**
//!
//! Every live store is relational now (see the lib crate's `db`
//! module); the sole remaining consumer of this type is the legacy
//! shared [`CompendiumStore`](super::store::CompendiumStore), which
//! exists purely as input to the one-shot per-user split migration
//! ([`super::migrate`]) and its bundle-seed bookkeeping.  The module
//! therefore lives here, next to that consumer, instead of in the
//! lib crate — new features must not reach for it.
//!
//! The stored value `T` is treated as a single document — load on
//! demand, mutate via a closure, persist as a whole.
//!
//! # Concurrency model
//!
//! A single `tokio::sync::Mutex<T>` serializes both reads and writes.
//! Concurrent mutate calls are queued; reads are queued behind any
//! in-flight mutate.  This is intentional — JSON files don't support
//! locking finer than the whole document, so we model that explicitly
//! at the type level.
//!
//! # Errors
//!
//! All public methods return `Result<_, JsonFileStoreError>` with
//! semantic variants per the project's error-handling discipline.
//! Each variant names the file path involved so log lines and HTTP
//! error bodies read as complete sentences.

use std::path::PathBuf;

use serde::{de::DeserializeOwned, Serialize};
use thiserror::Error;
use tokio::{
  fs,
  io::{AsyncReadExt, AsyncWriteExt},
  sync::Mutex,
};
use tracing::warn;

/// Semantic errors from JSON-file-backed value stores.
#[derive(Debug, Error)]
pub enum JsonFileStoreError {
  #[error("Failed to read JSON file at {path}: {source}")]
  ReadError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to write JSON file at {path}: {source}")]
  WriteError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error(
    "Failed to atomically rename JSON file from {from} to {to}: {source}"
  )]
  RenameError {
    from: PathBuf,
    to: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to encode value for JSON file at {path}: {source}")]
  EncodeError {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Failed to decode JSON file at {path}: {source}")]
  DecodeError {
    path: PathBuf,
    source: serde_json::Error,
  },
}

/// A JSON-file-backed value store.
///
/// `T` must be both `Serialize` and `DeserializeOwned`; in practice
/// it is the legacy shared compendium's `Vec<Creature>`.
///
/// The cache is loaded eagerly on construction (via
/// [`load_or_default`](Self::load_or_default)) so the first read
/// after server start doesn't pay the file-IO cost.
#[derive(Debug)]
pub struct JsonFileStore<T> {
  path: PathBuf,
  cache: Mutex<T>,
}

impl<T> JsonFileStore<T>
where
  T: Serialize + DeserializeOwned + Default + Clone + Send,
{
  /// Open the store at `path`.  If the file is missing, the in-memory
  /// cache is initialized to `T::default()` and the file is created
  /// on the first mutation.  If the file exists but contains
  /// malformed JSON, the corruption is logged at WARN and the cache
  /// is initialized to `T::default()` — a "soft-fail to empty" so a
  /// single corrupt file doesn't brick the whole server.
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, JsonFileStoreError> {
    let initial = match read_file::<T>(&path).await {
      Ok(value) => value,
      Err(JsonFileStoreError::DecodeError {
        path: corrupted,
        source,
      }) => {
        warn!(
          path = %corrupted.display(),
          error = %source,
          "JSON file is malformed; falling back to default value"
        );
        T::default()
      }
      Err(other) => return Err(other),
    };

    Ok(Self {
      path,
      cache: Mutex::new(initial),
    })
  }

  /// Snapshot the current value.  Cheap clone of the in-memory cache;
  /// no file IO.
  pub async fn read(&self) -> T {
    self.cache.lock().await.clone()
  }

  /// Apply `f` to a mutable reference to the cached value, then
  /// persist the result atomically.  Returns whatever `f` returns
  /// (typically the new value or a derived response payload).
  ///
  /// The mutex is held across the file write so concurrent mutates
  /// are linearizable.  This is intentional — see the module docs.
  pub async fn mutate<F, R>(&self, f: F) -> Result<R, JsonFileStoreError>
  where
    F: FnOnce(&mut T) -> R,
  {
    let mut guard = self.cache.lock().await;
    let result = f(&mut *guard);
    write_file(&self.path, &*guard).await?;
    Ok(result)
  }

  /// Replace the entire cached value and persist.  Used by the
  /// legacy store's reset-to-bundled path.
  pub async fn replace(&self, value: T) -> Result<(), JsonFileStoreError> {
    let mut guard = self.cache.lock().await;
    *guard = value;
    write_file(&self.path, &*guard).await
  }
}

/// Read + parse the file.  Missing-file is treated as `T::default()`
/// so first-launch bootstrap is implicit.  Decode failures bubble
/// up so the caller can decide whether to soft-fail or hard-fail.
async fn read_file<T>(path: &PathBuf) -> Result<T, JsonFileStoreError>
where
  T: DeserializeOwned + Default,
{
  let mut file = match fs::File::open(path).await {
    Ok(f) => f,
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
      return Ok(T::default())
    }
    Err(source) => {
      return Err(JsonFileStoreError::ReadError {
        path: path.clone(),
        source,
      })
    }
  };

  let mut bytes = Vec::new();
  file.read_to_end(&mut bytes).await.map_err(|source| {
    JsonFileStoreError::ReadError {
      path: path.clone(),
      source,
    }
  })?;

  serde_json::from_slice::<T>(&bytes).map_err(|source| {
    JsonFileStoreError::DecodeError {
      path: path.clone(),
      source,
    }
  })
}

/// Atomically replace the file with the JSON encoding of `value`.
/// Writes to a sibling tempfile and renames over the target so a
/// crash mid-write can't leave a half-truncated JSON behind.
async fn write_file<T>(
  path: &PathBuf,
  value: &T,
) -> Result<(), JsonFileStoreError>
where
  T: Serialize,
{
  if let Some(parent) = path.parent() {
    if !parent.as_os_str().is_empty() {
      // Best-effort parent creation; if this fails we'll surface the
      // actual write error below with full context.
      fs::create_dir_all(parent).await.ok();
    }
  }

  let bytes = serde_json::to_vec_pretty(value).map_err(|source| {
    JsonFileStoreError::EncodeError {
      path: path.clone(),
      source,
    }
  })?;

  let tmp = path.with_extension("tmp");
  {
    let mut file = fs::File::create(&tmp).await.map_err(|source| {
      JsonFileStoreError::WriteError {
        path: tmp.clone(),
        source,
      }
    })?;
    file.write_all(&bytes).await.map_err(|source| {
      JsonFileStoreError::WriteError {
        path: tmp.clone(),
        source,
      }
    })?;
    file.sync_data().await.ok();
  }
  fs::rename(&tmp, path).await.map_err(|source| {
    JsonFileStoreError::RenameError {
      from: tmp,
      to: path.clone(),
      source,
    }
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use tempfile::TempDir;

  #[tokio::test]
  async fn fresh_store_returns_default() {
    let dir = TempDir::new().unwrap();
    let store: JsonFileStore<Vec<String>> =
      JsonFileStore::load_or_default(dir.path().join("data.json"))
        .await
        .expect("load");

    assert_eq!(store.read().await, Vec::<String>::new());
  }

  #[tokio::test]
  async fn mutate_persists_across_reload() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("data.json");

    {
      let store: JsonFileStore<Vec<String>> =
        JsonFileStore::load_or_default(path.clone())
          .await
          .expect("load");
      store
        .mutate(|v| v.push("hello".to_string()))
        .await
        .expect("mutate");
    }

    let reopened: JsonFileStore<Vec<String>> =
      JsonFileStore::load_or_default(path).await.expect("reload");
    assert_eq!(reopened.read().await, vec!["hello".to_string()]);
  }

  #[tokio::test]
  async fn replace_overwrites_collection() {
    let dir = TempDir::new().unwrap();
    let store: JsonFileStore<Vec<i32>> =
      JsonFileStore::load_or_default(dir.path().join("data.json"))
        .await
        .expect("load");

    store.mutate(|v| v.extend([1, 2, 3])).await.expect("seed");
    store.replace(vec![10, 20]).await.expect("replace");

    assert_eq!(store.read().await, vec![10, 20]);
  }

  #[tokio::test]
  async fn malformed_json_falls_back_to_default() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("data.json");
    tokio::fs::write(&path, b"not json at all").await.unwrap();

    let store: JsonFileStore<Vec<String>> =
      JsonFileStore::load_or_default(path).await.expect("load");
    assert_eq!(store.read().await, Vec::<String>::new());
  }
}
