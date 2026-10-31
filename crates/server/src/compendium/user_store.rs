//! Per-user compendium **creature** store, relational edition.
//!
//! Each authenticated user owns their own set of compendium
//! creatures — anything they create, import, or duplicate from a
//! bundled creature.  Bundled (SRD) creatures live in
//! [`super::bundled::BundledCompendium`] and are shared read-only
//! across users; this store handles the mutable per-user layer
//! that overlays them.
//!
//! Storage is the `user_creatures` table family (migration 0003)
//! through the row codec in [`super::creature_rows`]; the legacy
//! `HashMap<UserId, Vec<Creature>>` JSON file is now only read by
//! the one-shot boot import.  List order round-trips through the
//! per-user `position` column, and the legacy Vec semantics are
//! preserved deliberately: duplicate wire ids within a user are
//! tolerated (`get`/`update` address the first by position, `remove`
//! drops them all), matching what the JSON store did with
//! `find` / `retain`.

use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

use ezpz_dndz_lib::{
  compendium::{Creature, CreatureDraft},
  db::Db,
  users::UserId,
};
use uuid::Uuid;

use super::creature_rows::{fetch_creatures, insert_creature, CreatureRow};
use super::error::CompendiumStoreError;

#[derive(Clone)]
pub struct UserCompendiumStore {
  db: Db,
}

