//! One-time per-user-compendium split migration.
//!
//! Before the split, all creatures lived in a single shared
//! `Vec<Creature>` keyed by no user — bundled SRD creatures, user-
//! edited bundled creatures, and user-created creatures were
//! indistinguishable in the on-disk format.  After the split,
//! bundled creatures live read-only in
//! [`BundledCompendium`](super::bundled::BundledCompendium) (in-
//! binary) and per-user creatures live in
//! [`UserCompendiumStore`](super::user_store::UserCompendiumStore).
//!
//! This module runs once at server boot.  Idempotent via a sidecar
//! marker file at `<compendium_dir>/.split-v1`; subsequent boots
//! see the marker and skip immediately.
//!
//! ### What runs
//!
//! 1. Read the legacy shared compendium (every Creature on disk).
//! 2. Partition into three buckets:
//!    - **Canonical bundled** — id is in `BundledCompendium`, and
//!      contents match the bundled version byte-for-byte.  Discarded
//!      (the bundle is the source of truth post-split).
//!    - **Edited bundled** — id is in `BundledCompendium` but
//!      contents differ.  Treated as a user fork: mint a fresh
//!      UUIDv4, prepend "Copy of " to the name, hand to the claim
//!      user.
//!    - **User-created** — id is NOT in `BundledCompendium` (a
//!      UUIDv4 from the legacy `create` path).  Hand to the claim
//!      user with its id intact so any existing encounter references
//!      keep resolving.
//! 3. If there's nothing in the "edited bundled" or "user-created"
//!    buckets, write the marker and return — no claim user needed.
//! 4. Otherwise the `--compendium-claim-user <email>` CLI flag (or
//!    the `compendium_claim_user` config-file key) must resolve to
//!    a known user; the server refuses to start otherwise so the
//!    operator can make the decision deliberately.
//! 5. Append every claimed creature to the user's per-user store.
//! 6. Write `<compendium_dir>/.split-v1` recording the migration.

use std::path::{Path, PathBuf};

use ezpz_dndz_lib::{compendium::Creature, users::UserStore};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};
use uuid::Uuid;

use super::bundled::BundledCompendium;
use super::error::CompendiumStoreError;
use super::store::CompendiumStore;
use super::user_store::UserCompendiumStore;

/// Schema version for the marker file.  Bumped if the migration
/// logic ever needs a v2 pass.
const MIGRATION_VERSION: i32 = 1;

const MARKER_FILE: &str = ".split-v1";

#[derive(Debug, Serialize, Deserialize)]
struct MigrationMarker {
  version: i32,
  ran_at_epoch_ms: i64,
  claimed_to: Option<String>,
  forks: usize,
  user_created: usize,
}

/// Run the split migration if the marker is absent.  No-op if the
/// marker is present.  Returns an error and refuses to proceed
/// when there's data to claim but no claim user was provided.
///
/// `compendium_dir` is the directory containing the legacy
/// `creatures.json`; the marker is written alongside it.
pub async fn run(
  compendium_dir: &Path,
  legacy_store: &CompendiumStore,
  bundled: &BundledCompendium,
  user_compendium: &UserCompendiumStore,
  user_store: &UserStore,
  claim_user_email: Option<&str>,
) -> Result<(), MigrationError> {
  let marker_path = compendium_dir.join(MARKER_FILE);
  if marker_path.exists() {
    return Ok(());
  }

  let all_legacy = legacy_store.list().await;
  let (forks, user_created) = partition_legacy(all_legacy, bundled);
  let total = forks.len() + user_created.len();

  if total == 0 {
    write_marker(&marker_path, None, 0, 0)?;
    info!(
      "compendium split migration: no legacy non-bundled creatures \
       found; wrote marker and proceeding"
    );
    return Ok(());
  }

  let email = claim_user_email.ok_or(MigrationError::ClaimUserMissing {
    forks: forks.len(),
    user_created: user_created.len(),
  })?;

  let user = user_store.find_by_email(email).await.ok_or_else(|| {
    MigrationError::ClaimUserNotFound {
      email: email.to_string(),
    }
  })?;

  let claim_user_id = user.id.clone();
  let claim_user_id_str = claim_user_id.as_str().to_string();

  // Forks: mint a fresh UUID and rename so the bundled originals
  // are restored to their canonical names.
  let mut to_insert: Vec<Creature> =
    Vec::with_capacity(forks.len() + user_created.len());
  for mut creature in forks {
    creature.id = Uuid::new_v4().to_string();
    creature.name = format!("Copy of {}", creature.name);
    creature.is_bundled = false;
    to_insert.push(creature);
  }
  for mut creature in user_created {
    creature.is_bundled = false;
    to_insert.push(creature);
  }

  let forks_count = to_insert
    .iter()
    .filter(|c| c.name.starts_with("Copy of "))
    .count();
  let user_created_count = to_insert.len() - forks_count;

  for creature in to_insert {
    user_compendium
      .insert_raw(&claim_user_id, creature)
      .await
      .map_err(MigrationError::Insert)?;
  }

  write_marker(
    &marker_path,
    Some(claim_user_id_str.clone()),
    forks_count,
    user_created_count,
  )?;

  warn!(
    claimed_to_user_id = %claim_user_id_str,
    claimed_to_email = %email,
    forks = forks_count,
    user_created = user_created_count,
    "compendium split migration applied: bundled-id creatures with \
     edits are now Copy-of forks in the claim user's compendium; \
     user-created creatures carry their original ids"
  );

  Ok(())
}

