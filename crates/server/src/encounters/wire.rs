//! Wire codec for the live encounter, mirroring
//! `frontend/src/Encounter/Wire.elm` (which is the schema spec).
//!
//! The decoder reproduces the Elm module's leniency exactly, since
//! the one-shot boot import feeds it payloads written by any
//! historical frontend version:
//!
//! - `required` fields fail the payload when missing or mistyped
//!   (`creatures`, `activeName`, `round`; per creature `name`,
//!   `initiative`, `currentHp`, `maxHp`, `armorClass`; and the
//!   interiors of any list the wire decodes all-or-nothing).
//! - `optional` fields never fail: absent, null, and
//!   present-but-mistyped values all fall back to the default —
//!   including whole lists (`conditions`, `saveNotices`,
//!   `rechargeAbilities`), where one bad item defaults the entire
//!   list, exactly as Elm's `D.oneOf [D.field … , D.null … ,
//!   D.succeed …]` does.
//! - `optionalEither` honors the legacy field names: `holding` for
//!   `readied`, and the pre-count `hasLegendaryActions` /
//!   `hasLegendaryResistance` bools (a `true` flag maps to the
//!   conservative 3-pip default; the numeric count wins when
//!   present).
//! - `treasure` accepts the legacy `{ "roll": … }` wrapper, treats
//!   any undecodable value as absent, and fills the later-added
//!   `source` / `contributions` / `loot` / `mundane` / `weapons` /
//!   `armor` fields with their pre-feature defaults.  Magic items
//!   without a `table` letter default to `"A"`.
//! - `treasureSettings` is total: every knob, toggle, and the
//!   scroll chance has a default, and an absent `hoardToggles`
//!   block falls back to the pre-split flat fields on the settings
//!   object itself.
//!
//! Enum-ish tokens (cover, phases, targets, treasure kinds,
//! brackets, tiers, rarities, auto-roll modes) are stored as their
//! validated wire spellings rather than Rust enums — the decoder is
//! the only writer, so an unknown token can never reach the tables.
//!
//! The encoder emits the canonical current shape exactly as the Elm
//! encoder would: every field present, `encodeMaybe`-style nulls for
//! absent optionals, spent-pip sets as sorted ascending lists, and
//! `originalMaxHp` materialized (the decoder already defaulted it to
//! `maxHp`).  For a payload produced by the current Elm encoder,
//! `encode(decode(v)) == v` value-for-value; the HTTP layer already
//! normalizes JSON object key order (serde_json), so value equality
//! is byte-shape equality on the wire.

use std::collections::BTreeSet;

use serde_json::{json, Map, Value};

// ── model ────────────────────────────────────────────────────────────────────

pub struct Encounter {
  pub creatures: Vec<Creature>,
  pub active_name: String,
  pub round: i64,
  pub treasure: Option<TreasureRoll>,
  pub treasure_settings: TreasureSettings,
}

pub struct Creature {
  pub name: String,
  pub kind: String,
  pub initiative: i64,
  pub initiative_bonus: i64,
  pub current_hp: i64,
  pub max_hp: i64,
  pub original_max_hp: i64,
  pub temp_hp: i64,
  pub armor_class: i64,
  pub speed: i64,
  pub conditions: Vec<Condition>,
  pub save_notices: Vec<SaveNotice>,
  pub selected: bool,
  pub cover: String,
  pub concentrating: bool,
  pub hiding: bool,
  pub dodging: bool,
  pub flying: bool,
  pub fly_height: i64,
  pub bloodied: bool,
  pub death_save_successes: i64,
  pub death_save_failures: i64,
  pub accepting_death_saves: bool,
  pub reaction_used: bool,
  pub recharge_abilities: Vec<RechargeAbility>,
  pub readied: bool,
  pub inactive: bool,
  pub note: String,
  pub memo: String,
  pub timer: Option<Timer>,
  pub creature_id: Option<String>,
  pub legendary_actions_count: i64,
  pub legendary_actions_lair_bonus: i64,
  /// Sorted ascending, deduplicated — Elm `Set Int` semantics.
  pub legendary_actions_used: Vec<i64>,
  pub legendary_resistance_count: i64,
  pub legendary_resistance_lair_bonus: i64,
  pub legendary_resistance_used: Vec<i64>,
  pub is_placeholder: bool,
  pub creature_kind: String,
  pub race: String,
  pub alignment: String,
  pub surprised: bool,
  pub has_special_reactions: bool,
}

pub struct Condition {
  pub id: i64,
  pub name: String,
  pub note: String,
  pub duration: Duration,
  pub save_to_end: Option<SaveToEnd>,
}

pub enum Duration {
  Manual,
  UntilTurn {
    phase: String,
    target: String,
    name: String,
  },
  Countdown {
    phase: String,
    remaining: i64,
    skip_next_tick: bool,
  },
}

pub struct SaveToEnd {
  pub ability: String,
  pub dc: i64,
  pub bonus: i64,
  pub auto_roll: String,
}

pub struct SaveNotice {
  pub id: i64,
  pub condition_name: String,
  pub turns_remaining: i64,
}

pub struct RechargeAbility {
  pub name: String,
  pub low: i64,
  pub high: i64,
  pub ready: bool,
  pub awaiting_roll: bool,
}

pub struct Timer {
  pub remaining: i64,
  pub phase: String,
  pub ringing: bool,
  pub note: String,
}

pub struct TreasureSettings {
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
  pub hoard_toggles: CategoryToggles,
  pub individual_toggles: CategoryToggles,
  pub magic_scroll_chance: i64,
}

pub struct CategoryToggles {
  pub coins_none: bool,
  pub gems_none: bool,
  pub art_none: bool,
  pub magic_none: bool,
  pub mundane_none: bool,
  pub weapons_none: bool,
  pub armor_none: bool,
}

pub struct TreasureRoll {
  pub kind: String,
  pub bracket: String,
  pub coins: Coins,
  pub gems: Vec<ValuedItem>,
  pub art: Vec<ValuedItem>,
  pub magic: Vec<MagicItem>,
  pub mundane: Vec<ValuedItem>,
  pub weapons: Vec<ValuedItem>,
  pub armor: Vec<ValuedItem>,
  pub source: Option<RowSource>,
  pub contributions: Vec<Contribution>,
  pub loot: Vec<String>,
}

