//! Wire codec + SQL for Save Chain presets.
//!
//! Mirrors `frontend/src/Encounter/SaveChain/Wire.elm`: the payload
//! is a JSON dict keyed by preset name.  The decoder reproduces every
//! legacy shape that module tolerates:
//!
//! - `save_dc` may be absent, null, or an int (absent / a failing
//!   inner value fall back to null).
//! - `on_fail` / `on_success` may be absent or malformed — either
//!   falls back to the empty outcome.
//! - An outcome's `effects` list may be replaced by the
//!   pre-multi-effect `condition_name` / `condition_note` top-level
//!   fields; a blank name means no effects.
//! - `save_to_end` accepts three shapes: the canonical string enum
//!   (`"manual"` / `"at_begin"` / `"at_end"`; unknown strings →
//!   null), the pre-mode bool (`true` → `"at_end"`, `false` → null),
//!   and null / absent.
//! - An HP `amount` may be a string (`"8d6"`) or a legacy int.
//!
//! One deliberate server-side extra beyond the Elm decoder: the
//! ability is also read from a camelCase `saveAbility` field when the
//! canonical `save_ability` is absent — historical hand-shaped
//! payloads (and the integration suite's partial fixtures) use the
//! Elm record-field spelling.
//!
//! The encoder emits the canonical current shape: HP effects flatten
//! to `{kind}` / `{kind, amount}` objects and `save_to_end` is the
//! string enum or null.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::{json, Map, Value};
use sqlx::{AnyConnection, Row};
use std::collections::BTreeMap;
use uuid::Uuid;

use super::{as_object, opt_str_or, req_str};
use crate::per_user_store::PerUserFeature;

pub struct Chain {
  pub name: String,
  pub save_ability: String,
  pub save_dc: Option<i64>,
  pub on_fail: Outcome,
  pub on_success: Outcome,
}

#[derive(Default)]
pub struct Outcome {
  pub hp: HpEffect,
  pub effects: Vec<Effect>,
}

#[derive(Default)]
pub enum HpEffect {
  #[default]
  None,
  Damage(String),
  Heal(String),
  HalfFail,
}

pub struct Effect {
  pub name: String,
  pub note: String,
  pub save_to_end: Option<String>,
}

/// The Save Chain presets feature: a name-keyed chain dict per user.
pub struct SaveChains;

impl PerUserFeature for SaveChains {
  const LABEL: &'static str = "save-chain-presets";
  const PARENT_TABLE: &'static str = "save_chain_sets";
  type Data = BTreeMap<String, Chain>;

  fn decode(payload: &Value) -> Result<Self::Data, String> {
    as_object(payload, "save-chain presets")?
      .iter()
      .map(|(key, raw)| Ok((key.clone(), decode_chain(raw, key)?)))
      .collect()
  }