impl UserCompendiumStore {
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  async fn rows(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<CreatureRow>, CompendiumStoreError> {
    let mut conn = self
      .db
      .pool()
      .acquire()
      .await
      .map_err(|source| CompendiumStoreError::CreatureRowsRead { source })?;
    fetch_creatures(&mut conn, user_id.as_str()).await
  }

  pub async fn list(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<Creature>, CompendiumStoreError> {
    Ok(
      self
        .rows(user_id)
        .await?
        .into_iter()
        .map(|r| r.creature)
        .collect(),
    )
  }

  pub async fn get(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<Option<Creature>, CompendiumStoreError> {
    Ok(
      self
        .rows(user_id)
        .await?
        .into_iter()
        .find(|r| r.creature.id == id)
        .map(|r| r.creature),
    )
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
    self.insert_raw(user_id, creature.clone()).await?;
    Ok(creature)
  }

  /// Insert a fully-materialised creature (id already chosen,
  /// timestamps already stamped).  Used by the duplicate endpoint
  /// and by the split migration that moves legacy shared-store
  /// creatures into a designated user's list.  Plain CRUD callers
  /// should use [`Self::insert`].
  pub async fn insert_raw(
    &self,
    user_id: &UserId,
    creature: Creature,
  ) -> Result<(), CompendiumStoreError> {
    let mut tx = self.begin().await?;
    let position = next_position(&mut tx, user_id).await?;
    insert_creature(&mut tx, user_id.as_str(), position, &creature).await?;
    commit(tx).await
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

    let mut tx = self.begin().await?;

    // The first row (by position) with this wire id, mirroring the
    // legacy Vec's `find`.  Delete-and-reinsert lets the whole child
    // family swap atomically while keeping the row's list slot and
    // original created_at.
    let existing = fetch_creatures(&mut tx, user_id.as_str())
      .await?
      .into_iter()
      .find(|r| r.creature.id == id)
      .ok_or_else(|| CompendiumStoreError::CreatureIdNotFoundError {
        id: id.to_string(),
      })?;

    creature.created_at = existing.creature.created_at;

    sqlx::query("DELETE FROM user_creatures WHERE row_id = $1")
      .bind(&existing.row_id)
      .execute(&mut *tx)
      .await
      .map_err(|source| CompendiumStoreError::CreatureRowsWrite { source })?;
    insert_creature(&mut tx, user_id.as_str(), existing.position, &creature)
      .await?;

    commit(tx).await?;
    Ok(creature)
  }

  pub async fn remove(
    &self,
    user_id: &UserId,
    id: &str,
  ) -> Result<(), CompendiumStoreError> {
    let result = sqlx::query(
      "DELETE FROM user_creatures WHERE user_id = $1 AND creature_id = $2",
    )
    .bind(user_id.as_str())
    .bind(id)
    .execute(self.db.pool())
    .await
    .map_err(|source| CompendiumStoreError::CreatureRowsWrite { source })?;
    if result.rows_affected() > 0 {
      Ok(())
    } else {
      Err(CompendiumStoreError::CreatureIdNotFoundError { id: id.to_string() })
    }
  }

  /// Append `creatures` to this user's list and keep what is there.
  /// Sign-in uses it to carry a signed-out session's work into the
  /// account.  A creature made while signed out has no creation time.
  /// It takes the time it joins the account.
  pub async fn append_for_user(
    &self,
    user_id: &UserId,
    creatures: Vec<Creature>,
  ) -> Result<(), CompendiumStoreError> {
    let now = epoch_millis();
    let mut tx = self.begin().await?;
    let first = next_position(&mut tx, user_id).await?;
    for (i, creature) in creatures.into_iter().enumerate() {
      let stamped = Creature {
        created_at: if creature.created_at > 0 {
          creature.created_at
        } else {
          now
        },
        updated_at: now,
        ..creature
      };
      insert_creature(&mut tx, user_id.as_str(), first + i as i64, &stamped)
        .await?;
    }
    commit(tx).await
  }

  /// Replace this user's entire creature list with `creatures`.
  /// Full-compendium import uses it to load a JSON export.  The
  /// server preserves nothing.  What the caller sends is what
  /// persists for this user.
  pub async fn replace_for_user(
    &self,
    user_id: &UserId,
    creatures: Vec<Creature>,
  ) -> Result<(), CompendiumStoreError> {
    let mut tx = self.begin().await?;
    write_creatures(&mut tx, user_id, &creatures).await?;
    commit(tx).await
  }

  /// The bundled creature ids this user has hidden from their list.
  pub async fn hidden_bundled(
    &self,
    user_id: &UserId,
  ) -> Result<HashSet<String>, CompendiumStoreError> {
    sqlx::query_scalar::<_, String>(
      "SELECT creature_id FROM compendium_hidden_bundled WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map(|ids| ids.into_iter().collect())
    .map_err(|source| CompendiumStoreError::HiddenBundledRead { source })
  }

  /// Make this user's library exactly `creatures` plus every bundled
  /// creature outside `hidden`.  One transaction writes both.  A reader
  /// never sees one without the other.  A reset keeps nothing
  /// and hides nothing.
  pub async fn keep(
    &self,
    user_id: &UserId,
    creatures: Vec<Creature>,
    hidden: Vec<String>,
  ) -> Result<(), CompendiumStoreError> {
    let mut tx = self.begin().await?;
    write_creatures(&mut tx, user_id, &creatures).await?;
    sqlx::query("DELETE FROM compendium_hidden_bundled WHERE user_id = $1")
      .bind(user_id.as_str())
      .execute(&mut *tx)
      .await
      .map_err(|source| CompendiumStoreError::HiddenBundledWrite { source })?;
    for id in &hidden {
      sqlx::query(
        "INSERT INTO compendium_hidden_bundled (user_id, creature_id) \
         VALUES ($1, $2)",
      )
      .bind(user_id.as_str())
      .bind(id)
      .execute(&mut *tx)
      .await
      .map_err(|source| CompendiumStoreError::HiddenBundledWrite { source })?;
    }
    commit(tx).await
  }

  async fn begin(
    &self,
  ) -> Result<sqlx::Transaction<'static, sqlx::Any>, CompendiumStoreError> {
    self.db.pool().begin().await.map_err(|source| {
      CompendiumStoreError::TransactionBegin {
        store: "creature",
        source,
      }
    })
  }
}

async fn write_creatures(
  tx: &mut sqlx::Transaction<'static, sqlx::Any>,
  user_id: &UserId,
  creatures: &[Creature],
) -> Result<(), CompendiumStoreError> {
  sqlx::query("DELETE FROM user_creatures WHERE user_id = $1")
    .bind(user_id.as_str())
    .execute(&mut **tx)
    .await
    .map_err(|source| CompendiumStoreError::CreatureRowsWrite { source })?;
  for (i, creature) in creatures.iter().enumerate() {
    insert_creature(tx, user_id.as_str(), i as i64, creature).await?;
  }
  Ok(())
}

async fn commit(
  tx: sqlx::Transaction<'static, sqlx::Any>,
) -> Result<(), CompendiumStoreError> {
  tx.commit()
    .await
    .map_err(|source| CompendiumStoreError::TransactionCommit {
      store: "creature",
      source,
    })
}

/// The next free list slot for this user (appends go at the end,
/// like the legacy Vec push).
async fn next_position(
  conn: &mut sqlx::AnyConnection,
  user_id: &UserId,
) -> Result<i64, CompendiumStoreError> {
  sqlx::query_scalar::<_, i64>(
    "SELECT COALESCE(MAX(position) + 1, 0) FROM user_creatures \
     WHERE user_id = $1",
  )
  .bind(user_id.as_str())
  .fetch_one(&mut *conn)
  .await
  .map_err(|source| CompendiumStoreError::CreatureRowsRead { source })
}

pub(crate) fn creature_from_draft(
  draft: CreatureDraft,
  id: String,
  now: i64,
) -> Creature {
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
    loot: draft.loot,
    created_at: now,
    updated_at: now,
    is_bundled: false,
    has_special_reactions: draft.has_special_reactions,
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map_or(0, |d| d.as_millis() as i64)
}