pub struct Coins {
  pub copper: i64,
  pub silver: i64,
  pub electrum: i64,
  pub gold: i64,
  pub platinum: i64,
}

/// Gems, art, and the flat mundane/weapons/armor items all share
/// the `{ name, valueGp }` wire shape.
pub struct ValuedItem {
  pub name: String,
  pub value_gp: i64,
}

pub struct MagicItem {
  pub name: String,
  pub rarity: String,
  pub table: String,
}

pub struct Contribution {
  pub creature_name: String,
  pub coins: Coins,
  pub gems: Vec<ValuedItem>,
  pub art: Vec<ValuedItem>,
  pub magic: Vec<MagicItem>,
  pub mundane: Vec<ValuedItem>,
  pub weapons: Vec<ValuedItem>,
  pub armor: Vec<ValuedItem>,
  pub loot: Vec<String>,
  pub bracket: String,
}

pub struct RowSource {
  pub coin_formulas: CoinFormulas,
  pub gems_spec: Option<Spec>,
  pub art_spec: Option<Spec>,
  pub magic_spec: Option<Spec>,
}

/// `(count, faces, mult)` per coin, `None` for a coin the
/// originating row doesn't produce.
#[derive(Default)]
pub struct CoinFormulas {
  pub copper: Option<(i64, i64, i64)>,
  pub silver: Option<(i64, i64, i64)>,
  pub electrum: Option<(i64, i64, i64)>,
  pub gold: Option<(i64, i64, i64)>,
  pub platinum: Option<(i64, i64, i64)>,
}

pub struct Spec {
  pub count: i64,
  pub faces: i64,
  pub tier: String,
}

impl Default for TreasureSettings {
  /// `Encounter.Treasure.defaultSettings`.
  fn default() -> Self {
    Self {
      coins_count: "normal".to_string(),
      gems_count: "normal".to_string(),
      gems_value: "normal".to_string(),
      art_count: "normal".to_string(),
      art_value: "normal".to_string(),
      magic_count: "normal".to_string(),
      magic_value: "normal".to_string(),
      mundane_count: "normal".to_string(),
      weapons_count: "normal".to_string(),
      armor_count: "normal".to_string(),
      hoard_toggles: CategoryToggles::default_hoard(),
      individual_toggles: CategoryToggles::default_individual(),
      magic_scroll_chance: 15,
    }
  }
}

impl CategoryToggles {
  /// `Encounter.Treasure.defaultHoardToggles`.
  fn default_hoard() -> Self {
    Self {
      coins_none: false,
      gems_none: false,
      art_none: false,
      magic_none: false,
      mundane_none: true,
      weapons_none: true,
      armor_none: true,
    }
  }

  /// `Encounter.Treasure.defaultIndividualToggles`.
  fn default_individual() -> Self {
    Self {
      coins_none: false,
      gems_none: true,
      art_none: true,
      magic_none: true,
      mundane_none: true,
      weapons_none: true,
      armor_none: true,
    }
  }
}

// ── decode helpers ───────────────────────────────────────────────────────────

/// Elm's `D.int`: an i64, or an f64 with no fractional part (Elm
/// ints are JS numbers, so `3.0` decodes as `3`).
fn as_int(value: &Value) -> Option<i64> {
  value.as_i64().or_else(|| {
    value.as_f64().and_then(|f| {
      (f.fract() == 0.0 && f >= i64::MIN as f64 && f <= i64::MAX as f64)
        .then_some(f as i64)
    })
  })
}

fn as_object<'a>(
  value: &'a Value,
  context: &str,
) -> Result<&'a Map<String, Value>, String> {
  value
    .as_object()
    .ok_or_else(|| format!("{context}: expected a JSON object"))
}

fn req_str(
  map: &Map<String, Value>,
  key: &str,
  context: &str,
) -> Result<String, String> {
  map
    .get(key)
    .and_then(Value::as_str)
    .map(str::to_string)
    .ok_or_else(|| format!("{context}: missing or non-string field {key:?}"))
}

fn req_int(
  map: &Map<String, Value>,
  key: &str,
  context: &str,
) -> Result<i64, String> {
  map
    .get(key)
    .and_then(as_int)
    .ok_or_else(|| format!("{context}: missing or non-integer field {key:?}"))
}

fn req_bool(
  map: &Map<String, Value>,
  key: &str,
  context: &str,
) -> Result<bool, String> {
  map
    .get(key)
    .and_then(Value::as_bool)
    .ok_or_else(|| format!("{context}: missing or non-bool field {key:?}"))
}

/// Elm Wire.elm's `optional`: absent, null, and present-but-invalid
/// all fall back to the default.  Total by construction.
fn opt_str(map: &Map<String, Value>, key: &str, default: &str) -> String {
  map
    .get(key)
    .and_then(Value::as_str)
    .map_or_else(|| default.to_string(), str::to_string)
}

fn opt_int(map: &Map<String, Value>, key: &str, default: i64) -> i64 {
  map.get(key).and_then(as_int).unwrap_or(default)
}

fn opt_bool(map: &Map<String, Value>, key: &str, default: bool) -> bool {
  map.get(key).and_then(Value::as_bool).unwrap_or(default)
}

/// Elm Wire.elm's `optionalEither current legacy D.bool default`:
/// the current name wins outright when present (a null or invalid
/// non-null value under the CURRENT name still consults the legacy
/// name only when the current decode *and* null checks both fail —
/// per `D.oneOf` order, current-valid, current-null, legacy-valid,
/// legacy-null, default).
fn opt_bool_either(
  map: &Map<String, Value>,
  current: &str,
  legacy: &str,
  default: bool,
) -> bool {
  match map.get(current) {
    Some(Value::Bool(b)) => *b,
    Some(Value::Null) => default,
    _ => match map.get(legacy) {
      Some(Value::Bool(b)) => *b,
      _ => default,
    },
  }
}

/// The legendary count decoder: `optionalEither count_field
/// legacy_bool_field (D.oneOf [D.int, D.bool |> D.map
/// boolToLegacyCount]) 0`.  A legacy `true` flag becomes 3 pips.
fn opt_legendary_count(
  map: &Map<String, Value>,
  current: &str,
  legacy: &str,
) -> i64 {
  let count_or_flag = |v: &Value| {
    as_int(v).or_else(|| v.as_bool().map(|b| if b { 3 } else { 0 }))
  };
  map.get(current).and_then(count_or_flag).unwrap_or_else(|| {
    if matches!(map.get(current), Some(Value::Null)) {
      0
    } else {
      map.get(legacy).and_then(count_or_flag).unwrap_or(0)
    }
  })
}

