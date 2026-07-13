//! Wire codec + SQL for the user-named condition presets.
//!
//! Mirrors `frontend/src/Ui/Condition/Wire.elm`: the payload is a
//! flat JSON dict keyed by preset name.  The Elm `decodePresets` also
//! accepts a literal `null` as the empty dict (that is what GET
//! returns before the first save), so the decoder here does too.
//!
//! Per the Elm `decodePreset`, every field is required except
//! `category` (defaults to `""` for presets saved before the
//! bundled-defaults pass); `saveToEnd` must be PRESENT but may be
//! null.  Unknown enum tokens (`durationKind`, phases, `autoRoll`)
//! fail the payload, exactly as the Elm decoder does.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::{json, Map, Value};
use sqlx::{AnyConnection, Row};
use std::collections::BTreeMap;

use super::{as_object, opt_str_or, req_i64, req_str};
use crate::per_user_store::PerUserFeature;

pub struct Preset {
  pub condition_name: String,
  pub custom_name: String,
  pub note: String,
  pub duration_kind: String,
  pub until_phase: String,
  pub countdown_turns_text: String,
  pub countdown_turns: i64,
  pub countdown_phase: String,
  pub save_to_end: Option<SaveToEnd>,
  pub category: String,
}

pub struct SaveToEnd {
  pub ability: String,
  pub dc_text: String,
  pub dc: i64,
  pub bonus_text: String,
  pub bonus: i64,
  pub auto_roll: String,
}

/// The condition-presets feature: a name-keyed preset dict per user.
pub struct ConditionPresets;

impl PerUserFeature for ConditionPresets {
  const LABEL: &'static str = "condition-presets";
  const PARENT_TABLE: &'static str = "condition_preset_sets";
  type Data = BTreeMap<String, Preset>;

  fn decode(payload: &Value) -> Result<Self::Data, String> {
    // `D.oneOf [D.null Dict.empty, D.dict decodePreset]`.
    if payload.is_null() {
      return Ok(BTreeMap::new());
    }
    as_object(payload, "condition presets")?
      .iter()
      .map(|(key, raw)| Ok((key.clone(), decode_preset(raw, key)?)))
      .collect()
  }

