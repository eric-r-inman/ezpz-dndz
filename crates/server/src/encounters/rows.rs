//! Live-encounter ↔ relational rows codec (migration 0004).
//!
//! Shared by [`super::store::EncounterStore`] and the one-shot JSON
//! boot import in `crate::json_import`.  The typed model in
//! [`super::wire`] is the unit of exchange: every scalar lands in a
//! column of `encounters` / `encounter_creatures` /
//! `encounter_treasure`, every list in a child table ordered by
//! `position`, and the optional sub-records (timer, saveToEnd, the
//! treasure row and its source pack) flatten to column packs that
//! are all NULL together when absent.
//!
//! Rows are written only by this codec (which in turn only receives
//! values validated by the wire decoder), so a row that fails to
//! decode back indicates schema corruption and surfaces as a
//! semantic error rather than being silently patched.
//!
//! Fetches reassemble one user's whole encounter (one query per
//! table, stitched by surrogate creature row id) — the write-hot
//! payload is a single user's combat, so per-user batches are
//! already minimal.

use std::collections::HashMap;

use sqlx::{any::AnyRow, AnyConnection, Row};
use uuid::Uuid;

use super::error::EncounterStoreError;
use super::wire::{
  CategoryToggles, Coins, Condition, Contribution, Creature, Duration,
  Encounter, MagicItem, RechargeAbility, RowSource, SaveNotice, SaveToEnd,
  Spec, Timer, TreasureRoll, TreasureSettings, ValuedItem,
};

fn read_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::LiveRowsRead { source }
}

fn write_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::LiveRowsWrite { source }
}

fn decode_error(detail: String) -> EncounterStoreError {
  EncounterStoreError::LiveRowDecode { detail }
}

/// The sentinel `contribution_position` marking an item row that
/// belongs to the roll itself rather than to a contribution.
const ROLL_LEVEL: i64 = -1;

// ── insert ───────────────────────────────────────────────────────────────────

/// Insert one user's whole live encounter (parent row + creatures +
/// treasure).  Takes a bare connection so callers control the
/// transaction; the caller is responsible for having deleted any
/// previous row first (PUT is delete-then-insert in one
/// transaction).
pub async fn insert_encounter(
  conn: &mut AnyConnection,
  user_id: &str,
  encounter: &Encounter,
) -> Result<(), EncounterStoreError> {
  let s = &encounter.treasure_settings;
  sqlx::query(
    "INSERT INTO encounters (user_id, active_name, round, coins_count, \
     gems_count, art_count, magic_count, mundane_count, weapons_count, \
     armor_count, gems_value, art_value, magic_value, hoard_coins_none, \
     hoard_gems_none, hoard_art_none, hoard_magic_none, hoard_mundane_none, \
     hoard_weapons_none, hoard_armor_none, individual_coins_none, \
     individual_gems_none, individual_art_none, individual_magic_none, \
     individual_mundane_none, individual_weapons_none, \
     individual_armor_none, magic_scroll_chance) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
     $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28)",
  )
  .bind(user_id)
  .bind(&encounter.active_name)
  .bind(encounter.round)
  .bind(&s.coins_count)
  .bind(&s.gems_count)
  .bind(&s.art_count)
  .bind(&s.magic_count)
  .bind(&s.mundane_count)
  .bind(&s.weapons_count)
  .bind(&s.armor_count)
  .bind(&s.gems_value)
  .bind(&s.art_value)
  .bind(&s.magic_value)
  .bind(i64::from(s.hoard_toggles.coins_none))
  .bind(i64::from(s.hoard_toggles.gems_none))
  .bind(i64::from(s.hoard_toggles.art_none))
  .bind(i64::from(s.hoard_toggles.magic_none))
  .bind(i64::from(s.hoard_toggles.mundane_none))
  .bind(i64::from(s.hoard_toggles.weapons_none))
  .bind(i64::from(s.hoard_toggles.armor_none))
  .bind(i64::from(s.individual_toggles.coins_none))
  .bind(i64::from(s.individual_toggles.gems_none))
  .bind(i64::from(s.individual_toggles.art_none))
  .bind(i64::from(s.individual_toggles.magic_none))
  .bind(i64::from(s.individual_toggles.mundane_none))
  .bind(i64::from(s.individual_toggles.weapons_none))
  .bind(i64::from(s.individual_toggles.armor_none))
  .bind(s.magic_scroll_chance)
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;

  for (i, creature) in encounter.creatures.iter().enumerate() {
    insert_creature(conn, user_id, i as i64, creature).await?;
  }

  if let Some(roll) = &encounter.treasure {
    insert_treasure(conn, user_id, roll).await?;
  }

  Ok(())
}