/// A validated token field: the decoder `dec` runs on the present
/// value; any failure (absent / null / unknown token) yields the
/// default, mirroring `optional name tokenDecoder default`.
fn opt_token(
  map: &Map<String, Value>,
  key: &str,
  allowed: &[&str],
  default: &str,
) -> String {
  map
    .get(key)
    .and_then(Value::as_str)
    .filter(|s| allowed.contains(s))
    .map_or_else(|| default.to_string(), str::to_string)
}

fn req_token(
  map: &Map<String, Value>,
  key: &str,
  allowed: &[&str],
  context: &str,
) -> Result<String, String> {
  let raw = req_str(map, key, context)?;
  if allowed.contains(&raw.as_str()) {
    Ok(raw)
  } else {
    Err(format!("{context}: unknown {key} token {raw:?}"))
  }
}

const PHASES: &[&str] = &["atBegin", "atEnd"];
const TARGETS: &[&str] = &["current", "next"];
const AUTO_ROLLS: &[&str] = &["manual", "atBegin", "atEnd"];
const COVERS: &[&str] = &["none", "half", "threeQuarters", "full"];
const TREASURE_KINDS: &[&str] = &["individual", "hoard"];
const BRACKETS: &[&str] = &["1to4", "5to10", "11to16", "17plus"];
const RARITIES: &[&str] =
  &["common", "uncommon", "rare", "very-rare", "legendary"];
const GEM_TIERS: &[&str] =
  &["10gp", "50gp", "100gp", "500gp", "1000gp", "5000gp"];
const ART_TIERS: &[&str] = &["25gp", "250gp", "750gp", "2500gp", "7500gp"];
const MAGIC_TABLES: &[&str] = &["A", "B", "C", "D", "E", "F", "G", "H", "I"];
const COUNT_ADJUSTS: &[&str] = &["fewer", "normal", "more"];
const VALUE_ADJUSTS: &[&str] = &["lower", "normal", "higher"];

// ── decode ───────────────────────────────────────────────────────────────────

/// Decode a wire encounter, with the full leniency documented in
/// the module docs.  The error string names the first field that
/// violated a `required` rule.
pub fn decode_encounter(value: &Value) -> Result<Encounter, String> {
  let map = as_object(value, "encounter")?;

  let creatures = map
    .get("creatures")
    .and_then(Value::as_array)
    .ok_or("encounter: missing or non-list field \"creatures\"")?
    .iter()
    .map(decode_creature)
    .collect::<Result<Vec<_>, _>>()?;

  Ok(Encounter {
    creatures,
    active_name: req_str(map, "activeName", "encounter")?,
    round: req_int(map, "round", "encounter")?,
    // `D.oneOf [D.field "treasure" (D.nullable decodeTreasureField),
    // D.succeed Nothing]`: an absent field, an explicit null, and a
    // present-but-undecodable value all read as no treasure.
    treasure: map
      .get("treasure")
      .and_then(|v| decode_treasure_field(v).ok()),
    treasure_settings: map
      .get("treasureSettings")
      .map(decode_settings)
      .unwrap_or_default(),
  })
}

fn decode_creature(value: &Value) -> Result<Creature, String> {
  let map = as_object(value, "creature")?;
  let context = "creature";
  let max_hp = req_int(map, "maxHp", context)?;

  Ok(Creature {
    name: req_str(map, "name", context)?,
    kind: opt_str(map, "kind", ""),
    initiative: req_int(map, "initiative", context)?,
    initiative_bonus: opt_int(map, "initiativeBonus", 0),
    current_hp: req_int(map, "currentHp", context)?,
    max_hp,
    // `optional "originalMaxHp" (D.map Just D.int) Nothing` then
    // `Maybe.withDefault maxHp`.
    original_max_hp: opt_int(map, "originalMaxHp", max_hp),
    temp_hp: opt_int(map, "tempHp", 0),
    armor_class: req_int(map, "armorClass", context)?,
    speed: opt_int(map, "speed", 30),
    conditions: decode_list_or_default(map, "conditions", decode_condition),
    save_notices: decode_list_or_default(
      map,
      "saveNotices",
      decode_save_notice,
    ),
    selected: opt_bool(map, "selected", false),
    cover: opt_token(map, "cover", COVERS, "none"),
    concentrating: opt_bool(map, "concentrating", false),
    hiding: opt_bool(map, "hiding", false),
    dodging: opt_bool(map, "dodging", false),
    flying: opt_bool(map, "flying", false),
    fly_height: opt_int(map, "flyHeight", 0),
    bloodied: opt_bool(map, "bloodied", false),
    death_save_successes: death_save(map, "successes"),
    death_save_failures: death_save(map, "failures"),
    accepting_death_saves: opt_bool(map, "acceptingDeathSaves", false),
    reaction_used: opt_bool(map, "reactionUsed", false),
    recharge_abilities: decode_list_or_default(
      map,
      "rechargeAbilities",
      decode_recharge,
    ),
    readied: opt_bool_either(map, "readied", "holding", false),
    inactive: opt_bool(map, "inactive", false),
    note: opt_str(map, "note", ""),
    memo: opt_str(map, "memo", ""),
    // `optional "timer" (D.nullable decodeTimer) Nothing`.
    timer: map.get("timer").and_then(|v| decode_timer(v).ok()),
    creature_id: map
      .get("creatureId")
      .and_then(Value::as_str)
      .map(str::to_string),
    legendary_actions_count: opt_legendary_count(
      map,
      "legendaryActionsCount",
      "hasLegendaryActions",
    ),
    legendary_actions_lair_bonus: opt_int(map, "legendaryActionsLairBonus", 0),
    legendary_actions_used: decode_int_set(map, "legendaryActionsUsed"),
    legendary_resistance_count: opt_legendary_count(
      map,
      "legendaryResistanceCount",
      "hasLegendaryResistance",
    ),
    legendary_resistance_lair_bonus: opt_int(
      map,
      "legendaryResistanceLairBonus",
      0,
    ),
    legendary_resistance_used: decode_int_set(map, "legendaryResistanceUsed"),
    is_placeholder: opt_bool(map, "isPlaceholder", false),
    creature_kind: opt_str(map, "creatureKind", "enemy"),
    race: opt_str(map, "race", ""),
    alignment: opt_str(map, "alignment", ""),
    surprised: opt_bool(map, "surprised", false),
    has_special_reactions: opt_bool(map, "hasSpecialReactions", false),
  })
}