  fn encode(data: &Self::Data) -> Value {
    Value::Object(
      data
        .iter()
        .map(|(key, chain)| (key.clone(), encode_chain(chain)))
        .collect(),
    )
  }

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    data: &Self::Data,
  ) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO save_chain_sets (user_id) VALUES ($1)")
      .bind(user_id.as_str())
      .execute(&mut *conn)
      .await?;

    for (key, chain) in data {
      let chain_id = Uuid::new_v4().to_string();
      let (fail_kind, fail_amount) = hp_columns(&chain.on_fail.hp);
      let (success_kind, success_amount) = hp_columns(&chain.on_success.hp);
      sqlx::query(
        "INSERT INTO save_chains (id, user_id, preset_key, name, \
         save_ability, save_dc, fail_hp_kind, fail_hp_amount, \
         success_hp_kind, success_hp_amount) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
      )
      .bind(&chain_id)
      .bind(user_id.as_str())
      .bind(key)
      .bind(&chain.name)
      .bind(&chain.save_ability)
      .bind(chain.save_dc)
      .bind(fail_kind)
      .bind(fail_amount)
      .bind(success_kind)
      .bind(success_amount)
      .execute(&mut *conn)
      .await?;

      for (side, effects) in [
        ("fail", &chain.on_fail.effects),
        ("success", &chain.on_success.effects),
      ] {
        for (i, effect) in effects.iter().enumerate() {
          sqlx::query(
            "INSERT INTO save_chain_effects (chain_id, side, \
             position, name, note, save_to_end) \
             VALUES ($1, $2, $3, $4, $5, $6)",
          )
          .bind(&chain_id)
          .bind(side)
          .bind(i as i64)
          .bind(&effect.name)
          .bind(&effect.note)
          .bind(&effect.save_to_end)
          .execute(&mut *conn)
          .await?;
        }
      }
    }
    Ok(())
  }

  async fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> Result<Option<Self::Data>, sqlx::Error> {
    if sqlx::query("SELECT user_id FROM save_chain_sets WHERE user_id = $1")
      .bind(user_id.as_str())
      .fetch_optional(db.pool())
      .await?
      .is_none()
    {
      return Ok(None);
    }

    let mut chains: Vec<(String, String, Chain)> = sqlx::query(
      "SELECT id, preset_key, name, save_ability, save_dc, \
       fail_hp_kind, fail_hp_amount, success_hp_kind, \
       success_hp_amount \
       FROM save_chains WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    .iter()
    .map(|row| {
      Ok::<_, sqlx::Error>((
        row.try_get::<String, _>("id")?,
        row.try_get::<String, _>("preset_key")?,
        Chain {
          name: row.try_get("name")?,
          save_ability: row.try_get("save_ability")?,
          save_dc: row.try_get("save_dc")?,
          on_fail: Outcome {
            hp: hp_from_columns(
              &row.try_get::<String, _>("fail_hp_kind")?,
              row.try_get("fail_hp_amount")?,
            ),
            effects: Vec::new(),
          },
          on_success: Outcome {
            hp: hp_from_columns(
              &row.try_get::<String, _>("success_hp_kind")?,
              row.try_get("success_hp_amount")?,
            ),
            effects: Vec::new(),
          },
        },
      ))
    })
    .collect::<Result<_, _>>()?;

    for row in sqlx::query(
      "SELECT e.chain_id, e.side, e.name, e.note, e.save_to_end \
       FROM save_chain_effects e \
       JOIN save_chains c ON c.id = e.chain_id \
       WHERE c.user_id = $1 ORDER BY e.position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let owner: String = row.try_get("chain_id")?;
      let side: String = row.try_get("side")?;
      if let Some((_, _, chain)) =
        chains.iter_mut().find(|(id, _, _)| *id == owner)
      {
        let outcome = if side == "success" {
          &mut chain.on_success
        } else {
          &mut chain.on_fail
        };
        outcome.effects.push(Effect {
          name: row.try_get("name")?,
          note: row.try_get("note")?,
          save_to_end: row.try_get("save_to_end")?,
        });
      }
    }

    Ok(Some(
      chains
        .into_iter()
        .map(|(_, key, chain)| (key, chain))
        .collect(),
    ))
  }
}

fn hp_columns(hp: &HpEffect) -> (&'static str, Option<String>) {
  match hp {
    HpEffect::None => ("none", None),
    HpEffect::Damage(amount) => ("damage", Some(amount.clone())),
    HpEffect::Heal(amount) => ("heal", Some(amount.clone())),
    HpEffect::HalfFail => ("half_fail", None),
  }
}

fn hp_from_columns(kind: &str, amount: Option<String>) -> HpEffect {
  match (kind, amount) {
    ("damage", Some(amount)) => HpEffect::Damage(amount),
    ("heal", Some(amount)) => HpEffect::Heal(amount),
    ("half_fail", _) => HpEffect::HalfFail,
    // "none", and defensively any unknown kind or a damage/heal row
    // that lost its amount, all read as no HP effect.
    _ => HpEffect::None,
  }
}

// ── decode ───────────────────────────────────────────────────────────────────

fn decode_chain(raw: &Value, key: &str) -> Result<Chain, String> {
  let context = format!("save chain {key:?}");
  let map = as_object(raw, &context)?;
  Ok(Chain {
    name: req_str(map, "name", &context)?,
    save_ability: decode_ability(map, &context)?,
    // `optionalField "save_dc" (D.nullable D.int) Nothing`: absent,
    // null, and a non-int value all fall back to Nothing.
    save_dc: map.get("save_dc").and_then(Value::as_i64),
    on_fail: decode_outcome(map.get("on_fail")),
    on_success: decode_outcome(map.get("on_success")),
  })
}

/// The canonical field is `save_ability`; the camelCase `saveAbility`
/// fallback covers historical hand-shaped payloads.  Ability tokens
/// are matched case-insensitively (the Elm decoder lowercases), and
/// an unknown token fails the payload, as `abilityDecoder` does.
fn decode_ability(
  map: &Map<String, Value>,
  context: &str,
) -> Result<String, String> {
  let raw = map
    .get("save_ability")
    .or_else(|| map.get("saveAbility"))
    .and_then(Value::as_str)
    .ok_or_else(|| {
      format!("{context}: missing or non-string field \"save_ability\"")
    })?;
  match raw.to_lowercase().as_str() {
    ability @ ("str" | "dex" | "con" | "int" | "wis" | "cha") => {
      Ok(ability.to_string())
    }
    other => Err(format!("{context}: unknown ability {other:?}")),
  }
}

