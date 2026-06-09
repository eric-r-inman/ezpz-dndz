//! Per-user compendium **creature** store.
//!
//! Each authenticated user owns their own set of compendium
//! creatures — anything they create, import, or duplicate from a
//! bundled creature.  Bundled (SRD) creatures live in
//! [`super::bundled::BundledCompendium`] and are shared read-only
//! across users; this store handles the mutable per-user layer
//! that overlays them.
//!
//! Disk shape is `HashMap<UserId, Vec<Creature>>` in a single
//! JSON file backed by [`JsonFileStore`].  Mirrors
//! [`CompendiumGroupStore`](super::groups::CompendiumGroupStore)
//! in disk layout and locking discipline; the difference is just
//! the body type (creatures vs groups).

use std::{
  collections::HashMap,
  path::PathBuf,
  sync::Arc,
  time::{SystemTime, UNIX_EPOCH},
};

use ezpz_dndz_lib::{
  compendium::{Creature, CreatureDraft},
  json_file_store::JsonFileStore,
  users::UserId,
};
use uuid::Uuid;

use super::error::CompendiumStoreError;

#[derive(Clone)]
pub struct UserCompendiumStore {
  inner: Arc<JsonFileStore<HashMap<UserId, Vec<Creature>>>>,
}

impl UserCompendiumStore {
  pub async fn load_or_default(
    path: PathBuf,
  ) -> Result<Self, CompendiumStoreError> {
    let inner =
      JsonFileStore::<HashMap<UserId, Vec<Creature>>>::load_or_default(path)
        .await?;
    Ok(Self {
      inner: Arc::new(inner),
    })
  }

  pub async fn list(&self, user_id: &UserId) -> Vec<Creature> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .cloned()
      .unwrap_or_default()
  }

  pub async fn get(&self, user_id: &UserId, id: &str) -> Option<Creature> {
    self
      .inner
      .read()
      .await
      .get(user_id)
      .and_then(|cs| cs.iter().find(|c| c.id == id).cloned())
  }

  /// Allocate a fresh UUIDv4 id + timestamps, append to this user's
  /// list, return the materialised `Creature` so the client doesn't
  /// have to GET to learn what the server picked.
  pub async fn insert(
    &self,
    user_id: &UserId,
    draft: CreatureDraft,
  ) -> Result<Creature, CompendiumStoreError> {
    let now = epoch_millis();
    let creature = creature_from_draft(draft, Uuid::new_v4().to_string(), now);
    let user_id_owned = user_id.clone();
    let to_return = creature.clone();
    self
      .inner
      .mutate(move |all| {
        all.entry(user_id_owned).or_default().push(creature);
      })
      .await?;
    Ok(to_return)
  }

  /// Insert a fully-materialised creature (id already chosen,
  /// timestamps already stamped).  Used by the migration path that
  /// moves legacy shared-store creatures into a designated user's
  /// per-user list.  Plain CRUD callers should use
  /// [`Self::insert`].
  pub async fn insert_raw(
    &self,
    user_id: &UserId,
    creature: Creature,
  ) -> Result<(), CompendiumStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.entry(user_id_owned).or_default().push(creature);
      })
      .await?;
    Ok(())
  }

  /// Replace the user's creature at `id` with the supplied record.
  /// `created_at` is preserved server-side; `updated_at` is bumped.
  /// Errors with `CreatureIdMismatchError` if the body id disagrees
  /// with the path id, and `CreatureIdNotFoundError` if no such
  /// creature exists for this user.  Callers that need to reject
  /// bundled-id writes should check
  /// [`super::bundled::BundledCompendium::contains`] before
  /// reaching this method.
  pub async fn update(
    &self,
    user_id: &UserId,
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
    let user_id_owned = user_id.clone();
    let outcome = self
      .inner
      .mutate(move |all| {
        let list = all.entry(user_id_owned).or_default();
        list.iter_mut().find(|c| c.id == id_owned).map(|slot| {
          let preserved_created_at = slot.created_at;
          *slot = creature;
          slot.created_at = preserved_created_at;
          slot.clone()
        })
      })
      .await?;
    outcome.ok_or_else(|| CompendiumStoreError::CreatureIdNotFoundError {
      id: id.to_string(),
    })
  }

  pub async fn remove(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<(), CompendiumStoreError> {
    let id_owned = id.to_string();
    let user_id_owned = user_id.clone();
    let removed = self
      .inner
      .mutate(move |all| {
        let list = all.entry(user_id_owned).or_default();
        let before = list.len();
        list.retain(|c| c.id != id_owned);
        before != list.len()
      })
      .await?;
    if removed {
      Ok(())
    } else {
      Err(CompendiumStoreError::CreatureIdNotFoundError { id: id.to_string() })
    }
  }

  /// Replace this user's entire creature list with `creatures`.
  /// Used by the reset-to-bundled path (empty `creatures`) and by
  /// full-compendium import (the user uploaded a JSON export).
  /// Server preserves nothing — what you send is what's on disk
  /// for this user.
  pub async fn replace_for_user(
    &self,
    user_id: &UserId,
    creatures: Vec<Creature>,
  ) -> Result<(), CompendiumStoreError> {
    let user_id_owned = user_id.clone();
    self
      .inner
      .mutate(move |all| {
        all.insert(user_id_owned, creatures);
      })
      .await?;
    Ok(())
  }
}

fn creature_from_draft(draft: CreatureDraft, id: String, now: i64) -> Creature {
  Creature {
    id,
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
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}