/// `optional name (D.list itemDecoder) []`: one bad item defaults
/// the whole list, exactly like the Elm `D.oneOf` fallback.
fn decode_list_or_default<T>(
  map: &Map<String, Value>,
  key: &str,
  item: fn(&Value) -> Result<T, String>,
) -> Vec<T> {
  map
    .get(key)
    .and_then(Value::as_array)
    .and_then(|items| items.iter().map(|v| item(v).ok()).collect())
    .unwrap_or_default()
}

/// One field of `optional "deathSaves" decodeDeathSaves {0, 0}`:
/// the sub-record needs BOTH ints valid or the whole record
/// defaults, so each accessor re-checks the sibling.
fn death_save(map: &Map<String, Value>, field: &str) -> i64 {
  map
    .get("deathSaves")
    .and_then(Value::as_object)
    .and_then(|d| {
      match (
        d.get("successes").and_then(as_int),
        d.get("failures").and_then(as_int),
      ) {
        (Some(s), Some(f)) => Some(if field == "successes" { s } else { f }),
        _ => None,
      }
    })
    .unwrap_or(0)
}

/// `optional key decodeIntSet Set.empty`, with Elm `Set` semantics
/// on the way out: sorted ascending, deduplicated.
fn decode_int_set(map: &Map<String, Value>, key: &str) -> Vec<i64> {
  map
    .get(key)
    .and_then(Value::as_array)
    .and_then(|items| {
      items.iter().map(as_int).collect::<Option<BTreeSet<i64>>>()
    })
    .map(|set| set.into_iter().collect())
    .unwrap_or_default()
}

fn decode_condition(value: &Value) -> Result<Condition, String> {
  let map = as_object(value, "condition")?;
  Ok(Condition {
    id: req_int(map, "id", "condition")?,
    name: req_str(map, "name", "condition")?,
    note: opt_str(map, "note", ""),
    duration: decode_duration(
      map
        .get("duration")
        .ok_or("condition: missing field \"duration\"")?,
    )?,
    // `D.oneOf [D.field "saveToEnd" (D.nullable decodeSaveToEnd),
    // D.succeed Nothing]`.
    save_to_end: map
      .get("saveToEnd")
      .and_then(|v| decode_save_to_end(v).ok()),
  })
}

fn decode_duration(value: &Value) -> Result<Duration, String> {
  let map = as_object(value, "duration")?;
  match req_str(map, "kind", "duration")?.as_str() {
    "manual" => Ok(Duration::Manual),
    "untilTurn" => Ok(Duration::UntilTurn {
      phase: req_token(map, "phase", PHASES, "duration")?,
      target: req_token(map, "target", TARGETS, "duration")?,
      name: req_str(map, "name", "duration")?,
    }),
    "countdown" => Ok(Duration::Countdown {
      phase: req_token(map, "phase", PHASES, "duration")?,
      remaining: req_int(map, "remaining", "duration")?,
      skip_next_tick: req_bool(map, "skipNextTick", "duration")?,
    }),
    other => Err(format!("duration: unknown kind {other:?}")),
  }
}

fn decode_save_to_end(value: &Value) -> Result<SaveToEnd, String> {
  let map = as_object(value, "saveToEnd")?;
  Ok(SaveToEnd {
    ability: req_str(map, "ability", "saveToEnd")?,
    dc: req_int(map, "dc", "saveToEnd")?,
    bonus: req_int(map, "bonus", "saveToEnd")?,
    auto_roll: req_token(map, "autoRoll", AUTO_ROLLS, "saveToEnd")?,
  })
}

fn decode_save_notice(value: &Value) -> Result<SaveNotice, String> {
  let map = as_object(value, "saveNotice")?;
  Ok(SaveNotice {
    id: req_int(map, "id", "saveNotice")?,
    condition_name: req_str(map, "conditionName", "saveNotice")?,
    turns_remaining: req_int(map, "turnsRemaining", "saveNotice")?,
  })
}

fn decode_recharge(value: &Value) -> Result<RechargeAbility, String> {
  let map = as_object(value, "rechargeAbility")?;
  Ok(RechargeAbility {
    name: req_str(map, "name", "rechargeAbility")?,
    low: req_int(map, "low", "rechargeAbility")?,
    high: req_int(map, "high", "rechargeAbility")?,
    ready: req_bool(map, "ready", "rechargeAbility")?,
    // Added after `ready`; older saves lack it.
    awaiting_roll: opt_bool(map, "awaitingRoll", false),
  })
}

fn decode_timer(value: &Value) -> Result<Timer, String> {
  let map = as_object(value, "timer")?;
  Ok(Timer {
    remaining: req_int(map, "remaining", "timer")?,
    phase: req_token(map, "phase", PHASES, "timer")?,
    ringing: req_bool(map, "ringing", "timer")?,
    note: opt_str(map, "note", ""),
  })
}

// ── decode: treasure ─────────────────────────────────────────────────────────

/// `decodeTreasureField`: the current raw `TreasureRoll` shape or
/// the legacy `{ "roll": TreasureRoll, … }` wrapper from the
/// removed party-loot-ledger feature (recipient data dropped).
fn decode_treasure_field(value: &Value) -> Result<TreasureRoll, String> {
  value
    .as_object()
    .and_then(|map| map.get("roll"))
    .and_then(|roll| decode_roll(roll).ok())
    .map_or_else(|| decode_roll(value), Ok)
}

