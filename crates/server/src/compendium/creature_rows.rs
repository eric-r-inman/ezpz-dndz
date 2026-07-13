//! `Creature` ↔ relational rows codec (migration 0003).
//!
//! Shared by [`super::user_store::UserCompendiumStore`] and the
//! one-shot JSON boot import in `crate::json_import`.  The serde
//! shape of [`Creature`] is the wire spec (the Elm decoders mirror
//! it), so this module round-trips exactly: every scalar lands in a
//! `user_creatures` column, every list in a child table ordered by
//! `position`, and the four `Option` sub-records flatten to column
//! packs that are all NULL together when absent.
//!
//! Enum tokens (kind, size, ability, habitat, treasure, usage kind)
//! are stored as their serde wire spellings and converted through
//! serde itself, so a rename in `types.rs` cannot silently diverge
//! from what these tables hold.
//!
//! Rows are written only by this codec; a row that fails to decode
//! back into a `Creature` therefore indicates schema corruption and
//! surfaces as a semantic error rather than being silently patched.
//!
//! Fetches reassemble a user's whole creature list (one batch query
//! per table, stitched by surrogate row id); single-creature lookups
//! filter the assembled list.  At the homelab scale this serves, a
//! user's list is small and the constant query count beats per-id
//! SQL that would need backend-specific NULL-parameter tricks.

use std::collections::HashMap;

use ezpz_dndz_lib::compendium::{
  Abilities, Ability, AbilitySave, Creature, CreatureKind, CustomSection,
  Feature, Habitat, InnatePerDay, LairActions, LegendaryActions,
  LegendaryOption, RegionalEffects, Senses, Size, SkillBonus, Speed,
  SpellSlotLevel, Spellcasting, Treasure, Usage,
};
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;
use sqlx::{any::AnyRow, AnyConnection, Row};
use uuid::Uuid;

use super::error::CompendiumStoreError;

/// The wire spelling of a unit-ish serde enum value ("enemy",
/// "gargantuan", "astral-plane", …).  Total for the enums used
/// here — they all serialize to plain JSON strings.
fn enum_token<T: Serialize>(value: &T) -> String {
  serde_json::to_value(value)
    .ok()
    .and_then(|v| v.as_str().map(str::to_string))
    .unwrap_or_default()
}

/// Parse a stored wire token back into its serde enum.  Fails with
/// a row-decode error naming the token, since the tables are only
/// ever written by [`enum_token`].
fn parse_token<T: DeserializeOwned>(
  token: &str,
  what: &str,
) -> Result<T, CompendiumStoreError> {
  serde_json::from_value(Value::String(token.to_string())).map_err(|_| {
    CompendiumStoreError::CreatureRowDecode {
      detail: format!("unknown {what} token {token:?}"),
    }
  })
}

fn read_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::CreatureRowsRead { source }
}

fn write_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::CreatureRowsWrite { source }
}

fn decode_error(detail: String) -> CompendiumStoreError {
  CompendiumStoreError::CreatureRowDecode { detail }
}

// ── insert ───────────────────────────────────────────────────────────────────