/// `optionalField … outcomeDecoder SaveChain.empty` — and the Elm
/// outcome decoder itself never fails (every sub-decoder is wrapped
/// in a fallback), so this function is total.
fn decode_outcome(raw: Option<&Value>) -> Outcome {
  let Some(map) = raw.and_then(Value::as_object) else {
    return Outcome::default();
  };
  Outcome {
    hp: decode_hp(map.get("hp")),
    effects: decode_effects(map),
  }
}

/// `D.oneOf [D.field "effects" (D.list effectDecoder),
/// legacyEffectsDecoder]`: a missing or partially-invalid effects
/// list falls through to the pre-multi-effect `condition_name` /
/// `condition_note` shape, where a blank name means no effects.
fn decode_effects(map: &Map<String, Value>) -> Vec<Effect> {
  map
    .get("effects")
    .and_then(Value::as_array)
    .and_then(|items| {
      items.iter().map(decode_effect).collect::<Option<Vec<_>>>()
    })
    .unwrap_or_else(|| {
      let name = opt_str_or(map, "condition_name", "");
      if name.trim().is_empty() {
        Vec::new()
      } else {
        vec![Effect {
          name,
          note: opt_str_or(map, "condition_note", ""),
          save_to_end: None,
        }]
      }
    })
}

/// One effect; `None` when the item does not decode (which fails the
/// whole list, matching `D.list effectDecoder`).
fn decode_effect(raw: &Value) -> Option<Effect> {
  let map = raw.as_object()?;
  Some(Effect {
    name: map.get("name").and_then(Value::as_str)?.to_string(),
    note: opt_str_or(map, "note", ""),
    save_to_end: decode_save_to_end(map.get("save_to_end")),
  })
}

/// The three-shape `save_to_end` decoder: canonical string enum
/// (unknown strings → null), legacy bool (`true` → `"at_end"`), and
/// null / absent / other types → null.
fn decode_save_to_end(raw: Option<&Value>) -> Option<String> {
  match raw {
    Some(Value::String(s)) => match s.as_str() {
      mode @ ("manual" | "at_begin" | "at_end") => Some(mode.to_string()),
      _ => None,
    },
    Some(Value::Bool(true)) => Some("at_end".to_string()),
    _ => None,
  }
}

/// `optionalField "hp" hpEffectDecoder NoHpEffect`: a missing kind,
/// an unknown kind, or a damage/heal without a usable amount all fall
/// back to no effect.  The legacy int amount is stringified, as the
/// Elm `amountDecoder` does.
fn decode_hp(raw: Option<&Value>) -> HpEffect {
  let Some(map) = raw.and_then(Value::as_object) else {
    return HpEffect::None;
  };
  let amount = || {
    map.get("amount").and_then(|v| match v {
      Value::String(s) => Some(s.clone()),
      Value::Number(n) => n.as_i64().map(|i| i.to_string()),
      _ => None,
    })
  };
  match map.get("kind").and_then(Value::as_str) {
    Some("damage") => amount().map_or(HpEffect::None, HpEffect::Damage),
    Some("heal") => amount().map_or(HpEffect::None, HpEffect::Heal),
    Some("half_fail") => HpEffect::HalfFail,
    _ => HpEffect::None,
  }
}

// ── encode ───────────────────────────────────────────────────────────────────

fn encode_chain(chain: &Chain) -> Value {
  json!({
    "name": chain.name,
    "save_ability": chain.save_ability,
    "save_dc": chain.save_dc,
    "on_fail": encode_outcome(&chain.on_fail),
    "on_success": encode_outcome(&chain.on_success),
  })
}

fn encode_outcome(outcome: &Outcome) -> Value {
  json!({
    "hp": encode_hp(&outcome.hp),
    "effects": outcome.effects.iter().map(encode_effect).collect::<Vec<_>>(),
  })
}

fn encode_hp(hp: &HpEffect) -> Value {
  match hp {
    HpEffect::None => json!({ "kind": "none" }),
    HpEffect::Damage(amount) => json!({ "kind": "damage", "amount": amount }),
    HpEffect::Heal(amount) => json!({ "kind": "heal", "amount": amount }),
    HpEffect::HalfFail => json!({ "kind": "half_fail" }),
  }
}

fn encode_effect(effect: &Effect) -> Value {
  json!({
    "name": effect.name,
    "note": effect.note,
    "save_to_end": effect.save_to_end,
  })
}
