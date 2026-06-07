//! File-backed compendium store.
//!
//! Thin wrapper around [`JsonFileStore<Vec<Creature>>`] from the
//! lib crate.  Adds compendium-specific concerns:
//!
//! - **Bootstrap**: on first launch (file absent) we seed the
//!   store with the bundled creatures embedded via `include_str!`.
//! - **Bundle versioning**: a sidecar `*.bundle-seed.json` file
//!   tracks the highest [`BUNDLED_VERSION`] we've ever merged
//!   into this store, plus per-creature content hashes recorded
//!   at apply time.  When the constant in source bumps past the
//!   recorded value, the next boot runs a HASH-AWARE merge:
//!   - **New bundled creatures** (id not on disk) → ADD.
//!   - **Bundled creatures the user hasn't touched** (disk hash
//!     equals the previously-recorded apply hash) → REPLACE with
//!     the new bundle contents so data fixes (typo corrections,
//!     newly-tagged recharge abilities, etc.) flow through.
//!   - **Bundled creatures the user HAS edited** (disk hash
//!     differs from the recorded apply hash) → LEAVE.  The user's
//!     customisation wins.
//!   - **Creatures with no recorded hash** (degraded seed file
//!     from the v1 era before hash tracking) → REPLACE on first
//!     migration so the long-standing data fixes can finally
//!     flow; record fresh hashes so future bumps gain edit
//!     detection.  This is a one-shot caveat documented in
//!     the warning log.
//!   - **User-created creatures** (id not in the bundle) → never
//!     touched.
//! - **Id allocation**: server-side UUIDv4 on insert; stable
//!   hand-picked UUIDs on bundled creatures so the version-merge
//!   logic can reliably match across versions.
//! - **Timestamps**: `created_at` / `updated_at` set / advanced
//!   server-side so clients can't lie about them.
//! - **Reset**: restore the bundled set, discarding user edits.
//!   Also bumps the seed file (version + fresh hashes) so the
//!   next merge starts from a known clean baseline.

use std::{
  collections::HashMap,
  path::{Path, PathBuf},
  sync::Arc,
  time::SystemTime,
};

use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};
use ezpz_dndz_lib::json_file_store::JsonFileStore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tracing::{info, warn};
use uuid::Uuid;

use super::error::CompendiumStoreError;

/// Generate a fresh UUIDv4 as a string.  Centralized so any
/// future format change (e.g. ULIDs) only touches one site.
fn fresh_id() -> String {
  Uuid::new_v4().to_string()
}

/// Bundled creatures shipped with the binary.  Parsed once at
/// store-construction time; baked into the binary via
/// `include_str!` so deployments don't need to copy a separate
/// data file.
///
/// Anonymous (unauthenticated) sessions in the Elm frontend read
/// the same data from `frontend/public/bundled-creatures.json`,
/// which is served as a static asset.  When this file is updated
/// the static copy MUST be refreshed in lockstep, otherwise
/// anonymous browsers will see a stale compendium even though
/// the server has been redeployed.
const BUNDLED_JSON: &str =
  include_str!("../../../lib/data/bundled-creatures.json");

/// Source-of-truth version for the bundled creature set.  Bump
/// this any time `bundled-creatures.json` changes — adding a
/// creature, fixing a typo on an existing one, etc.  The next
/// startup of any deployment that recorded a smaller value will
/// run a HASH-AWARE merge against the embedded bundle (see the
/// module docstring for the full semantics).
///
/// We don't store this inside the JSON itself because the JSON
/// shape doubles as the public Import / Export wire format; the
/// version is server-side metadata and lives in source.
pub const BUNDLED_VERSION: i32 = 3;

/// Sidecar metadata recording the highest bundled-version we've
/// merged into a given store, plus the content hash of each
/// bundled creature as it stood at apply time.  The hashes let
/// future bundle bumps detect whether a disk creature still
/// matches the previously-applied bundle (safe to refresh) or has
/// drifted from it (the user edited; preserve).
///
/// Persisted as a tiny JSON file alongside the creatures file so
/// a rename / move of the data directory carries it along
/// automatically.  Old seed files written before hash tracking
/// existed parse fine — `hashes` defaults to empty and the merge
/// treats that as the degraded "first migration" path.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct BundleSeed {
  version: i32,
  #[serde(default)]
  hashes: HashMap<String, String>,
}