fn decode_roll(value: &Value) -> Result<TreasureRoll, String> {
  let map = as_object(value, "treasure roll")?;
  Ok(TreasureRoll {
    kind: req_token(map, "kind", TREASURE_KINDS, "treasure roll")?,
    bracket: req_token(map, "bracket", BRACKETS, "treasure roll")?,
    coins: decode_coins(
      map
        .get("coins")
        .ok_or("treasure roll: missing field \"coins\"")?,
    )?,
    gems: req_item_list(map, "gems", decode_valued_item)?,
    art: req_item_list(map, "art", decode_valued_item)?,
    magic: req_item_list(map, "magic", decode_magic_item)?,
    // `decodeFlatList`: absent or invalid → [] (pre-feature rolls).
    mundane: decode_list_or_default(map, "mundane", decode_valued_item),
    weapons: decode_list_or_default(map, "weapons", decode_valued_item),
    armor: decode_list_or_default(map, "armor", decode_valued_item),
    // Pre-source rolls decode `source = Nothing`.
    source: map.get("source").and_then(|v| decode_row_source(v).ok()),
    // Pre-sum rolls decode as [].
    contributions: decode_list_or_default(
      map,
      "contributions",
      decode_contribution,
    ),
    loot: decode_list_or_default(map, "loot", decode_loot_name),
  })
}

/// A required item list on the roll (`gems` / `art` / `magic`): a
/// missing field or any bad item fails the roll, which the outer
/// treasure `oneOf` then reads as "no treasure".
fn req_item_list<T>(
  map: &Map<String, Value>,
  key: &str,
  item: fn(&Value) -> Result<T, String>,
) -> Result<Vec<T>, String> {
  map
    .get(key)
    .and_then(Value::as_array)
    .ok_or_else(|| format!("treasure roll: missing or non-list field {key:?}"))?
    .iter()
    .map(item)
    .collect()
}

fn decode_loot_name(value: &Value) -> Result<String, String> {
  value
    .as_str()
    .map(str::to_string)
    .ok_or_else(|| "loot: expected a string".to_string())
}

fn decode_coins(value: &Value) -> Result<Coins, String> {
  let map = as_object(value, "coins")?;
  Ok(Coins {
    copper: req_int(map, "copper", "coins")?,
    silver: req_int(map, "silver", "coins")?,
    electrum: req_int(map, "electrum", "coins")?,
    gold: req_int(map, "gold", "coins")?,
    platinum: req_int(map, "platinum", "coins")?,
  })
}

fn decode_valued_item(value: &Value) -> Result<ValuedItem, String> {
  let map = as_object(value, "treasure item")?;
  Ok(ValuedItem {
    name: req_str(map, "name", "treasure item")?,
    value_gp: req_int(map, "valueGp", "treasure item")?,
  })
}

fn decode_magic_item(value: &Value) -> Result<MagicItem, String> {
  let map = as_object(value, "magic item")?;
  Ok(MagicItem {
    name: req_str(map, "name", "magic item")?,
    rarity: req_token(map, "rarity", RARITIES, "magic item")?,
    // Pre-table-letter rolls default to Table A.
    table: opt_token(map, "table", MAGIC_TABLES, "A"),
  })
}

fn decode_contribution(value: &Value) -> Result<Contribution, String> {
  let map = as_object(value, "contribution")?;
  Ok(Contribution {
    creature_name: req_str(map, "creatureName", "contribution")?,
    coins: decode_coins(
      map
        .get("coins")
        .ok_or("contribution: missing field \"coins\"")?,
    )?,
    gems: decode_list_or_default(map, "gems", decode_valued_item),
    art: decode_list_or_default(map, "art", decode_valued_item),
    magic: decode_list_or_default(map, "magic", decode_magic_item),
    mundane: decode_list_or_default(map, "mundane", decode_valued_item),
    weapons: decode_list_or_default(map, "weapons", decode_valued_item),
    armor: decode_list_or_default(map, "armor", decode_valued_item),
    loot: decode_list_or_default(map, "loot", decode_loot_name),
    bracket: opt_token(map, "bracket", BRACKETS, "1to4"),
  })
}

/// `decodeRowSource`: the `coinFormulas` FIELD must be present
/// (its inner decoder is total), the three specs are optional and
/// fall back to `None` on any mismatch.
fn decode_row_source(value: &Value) -> Result<RowSource, String> {
  let map = as_object(value, "row source")?;
  let formulas = map
    .get("coinFormulas")
    .ok_or("row source: missing field \"coinFormulas\"")?;
  let fmap = formulas.as_object();
  let coin = |key: &str| {
    fmap.and_then(|m| m.get(key)).and_then(|v| {
      let m = v.as_object()?;
      Some((
        m.get("count").and_then(as_int)?,
        m.get("faces").and_then(as_int)?,
        m.get("mult").and_then(as_int)?,
      ))
    })
  };
  Ok(RowSource {
    coin_formulas: CoinFormulas {
      copper: coin("copper"),
      silver: coin("silver"),
      electrum: coin("electrum"),
      gold: coin("gold"),
      platinum: coin("platinum"),
    },
    gems_spec: map.get("gemsSpec").and_then(|v| decode_spec(v, GEM_TIERS)),
    art_spec: map.get("artSpec").and_then(|v| decode_spec(v, ART_TIERS)),
    magic_spec: map
      .get("magicSpec")
      .and_then(|v| decode_spec(v, MAGIC_TABLES)),
  })
}

fn decode_spec(value: &Value, tiers: &[&str]) -> Option<Spec> {
  let map = value.as_object()?;
  Some(Spec {
    count: map.get("count").and_then(as_int)?,
    faces: map.get("faces").and_then(as_int)?,
    tier: map
      .get("tier")
      .and_then(Value::as_str)
      .filter(|t| tiers.contains(t))?
      .to_string(),
  })
}

// ── decode: treasure settings ────────────────────────────────────────────────

/// `decodeTreasureSettings`: total for any value — every knob has a
/// default, and an absent `hoardToggles` block falls back to the
/// pre-split flat fields on the settings object itself.
fn decode_settings(value: &Value) -> TreasureSettings {
  let empty = Map::new();
  let map = value.as_object().unwrap_or(&empty);
  TreasureSettings {
    coins_count: opt_token(map, "coinsCount", COUNT_ADJUSTS, "normal"),
    gems_count: opt_token(map, "gemsCount", COUNT_ADJUSTS, "normal"),
    gems_value: opt_token(map, "gemsValue", VALUE_ADJUSTS, "normal"),
    art_count: opt_token(map, "artCount", COUNT_ADJUSTS, "normal"),
    art_value: opt_token(map, "artValue", VALUE_ADJUSTS, "normal"),
    magic_count: opt_token(map, "magicCount", COUNT_ADJUSTS, "normal"),
    magic_value: opt_token(map, "magicValue", VALUE_ADJUSTS, "normal"),
    mundane_count: opt_token(map, "mundaneCount", COUNT_ADJUSTS, "normal"),
    weapons_count: opt_token(map, "weaponsCount", COUNT_ADJUSTS, "normal"),
    armor_count: opt_token(map, "armorCount", COUNT_ADJUSTS, "normal"),
    hoard_toggles: map
      .get("hoardToggles")
      .map_or_else(|| decode_toggles(map), decode_toggles_value),
    individual_toggles: map
      .get("individualToggles")
      .map_or_else(CategoryToggles::default_individual, decode_toggles_value),
    magic_scroll_chance: opt_int(map, "magicScrollChance", 15),
  }
}

