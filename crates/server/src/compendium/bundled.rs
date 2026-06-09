//! Shared, read-only bundled creature set.
//!
//! Holds the SRD creatures parsed once at startup from the
//! `bundled-creatures.json` file embedded via `include_str!`.
//! Every authenticated user sees the same bundled list; the
//! per-user mutable layer lives in
//! [`UserCompendiumStore`](super::user_store::UserCompendiumStore)
//! and overlays this set at read time.
//!
//! Bundled creatures cannot be edited or deleted through the
//! HTTP API.  Users who want to modify one must invoke the
//! `duplicate` endpoint, which clones the creature into their
//! per-user store with a fresh UUIDv4 id.
//!
//! The id set is precomputed so handlers can answer "is this id
//! bundled?" in O(1) without re-parsing JSON or walking the
//! creature list.

use std::collections::HashSet;
use std::sync::Arc;

use ezpz_dndz_lib::compendium::Creature;

use super::error::CompendiumStoreError;

/// Embedded SRD creature bundle.  Same `include_str!` source as
/// the legacy [`CompendiumStore`](super::store::CompendiumStore);
/// once the per-user split is fully wired up, this is the only
/// place the bundled bytes are parsed at runtime.
const BUNDLED_JSON: &str =
  include_str!("../../../lib/data/bundled-creatures.json");

#[derive(Clone)]
pub struct BundledCompendium {
  creatures: Arc<Vec<Creature>>,
  ids: Arc<HashSet<String>>,
}

impl BundledCompendium {
  /// Parse the embedded JSON.  Returns an error if the bytes
  /// shipped in the binary fail to decode, which would indicate
  /// a build-time data problem and is treated as fatal at startup.
  pub fn load() -> Result<Self, CompendiumStoreError> {
    let creatures: Vec<Creature> = serde_json::from_str(BUNDLED_JSON)
      .map_err(|source| CompendiumStoreError::BundledParseError { source })?;
    let ids = creatures.iter().map(|c| c.id.clone()).collect();
    Ok(Self {
      creatures: Arc::new(creatures),
      ids: Arc::new(ids),
    })
  }

  /// All bundled creatures, in the order they appear in the JSON.
  /// Returned as a slice — callers that need an owned `Vec` should
  /// clone explicitly so the cost is visible at the call site.
  pub fn list(&self) -> &[Creature] {
    &self.creatures
  }

  /// O(1) check: does this id belong to a bundled creature?  Used
  /// by handlers to reject PUT/DELETE on bundled rows and by the
  /// `is_bundled` wire field computation.
  pub fn contains(&self, id: &str) -> bool {
    self.ids.contains(id)
  }

  /// Look up a single bundled creature by id.  `None` for any id
  /// not in the bundle (including user-created ids).
  pub fn get(&self, id: &str) -> Option<&Creature> {
    self.creatures.iter().find(|c| c.id == id)
  }
}