/// What the merge decided to do with one bundled creature on a
/// version bump.  Used purely for the summary log line so admins
/// can audit what flowed through and what was preserved.
#[derive(Debug, Default)]
struct MergeCounts {
  added: usize,
  refreshed: usize,
  preserved: usize,
}

#[derive(Clone)]
pub struct CompendiumStore {
  inner: Arc<JsonFileStore<Vec<Creature>>>,
  seed_path: PathBuf,
}

impl CompendiumStore {
  /// Open the store at `path`.  Always runs the bundle-merge
  /// step; on a fresh install (no creatures, no seed) that's a
  /// full bootstrap, on subsequent boots it's a no-op when
  /// already current and an ADD-ONLY merge when the embedded
  /// version has grown past the recorded one.
  pub async fn load_or_bootstrap(
    path: PathBuf,
  ) -> Result<Self, CompendiumStoreError> {
    let inner =
      JsonFileStore::<Vec<Creature>>::load_or_default(path.clone()).await?;
    let store = Self {
      inner: Arc::new(inner),
      seed_path: bundle_seed_path(&path),
    };
    store.maybe_apply_bundle().await?;
    Ok(store)
  }

  /// If the embedded `BUNDLED_VERSION` is newer than what's
  /// recorded on disk, run a HASH-AWARE merge.  See the module
  /// docstring for the full semantics; the short version is
  /// "refresh creatures the user hasn't touched; preserve the
  /// ones they have."
  ///
  /// Empty store + missing seed file is the fresh-install path —
  /// every bundled creature gets added, fresh hashes are recorded,
  /// and the seed records the current version.
  async fn maybe_apply_bundle(&self) -> Result<(), CompendiumStoreError> {
    let seed = self.read_seed();
    let disk_version = seed.version;
    if BUNDLED_VERSION <= disk_version {
      return Ok(());
    }

    let bundle = parse_bundled()?;
    let bundle_ids: std::collections::HashSet<String> =
      bundle.iter().map(|c| c.id.clone()).collect();
    let recorded_hashes = seed.hashes.clone();
    let first_migration = recorded_hashes.is_empty();

    // Move-able by id so the mutator closure can take ownership.
    let bundle_by_id: HashMap<String, Creature> =
      bundle.into_iter().map(|c| (c.id.clone(), c)).collect();

    let counts = self
      .inner
      .mutate(move |all| {
        let mut counts = MergeCounts::default();

        // Walk existing on-disk creatures, deciding whether to
        // refresh each one in place.  Pre-collect ids that need
        // adding (in the bundle but not on disk) so we don't
        // mutate the vec while iterating.
        let existing_ids: std::collections::HashSet<String> =
          all.iter().map(|c| c.id.clone()).collect();

        for creature in all.iter_mut() {
          if let Some(new_version) = bundle_by_id.get(&creature.id) {
            let disk_hash = content_hash(creature);
            // No recorded hash → first migration: treat
            // bundled-id creatures as unedited so the long-
            // standing data fixes can finally flow.  Future
            // bumps will have full edit detection because we
            // record fresh hashes below.
            let unedited = recorded_hashes
              .get(&creature.id)
              .map_or(first_migration, |rec| *rec == disk_hash);

            if unedited {
              *creature = new_version.clone();
              counts.refreshed += 1;
            } else {
              counts.preserved += 1;
            }
          }
        }

        // ADD new bundled creatures whose ids aren't on disk yet.
        // Order doesn't matter — the client sorts on receipt.
        for (id, new_creature) in bundle_by_id.iter() {
          if !existing_ids.contains(id) {
            all.push(new_creature.clone());
            counts.added += 1;
          }
        }

        counts
      })
      .await?;

    // Record fresh hashes against the current disk state, so the
    // next bump can detect edits.  We hash from the current store
    // (post-merge) rather than from the bundle to capture any
    // server-side timestamp updates uniformly.
    let post_merge = self.inner.read().await;
    let fresh_hashes = post_merge
      .iter()
      .filter(|c| bundle_ids.contains(&c.id))
      .map(|c| (c.id.clone(), content_hash(c)))
      .collect();
    self.write_seed(BundleSeed {
      version: BUNDLED_VERSION,
      hashes: fresh_hashes,
    })?;

    if first_migration && (counts.refreshed > 0 || counts.added > 0) {
      warn!(
        added = counts.added,
        refreshed = counts.refreshed,
        from_version = disk_version,
        to_version = BUNDLED_VERSION,
        "first hash-tracked bundle migration: no prior hashes \
         recorded, so all bundled-id creatures on disk were \
         refreshed unconditionally — manual user edits to bundled \
         creatures will need to be re-applied.  Future bumps will \
         use the freshly-recorded hashes to skip user edits."
      );
    } else if counts.added > 0 || counts.refreshed > 0 || counts.preserved > 0 {
      info!(
        added = counts.added,
        refreshed = counts.refreshed,
        preserved = counts.preserved,
        from_version = disk_version,
        to_version = BUNDLED_VERSION,
        "applied bundle update to compendium"
      );
    }

    Ok(())
  }

