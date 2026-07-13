//! Wire codec + SQL for the "Tune your rolls" treasure profiles.
//!
//! Mirrors `frontend/src/Encounter/Treasure/ProfileWire.elm`, whose
//! per-profile body is `Encounter.Wire.decodeTreasureSettings` /
//! `encodeTreasureSettings`.  The Elm settings decoder is fully
//! tolerant — every knob falls back to a default when absent or
//! mistyped — so a profile body can be any JSON object (or even a
//! scalar; Elm's `D.field` lookups simply fail into their fallbacks).
//! The only decode failure is a top-level payload that is neither an
//! object nor null (`decodeProfiles` accepts null as the empty dict).
//!
//! Fallback rules, straight from `Encounter.Wire`:
//!
//! - Count knobs (`coinsCount`, …): unknown or missing → `"normal"`
//!   (`countAdjustFromWire` never fails).
//! - Value knobs (`gemsValue`, …): unknown or missing → `"normal"`.
//! - `hoardToggles`: when the field is present, each of the seven
//!   bools defaults per `decodeToggles` (coins/gems/art/magic False,
//!   mundane/weapons/armor True); when absent, the legacy pre-split
//!   flat fields are read off the profile body itself with the same
//!   defaults.
//! - `individualToggles`: when present, decoded like `hoardToggles`;
//!   when absent, the `defaultIndividualToggles` constant (only coins
//!   enabled).
//! - `magicScrollChance`: missing or non-int → 15.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::{json, Map, Value};
use sqlx::{AnyConnection, Row};
use std::collections::BTreeMap;

use super::{as_object, opt_bool_or, opt_i64_or};
use crate::per_user_store::PerUserFeature;

pub struct Settings {
  pub coins_count: String,
  pub gems_count: String,
  pub gems_value: String,
  pub art_count: String,
  pub art_value: String,
  pub magic_count: String,
  pub magic_value: String,
  pub mundane_count: String,
  pub weapons_count: String,
  pub armor_count: String,
  pub hoard_toggles: Toggles,
  pub individual_toggles: Toggles,
  pub magic_scroll_chance: i64,
}

pub struct Toggles {
  pub coins_none: bool,
  pub gems_none: bool,
  pub art_none: bool,
  pub magic_none: bool,
  pub mundane_none: bool,
  pub weapons_none: bool,
  pub armor_none: bool,
}

/// `Encounter.Treasure.defaultIndividualToggles`: only coins roll by
/// default on individual treasure.
fn default_individual_toggles() -> Toggles {
  Toggles {
    coins_none: false,
    gems_none: true,
    art_none: true,
    magic_none: true,
    mundane_none: true,
    weapons_none: true,
    armor_none: true,
  }
}

/// The treasure-profiles feature: a name-keyed settings dict per
/// user.
pub struct TreasureProfiles;

impl PerUserFeature for TreasureProfiles {
  const LABEL: &'static str = "treasure-profiles";
  const PARENT_TABLE: &'static str = "treasure_profile_sets";
  type Data = BTreeMap<String, Settings>;

  fn decode(payload: &Value) -> Result<Self::Data, String> {
    // `D.oneOf [D.null Dict.empty, D.dict decodeTreasureSettings]`.
    if payload.is_null() {
      return Ok(BTreeMap::new());
    }
    Ok(
      as_object(payload, "treasure profiles")?
        .iter()
        .map(|(name, raw)| (name.clone(), decode_settings(raw)))
        .collect(),
    )
  }

  fn encode(data: &Self::Data) -> Value {
    Value::Object(
      data
        .iter()
        .map(|(name, settings)| (name.clone(), encode_settings(settings)))
        .collect(),
    )
  }

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    data: &Self::Data,
  ) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO treasure_profile_sets (user_id) VALUES ($1)")
      .bind(user_id.as_str())
      .execute(&mut *conn)
      .await?;

    for (name, s) in data {
      sqlx::query(
        "INSERT INTO treasure_profiles (user_id, name, coins_count, \
         gems_count, art_count, magic_count, mundane_count, \
         weapons_count, armor_count, gems_value, art_value, \
         magic_value, hoard_coins_none, hoard_gems_none, \
         hoard_art_none, hoard_magic_none, hoard_mundane_none, \
         hoard_weapons_none, hoard_armor_none, \
         individual_coins_none, individual_gems_none, \
         individual_art_none, individual_magic_none, \
         individual_mundane_none, individual_weapons_none, \
         individual_armor_none, magic_scroll_chance) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, \
         $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, \
         $25, $26, $27)",
      )
      .bind(user_id.as_str())
      .bind(name)
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
      .await?;
    }
    Ok(())
  }

  async fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> Result<Option<Self::Data>, sqlx::Error> {
    if sqlx::query(
      "SELECT user_id FROM treasure_profile_sets WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_optional(db.pool())
    .await?
    .is_none()
    {
      return Ok(None);
    }

    sqlx::query("SELECT * FROM treasure_profiles WHERE user_id = $1")
      .bind(user_id.as_str())
      .fetch_all(db.pool())
      .await?
      .iter()
      .map(|row| {
        let toggles = |prefix: &str| -> Result<Toggles, sqlx::Error> {
          let get = |col: String| -> Result<bool, sqlx::Error> {
            Ok(row.try_get::<i64, _>(col.as_str())? != 0)
          };
          Ok(Toggles {
            coins_none: get(format!("{prefix}_coins_none"))?,
            gems_none: get(format!("{prefix}_gems_none"))?,
            art_none: get(format!("{prefix}_art_none"))?,
            magic_none: get(format!("{prefix}_magic_none"))?,
            mundane_none: get(format!("{prefix}_mundane_none"))?,
            weapons_none: get(format!("{prefix}_weapons_none"))?,
            armor_none: get(format!("{prefix}_armor_none"))?,
          })
        };
        Ok((
          row.try_get::<String, _>("name")?,
          Settings {
            coins_count: row.try_get("coins_count")?,
            gems_count: row.try_get("gems_count")?,
            gems_value: row.try_get("gems_value")?,
            art_count: row.try_get("art_count")?,
            art_value: row.try_get("art_value")?,
            magic_count: row.try_get("magic_count")?,
            magic_value: row.try_get("magic_value")?,
            mundane_count: row.try_get("mundane_count")?,
            weapons_count: row.try_get("weapons_count")?,
            armor_count: row.try_get("armor_count")?,
            hoard_toggles: toggles("hoard")?,
            individual_toggles: toggles("individual")?,
            magic_scroll_chance: row.try_get("magic_scroll_chance")?,
          },
        ))
      })
      .collect::<Result<BTreeMap<_, _>, sqlx::Error>>()
      .map(Some)
  }
}

