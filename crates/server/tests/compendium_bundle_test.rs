//! Integration tests for the compendium bundle-version logic.
//!
//! Covers the four states the version-aware bootstrap can land in:
//!
//! 1. Fresh install (no creatures, no seed) → full bootstrap.
//! 2. Re-launch at the same version → no-op.
//! 3. Migration (creatures exist with non-bundled ids, no seed) →
//!    ADD-ONLY merge adds the full bundle alongside customs.
//! 4. `reset_to_bundled` → bumps the seed file to current.

// File-level override: `allow-expect-in-tests` only covers items
// inside `#[test]` / `#[cfg(test)]`; helpers at crate scope here use
// `expect` for setup that should panic on failure.
#![allow(clippy::expect_used, clippy::unwrap_used)]

use ezpz_dndz_server::compendium::CompendiumStore;
use serde_json::json;
use std::path::PathBuf;
use tempfile::TempDir;

/// Stable id of one bundled creature ("Goblin Warrior").
/// Hard-coded to verify the version-merge is matching by id,
/// not by name — renaming a bundled entry should NOT cause the
/// merge to add a duplicate.
///
/// Bundled UUIDs are derived deterministically via UUIDv5 from
/// the source slug (`stable_uuid_from_key("goblin-warrior")`),
/// so re-harvesting from Open5e produces the same id and this
/// constant stays valid.
const BUNDLED_GOBLIN_ID: &str = "77616fb2-b1c8-5d2f-9f07-f8956b40743a";

/// Stable id of one larger bundled creature ("Young White
/// Dragon"), used for the second-creature checks.
const BUNDLED_YOUNG_WHITE_DRAGON_ID: &str =
  "86800bb0-c035-50ff-a4d0-9d783fecbf71";

/// Lower bound on the bundled-creature count.  The full SRD-2024
/// harvest carries ~330; we assert a floor rather than an exact
/// number so re-harvests that pick up a creature or two don't
/// break the test.
const MIN_BUNDLED_COUNT: usize = 300;

fn temp_creatures_path() -> (TempDir, PathBuf) {
  let dir = TempDir::new().expect("tempdir");
  let path = dir.path().join("creatures.json");
  (dir, path)
}

#[tokio::test]
async fn fresh_install_bootstraps_full_bundle() {
  let (_dir, path) = temp_creatures_path();
  let store = CompendiumStore::load_or_bootstrap(path.clone())
    .await
    .expect("bootstrap");
  let creatures = store.list().await;
  assert!(
    creatures.len() >= MIN_BUNDLED_COUNT,
    "expected at least {MIN_BUNDLED_COUNT} bundled creatures on fresh \
     install, got {}",
    creatures.len(),
  );
  assert!(
    creatures.iter().any(|c| c.id == BUNDLED_GOBLIN_ID),
    "bundled Goblin Warrior should appear by stable id"
  );
  assert!(
    creatures
      .iter()
      .any(|c| c.id == BUNDLED_YOUNG_WHITE_DRAGON_ID),
    "expected the high-CR dragon to land too"
  );
  // Seed file gets written sibling to the creatures file.
  let seed_path = path.with_file_name("creatures.json.bundle-seed.json");
  assert!(seed_path.exists(), "seed sidecar should be written");
}

#[tokio::test]
async fn relaunch_at_same_version_is_noop() {
  let (_dir, path) = temp_creatures_path();
  // First launch: seeds the full bundle.
  let _ = CompendiumStore::load_or_bootstrap(path.clone())
    .await
    .expect("bootstrap-1");
  let after_first = std::fs::read_to_string(&path).expect("read after 1st");
  // Second launch: same version on disk and in source → nothing
  // added.
  let _ = CompendiumStore::load_or_bootstrap(path.clone())
    .await
    .expect("bootstrap-2");
  let after_second = std::fs::read_to_string(&path).expect("read after 2nd");
  assert_eq!(
    after_first, after_second,
    "second launch should NOT re-merge or duplicate creatures"
  );
}