/// Partition the legacy creature list into (edited-bundled,
/// user-created) buckets.  Bundled creatures whose contents match
/// the canonical bundle byte-for-byte are dropped — the bundle in
/// the binary will serve them post-migration.
fn partition_legacy(
  all_legacy: Vec<Creature>,
  bundled: &BundledCompendium,
) -> (Vec<Creature>, Vec<Creature>) {
  let mut forks = Vec::new();
  let mut user_created = Vec::new();
  for creature in all_legacy {
    if bundled.contains(&creature.id) {
      if let Some(canonical) = bundled.get(&creature.id) {
        if creature_content_equals(&creature, canonical) {
          continue;
        }
      }
      forks.push(creature);
    } else {
      user_created.push(creature);
    }
  }
  (forks, user_created)
}

/// Equality check that ignores `id`, `is_bundled`, `created_at`,
/// `updated_at`.  Two creatures are "the same" for migration
/// purposes when their stat-block contents match; timestamp drift
/// or the new `is_bundled` flag shouldn't force a fork.
fn creature_content_equals(a: &Creature, b: &Creature) -> bool {
  let normalize = |c: &Creature| {
    let mut clone = c.clone();
    clone.id.clear();
    clone.is_bundled = false;
    clone.created_at = 0;
    clone.updated_at = 0;
    clone
  };
  serde_json::to_string(&normalize(a)).ok()
    == serde_json::to_string(&normalize(b)).ok()
}

fn write_marker(
  path: &PathBuf,
  claimed_to: Option<String>,
  forks: usize,
  user_created: usize,
) -> Result<(), MigrationError> {
  if let Some(parent) = path.parent() {
    std::fs::create_dir_all(parent).map_err(MigrationError::MarkerWrite)?;
  }
  let marker = MigrationMarker {
    version: MIGRATION_VERSION,
    ran_at_epoch_ms: epoch_millis(),
    claimed_to,
    forks,
    user_created,
  };
  let json = serde_json::to_string_pretty(&marker)
    .map_err(MigrationError::MarkerSerialize)?;
  std::fs::write(path, json).map_err(MigrationError::MarkerWrite)?;
  Ok(())
}

fn epoch_millis() -> i64 {
  std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}

#[derive(Debug, thiserror::Error)]
pub enum MigrationError {
  #[error(
    "compendium split migration needs --compendium-claim-user <email>: \
     found {forks} edited-bundled and {user_created} user-created \
     creatures in the legacy shared store; pass the flag to claim \
     them for a specific user, or delete the legacy store file to \
     wipe them"
  )]
  ClaimUserMissing { forks: usize, user_created: usize },

  #[error(
    "compendium claim user {email} not found in the user store; \
     register the account first or pass a different email"
  )]
  ClaimUserNotFound { email: String },

  #[error("failed to append migrated creature to per-user store: {0}")]
  Insert(#[source] CompendiumStoreError),

  #[error("failed to write split-migration marker file: {0}")]
  MarkerWrite(#[source] std::io::Error),

  #[error("failed to serialize split-migration marker: {0}")]
  MarkerSerialize(#[source] serde_json::Error),
}
