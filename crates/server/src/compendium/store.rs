//! File-backed compendium store.
//!
//! Thin wrapper around [`JsonFileStore<Vec<Creature>>`] from the
//! lib crate.  Adds compendium-specific concerns:
//!
//! - **Bootstrap**: on first launch (file absent) we seed the
//!   store with the bundled creatures embedded via `include_str!`.
//! - **Id allocation**: server-side UUIDv4 on insert.
//! - **Timestamps**: `created_at` / `updated_at` set / advanced
//!   server-side so clients can't lie about them.
//! - **Reset**: restore the bundled set, discarding user edits.

use std::{path::PathBuf, sync::Arc, time::SystemTime};

use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};
use ezpz_dndz_lib::json_file_store::JsonFileStore;
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

#[derive(Clone)]
pub struct CompendiumStore {
  inner: Arc<JsonFileStore<Vec<Creature>>>,
}

impl CompendiumStore {
  /// Open the store at `path`.  If the file is absent, write the
  /// bundled set out so the user can browse a non-empty compendium
  /// on first load.
  pub async fn load_or_bootstrap(
    path: PathBuf,
  ) -> Result<Self, CompendiumStoreError> {
    let inner = JsonFileStore::<Vec<Creature>>::load_or_default(path).await?;
    let needs_bootstrap = inner.read().await.is_empty();
    if needs_bootstrap {
      let bundled = parse_bundled()?;
      inner.replace(bundled).await?;
    }
    Ok(Self {
      inner: Arc::new(inner),
    })
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
    Ok(to_return)
  }
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