fn decode_toggles_value(value: &Value) -> CategoryToggles {
  let empty = Map::new();
  decode_toggles(value.as_object().unwrap_or(&empty))
}

/// `decodeToggles` / `decodeLegacyHoardToggles` (identical field
/// sets and defaults; the legacy variant just reads them off the
/// settings object itself).
fn decode_toggles(map: &Map<String, Value>) -> CategoryToggles {
  CategoryToggles {
    coins_none: opt_bool(map, "coinsNone", false),
    gems_none: opt_bool(map, "gemsNone", false),
    art_none: opt_bool(map, "artNone", false),
    magic_none: opt_bool(map, "magicNone", false),
    mundane_none: opt_bool(map, "mundaneNone", true),
    weapons_none: opt_bool(map, "weaponsNone", true),
    armor_none: opt_bool(map, "armorNone", true),
  }
}

// ── encode ───────────────────────────────────────────────────────────────────

/// Emit the canonical current wire shape, exactly as Elm's
/// `encodeEncounter` would.
pub fn encode_encounter(enc: &Encounter) -> Value {
  json!({
    "creatures": enc.creatures.iter().map(encode_creature).collect::<Vec<_>>(),
    "activeName": enc.active_name,
    "round": enc.round,
    "treasure": enc.treasure.as_ref().map_or(Value::Null, encode_roll),
    "treasureSettings": encode_settings(&enc.treasure_settings),
  })
}

fn encode_creature(c: &Creature) -> Value {
  // 41 fields overflow `json!`'s macro recursion limit, so this one
  // object assembles through explicit inserts, in the Elm encoder's
  // field order.
  let mut map = Map::new();
  let mut put = |key: &str, value: Value| {
    map.insert(key.to_string(), value);
  };
  put("name", json!(c.name));
  put("kind", json!(c.kind));
  put("initiative", json!(c.initiative));
  put("initiativeBonus", json!(c.initiative_bonus));
  put("currentHp", json!(c.current_hp));
  put("maxHp", json!(c.max_hp));
  put("originalMaxHp", json!(c.original_max_hp));
  put("tempHp", json!(c.temp_hp));
  put("armorClass", json!(c.armor_class));
  put("speed", json!(c.speed));
  put(
    "conditions",
    Value::Array(c.conditions.iter().map(encode_condition).collect()),
  );
  put(
    "saveNotices",
    Value::Array(c.save_notices.iter().map(encode_save_notice).collect()),
  );
  put("selected", json!(c.selected));
  put("cover", json!(c.cover));
  put("concentrating", json!(c.concentrating));
  put("hiding", json!(c.hiding));
  put("dodging", json!(c.dodging));
  put("flying", json!(c.flying));
  put("flyHeight", json!(c.fly_height));
  put("bloodied", json!(c.bloodied));
  put(
    "deathSaves",
    json!({
      "successes": c.death_save_successes,
      "failures": c.death_save_failures,
    }),
  );
  put("acceptingDeathSaves", json!(c.accepting_death_saves));
  put("reactionUsed", json!(c.reaction_used));
  put(
    "rechargeAbilities",
    Value::Array(c.recharge_abilities.iter().map(encode_recharge).collect()),
  );
  put("readied", json!(c.readied));
  put("inactive", json!(c.inactive));
  put("note", json!(c.note));
  put("memo", json!(c.memo));
  put("timer", c.timer.as_ref().map_or(Value::Null, encode_timer));
  put("creatureId", json!(c.creature_id));
  put("legendaryActionsCount", json!(c.legendary_actions_count));
  put("legendaryActionsLairBonus", json!(c.legendary_actions_lair_bonus));
  put("legendaryActionsUsed", json!(c.legendary_actions_used));
  put("legendaryResistanceCount", json!(c.legendary_resistance_count));
  put("legendaryResistanceLairBonus", json!(c.legendary_resistance_lair_bonus));
  put("legendaryResistanceUsed", json!(c.legendary_resistance_used));
  put("isPlaceholder", json!(c.is_placeholder));
  put("creatureKind", json!(c.creature_kind));
  put("race", json!(c.race));
  put("alignment", json!(c.alignment));
  put("surprised", json!(c.surprised));
  put("hasSpecialReactions", json!(c.has_special_reactions));
  Value::Object(map)
}

fn encode_condition(cond: &Condition) -> Value {
  json!({
    "id": cond.id,
    "name": cond.name,
    "note": cond.note,
    "duration": encode_duration(&cond.duration),
    "saveToEnd": cond.save_to_end.as_ref().map_or(Value::Null, encode_save_to_end),
  })
}

fn encode_duration(duration: &Duration) -> Value {
  match duration {
    Duration::Manual => json!({ "kind": "manual" }),
    Duration::UntilTurn {
      phase,
      target,
      name,
    } => json!({
      "kind": "untilTurn",
      "phase": phase,
      "target": target,
      "name": name,
    }),
    Duration::Countdown {
      phase,
      remaining,
      skip_next_tick,
    } => json!({
      "kind": "countdown",
      "phase": phase,
      "remaining": remaining,
      "skipNextTick": skip_next_tick,
    }),
  }
}

fn encode_save_to_end(save: &SaveToEnd) -> Value {
  json!({
    "ability": save.ability,
    "dc": save.dc,
    "bonus": save.bonus,
    "autoRoll": save.auto_roll,
  })
}

fn encode_save_notice(notice: &SaveNotice) -> Value {
  json!({
    "id": notice.id,
    "conditionName": notice.condition_name,
    "turnsRemaining": notice.turns_remaining,
  })
}