  fn read_seed(&self) -> BundleSeed {
    let Ok(text) = std::fs::read_to_string(&self.seed_path) else {
      return BundleSeed::default();
    };
    serde_json::from_str::<BundleSeed>(&text).unwrap_or_else(|err| {
      warn!(
        error = %err,
        path = %self.seed_path.display(),
        "compendium bundle-seed file malformed; treating as version 0"
      );
      BundleSeed::default()
    })
  }

  fn write_seed(&self, seed: BundleSeed) -> Result<(), CompendiumStoreError> {
    let json = serde_json::to_string_pretty(&seed).map_err(|source| {
      CompendiumStoreError::BundleSeedParseError { source }
    })?;
    if let Some(parent) = self.seed_path.parent() {
      if !parent.as_os_str().is_empty() {
        std::fs::create_dir_all(parent)?;
      }
    }
    std::fs::write(&self.seed_path, json)?;
    Ok(())
  }

  pub async fn list(&self) -> Vec<Creature> {
    self.inner.read().await
  }

  pub async fn get(&self, id: &str) -> Option<Creature> {
    self.inner.read().await.into_iter().find(|c| c.id == id)
  }

  pub async fn insert(
    &self,
    draft: CreatureDraft,
  ) -> Result<Creature, CompendiumStoreError> {
    let now = epoch_millis();
    let creature = Creature {
      id: fresh_id(),
      name: draft.name,
      kind: draft.kind,
      size: draft.size,
      race: draft.race,
      subrace: draft.subrace,
      alignment: draft.alignment,
      source: draft.source,
      description: draft.description,
      armor_class: draft.armor_class,
      armor_class_note: draft.armor_class_note,
      max_hp: draft.max_hp,
      hp_formula: draft.hp_formula,
      initiative_bonus: draft.initiative_bonus,
      speed: draft.speed,
      abilities: draft.abilities,
      saving_throws: draft.saving_throws,
      skills: draft.skills,
      damage_vulnerabilities: draft.damage_vulnerabilities,
      damage_resistances: draft.damage_resistances,
      damage_immunities: draft.damage_immunities,
      condition_immunities: draft.condition_immunities,
      senses: draft.senses,
      languages: draft.languages,
      challenge_rating: draft.challenge_rating,
      xp: draft.xp,
      xp_in_lair: draft.xp_in_lair,
      proficiency_bonus: draft.proficiency_bonus,
      traits: draft.traits,
      actions: draft.actions,
      bonus_actions: draft.bonus_actions,
      reactions: draft.reactions,
      legendary_actions: draft.legendary_actions,
      lair_actions: draft.lair_actions,
      regional_effects: draft.regional_effects,
      spellcasting: draft.spellcasting,
      custom_sections: draft.custom_sections,
      habitats: draft.habitats,
      treasures: draft.treasures,
      tags: draft.tags,
      created_at: now,
      updated_at: now,
    };
    let to_return = creature.clone();
    self.inner.mutate(|all| all.push(creature)).await?;
    Ok(to_return)
  }