  fn encode(data: &Self::Data) -> Value {
    Value::Object(
      data
        .iter()
        .map(|(key, preset)| (key.clone(), encode_preset(preset)))
        .collect(),
    )
  }

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    data: &Self::Data,
  ) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO condition_preset_sets (user_id) VALUES ($1)")
      .bind(user_id.as_str())
      .execute(&mut *conn)
      .await?;

    for (key, preset) in data {
      sqlx::query(
        "INSERT INTO condition_presets (user_id, preset_key, \
         condition_name, custom_name, note, duration_kind, \
         until_phase, countdown_turns_text, countdown_turns, \
         countdown_phase, save_ability, save_dc_text, save_dc, \
         save_bonus_text, save_bonus, save_auto_roll, category) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, \
         $13, $14, $15, $16, $17)",
      )
      .bind(user_id.as_str())
      .bind(key)
      .bind(&preset.condition_name)
      .bind(&preset.custom_name)
      .bind(&preset.note)
      .bind(&preset.duration_kind)
      .bind(&preset.until_phase)
      .bind(&preset.countdown_turns_text)
      .bind(preset.countdown_turns)
      .bind(&preset.countdown_phase)
      .bind(preset.save_to_end.as_ref().map(|s| s.ability.clone()))
      .bind(preset.save_to_end.as_ref().map(|s| s.dc_text.clone()))
      .bind(preset.save_to_end.as_ref().map(|s| s.dc))
      .bind(preset.save_to_end.as_ref().map(|s| s.bonus_text.clone()))
      .bind(preset.save_to_end.as_ref().map(|s| s.bonus))
      .bind(preset.save_to_end.as_ref().map(|s| s.auto_roll.clone()))
      .bind(&preset.category)
      .execute(&mut *conn)
      .await?;
    }
    Ok(())
  }

  async fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> Result<Option<Self::Data>, sqlx::Error> {
    if sqlx::query(
      "SELECT user_id FROM condition_preset_sets WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_optional(db.pool())
    .await?
    .is_none()
    {
      return Ok(None);
    }

    sqlx::query(
      "SELECT preset_key, condition_name, custom_name, note, \
       duration_kind, until_phase, countdown_turns_text, \
       countdown_turns, countdown_phase, save_ability, save_dc_text, \
       save_dc, save_bonus_text, save_bonus, save_auto_roll, category \
       FROM condition_presets WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    .iter()
    .map(|row| {
      Ok((
        row.try_get::<String, _>("preset_key")?,
        Preset {
          condition_name: row.try_get("condition_name")?,
          custom_name: row.try_get("custom_name")?,
          note: row.try_get("note")?,
          duration_kind: row.try_get("duration_kind")?,
          until_phase: row.try_get("until_phase")?,
          countdown_turns_text: row.try_get("countdown_turns_text")?,
          countdown_turns: row.try_get("countdown_turns")?,
          countdown_phase: row.try_get("countdown_phase")?,
          save_to_end: save_to_end_from_row(row)?,
          category: row.try_get("category")?,
        },
      ))
    })
    .collect::<Result<BTreeMap<_, _>, sqlx::Error>>()
    .map(Some)
  }
}

/// The saveToEnd block is all-or-nothing: a NULL `save_ability` marks
/// the whole block absent (`"saveToEnd": null` on the wire).
fn save_to_end_from_row(
  row: &sqlx::any::AnyRow,
) -> Result<Option<SaveToEnd>, sqlx::Error> {
  row
    .try_get::<Option<String>, _>("save_ability")?
    .map(|ability| {
      Ok(SaveToEnd {
        ability,
        dc_text: row
          .try_get::<Option<String>, _>("save_dc_text")?
          .unwrap_or_default(),
        dc: row.try_get::<Option<i64>, _>("save_dc")?.unwrap_or(0),
        bonus_text: row
          .try_get::<Option<String>, _>("save_bonus_text")?
          .unwrap_or_default(),
        bonus: row.try_get::<Option<i64>, _>("save_bonus")?.unwrap_or(0),
        auto_roll: row
          .try_get::<Option<String>, _>("save_auto_roll")?
          .unwrap_or_else(|| "atEnd".to_string()),
      })
    })
    .transpose()
}

fn decode_preset(raw: &Value, key: &str) -> Result<Preset, String> {
  let context = format!("condition preset {key:?}");
  let map = as_object(raw, &context)?;
  Ok(Preset {
    condition_name: req_str(map, "conditionName", &context)?,
    custom_name: req_str(map, "customName", &context)?,
    note: req_str(map, "note", &context)?,
    duration_kind: duration_kind(map, &context)?,
    until_phase: turn_phase(map, "untilPhase", &context)?,
    countdown_turns_text: req_str(map, "countdownTurnsText", &context)?,
    countdown_turns: req_i64(map, "countdownTurns", &context)?,
    countdown_phase: turn_phase(map, "countdownPhase", &context)?,
    save_to_end: decode_save_to_end(map, &context)?,
    category: opt_str_or(map, "category", ""),
  })
}

fn duration_kind(
  map: &Map<String, Value>,
  context: &str,
) -> Result<String, String> {
  match req_str(map, "durationKind", context)?.as_str() {
    kind @ ("manual" | "untilTurn" | "countdown") => Ok(kind.to_string()),
    other => Err(format!("{context}: unknown duration kind {other:?}")),
  }
}

fn turn_phase(
  map: &Map<String, Value>,
  key: &str,
  context: &str,
) -> Result<String, String> {
  match req_str(map, key, context)?.as_str() {
    phase @ ("atBegin" | "atEnd") => Ok(phase.to_string()),
    other => Err(format!("{context}: unknown turn phase {other:?} in {key:?}")),
  }
}

/// `required "saveToEnd" (D.nullable decodeSaveToEnd)`: the field
/// must exist, but null decodes to `None`.
fn decode_save_to_end(
  map: &Map<String, Value>,
  context: &str,
) -> Result<Option<SaveToEnd>, String> {
  match map.get("saveToEnd") {
    None => Err(format!("{context}: missing required field \"saveToEnd\"")),
    Some(Value::Null) => Ok(None),
    Some(raw) => {
      let inner_context = format!("{context}, saveToEnd");
      let inner = as_object(raw, &inner_context)?;
      Ok(Some(SaveToEnd {
        ability: req_str(inner, "ability", &inner_context)?,
        dc_text: req_str(inner, "dcText", &inner_context)?,
        dc: req_i64(inner, "dc", &inner_context)?,
        bonus_text: req_str(inner, "bonusText", &inner_context)?,
        bonus: req_i64(inner, "bonus", &inner_context)?,
        auto_roll: match req_str(inner, "autoRoll", &inner_context)?.as_str() {
          mode @ ("manual" | "atBegin" | "atEnd") => mode.to_string(),
          other => {
            return Err(format!(
              "{inner_context}: unknown auto-roll mode {other:?}"
            ))
          }
        },
      }))
    }
  }
}

fn encode_preset(preset: &Preset) -> Value {
  json!({
    "conditionName": preset.condition_name,
    "customName": preset.custom_name,
    "note": preset.note,
    "durationKind": preset.duration_kind,
    "untilPhase": preset.until_phase,
    "countdownTurnsText": preset.countdown_turns_text,
    "countdownTurns": preset.countdown_turns,
    "countdownPhase": preset.countdown_phase,
    "saveToEnd": preset.save_to_end.as_ref().map_or(Value::Null, |s| json!({
      "ability": s.ability,
      "dcText": s.dc_text,
      "dc": s.dc,
      "bonusText": s.bonus_text,
      "bonus": s.bonus,
      "autoRoll": s.auto_roll,
    })),
    "category": preset.category,
  })
}