fn encode_recharge(ability: &RechargeAbility) -> Value {
  json!({
    "name": ability.name,
    "low": ability.low,
    "high": ability.high,
    "ready": ability.ready,
    "awaitingRoll": ability.awaiting_roll,
  })
}

fn encode_timer(timer: &Timer) -> Value {
  json!({
    "remaining": timer.remaining,
    "phase": timer.phase,
    "ringing": timer.ringing,
    "note": timer.note,
  })
}

fn encode_settings(s: &TreasureSettings) -> Value {
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

fn encode_toggles(t: &CategoryToggles) -> Value {
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

fn encode_roll(roll: &TreasureRoll) -> Value {
  json!({
    "kind": roll.kind,
    "bracket": roll.bracket,
    "coins": encode_coins(&roll.coins),
    "gems": roll.gems.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "art": roll.art.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "magic": roll.magic.iter().map(encode_magic_item).collect::<Vec<_>>(),
    "mundane": roll.mundane.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "weapons": roll.weapons.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "armor": roll.armor.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "source": roll.source.as_ref().map_or(Value::Null, encode_row_source),
    "contributions": roll.contributions.iter().map(encode_contribution).collect::<Vec<_>>(),
    "loot": roll.loot,
  })
}

fn encode_coins(coins: &Coins) -> Value {
  json!({
    "copper": coins.copper,
    "silver": coins.silver,
    "electrum": coins.electrum,
    "gold": coins.gold,
    "platinum": coins.platinum,
  })
}

fn encode_valued_item(item: &ValuedItem) -> Value {
  json!({ "name": item.name, "valueGp": item.value_gp })
}

fn encode_magic_item(item: &MagicItem) -> Value {
  json!({
    "name": item.name,
    "rarity": item.rarity,
    "table": item.table,
  })
}

fn encode_contribution(c: &Contribution) -> Value {
  json!({
    "creatureName": c.creature_name,
    "coins": encode_coins(&c.coins),
    "gems": c.gems.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "art": c.art.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "magic": c.magic.iter().map(encode_magic_item).collect::<Vec<_>>(),
    "mundane": c.mundane.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "weapons": c.weapons.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "armor": c.armor.iter().map(encode_valued_item).collect::<Vec<_>>(),
    "loot": c.loot,
    "bracket": c.bracket,
  })
}

fn encode_row_source(source: &RowSource) -> Value {
  let coin = |formula: &Option<(i64, i64, i64)>| {
    formula.as_ref().map_or(Value::Null, |(count, faces, mult)| {
      json!({ "count": count, "faces": faces, "mult": mult })
    })
  };
  let spec = |spec: &Option<Spec>| {
    spec.as_ref().map_or(
      Value::Null,
      |s| json!({ "count": s.count, "faces": s.faces, "tier": s.tier }),
    )
  };
  json!({
    "coinFormulas": {
      "copper": coin(&source.coin_formulas.copper),
      "silver": coin(&source.coin_formulas.silver),
      "electrum": coin(&source.coin_formulas.electrum),
      "gold": coin(&source.coin_formulas.gold),
      "platinum": coin(&source.coin_formulas.platinum),
    },
    "gemsSpec": spec(&source.gems_spec),
    "artSpec": spec(&source.art_spec),
    "magicSpec": spec(&source.magic_spec),
  })
}

#[cfg(test)]
mod tests {
  #![allow(clippy::expect_used, clippy::unwrap_used)]

  use super::*;

  /// A canonical payload as the current Elm encoder writes it, with
  /// every optional block populated.  Parsed from text rather than
  /// built with `json!` — the fixture is large enough to overflow
  /// the macro's recursion limit, and raw JSON is closer to what a
  /// client actually sends anyway.
  fn canonical_maximal() -> Value {
    serde_json::from_str(
      r#"{
      "creatures": [{
        "name": "Adult Red Dragon",
        "kind": "dragon",
        "initiative": 17,
        "initiativeBonus": 2,
        "currentHp": 212,
        "maxHp": 256,
        "originalMaxHp": 256,
        "tempHp": 10,
        "armorClass": 19,
        "speed": 40,
        "conditions": [
          {
            "id": 1,
            "name": "Restrained",
            "note": "net",
            "duration": { "kind": "manual" },
            "saveToEnd": { "ability": "STR", "dc": 15, "bonus": 4, "autoRoll": "atEnd" }
          },
          {
            "id": 2,
            "name": "Blessed",
            "note": "",
            "duration": { "kind": "untilTurn", "phase": "atBegin", "target": "next", "name": "Cleric" },
            "saveToEnd": null
          },
          {
            "id": 3,
            "name": "Burning",
            "note": "",
            "duration": { "kind": "countdown", "phase": "atEnd", "remaining": 3, "skipNextTick": true },
            "saveToEnd": null
          }
        ],
        "saveNotices": [
          { "id": 9, "conditionName": "Restrained", "turnsRemaining": 2 }
        ],
        "selected": true,
        "cover": "threeQuarters",
        "concentrating": true,
        "hiding": false,
        "dodging": true,
        "flying": true,
        "flyHeight": 30,
        "bloodied": true,
        "deathSaves": { "successes": 1, "failures": 2 },
        "acceptingDeathSaves": true,
        "reactionUsed": true,
        "rechargeAbilities": [
          { "name": "Fire Breath", "low": 5, "high": 6, "ready": false, "awaitingRoll": true }
        ],
        "readied": true,
        "inactive": false,
        "note": "angry",
        "memo": "hoards gold",
        "timer": { "remaining": 4, "phase": "atEnd", "ringing": false, "note": "lair" },
        "creatureId": "dragon-uuid",
        "legendaryActionsCount": 3,
        "legendaryActionsLairBonus": 1,
        "legendaryActionsUsed": [1, 3],
        "legendaryResistanceCount": 3,
        "legendaryResistanceLairBonus": 0,
        "legendaryResistanceUsed": [2],
        "isPlaceholder": false,
        "creatureKind": "enemy",
        "race": "Dragon",
        "alignment": "chaotic evil",
        "surprised": true,
        "hasSpecialReactions": true
      }],
      "activeName": "Adult Red Dragon",
      "round": 7,
      "treasure": {
        "kind": "hoard",
        "bracket": "17plus",
        "coins": { "copper": 0, "silver": 100, "electrum": 0, "gold": 12000, "platinum": 800 },
        "gems": [{ "name": "Ruby", "valueGp": 5000 }],
        "art": [{ "name": "Gold cup", "valueGp": 750 }],
        "magic": [{ "name": "Vorpal Sword", "rarity": "legendary", "table": "I" }],
        "mundane": [{ "name": "Rope", "valueGp": 1 }],
        "weapons": [{ "name": "Longsword", "valueGp": 15 }],
        "armor": [{ "name": "Chain mail", "valueGp": 75 }],
        "source": {
          "coinFormulas": {
            "copper": null,
            "silver": { "count": 2, "faces": 6, "mult": 100 },
            "electrum": null,
            "gold": { "count": 12, "faces": 6, "mult": 1000 },
            "platinum": { "count": 8, "faces": 6, "mult": 100 }
          },
          "gemsSpec": { "count": 3, "faces": 6, "tier": "5000gp" },
          "artSpec": null,
          "magicSpec": { "count": 1, "faces": 4, "tier": "I" }
        },
        "contributions": [{
          "creatureName": "Adult Red Dragon",
          "coins": { "copper": 0, "silver": 100, "electrum": 0, "gold": 12000, "platinum": 800 },
          "gems": [{ "name": "Ruby", "valueGp": 5000 }],
          "art": [],
          "magic": [{ "name": "Vorpal Sword", "rarity": "legendary", "table": "I" }],
          "mundane": [],
          "weapons": [],
          "armor": [],
          "loot": ["Dragon scale"],
          "bracket": "17plus"
        }],
        "loot": ["Dragon scale"]
      },
      "treasureSettings": {
        "coinsCount": "more",
        "gemsCount": "normal",
        "gemsValue": "higher",
        "artCount": "fewer",
        "artValue": "normal",
        "magicCount": "normal",
        "magicValue": "lower",
        "mundaneCount": "normal",
        "weaponsCount": "normal",
        "armorCount": "normal",
        "hoardToggles": {
          "coinsNone": false, "gemsNone": false, "artNone": false,
          "magicNone": false, "mundaneNone": false, "weaponsNone": true,
          "armorNone": true
        },
        "individualToggles": {
          "coinsNone": false, "gemsNone": true, "artNone": true,
          "magicNone": true, "mundaneNone": true, "weaponsNone": true,
          "armorNone": true
        },
        "magicScrollChance": 25
      }
    }"#,
    )
    .expect("maximal fixture parses")
  }

  #[test]
  fn canonical_payload_round_trips_exactly() {
    let payload = canonical_maximal();
    let decoded = decode_encounter(&payload).expect("decode");
    assert_eq!(encode_encounter(&decoded), payload);
  }

  #[test]
  fn legacy_shapes_decode_with_wire_elm_fallbacks() {
    let legacy = json!({
      "creatures": [{
        "name": "Old Ghoul",
        "initiative": 12,
        "currentHp": 22,
        "maxHp": 22,
        "armorClass": 12,
        "holding": true,
        "hasLegendaryActions": true,
        "hasLegendaryResistance": false,
        "conditions": [{
          "id": 1,
          "name": "Paralyzed",
          "duration": { "kind": "manual" }
        }]
      }],
      "activeName": "Old Ghoul",
      "round": 2,
      "treasure": {
        "roll": {
          "kind": "individual",
          "bracket": "1to4",
          "coins": { "copper": 10, "silver": 0, "electrum": 0, "gold": 2, "platinum": 0 },
          "gems": [],
          "art": [],
          "magic": [{ "name": "Potion of Healing", "rarity": "common" }]
        },
        "recipients": { "ignored": true }
      }
    });
    let decoded = decode_encounter(&legacy).expect("decode legacy");

    let creature = &decoded.creatures[0];
    assert!(creature.readied, "legacy `holding` maps to readied");
    assert_eq!(
      creature.legendary_actions_count, 3,
      "legacy hasLegendaryActions: true maps to 3 pips"
    );
    assert_eq!(creature.legendary_resistance_count, 0);
    assert_eq!(creature.original_max_hp, 22, "defaults to maxHp");
    assert_eq!(creature.conditions[0].note, "", "missing note defaults");

    let treasure = decoded.treasure.as_ref().expect("treasure unwrapped");
    assert_eq!(treasure.kind, "individual", "legacy roll wrapper unwrapped");
    assert_eq!(treasure.magic[0].table, "A", "missing table defaults to A");
    assert!(treasure.source.is_none(), "pre-source roll");
    assert!(treasure.contributions.is_empty(), "pre-sum roll");

    // Missing treasureSettings decode as the full default block.
    let settings = &decoded.treasure_settings;
    assert_eq!(settings.magic_scroll_chance, 15);
    assert!(settings.individual_toggles.gems_none);
    assert!(!settings.hoard_toggles.gems_none);
  }

  #[test]
  fn invalid_optional_blocks_default_instead_of_failing() {
    let payload = json!({
      "creatures": [{
        "name": "Wobbly",
        "initiative": 1,
        "currentHp": 1,
        "maxHp": 1,
        "armorClass": 10,
        "conditions": [{ "id": 1, "name": "Bad", "duration": { "kind": "nonsense" } }],
        "cover": "behind-a-tree",
        "timer": { "remaining": "soon" }
      }],
      "activeName": "",
      "round": 1,
      "treasure": { "kind": "mystery" }
    });
    let decoded = decode_encounter(&payload).expect("decode");
    let creature = &decoded.creatures[0];
    assert!(
      creature.conditions.is_empty(),
      "a bad condition defaults the whole list"
    );
    assert_eq!(creature.cover, "none", "unknown cover token defaults");
    assert!(creature.timer.is_none(), "bad timer decodes as absent");
    assert!(decoded.treasure.is_none(), "undecodable treasure reads absent");
  }

  #[test]
  fn missing_required_fields_fail_decode() {
    assert!(decode_encounter(&json!({ "creatures": [] })).is_err());
    assert!(decode_encounter(&json!({
      "activeName": "x", "round": 1
    }))
    .is_err());
    assert!(decode_encounter(&json!({
      "creatures": [{ "name": "No HP", "initiative": 1, "armorClass": 10 }],
      "activeName": "x",
      "round": 1
    }))
    .is_err());
  }
}
