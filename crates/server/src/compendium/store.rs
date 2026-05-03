//! File-backed compendium store.
//!
//! Thin wrapper around [`JsonFileStore<Vec<Creature>>`] from the
//! lib crate.  Adds compendium-specific concerns:
//!
//! - **Bootstrap**: on first launch (file absent) we seed the
//!   store with the bundled creatures embedded via `include_str!`.
//! - **Bundle versioning**: a sidecar `*.bundle-seed.json` file
//!   tracks the highest [`BUNDLED_VERSION`] we've ever merged
//!   into this store.  When the constant in source bumps past
//!   the recorded value, the next boot does an ADD-ONLY merge:
//!   any bundled creature whose stable id isn't already on disk
//!   gets added.  Existing creatures (whether earlier-bundled or
//!   user-created) are never touched.  This means new bundle
//!   releases ship new content without overwriting customs or
//!   user edits to previously-bundled creatures.
//! - **Id allocation**: server-side UUIDv4 on insert; stable
//!   hand-picked UUIDs on bundled creatures so the version-merge
//!   logic can reliably skip existing entries.
//! - **Timestamps**: `created_at` / `updated_at` set / advanced
//!   server-side so clients can't lie about them.
//! - **Reset**: restore the bundled set, discarding user edits.
//!   Also bumps the seed file to the current version.

use std::{
  path::{Path, PathBuf},
  sync::Arc,
  time::SystemTime,
};

use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};
use ezpz_dndz_lib::json_file_store::JsonFileStore;
use serde::{Deserialize, Serialize};
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
const BUNDLED_JSON: &str =
  include_str!("../../../lib/data/bundled-creatures.json");

/// Source-of-truth version for the bundled creature set.  Bump
/// this any time `bundled-creatures.json` changes — adding a
/// creature, fixing a typo on an existing one, etc.  The next
/// startup of any deployment that recorded a smaller value will
/// run an ADD-ONLY merge that backfills missing bundled
/// creatures (matched by their stable ids).
///
/// We don't store this inside the JSON itself because the JSON
/// shape doubles as the public Import / Export wire format; the
/// version is server-side metadata and lives in source.
pub const BUNDLED_VERSION: i32 = 1;

/// Sidecar metadata recording the highest bundled-version we've
/// merged into a given store.  Persisted as a tiny JSON file
/// alongside the creatures file so a rename / move of the data
/// directory carries it along automatically.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct BundleSeed {
  version: i32,
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
  /// recorded on disk, run an ADD-ONLY merge: each bundled
  /// creature whose stable id isn't already in the store gets
  /// pushed; existing creatures (bundled-but-edited, or
  /// user-created) are left alone.  Then bump the seed file.
  ///
  /// Empty store + missing seed file is the fresh-install path
  /// — every bundled creature gets added, and the seed records
  /// the current version.
  async fn maybe_apply_bundle(&self) -> Result<(), CompendiumStoreError> {
    let disk_version = self.read_seed_version();
    if BUNDLED_VERSION <= disk_version {
      return Ok(());
    }
    let bundle = parse_bundled()?;
    let added = self
      .inner
      .mutate(move |all| {
        let mut count = 0;
        for bundled in bundle {
          if !all.iter().any(|c| c.id == bundled.id) {
            all.push(bundled);
            count += 1;
          }
        }
        count
      })
      .await?;
    if added > 0 {
      info!(
        added,
        from_version = disk_version,
        to_version = BUNDLED_VERSION,
        "merged new bundled creatures into compendium"
      );
    }
    self.write_seed_version(BUNDLED_VERSION)?;
    Ok(())
  }

  fn read_seed_version(&self) -> i32 {
    match std::fs::read_to_string(&self.seed_path) {
      Ok(text) => match serde_json::from_str::<BundleSeed>(&text) {
        Ok(seed) => seed.version,
        Err(err) => {
          warn!(
            error = %err,
            path = %self.seed_path.display(),
            "compendium bundle-seed file malformed; treating as version 0"
          );
          0
        }
      },
      Err(_) => 0,
    }
  }

  fn write_seed_version(
    &self,
    version: i32,
  ) -> Result<(), CompendiumStoreError> {
    let seed = BundleSeed { version };
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
    self.inner.replace(bundled).await?;
    // After a reset, the on-disk creatures match the embedded
    // bundle exactly — so the seed file should record the
    // current version.  Without this bump, the next startup
    // would incorrectly conclude "we have an older bundle" and
    // re-run the merge (a no-op in this case, but wasteful and
    // potentially confusing if log messages fire).
    self.write_seed_version(BUNDLED_VERSION)?;
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