/// Insert one creature (parent row + every child list) for `user_id`
/// at list `position`.  Takes a bare connection so callers control
/// the transaction.
pub async fn insert_creature(
  conn: &mut AnyConnection,
  user_id: &str,
  position: i64,
  creature: &Creature,
) -> Result<(), CompendiumStoreError> {
  let row_id = Uuid::new_v4().to_string();
  let legendary = creature.legendary_actions.as_ref();
  let lair = creature.lair_actions.as_ref();
  let regional = creature.regional_effects.as_ref();
  let spellcasting = creature.spellcasting.as_ref();

  sqlx::query(
    "INSERT INTO user_creatures (row_id, user_id, position, creature_id, \
     name, kind, size, race, subrace, alignment, source, description, \
     armor_class, armor_class_note, max_hp, hp_formula, initiative_bonus, \
     speed_walk, speed_fly, speed_swim, speed_climb, speed_burrow, \
     speed_hover, ability_str, ability_dex, ability_con, ability_int, \
     ability_wis, ability_cha, senses_blindsight, senses_darkvision, \
     senses_tremorsense, senses_truesight, passive_perception, \
     challenge_rating, xp, xp_in_lair, proficiency_bonus, legendary_uses, \
     legendary_uses_in_lair, legendary_description, lair_initiative, \
     lair_description, regional_description, regional_fade_after, \
     spellcasting_ability, spellcasting_description, spellcasting_save_dc, \
     spellcasting_attack_bonus, created_at, updated_at, \
     has_special_reactions) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
     $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, \
     $29, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $40, $41, $42, \
     $43, $44, $45, $46, $47, $48, $49, $50, $51, $52)",
  )
  .bind(&row_id)
  .bind(user_id)
  .bind(position)
  .bind(&creature.id)
  .bind(&creature.name)
  .bind(enum_token(&creature.kind))
  .bind(enum_token(&creature.size))
  .bind(&creature.race)
  .bind(&creature.subrace)
  .bind(&creature.alignment)
  .bind(&creature.source)
  .bind(&creature.description)
  .bind(i64::from(creature.armor_class))
  .bind(&creature.armor_class_note)
  .bind(i64::from(creature.max_hp))
  .bind(&creature.hp_formula)
  .bind(i64::from(creature.initiative_bonus))
  .bind(i64::from(creature.speed.walk))
  .bind(i64::from(creature.speed.fly))
  .bind(i64::from(creature.speed.swim))
  .bind(i64::from(creature.speed.climb))
  .bind(i64::from(creature.speed.burrow))
  .bind(i64::from(creature.speed.hover))
  .bind(i64::from(creature.abilities.str))
  .bind(i64::from(creature.abilities.dex))
  .bind(i64::from(creature.abilities.con))
  .bind(i64::from(creature.abilities.int))
  .bind(i64::from(creature.abilities.wis))
  .bind(i64::from(creature.abilities.cha))
  .bind(i64::from(creature.senses.blindsight))
  .bind(i64::from(creature.senses.darkvision))
  .bind(i64::from(creature.senses.tremorsense))
  .bind(i64::from(creature.senses.truesight))
  .bind(i64::from(creature.senses.passive_perception))
  .bind(&creature.challenge_rating)
  .bind(creature.xp)
  .bind(creature.xp_in_lair)
  .bind(i64::from(creature.proficiency_bonus))
  .bind(legendary.map(|l| i64::from(l.uses)))
  .bind(legendary.map(|l| i64::from(l.uses_in_lair)))
  .bind(legendary.map(|l| l.description.clone()))
  .bind(lair.map(|l| i64::from(l.initiative)))
  .bind(lair.map(|l| l.description.clone()))
  .bind(regional.map(|r| r.description.clone()))
  .bind(regional.map(|r| r.fade_after.clone()))
  .bind(spellcasting.map(|s| enum_token(&s.ability)))
  .bind(spellcasting.map(|s| s.description.clone()))
  .bind(spellcasting.map(|s| i64::from(s.save_dc)))
  .bind(spellcasting.map(|s| i64::from(s.attack_bonus)))
  .bind(creature.created_at)
  .bind(creature.updated_at)
  .bind(i64::from(creature.has_special_reactions))
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;

  for (i, save) in creature.saving_throws.iter().enumerate() {
    sqlx::query(
      "INSERT INTO user_creature_saving_throws (creature_row_id, position, \
       ability, bonus) VALUES ($1, $2, $3, $4)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(enum_token(&save.ability))
    .bind(i64::from(save.bonus))
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (i, skill) in creature.skills.iter().enumerate() {
    sqlx::query(
      "INSERT INTO user_creature_skills (creature_row_id, position, name, \
       bonus) VALUES ($1, $2, $3, $4)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(&skill.name)
    .bind(i64::from(skill.bonus))
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (relation, values) in [
    ("vulnerability", &creature.damage_vulnerabilities),
    ("resistance", &creature.damage_resistances),
    ("immunity", &creature.damage_immunities),
    ("condition_immunity", &creature.condition_immunities),
  ] {
    for (i, value) in values.iter().enumerate() {
      sqlx::query(
        "INSERT INTO user_creature_damage_relations (creature_row_id, \
         relation, position, value) VALUES ($1, $2, $3, $4)",
      )
      .bind(&row_id)
      .bind(relation)
      .bind(i as i64)
      .bind(value)
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
    }
  }

  let habitat_tokens: Vec<String> =
    creature.habitats.iter().map(enum_token).collect();
  let treasure_tokens: Vec<String> =
    creature.treasures.iter().map(enum_token).collect();
  for (list_kind, values) in [
    ("language", &creature.languages),
    ("habitat", &habitat_tokens),
    ("treasure", &treasure_tokens),
    ("tag", &creature.tags),
    ("loot", &creature.loot),
  ] {
    for (i, value) in values.iter().enumerate() {
      sqlx::query(
        "INSERT INTO user_creature_strings (creature_row_id, list_kind, \
         position, value) VALUES ($1, $2, $3, $4)",
      )
      .bind(&row_id)
      .bind(list_kind)
      .bind(i as i64)
      .bind(value)
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
    }
  }

  let no_features: Vec<Feature> = Vec::new();
  for (feature_group, features) in [
    ("trait", &creature.traits),
    ("action", &creature.actions),
    ("bonus_action", &creature.bonus_actions),
    ("reaction", &creature.reactions),
    ("lair_option", lair.map_or(&no_features, |l| &l.options)),
    ("regional_effect", regional.map_or(&no_features, |r| &r.effects)),
  ] {
    for (i, feature) in features.iter().enumerate() {
      insert_feature(conn, &row_id, feature_group, i as i64, feature).await?;
    }
  }

  let no_options: Vec<LegendaryOption> = Vec::new();
  for (i, option) in legendary
    .map_or(&no_options, |l| &l.options)
    .iter()
    .enumerate()
  {
    sqlx::query(
      "INSERT INTO user_creature_legendary_options (creature_row_id, \
       position, name, cost, description) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(&option.name)
    .bind(i64::from(option.cost))
    .bind(&option.description)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (i, section) in creature.custom_sections.iter().enumerate() {
    sqlx::query(
      "INSERT INTO user_creature_custom_sections (creature_row_id, \
       position, name, body) VALUES ($1, $2, $3, $4)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(&section.name)
    .bind(&section.body)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  if let Some(sc) = spellcasting {
    insert_spell_names(conn, &row_id, "at_will", 0, &sc.at_will).await?;
    for (i, level) in sc.slots.iter().enumerate() {
      sqlx::query(
        "INSERT INTO user_creature_spell_levels (creature_row_id, position, \
         spell_level, slots) VALUES ($1, $2, $3, $4)",
      )
      .bind(&row_id)
      .bind(i as i64)
      .bind(i64::from(level.level))
      .bind(i64::from(level.slots))
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
      insert_spell_names(conn, &row_id, "slot", i as i64, &level.spells)
        .await?;
    }
    for (i, innate) in sc.innate_per_day.iter().enumerate() {
      sqlx::query(
        "INSERT INTO user_creature_innate_groups (creature_row_id, \
         position, uses) VALUES ($1, $2, $3)",
      )
      .bind(&row_id)
      .bind(i as i64)
      .bind(i64::from(innate.uses))
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
      insert_spell_names(conn, &row_id, "innate", i as i64, &innate.spells)
        .await?;
    }
  }

  Ok(())
}

async fn insert_feature(
  conn: &mut AnyConnection,
  row_id: &str,
  feature_group: &str,
  position: i64,
  feature: &Feature,
) -> Result<(), CompendiumStoreError> {
  let (usage_kind, low, high, uses) = match &feature.usage {
    None => (None, None, None, None),
    Some(Usage::Recharge { low, high }) => {
      (Some("recharge"), Some(i64::from(*low)), Some(i64::from(*high)), None)
    }
    Some(Usage::PerDay { uses }) => {
      (Some("per_day"), None, None, Some(i64::from(*uses)))
    }
    Some(Usage::PerShortRest { uses }) => {
      (Some("per_short_rest"), None, None, Some(i64::from(*uses)))
    }
    Some(Usage::PerLongRest { uses }) => {
      (Some("per_long_rest"), None, None, Some(i64::from(*uses)))
    }
    Some(Usage::AtWill) => (Some("at_will"), None, None, None),
  };
  sqlx::query(
    "INSERT INTO user_creature_features (creature_row_id, feature_group, \
     position, name, description, usage_kind, usage_low, usage_high, \
     usage_uses) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
  )
  .bind(row_id)
  .bind(feature_group)
  .bind(position)
  .bind(&feature.name)
  .bind(&feature.description)
  .bind(usage_kind)
  .bind(low)
  .bind(high)
  .bind(uses)
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;
  Ok(())
}

async fn insert_spell_names(
  conn: &mut AnyConnection,
  row_id: &str,
  list_kind: &str,
  list_position: i64,
  names: &[String],
) -> Result<(), CompendiumStoreError> {
  for (i, name) in names.iter().enumerate() {
    sqlx::query(
      "INSERT INTO user_creature_spell_names (creature_row_id, list_kind, \
       list_position, position, name) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(row_id)
    .bind(list_kind)
    .bind(list_position)
    .bind(i as i64)
    .bind(name)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }
  Ok(())
}

// ── fetch ────────────────────────────────────────────────────────────────────

/// One reassembled creature plus its row-level bookkeeping, so the
/// store can preserve `position` / `created_at` on updates without
/// a second query.
pub struct CreatureRow {
  pub row_id: String,
  pub position: i64,
  pub creature: Creature,
}

/// One child-table batch: rows for every creature the user owns,
/// stitched onto the assembled list by surrogate row id.
async fn stitch_children<F>(
  conn: &mut AnyConnection,
  user_id: &str,
  sql: &str,
  rows: &mut [CreatureRow],
  index: &HashMap<String, usize>,
  mut apply: F,
) -> Result<(), CompendiumStoreError>
where
  F: FnMut(&mut CreatureRow, &AnyRow) -> Result<(), CompendiumStoreError>,
{
  let child_rows = sqlx::query(sql)
    .bind(user_id)
    .fetch_all(&mut *conn)
    .await
    .map_err(read_error)?;
  for row in &child_rows {
    let owner: String = row.try_get("creature_row_id").map_err(read_error)?;
    if let Some(i) = index.get(&owner) {
      apply(&mut rows[*i], row)?;
    }
  }
  Ok(())
}

/// Reassemble every creature `user_id` owns, in list (`position`)
/// order.
pub async fn fetch_creatures(
  conn: &mut AnyConnection,
  user_id: &str,
) -> Result<Vec<CreatureRow>, CompendiumStoreError> {
  let parents = sqlx::query(
    "SELECT * FROM user_creatures WHERE user_id = $1 ORDER BY position",
  )
  .bind(user_id)
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?;

  let mut rows = Vec::with_capacity(parents.len());
  let mut index: HashMap<String, usize> = HashMap::new();
  for row in &parents {
    let parsed = parent_from_row(row)?;
    index.insert(parsed.row_id.clone(), rows.len());
    rows.push(parsed);
  }
  if rows.is_empty() {
    return Ok(rows);
  }

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_saving_throws t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      slot.creature.saving_throws.push(AbilitySave {
        ability: parse_token::<Ability>(
          &row.try_get::<String, _>("ability").map_err(read_error)?,
          "ability",
        )?,
        bonus: row.try_get::<i64, _>("bonus").map_err(read_error)? as i32,
      });
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_skills t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      slot.creature.skills.push(SkillBonus {
        name: row.try_get("name").map_err(read_error)?,
        bonus: row.try_get::<i64, _>("bonus").map_err(read_error)? as i32,
      });
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_damage_relations t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.relation, t.position",
    &mut rows,
    &index,
    |slot, row| {
      let relation: String = row.try_get("relation").map_err(read_error)?;
      let value: String = row.try_get("value").map_err(read_error)?;
      match relation.as_str() {
        "vulnerability" => slot.creature.damage_vulnerabilities.push(value),
        "resistance" => slot.creature.damage_resistances.push(value),
        "immunity" => slot.creature.damage_immunities.push(value),
        "condition_immunity" => slot.creature.condition_immunities.push(value),
        other => {
          return Err(decode_error(format!(
            "unknown damage relation {other:?}"
          )))
        }
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_strings t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.list_kind, t.position",
    &mut rows,
    &index,
    |slot, row| {
      let list_kind: String = row.try_get("list_kind").map_err(read_error)?;
      let value: String = row.try_get("value").map_err(read_error)?;
      match list_kind.as_str() {
        "language" => slot.creature.languages.push(value),
        "habitat" => slot
          .creature
          .habitats
          .push(parse_token::<Habitat>(&value, "habitat")?),
        "treasure" => slot
          .creature
          .treasures
          .push(parse_token::<Treasure>(&value, "treasure")?),
        "tag" => slot.creature.tags.push(value),
        "loot" => slot.creature.loot.push(value),
        other => {
          return Err(decode_error(format!(
            "unknown string-list kind {other:?}"
          )))
        }
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_features t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.feature_group, t.position",
    &mut rows,
    &index,
    |slot, row| {
      let group: String = row.try_get("feature_group").map_err(read_error)?;
      let feature = feature_from_row(row)?;
      match group.as_str() {
        "trait" => slot.creature.traits.push(feature),
        "action" => slot.creature.actions.push(feature),
        "bonus_action" => slot.creature.bonus_actions.push(feature),
        "reaction" => slot.creature.reactions.push(feature),
        "lair_option" => {
          if let Some(lair) = slot.creature.lair_actions.as_mut() {
            lair.options.push(feature);
          }
        }
        "regional_effect" => {
          if let Some(regional) = slot.creature.regional_effects.as_mut() {
            regional.effects.push(feature);
          }
        }
        other => {
          return Err(decode_error(format!("unknown feature group {other:?}")))
        }
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_legendary_options t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      if let Some(legendary) = slot.creature.legendary_actions.as_mut() {
        legendary.options.push(LegendaryOption {
          name: row.try_get("name").map_err(read_error)?,
          cost: row.try_get::<i64, _>("cost").map_err(read_error)? as i32,
          description: row.try_get("description").map_err(read_error)?,
        });
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_custom_sections t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      slot.creature.custom_sections.push(CustomSection {
        name: row.try_get("name").map_err(read_error)?,
        body: row.try_get("body").map_err(read_error)?,
      });
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_spell_levels t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      if let Some(sc) = slot.creature.spellcasting.as_mut() {
        sc.slots.push(SpellSlotLevel {
          level: row.try_get::<i64, _>("spell_level").map_err(read_error)?
            as i32,
          slots: row.try_get::<i64, _>("slots").map_err(read_error)? as i32,
          spells: Vec::new(),
        });
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_innate_groups t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut rows,
    &index,
    |slot, row| {
      if let Some(sc) = slot.creature.spellcasting.as_mut() {
        sc.innate_per_day.push(InnatePerDay {
          uses: row.try_get::<i64, _>("uses").map_err(read_error)? as i32,
          spells: Vec::new(),
        });
      }
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM user_creature_spell_names t \
     JOIN user_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 \
     ORDER BY t.list_kind, t.list_position, t.position",
    &mut rows,
    &index,
    |slot, row| {
      let list_kind: String = row.try_get("list_kind").map_err(read_error)?;
      let list_position: i64 =
        row.try_get("list_position").map_err(read_error)?;
      let name: String = row.try_get("name").map_err(read_error)?;
      if let Some(sc) = slot.creature.spellcasting.as_mut() {
        match list_kind.as_str() {
          "at_will" => sc.at_will.push(name),
          "slot" => {
            if let Some(level) = sc.slots.get_mut(list_position as usize) {
              level.spells.push(name);
            }
          }
          "innate" => {
            if let Some(group) =
              sc.innate_per_day.get_mut(list_position as usize)
            {
              group.spells.push(name);
            }
          }
          other => {
            return Err(decode_error(format!(
              "unknown spell-list kind {other:?}"
            )))
          }
        }
      }
      Ok(())
    },
  )
  .await?;

  Ok(rows)
}

/// Decode the `user_creatures` scalar columns; list fields start
/// empty and the child-table stitch in [`fetch_creatures`] fills
/// them in.
fn parent_from_row(row: &AnyRow) -> Result<CreatureRow, CompendiumStoreError> {
  let i32_col = |name: &str| -> Result<i32, CompendiumStoreError> {
    Ok(row.try_get::<i64, _>(name).map_err(read_error)? as i32)
  };
  let legendary_uses: Option<i64> =
    row.try_get("legendary_uses").map_err(read_error)?;
  let lair_initiative: Option<i64> =
    row.try_get("lair_initiative").map_err(read_error)?;
  let regional_description: Option<String> =
    row.try_get("regional_description").map_err(read_error)?;
  let spellcasting_ability: Option<String> =
    row.try_get("spellcasting_ability").map_err(read_error)?;

  let legendary_actions = legendary_uses
    .map(|uses| -> Result<LegendaryActions, CompendiumStoreError> {
      Ok(LegendaryActions {
        description: row
          .try_get::<Option<String>, _>("legendary_description")
          .map_err(read_error)?
          .unwrap_or_default(),
        uses: uses as i32,
        uses_in_lair: row
          .try_get::<Option<i64>, _>("legendary_uses_in_lair")
          .map_err(read_error)?
          .unwrap_or_default() as i32,
        options: Vec::new(),
      })
    })
    .transpose()?;

  let lair_actions = lair_initiative
    .map(|initiative| -> Result<LairActions, CompendiumStoreError> {
      Ok(LairActions {
        initiative: initiative as i32,
        description: row
          .try_get::<Option<String>, _>("lair_description")
          .map_err(read_error)?
          .unwrap_or_default(),
        options: Vec::new(),
      })
    })
    .transpose()?;

  let regional_effects = regional_description
    .map(|description| -> Result<RegionalEffects, CompendiumStoreError> {
      Ok(RegionalEffects {
        description,
        effects: Vec::new(),
        fade_after: row
          .try_get::<Option<String>, _>("regional_fade_after")
          .map_err(read_error)?
          .unwrap_or_default(),
      })
    })
    .transpose()?;

  let spellcasting = spellcasting_ability
    .map(|ability| -> Result<Spellcasting, CompendiumStoreError> {
      Ok(Spellcasting {
        description: row
          .try_get::<Option<String>, _>("spellcasting_description")
          .map_err(read_error)?
          .unwrap_or_default(),
        ability: parse_token::<Ability>(&ability, "spellcasting ability")?,
        save_dc: row
          .try_get::<Option<i64>, _>("spellcasting_save_dc")
          .map_err(read_error)?
          .unwrap_or_default() as i32,
        attack_bonus: row
          .try_get::<Option<i64>, _>("spellcasting_attack_bonus")
          .map_err(read_error)?
          .unwrap_or_default() as i32,
        at_will: Vec::new(),
        slots: Vec::new(),
        innate_per_day: Vec::new(),
      })
    })
    .transpose()?;

  Ok(CreatureRow {
    row_id: row.try_get("row_id").map_err(read_error)?,
    position: row.try_get("position").map_err(read_error)?,
    creature: Creature {
      id: row.try_get("creature_id").map_err(read_error)?,
      name: row.try_get("name").map_err(read_error)?,
      kind: parse_token::<CreatureKind>(
        &row.try_get::<String, _>("kind").map_err(read_error)?,
        "creature kind",
      )?,
      size: parse_token::<Size>(
        &row.try_get::<String, _>("size").map_err(read_error)?,
        "size",
      )?,
      race: row.try_get("race").map_err(read_error)?,
      subrace: row.try_get("subrace").map_err(read_error)?,
      alignment: row.try_get("alignment").map_err(read_error)?,
      source: row.try_get("source").map_err(read_error)?,
      description: row.try_get("description").map_err(read_error)?,
      armor_class: i32_col("armor_class")?,
      armor_class_note: row.try_get("armor_class_note").map_err(read_error)?,
      max_hp: i32_col("max_hp")?,
      hp_formula: row.try_get("hp_formula").map_err(read_error)?,
      initiative_bonus: i32_col("initiative_bonus")?,
      speed: Speed {
        walk: i32_col("speed_walk")?,
        fly: i32_col("speed_fly")?,
        swim: i32_col("speed_swim")?,
        climb: i32_col("speed_climb")?,
        burrow: i32_col("speed_burrow")?,
        hover: row.try_get::<i64, _>("speed_hover").map_err(read_error)? != 0,
      },
      abilities: Abilities {
        str: i32_col("ability_str")?,
        dex: i32_col("ability_dex")?,
        con: i32_col("ability_con")?,
        int: i32_col("ability_int")?,
        wis: i32_col("ability_wis")?,
        cha: i32_col("ability_cha")?,
      },
      saving_throws: Vec::new(),
      skills: Vec::new(),
      damage_vulnerabilities: Vec::new(),
      damage_resistances: Vec::new(),
      damage_immunities: Vec::new(),
      condition_immunities: Vec::new(),
      senses: Senses {
        blindsight: i32_col("senses_blindsight")?,
        darkvision: i32_col("senses_darkvision")?,
        tremorsense: i32_col("senses_tremorsense")?,
        truesight: i32_col("senses_truesight")?,
        passive_perception: i32_col("passive_perception")?,
      },
      languages: Vec::new(),
      challenge_rating: row.try_get("challenge_rating").map_err(read_error)?,
      xp: row.try_get("xp").map_err(read_error)?,
      xp_in_lair: row.try_get("xp_in_lair").map_err(read_error)?,
      proficiency_bonus: i32_col("proficiency_bonus")?,
      traits: Vec::new(),
      actions: Vec::new(),
      bonus_actions: Vec::new(),
      reactions: Vec::new(),
      legendary_actions,
      lair_actions,
      regional_effects,
      spellcasting,
      custom_sections: Vec::new(),
      habitats: Vec::new(),
      treasures: Vec::new(),
      tags: Vec::new(),
      loot: Vec::new(),
      created_at: row.try_get("created_at").map_err(read_error)?,
      updated_at: row.try_get("updated_at").map_err(read_error)?,
      is_bundled: false,
      has_special_reactions: row
        .try_get::<i64, _>("has_special_reactions")
        .map_err(read_error)?
        != 0,
    },
  })
}

fn feature_from_row(row: &AnyRow) -> Result<Feature, CompendiumStoreError> {
  let usage_kind: Option<String> =
    row.try_get("usage_kind").map_err(read_error)?;
  let int_param = |name: &str| -> Result<i32, CompendiumStoreError> {
    Ok(
      row
        .try_get::<Option<i64>, _>(name)
        .map_err(read_error)?
        .unwrap_or_default() as i32,
    )
  };
  let usage = usage_kind
    .map(|kind| -> Result<Usage, CompendiumStoreError> {
      match kind.as_str() {
        "recharge" => Ok(Usage::Recharge {
          low: int_param("usage_low")?,
          high: int_param("usage_high")?,
        }),
        "per_day" => Ok(Usage::PerDay {
          uses: int_param("usage_uses")?,
        }),
        "per_short_rest" => Ok(Usage::PerShortRest {
          uses: int_param("usage_uses")?,
        }),
        "per_long_rest" => Ok(Usage::PerLongRest {
          uses: int_param("usage_uses")?,
        }),
        "at_will" => Ok(Usage::AtWill),
        other => {
          Err(decode_error(format!("unknown feature usage kind {other:?}")))
        }
      }
    })
    .transpose()?;
  Ok(Feature {
    name: row.try_get("name").map_err(read_error)?,
    description: row.try_get("description").map_err(read_error)?,
    usage,
  })
}