  pub async fn update(
    &self,
    id: &str,
    mut creature: Creature,
  ) -> Result<Creature, CompendiumStoreError> {
    if creature.id != id {
      return Err(CompendiumStoreError::CreatureIdMismatchError {
        path_id: id.to_string(),
        body_id: creature.id.clone(),
      });
    }
    creature.updated_at = epoch_millis();
    let id_owned = id.to_string();
    let result_creature = creature.clone();
    let updated = self
      .inner
      .mutate(move |all| {
        if let Some(slot) = all.iter_mut().find(|c| c.id == id_owned) {
          *slot = creature;
          true
        } else {
          false
        }
      })
      .await?;
    if updated {
      Ok(result_creature)
    } else {
      Err(CompendiumStoreError::CreatureIdNotFoundError { id: id.to_string() })
    }
  }

  pub async fn remove(&self, id: &str) -> Result<(), CompendiumStoreError> {
    let id_owned = id.to_string();
    let removed = self
      .inner
      .mutate(move |all| {
        let before = all.len();
        all.retain(|c| c.id != id_owned);
        before != all.len()
      })
      .await?;
    if removed {
      Ok(())
    } else {
      Err(CompendiumStoreError::CreatureIdNotFoundError { id: id.to_string() })
    }
  }

  pub async fn replace_all(
    &self,
    creatures: Vec<Creature>,
  ) -> Result<(), CompendiumStoreError> {
    self.inner.replace(creatures).await?;
    Ok(())
  }

  pub async fn reset_to_bundled(
    &self,
  ) -> Result<Vec<Creature>, CompendiumStoreError> {
    let bundled = parse_bundled()?;
    let to_return = bundled.clone();
    self.inner.replace(bundled.clone()).await?;
    // After a reset, the on-disk creatures match the embedded
    // bundle exactly — record the current version + a fresh hash
    // for each creature so the next bundle bump starts from a
    // known baseline.  Without this, the next startup would
    // re-run the merge (a no-op here, but wasteful) AND any
    // intervening edits would be treated as "no recorded hash"
    // first-migration cases.
    let hashes = bundled
      .iter()
      .map(|c| (c.id.clone(), content_hash(c)))
      .collect();
    self.write_seed(BundleSeed {
      version: BUNDLED_VERSION,
      hashes,
    })?;
    Ok(to_return)
  }
}

/// Compute the bundle-seed sidecar path from the creatures
/// file's path: same directory, same stem, `.bundle-seed.json`
/// suffix.  This way two stores in the same directory have
/// distinct seed files (matters for the integration tests,
/// which use random `NamedTempFile` paths in `/tmp`).
fn bundle_seed_path(creatures_path: &Path) -> PathBuf {
  let mut path = creatures_path.to_path_buf();
  let filename = path
    .file_name()
    .map(|s| s.to_string_lossy().into_owned())
    .unwrap_or_else(|| "compendium".to_string());
  path.set_file_name(format!("{filename}.bundle-seed.json"));
  path
}

/// Parse the embedded bundled JSON.  Failure here represents a
/// build-time misconfiguration (the JSON file went out of sync
/// with the schema) and surfaces as a 500 to the caller.
fn parse_bundled() -> Result<Vec<Creature>, CompendiumStoreError> {
  serde_json::from_str(BUNDLED_JSON)
    .map_err(|source| CompendiumStoreError::BundledParseError { source })
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(SystemTime::UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}

/// SHA-256 hex digest of a creature's serialized form.  Used by
/// the bundle-merge edit detector: if a creature's digest at boot
/// time matches the one we recorded the last time the bundle was
/// applied, the user hasn't edited it and we can safely refresh
/// from the new bundle.  A mismatch means a user edit happened
/// in between and the disk copy wins.
///
/// We hash the serialized JSON rather than a custom field
/// projection so any future schema addition is automatically
/// covered — every meaningful change to the creature's content
/// (including timestamps, which is fine: an `update()` call
/// bumps `updated_at` to "now", so an edited creature looks
/// different from the bundle even before we get to the
/// substantive fields).
///
/// Serialization failure is vanishingly unlikely (a Creature
/// always serialises) — the fallback `""` makes the digest
/// useless for that creature, which collapses to the
/// "treat as user-edited; preserve" branch.  That's the safe
/// default in case of trouble.
fn content_hash(c: &Creature) -> String {
  let json = serde_json::to_string(c).unwrap_or_default();
  let mut hasher = Sha256::new();
  hasher.update(json.as_bytes());
  format!("{:x}", hasher.finalize())
}