// ── decode ───────────────────────────────────────────────────────────────────

/// Decode one settings body.  Total: the Elm decoder never fails, so
/// neither does this.  A non-object body decodes as all defaults
/// (every `D.field` lookup fails into its fallback).
fn decode_settings(raw: &Value) -> Settings {
  let empty = Map::new();
  let map = raw.as_object().unwrap_or(&empty);
  Settings {
    coins_count: count_adjust(map, "coinsCount"),
    gems_count: count_adjust(map, "gemsCount"),
    gems_value: value_adjust(map, "gemsValue"),
    art_count: count_adjust(map, "artCount"),
    art_value: value_adjust(map, "artValue"),
    magic_count: count_adjust(map, "magicCount"),
    magic_value: value_adjust(map, "magicValue"),
    mundane_count: count_adjust(map, "mundaneCount"),
    weapons_count: count_adjust(map, "weaponsCount"),
    armor_count: count_adjust(map, "armorCount"),
    // Present hoardToggles (of ANY type — a non-object just yields
    // all defaults, since Elm's `decodeToggles` never fails) wins;
    // absent → the legacy flat fields live on the profile body
    // itself, with the same per-field defaults.
    hoard_toggles: decode_toggles(
      map
        .get("hoardToggles")
        .map_or(map, |v| v.as_object().unwrap_or(&empty)),
    ),
    individual_toggles: map
      .get("individualToggles")
      .map_or_else(default_individual_toggles, |v| {
        decode_toggles(v.as_object().unwrap_or(&empty))
      }),
    magic_scroll_chance: opt_i64_or(map, "magicScrollChance", 15),
  }
}

/// `countAdjustFromWire` never fails: anything but the two known
/// tokens is "normal".
fn count_adjust(map: &Map<String, Value>, key: &str) -> String {
  match map.get(key).and_then(Value::as_str) {
    Some(token @ ("fewer" | "more")) => token.to_string(),
    _ => "normal".to_string(),
  }
}

fn value_adjust(map: &Map<String, Value>, key: &str) -> String {
  match map.get(key).and_then(Value::as_str) {
    Some(token @ ("lower" | "higher")) => token.to_string(),
    _ => "normal".to_string(),
  }
}

/// `decodeToggles`: per-field defaults False for the four original
/// categories, True (off) for the three later-added ones.
fn decode_toggles(map: &Map<String, Value>) -> Toggles {
  Toggles {
    coins_none: opt_bool_or(map, "coinsNone", false),
    gems_none: opt_bool_or(map, "gemsNone", false),
    art_none: opt_bool_or(map, "artNone", false),
    magic_none: opt_bool_or(map, "magicNone", false),
    mundane_none: opt_bool_or(map, "mundaneNone", true),
    weapons_none: opt_bool_or(map, "weaponsNone", true),
    armor_none: opt_bool_or(map, "armorNone", true),
  }
}

// ── encode ───────────────────────────────────────────────────────────────────

fn encode_settings(s: &Settings) -> Value {
  json!({
    "coinsCount": s.coins_count,
    "gemsCount": s.gems_count,
    "gemsValue": s.gems_value,
    "artCount": s.art_count,
    "artValue": s.art_value,
    "magicCount": s.magic_count,
    "magicValue": s.magic_value,
    "mundaneCount": s.mundane_count,
    "weaponsCount": s.weapons_count,
    "armorCount": s.armor_count,
    "hoardToggles": encode_toggles(&s.hoard_toggles),
    "individualToggles": encode_toggles(&s.individual_toggles),
    "magicScrollChance": s.magic_scroll_chance,
  })
}

fn encode_toggles(t: &Toggles) -> Value {
  json!({
    "coinsNone": t.coins_none,
    "gemsNone": t.gems_none,
    "artNone": t.art_none,
    "magicNone": t.magic_none,
    "mundaneNone": t.mundane_none,
    "weaponsNone": t.weapons_none,
    "armorNone": t.armor_none,
  })
}