async fn insert_creature(
  conn: &mut AnyConnection,
  user_id: &str,
  position: i64,
  c: &Creature,
) -> Result<(), EncounterStoreError> {
  let row_id = Uuid::new_v4().to_string();
  let timer = c.timer.as_ref();

  sqlx::query(
    "INSERT INTO encounter_creatures (row_id, user_id, position, name, \
     kind, initiative, initiative_bonus, current_hp, max_hp, \
     original_max_hp, temp_hp, armor_class, speed, selected, cover, \
     concentrating, hiding, dodging, flying, fly_height, bloodied, \
     death_save_successes, death_save_failures, accepting_death_saves, \
     reaction_used, readied, inactive, note, memo, timer_remaining, \
     timer_phase, timer_ringing, timer_note, creature_id, \
     legendary_actions_count, legendary_actions_lair_bonus, \
     legendary_resistance_count, legendary_resistance_lair_bonus, \
     is_placeholder, creature_kind, race, alignment, surprised, \
     has_special_reactions) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
     $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, \
     $29, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $40, $41, $42, \
     $43, $44)",
  )
  .bind(&row_id)
  .bind(user_id)
  .bind(position)
  .bind(&c.name)
  .bind(&c.kind)
  .bind(c.initiative)
  .bind(c.initiative_bonus)
  .bind(c.current_hp)
  .bind(c.max_hp)
  .bind(c.original_max_hp)
  .bind(c.temp_hp)
  .bind(c.armor_class)
  .bind(c.speed)
  .bind(i64::from(c.selected))
  .bind(&c.cover)
  .bind(i64::from(c.concentrating))
  .bind(i64::from(c.hiding))
  .bind(i64::from(c.dodging))
  .bind(i64::from(c.flying))
  .bind(c.fly_height)
  .bind(i64::from(c.bloodied))
  .bind(c.death_save_successes)
  .bind(c.death_save_failures)
  .bind(i64::from(c.accepting_death_saves))
  .bind(i64::from(c.reaction_used))
  .bind(i64::from(c.readied))
  .bind(i64::from(c.inactive))
  .bind(&c.note)
  .bind(&c.memo)
  .bind(timer.map(|t| t.remaining))
  .bind(timer.map(|t| t.phase.clone()))
  .bind(timer.map(|t| i64::from(t.ringing)))
  .bind(timer.map(|t| t.note.clone()))
  .bind(&c.creature_id)
  .bind(c.legendary_actions_count)
  .bind(c.legendary_actions_lair_bonus)
  .bind(c.legendary_resistance_count)
  .bind(c.legendary_resistance_lair_bonus)
  .bind(i64::from(c.is_placeholder))
  .bind(&c.creature_kind)
  .bind(&c.race)
  .bind(&c.alignment)
  .bind(i64::from(c.surprised))
  .bind(i64::from(c.has_special_reactions))
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;

  for (i, condition) in c.conditions.iter().enumerate() {
    insert_condition(conn, &row_id, i as i64, condition).await?;
  }

  for (i, notice) in c.save_notices.iter().enumerate() {
    sqlx::query(
      "INSERT INTO encounter_creature_save_notices (creature_row_id, \
       position, notice_id, condition_name, turns_remaining) \
       VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(notice.id)
    .bind(&notice.condition_name)
    .bind(notice.turns_remaining)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (i, ability) in c.recharge_abilities.iter().enumerate() {
    sqlx::query(
      "INSERT INTO encounter_creature_recharge_abilities (creature_row_id, \
       position, name, low, high, ready, awaiting_roll) \
       VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(&row_id)
    .bind(i as i64)
    .bind(&ability.name)
    .bind(ability.low)
    .bind(ability.high)
    .bind(i64::from(ability.ready))
    .bind(i64::from(ability.awaiting_roll))
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (pip_kind, values) in [
    ("action", &c.legendary_actions_used),
    ("resistance", &c.legendary_resistance_used),
  ] {
    for (i, value) in values.iter().enumerate() {
      sqlx::query(
        "INSERT INTO encounter_creature_pips (creature_row_id, pip_kind, \
         position, value) VALUES ($1, $2, $3, $4)",
      )
      .bind(&row_id)
      .bind(pip_kind)
      .bind(i as i64)
      .bind(value)
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
    }
  }

  Ok(())
}

async fn insert_condition(
  conn: &mut AnyConnection,
  row_id: &str,
  position: i64,
  cond: &Condition,
) -> Result<(), EncounterStoreError> {
  let (kind, phase, target, turn_name, remaining, skip_next) =
    match &cond.duration {
      Duration::Manual => ("manual", None, None, None, None, None),
      Duration::UntilTurn {
        phase,
        target,
        name,
      } => (
        "untilTurn",
        Some(phase.clone()),
        Some(target.clone()),
        Some(name.clone()),
        None,
        None,
      ),
      Duration::Countdown {
        phase,
        remaining,
        skip_next_tick,
      } => (
        "countdown",
        Some(phase.clone()),
        None,
        None,
        Some(*remaining),
        Some(i64::from(*skip_next_tick)),
      ),
    };
  let save = cond.save_to_end.as_ref();
  sqlx::query(
    "INSERT INTO encounter_creature_conditions (creature_row_id, position, \
     condition_id, name, note, duration_kind, duration_phase, \
     duration_target, duration_name, duration_remaining, \
     duration_skip_next, save_ability, save_dc, save_bonus, \
     save_auto_roll) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
     $15)",
  )
  .bind(row_id)
  .bind(position)
  .bind(cond.id)
  .bind(&cond.name)
  .bind(&cond.note)
  .bind(kind)
  .bind(phase)
  .bind(target)
  .bind(turn_name)
  .bind(remaining)
  .bind(skip_next)
  .bind(save.map(|s| s.ability.clone()))
  .bind(save.map(|s| s.dc))
  .bind(save.map(|s| s.bonus))
  .bind(save.map(|s| s.auto_roll.clone()))
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;
  Ok(())
}

async fn insert_treasure(
  conn: &mut AnyConnection,
  user_id: &str,
  roll: &TreasureRoll,
) -> Result<(), EncounterStoreError> {
  let source = roll.source.as_ref();
  let coin = |pick: fn(&RowSource) -> Option<(i64, i64, i64)>, part: usize| {
    source.and_then(pick).map(|triple| match part {
      0 => triple.0,
      1 => triple.1,
      _ => triple.2,
    })
  };
  let spec_int = |pick: fn(&RowSource) -> Option<&Spec>, part: usize| {
    source
      .and_then(pick)
      .map(|s| if part == 0 { s.count } else { s.faces })
  };
  let spec_tier = |pick: fn(&RowSource) -> Option<&Spec>| {
    source.and_then(pick).map(|s| s.tier.clone())
  };

  sqlx::query(
    "INSERT INTO encounter_treasure (user_id, kind, bracket, coin_copper, \
     coin_silver, coin_electrum, coin_gold, coin_platinum, has_source, \
     src_copper_count, src_copper_faces, src_copper_mult, \
     src_silver_count, src_silver_faces, src_silver_mult, \
     src_electrum_count, src_electrum_faces, src_electrum_mult, \
     src_gold_count, src_gold_faces, src_gold_mult, src_platinum_count, \
     src_platinum_faces, src_platinum_mult, src_gems_count, \
     src_gems_faces, src_gems_tier, src_art_count, src_art_faces, \
     src_art_tier, src_magic_count, src_magic_faces, src_magic_table) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, \
     $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, \
     $29, $30, $31, $32, $33)",
  )
  .bind(user_id)
  .bind(&roll.kind)
  .bind(&roll.bracket)
  .bind(roll.coins.copper)
  .bind(roll.coins.silver)
  .bind(roll.coins.electrum)
  .bind(roll.coins.gold)
  .bind(roll.coins.platinum)
  .bind(i64::from(source.is_some()))
  .bind(coin(|s| s.coin_formulas.copper, 0))
  .bind(coin(|s| s.coin_formulas.copper, 1))
  .bind(coin(|s| s.coin_formulas.copper, 2))
  .bind(coin(|s| s.coin_formulas.silver, 0))
  .bind(coin(|s| s.coin_formulas.silver, 1))
  .bind(coin(|s| s.coin_formulas.silver, 2))
  .bind(coin(|s| s.coin_formulas.electrum, 0))
  .bind(coin(|s| s.coin_formulas.electrum, 1))
  .bind(coin(|s| s.coin_formulas.electrum, 2))
  .bind(coin(|s| s.coin_formulas.gold, 0))
  .bind(coin(|s| s.coin_formulas.gold, 1))
  .bind(coin(|s| s.coin_formulas.gold, 2))
  .bind(coin(|s| s.coin_formulas.platinum, 0))
  .bind(coin(|s| s.coin_formulas.platinum, 1))
  .bind(coin(|s| s.coin_formulas.platinum, 2))
  .bind(spec_int(|s| s.gems_spec.as_ref(), 0))
  .bind(spec_int(|s| s.gems_spec.as_ref(), 1))
  .bind(spec_tier(|s| s.gems_spec.as_ref()))
  .bind(spec_int(|s| s.art_spec.as_ref(), 0))
  .bind(spec_int(|s| s.art_spec.as_ref(), 1))
  .bind(spec_tier(|s| s.art_spec.as_ref()))
  .bind(spec_int(|s| s.magic_spec.as_ref(), 0))
  .bind(spec_int(|s| s.magic_spec.as_ref(), 1))
  .bind(spec_tier(|s| s.magic_spec.as_ref()))
  .execute(&mut *conn)
  .await
  .map_err(write_error)?;

  insert_item_lists(
    conn,
    user_id,
    ROLL_LEVEL,
    &roll.gems,
    &roll.art,
    &roll.magic,
    &roll.mundane,
    &roll.weapons,
    &roll.armor,
    &roll.loot,
  )
  .await?;

  for (i, contribution) in roll.contributions.iter().enumerate() {
    sqlx::query(
      "INSERT INTO encounter_treasure_contributions (user_id, position, \
       creature_name, bracket, coin_copper, coin_silver, coin_electrum, \
       coin_gold, coin_platinum) \
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(user_id)
    .bind(i as i64)
    .bind(&contribution.creature_name)
    .bind(&contribution.bracket)
    .bind(contribution.coins.copper)
    .bind(contribution.coins.silver)
    .bind(contribution.coins.electrum)
    .bind(contribution.coins.gold)
    .bind(contribution.coins.platinum)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;

    insert_item_lists(
      conn,
      user_id,
      i as i64,
      &contribution.gems,
      &contribution.art,
      &contribution.magic,
      &contribution.mundane,
      &contribution.weapons,
      &contribution.armor,
      &contribution.loot,
    )
    .await?;
  }

  Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn insert_item_lists(
  conn: &mut AnyConnection,
  user_id: &str,
  contribution_position: i64,
  gems: &[ValuedItem],
  art: &[ValuedItem],
  magic: &[MagicItem],
  mundane: &[ValuedItem],
  weapons: &[ValuedItem],
  armor: &[ValuedItem],
  loot: &[String],
) -> Result<(), EncounterStoreError> {
  let insert_row = |category: &'static str,
                    position: i64,
                    name: String,
                    value_gp: Option<i64>,
                    rarity: Option<String>,
                    table_key: Option<String>| {
    sqlx::query(
      "INSERT INTO encounter_treasure_items (user_id, \
       contribution_position, category, position, name, value_gp, rarity, \
       table_key) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(user_id.to_string())
    .bind(contribution_position)
    .bind(category)
    .bind(position)
    .bind(name)
    .bind(value_gp)
    .bind(rarity)
    .bind(table_key)
  };

  for (category, items) in [
    ("gems", gems),
    ("art", art),
    ("mundane", mundane),
    ("weapons", weapons),
    ("armor", armor),
  ] {
    for (i, item) in items.iter().enumerate() {
      insert_row(
        category,
        i as i64,
        item.name.clone(),
        Some(item.value_gp),
        None,
        None,
      )
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
    }
  }

  for (i, item) in magic.iter().enumerate() {
    insert_row(
      "magic",
      i as i64,
      item.name.clone(),
      None,
      Some(item.rarity.clone()),
      Some(item.table.clone()),
    )
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;
  }

  for (i, name) in loot.iter().enumerate() {
    insert_row("loot", i as i64, name.clone(), None, None, None)
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
  }

  Ok(())
}

// ── fetch ────────────────────────────────────────────────────────────────────

/// Reassemble `user_id`'s live encounter, or `None` when the user
/// has never persisted one (which the HTTP layer serves as JSON
/// `null`).
pub async fn fetch_encounter(
  conn: &mut AnyConnection,
  user_id: &str,
) -> Result<Option<Encounter>, EncounterStoreError> {
  let Some(parent) = sqlx::query("SELECT * FROM encounters WHERE user_id = $1")
    .bind(user_id)
    .fetch_optional(&mut *conn)
    .await
    .map_err(read_error)?
  else {
    return Ok(None);
  };

  Ok(Some(Encounter {
    creatures: fetch_creatures(conn, user_id).await?,
    active_name: parent.try_get("active_name").map_err(read_error)?,
    round: parent.try_get("round").map_err(read_error)?,
    treasure: fetch_treasure(conn, user_id).await?,
    treasure_settings: settings_from_row(&parent)?,
  }))
}

fn settings_from_row(
  row: &AnyRow,
) -> Result<TreasureSettings, EncounterStoreError> {
  let text = |name: &str| -> Result<String, EncounterStoreError> {
    row.try_get(name).map_err(read_error)
  };
  let flag = |name: &str| -> Result<bool, EncounterStoreError> {
    Ok(row.try_get::<i64, _>(name).map_err(read_error)? != 0)
  };
  Ok(TreasureSettings {
    coins_count: text("coins_count")?,
    gems_count: text("gems_count")?,
    gems_value: text("gems_value")?,
    art_count: text("art_count")?,
    art_value: text("art_value")?,
    magic_count: text("magic_count")?,
    magic_value: text("magic_value")?,
    mundane_count: text("mundane_count")?,
    weapons_count: text("weapons_count")?,
    armor_count: text("armor_count")?,
    hoard_toggles: CategoryToggles {
      coins_none: flag("hoard_coins_none")?,
      gems_none: flag("hoard_gems_none")?,
      art_none: flag("hoard_art_none")?,
      magic_none: flag("hoard_magic_none")?,
      mundane_none: flag("hoard_mundane_none")?,
      weapons_none: flag("hoard_weapons_none")?,
      armor_none: flag("hoard_armor_none")?,
    },
    individual_toggles: CategoryToggles {
      coins_none: flag("individual_coins_none")?,
      gems_none: flag("individual_gems_none")?,
      art_none: flag("individual_art_none")?,
      magic_none: flag("individual_magic_none")?,
      mundane_none: flag("individual_mundane_none")?,
      weapons_none: flag("individual_weapons_none")?,
      armor_none: flag("individual_armor_none")?,
    },
    magic_scroll_chance: row
      .try_get("magic_scroll_chance")
      .map_err(read_error)?,
  })
}

async fn fetch_creatures(
  conn: &mut AnyConnection,
  user_id: &str,
) -> Result<Vec<Creature>, EncounterStoreError> {
  let parents = sqlx::query(
    "SELECT * FROM encounter_creatures WHERE user_id = $1 ORDER BY position",
  )
  .bind(user_id)
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?;

  let mut creatures = Vec::with_capacity(parents.len());
  let mut index: HashMap<String, usize> = HashMap::new();
  for row in &parents {
    let row_id: String = row.try_get("row_id").map_err(read_error)?;
    index.insert(row_id, creatures.len());
    creatures.push(creature_from_row(row)?);
  }
  if creatures.is_empty() {
    return Ok(creatures);
  }

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM encounter_creature_conditions t \
     JOIN encounter_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut creatures,
    &index,
    |creature, row| {
      creature.conditions.push(condition_from_row(row)?);
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM encounter_creature_save_notices t \
     JOIN encounter_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut creatures,
    &index,
    |creature, row| {
      creature.save_notices.push(SaveNotice {
        id: row.try_get("notice_id").map_err(read_error)?,
        condition_name: row.try_get("condition_name").map_err(read_error)?,
        turns_remaining: row.try_get("turns_remaining").map_err(read_error)?,
      });
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM encounter_creature_recharge_abilities t \
     JOIN encounter_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.position",
    &mut creatures,
    &index,
    |creature, row| {
      creature.recharge_abilities.push(RechargeAbility {
        name: row.try_get("name").map_err(read_error)?,
        low: row.try_get("low").map_err(read_error)?,
        high: row.try_get("high").map_err(read_error)?,
        ready: row.try_get::<i64, _>("ready").map_err(read_error)? != 0,
        awaiting_roll: row
          .try_get::<i64, _>("awaiting_roll")
          .map_err(read_error)?
          != 0,
      });
      Ok(())
    },
  )
  .await?;

  stitch_children(
    conn,
    user_id,
    "SELECT t.* FROM encounter_creature_pips t \
     JOIN encounter_creatures c ON c.row_id = t.creature_row_id \
     WHERE c.user_id = $1 ORDER BY t.pip_kind, t.position",
    &mut creatures,
    &index,
    |creature, row| {
      let pip_kind: String = row.try_get("pip_kind").map_err(read_error)?;
      let value: i64 = row.try_get("value").map_err(read_error)?;
      match pip_kind.as_str() {
        "action" => creature.legendary_actions_used.push(value),
        "resistance" => creature.legendary_resistance_used.push(value),
        other => {
          return Err(decode_error(format!("unknown pip kind {other:?}")))
        }
      }
      Ok(())
    },
  )
  .await?;

  Ok(creatures)
}

/// One child-table batch for this user's creatures, stitched onto
/// the assembled list by surrogate row id.
async fn stitch_children<F>(
  conn: &mut AnyConnection,
  user_id: &str,
  sql: &str,
  creatures: &mut [Creature],
  index: &HashMap<String, usize>,
  mut apply: F,
) -> Result<(), EncounterStoreError>
where
  F: FnMut(&mut Creature, &AnyRow) -> Result<(), EncounterStoreError>,
{
  let child_rows = sqlx::query(sql)
    .bind(user_id)
    .fetch_all(&mut *conn)
    .await
    .map_err(read_error)?;
  for row in &child_rows {
    let owner: String = row.try_get("creature_row_id").map_err(read_error)?;
    if let Some(i) = index.get(&owner) {
      apply(&mut creatures[*i], row)?;
    }
  }
  Ok(())
}

fn creature_from_row(row: &AnyRow) -> Result<Creature, EncounterStoreError> {
  let flag = |name: &str| -> Result<bool, EncounterStoreError> {
    Ok(row.try_get::<i64, _>(name).map_err(read_error)? != 0)
  };
  let timer_remaining: Option<i64> =
    row.try_get("timer_remaining").map_err(read_error)?;
  let timer = timer_remaining
    .map(|remaining| -> Result<Timer, EncounterStoreError> {
      Ok(Timer {
        remaining,
        phase: row
          .try_get::<Option<String>, _>("timer_phase")
          .map_err(read_error)?
          .unwrap_or_default(),
        ringing: row
          .try_get::<Option<i64>, _>("timer_ringing")
          .map_err(read_error)?
          .unwrap_or_default()
          != 0,
        note: row
          .try_get::<Option<String>, _>("timer_note")
          .map_err(read_error)?
          .unwrap_or_default(),
      })
    })
    .transpose()?;

  Ok(Creature {
    name: row.try_get("name").map_err(read_error)?,
    kind: row.try_get("kind").map_err(read_error)?,
    initiative: row.try_get("initiative").map_err(read_error)?,
    initiative_bonus: row.try_get("initiative_bonus").map_err(read_error)?,
    current_hp: row.try_get("current_hp").map_err(read_error)?,
    max_hp: row.try_get("max_hp").map_err(read_error)?,
    original_max_hp: row.try_get("original_max_hp").map_err(read_error)?,
    temp_hp: row.try_get("temp_hp").map_err(read_error)?,
    armor_class: row.try_get("armor_class").map_err(read_error)?,
    speed: row.try_get("speed").map_err(read_error)?,
    conditions: Vec::new(),
    save_notices: Vec::new(),
    selected: flag("selected")?,
    cover: row.try_get("cover").map_err(read_error)?,
    concentrating: flag("concentrating")?,
    hiding: flag("hiding")?,
    dodging: flag("dodging")?,
    flying: flag("flying")?,
    fly_height: row.try_get("fly_height").map_err(read_error)?,
    bloodied: flag("bloodied")?,
    death_save_successes: row
      .try_get("death_save_successes")
      .map_err(read_error)?,
    death_save_failures: row
      .try_get("death_save_failures")
      .map_err(read_error)?,
    accepting_death_saves: flag("accepting_death_saves")?,
    reaction_used: flag("reaction_used")?,
    recharge_abilities: Vec::new(),
    readied: flag("readied")?,
    inactive: flag("inactive")?,
    note: row.try_get("note").map_err(read_error)?,
    memo: row.try_get("memo").map_err(read_error)?,
    timer,
    creature_id: row.try_get("creature_id").map_err(read_error)?,
    legendary_actions_count: row
      .try_get("legendary_actions_count")
      .map_err(read_error)?,
    legendary_actions_lair_bonus: row
      .try_get("legendary_actions_lair_bonus")
      .map_err(read_error)?,
    legendary_actions_used: Vec::new(),
    legendary_resistance_count: row
      .try_get("legendary_resistance_count")
      .map_err(read_error)?,
    legendary_resistance_lair_bonus: row
      .try_get("legendary_resistance_lair_bonus")
      .map_err(read_error)?,
    legendary_resistance_used: Vec::new(),
    is_placeholder: flag("is_placeholder")?,
    creature_kind: row.try_get("creature_kind").map_err(read_error)?,
    race: row.try_get("race").map_err(read_error)?,
    alignment: row.try_get("alignment").map_err(read_error)?,
    surprised: flag("surprised")?,
    has_special_reactions: flag("has_special_reactions")?,
  })
}

fn condition_from_row(row: &AnyRow) -> Result<Condition, EncounterStoreError> {
  let opt_text = |name: &str| -> Result<Option<String>, EncounterStoreError> {
    row.try_get(name).map_err(read_error)
  };
  let kind: String = row.try_get("duration_kind").map_err(read_error)?;
  let duration = match kind.as_str() {
    "manual" => Duration::Manual,
    "untilTurn" => Duration::UntilTurn {
      phase: opt_text("duration_phase")?.unwrap_or_default(),
      target: opt_text("duration_target")?.unwrap_or_default(),
      name: opt_text("duration_name")?.unwrap_or_default(),
    },
    "countdown" => Duration::Countdown {
      phase: opt_text("duration_phase")?.unwrap_or_default(),
      remaining: row
        .try_get::<Option<i64>, _>("duration_remaining")
        .map_err(read_error)?
        .unwrap_or_default(),
      skip_next_tick: row
        .try_get::<Option<i64>, _>("duration_skip_next")
        .map_err(read_error)?
        .unwrap_or_default()
        != 0,
    },
    other => {
      return Err(decode_error(format!("unknown duration kind {other:?}")))
    }
  };
  let save_to_end = opt_text("save_ability")?
    .map(|ability| -> Result<SaveToEnd, EncounterStoreError> {
      Ok(SaveToEnd {
        ability,
        dc: row
          .try_get::<Option<i64>, _>("save_dc")
          .map_err(read_error)?
          .unwrap_or_default(),
        bonus: row
          .try_get::<Option<i64>, _>("save_bonus")
          .map_err(read_error)?
          .unwrap_or_default(),
        auto_roll: opt_text("save_auto_roll")?.unwrap_or_default(),
      })
    })
    .transpose()?;
  Ok(Condition {
    id: row.try_get("condition_id").map_err(read_error)?,
    name: row.try_get("name").map_err(read_error)?,
    note: row.try_get("note").map_err(read_error)?,
    duration,
    save_to_end,
  })
}

async fn fetch_treasure(
  conn: &mut AnyConnection,
  user_id: &str,
) -> Result<Option<TreasureRoll>, EncounterStoreError> {
  let Some(row) =
    sqlx::query("SELECT * FROM encounter_treasure WHERE user_id = $1")
      .bind(user_id)
      .fetch_optional(&mut *conn)
      .await
      .map_err(read_error)?
  else {
    return Ok(None);
  };

  let mut roll = TreasureRoll {
    kind: row.try_get("kind").map_err(read_error)?,
    bracket: row.try_get("bracket").map_err(read_error)?,
    coins: coins_from_row(&row)?,
    gems: Vec::new(),
    art: Vec::new(),
    magic: Vec::new(),
    mundane: Vec::new(),
    weapons: Vec::new(),
    armor: Vec::new(),
    source: source_from_row(&row)?,
    contributions: fetch_contributions(conn, user_id).await?,
    loot: Vec::new(),
  };

  let items = sqlx::query(
    "SELECT * FROM encounter_treasure_items WHERE user_id = $1 \
     ORDER BY position",
  )
  .bind(user_id)
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?;

  for item in &items {
    let contribution_position: i64 =
      item.try_get("contribution_position").map_err(read_error)?;
    let category: String = item.try_get("category").map_err(read_error)?;
    if contribution_position == ROLL_LEVEL {
      apply_item(
        &category,
        item,
        &mut roll.gems,
        &mut roll.art,
        &mut roll.magic,
        &mut roll.mundane,
        &mut roll.weapons,
        &mut roll.armor,
        &mut roll.loot,
      )?;
    } else {
      let Some(contribution) =
        roll.contributions.get_mut(contribution_position as usize)
      else {
        return Err(decode_error(format!(
          "treasure item references missing contribution \
           {contribution_position}"
        )));
      };
      apply_item(
        &category,
        item,
        &mut contribution.gems,
        &mut contribution.art,
        &mut contribution.magic,
        &mut contribution.mundane,
        &mut contribution.weapons,
        &mut contribution.armor,
        &mut contribution.loot,
      )?;
    }
  }

  Ok(Some(roll))
}

#[allow(clippy::too_many_arguments)]
fn apply_item(
  category: &str,
  row: &AnyRow,
  gems: &mut Vec<ValuedItem>,
  art: &mut Vec<ValuedItem>,
  magic: &mut Vec<MagicItem>,
  mundane: &mut Vec<ValuedItem>,
  weapons: &mut Vec<ValuedItem>,
  armor: &mut Vec<ValuedItem>,
  loot: &mut Vec<String>,
) -> Result<(), EncounterStoreError> {
  let name: String = row.try_get("name").map_err(read_error)?;
  let valued = |name: String| -> Result<ValuedItem, EncounterStoreError> {
    Ok(ValuedItem {
      name,
      value_gp: row
        .try_get::<Option<i64>, _>("value_gp")
        .map_err(read_error)?
        .unwrap_or_default(),
    })
  };
  match category {
    "gems" => gems.push(valued(name)?),
    "art" => art.push(valued(name)?),
    "mundane" => mundane.push(valued(name)?),
    "weapons" => weapons.push(valued(name)?),
    "armor" => armor.push(valued(name)?),
    "magic" => magic.push(MagicItem {
      name,
      rarity: row
        .try_get::<Option<String>, _>("rarity")
        .map_err(read_error)?
        .unwrap_or_default(),
      table: row
        .try_get::<Option<String>, _>("table_key")
        .map_err(read_error)?
        .unwrap_or_default(),
    }),
    "loot" => loot.push(name),
    other => {
      return Err(decode_error(format!(
        "unknown treasure item category {other:?}"
      )))
    }
  }
  Ok(())
}

async fn fetch_contributions(
  conn: &mut AnyConnection,
  user_id: &str,
) -> Result<Vec<Contribution>, EncounterStoreError> {
  sqlx::query(
    "SELECT * FROM encounter_treasure_contributions WHERE user_id = $1 \
     ORDER BY position",
  )
  .bind(user_id)
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?
  .iter()
  .map(|row| {
    Ok(Contribution {
      creature_name: row.try_get("creature_name").map_err(read_error)?,
      coins: coins_from_row(row)?,
      gems: Vec::new(),
      art: Vec::new(),
      magic: Vec::new(),
      mundane: Vec::new(),
      weapons: Vec::new(),
      armor: Vec::new(),
      loot: Vec::new(),
      bracket: row.try_get("bracket").map_err(read_error)?,
    })
  })
  .collect()
}

fn coins_from_row(row: &AnyRow) -> Result<Coins, EncounterStoreError> {
  Ok(Coins {
    copper: row.try_get("coin_copper").map_err(read_error)?,
    silver: row.try_get("coin_silver").map_err(read_error)?,
    electrum: row.try_get("coin_electrum").map_err(read_error)?,
    gold: row.try_get("coin_gold").map_err(read_error)?,
    platinum: row.try_get("coin_platinum").map_err(read_error)?,
  })
}

fn source_from_row(
  row: &AnyRow,
) -> Result<Option<RowSource>, EncounterStoreError> {
  if row.try_get::<i64, _>("has_source").map_err(read_error)? == 0 {
    return Ok(None);
  }
  let coin =
    |prefix: &str| -> Result<Option<(i64, i64, i64)>, EncounterStoreError> {
      let count: Option<i64> = row
        .try_get(format!("src_{prefix}_count").as_str())
        .map_err(read_error)?;
      let faces: Option<i64> = row
        .try_get(format!("src_{prefix}_faces").as_str())
        .map_err(read_error)?;
      let mult: Option<i64> = row
        .try_get(format!("src_{prefix}_mult").as_str())
        .map_err(read_error)?;
      Ok(match (count, faces, mult) {
        (Some(c), Some(f), Some(m)) => Some((c, f, m)),
        _ => None,
      })
    };
  let spec = |prefix: &str,
              tier_col: &str|
   -> Result<Option<Spec>, EncounterStoreError> {
    let count: Option<i64> = row
      .try_get(format!("src_{prefix}_count").as_str())
      .map_err(read_error)?;
    let faces: Option<i64> = row
      .try_get(format!("src_{prefix}_faces").as_str())
      .map_err(read_error)?;
    let tier: Option<String> = row.try_get(tier_col).map_err(read_error)?;
    Ok(match (count, faces, tier) {
      (Some(count), Some(faces), Some(tier)) => {
        Some(Spec { count, faces, tier })
      }
      _ => None,
    })
  };
  Ok(Some(RowSource {
    coin_formulas: super::wire::CoinFormulas {
      copper: coin("copper")?,
      silver: coin("silver")?,
      electrum: coin("electrum")?,
      gold: coin("gold")?,
      platinum: coin("platinum")?,
    },
    gems_spec: spec("gems", "src_gems_tier")?,
    art_spec: spec("art", "src_art_tier")?,
    magic_spec: spec("magic", "src_magic_table")?,
  }))
}