#[tokio::test]
async fn migration_from_legacy_bundle_preserves_customs() {
  // Simulate a deployment that's been running with the OLD bundle
  // (random-uuid creatures) PLUS one custom user creature.  When
  // we add the BUNDLED_VERSION constant and bump it on a new
  // release, the next boot should ADD the new bundle creatures
  // without touching the existing on-disk content.
  let (_dir, path) = temp_creatures_path();
  let legacy_creature_id = "deadbeef-0000-4000-a000-000000000001";
  let custom_creature_id = "feedface-0000-4000-a000-000000000002";
  let legacy = json!([
    {
      "id": legacy_creature_id,
      "name": "Old Bundle Goblin",
      "kind": "enemy",
      "size": "small",
      "race": "Humanoid",
      "subrace": "",
      "alignment": "neutral evil",
      "source": "Bundled (old)",
      "description": "",
      "armor_class": 15,
      "armor_class_note": "",
      "max_hp": 7,
      "hp_formula": "",
      "initiative_bonus": 0,
      "speed": {"walk": 30, "fly": 0, "swim": 0, "climb": 0, "burrow": 0, "hover": false},
      "abilities": {"str": 8, "dex": 14, "con": 10, "int": 10, "wis": 8, "cha": 8},
      "senses": {"blindsight": 0, "darkvision": 0, "tremorsense": 0, "truesight": 0, "passive_perception": 10},
      "challenge_rating": "1/4",
      "xp": 50,
      "proficiency_bonus": 2,
      "created_at": 0,
      "updated_at": 0
    },
    {
      "id": custom_creature_id,
      "name": "User's Pet Slime",
      "kind": "enemy",
      "size": "medium",
      "race": "Ooze",
      "subrace": "",
      "alignment": "unaligned",
      "source": "Custom",
      "description": "",
      "armor_class": 8,
      "armor_class_note": "",
      "max_hp": 15,
      "hp_formula": "",
      "initiative_bonus": 0,
      "speed": {"walk": 10, "fly": 0, "swim": 0, "climb": 0, "burrow": 0, "hover": false},
      "abilities": {"str": 8, "dex": 6, "con": 14, "int": 1, "wis": 6, "cha": 1},
      "senses": {"blindsight": 60, "darkvision": 0, "tremorsense": 0, "truesight": 0, "passive_perception": 8},
      "challenge_rating": "1/4",
      "xp": 50,
      "proficiency_bonus": 2,
      "created_at": 0,
      "updated_at": 0
    }
  ]);
  std::fs::write(&path, serde_json::to_string_pretty(&legacy).unwrap())
    .expect("seed legacy file");

  // No seed sidecar → load_or_bootstrap concludes "we've never
  // applied a bundle here" and runs the merge.
  let store = CompendiumStore::load_or_bootstrap(path.clone())
    .await
    .expect("bootstrap-after-legacy");
  let after = store.list().await;
  assert!(
    after.len() >= 2 + MIN_BUNDLED_COUNT,
    "expected the 2 legacy creatures to stay AND the full bundle to be \
     added; got {} (need >= {})",
    after.len(),
    2 + MIN_BUNDLED_COUNT,
  );
  // Legacy creatures preserved by id.
  assert!(
    after.iter().any(|c| c.id == legacy_creature_id),
    "legacy Old Bundle Goblin should NOT have been removed"
  );
  assert!(
    after.iter().any(|c| c.id == custom_creature_id),
    "user-created custom creature should NOT have been removed"
  );
  // New bundled creatures present.
  assert!(
    after.iter().any(|c| c.id == BUNDLED_GOBLIN_ID),
    "new bundled Goblin should have been added"
  );
}

#[tokio::test]
async fn reset_to_bundled_writes_seed() {
  let (_dir, path) = temp_creatures_path();
  // Boot, then have the user delete the seed sidecar to simulate
  // pre-existing state without a recorded version.
  let store = CompendiumStore::load_or_bootstrap(path.clone())
    .await
    .expect("bootstrap");
  let seed_path = path.with_file_name("creatures.json.bundle-seed.json");
  std::fs::remove_file(&seed_path).ok();
  // Reset to bundled rewrites both the creatures AND the seed.
  let _ = store.reset_to_bundled().await.expect("reset");
  assert!(seed_path.exists(), "reset_to_bundled should write the seed sidecar");
}

#[tokio::test]
async fn bundle_creatures_use_stable_uuids() {
  // Belt-and-braces sanity check: bundled creatures get UUIDv5
  // ids derived from their Open5e source slugs, so re-harvesting
  // produces identical ids and the version-merge logic stays
  // consistent.  A future bundle change that accidentally
  // regenerated random UUIDs would break the migration logic;
  // this test would catch it.
  let (_dir, path) = temp_creatures_path();
  let store = CompendiumStore::load_or_bootstrap(path)
    .await
    .expect("bootstrap");
  let creatures = store.list().await;
  let mut ids: Vec<String> = creatures.iter().map(|c| c.id.clone()).collect();
  ids.sort();
  assert!(
    ids.iter().any(|id| id == BUNDLED_GOBLIN_ID),
    "stable Goblin Warrior id missing — re-harvest produced different UUIDs"
  );
  assert!(
    ids.iter().any(|id| id == BUNDLED_YOUNG_WHITE_DRAGON_ID),
    "stable Young White Dragon id missing"
  );
  // No collisions in the bundled set.
  let unique_count = creatures
    .iter()
    .map(|c| c.id.as_str())
    .collect::<std::collections::HashSet<_>>()
    .len();
  assert_eq!(unique_count, creatures.len(), "bundled ids must be unique");
}
