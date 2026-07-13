//! Per-feature wire codecs + SQL for the five per-user preset stores.
//!
//! Each submodule implements [`crate::per_user_store::PerUserFeature`]
//! for one feature, mirroring the matching Elm `*.Wire` module:
//!
//! - [`lore_groups`] ↔ `Encounter.RandomEncounter.Lore.Wire`
//! - [`condition_presets`] ↔ `Ui.Condition.Wire`
//! - [`save_chains`] ↔ `Encounter.SaveChain.Wire`
//! - [`treasure_table`] ↔ `Encounter.Treasure.TableWire`
//! - [`treasure_profiles`] ↔ `Encounter.Treasure.ProfileWire`
//!
//! The Elm modules are the schema spec.  Decoders reproduce their
//! leniency (legacy field shapes, absent-field defaults, tolerated
//! type mismatches) so the one-shot boot import accepts payloads
//! written by any historical frontend version; encoders emit the
//! canonical current shape exactly as the Elm encoder would,
//! including null-vs-absent choices.
//!
//! The helpers below reproduce the two field-access idioms every Elm
//! wire module builds on: a required field (decode failure fails the
//! payload) and Elm's `optionalField` (absent field, non-object
//! parent, or a failing inner decoder all fall back to a default).

use serde_json::{Map, Value};

pub mod condition_presets;
pub mod lore_groups;
pub mod save_chains;
pub mod treasure_profiles;
pub mod treasure_table;

/// View `value` as a JSON object, or fail with a message naming
/// `context`.
pub(crate) fn as_object<'a>(
  value: &'a Value,
  context: &str,
) -> Result<&'a Map<String, Value>, String> {
  value
    .as_object()
    .ok_or_else(|| format!("{context}: expected a JSON object"))
}

/// A required string field, like Elm's `D.field key D.string`.
pub(crate) fn req_str(
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

/// A required integer field, like Elm's `D.field key D.int`.
pub(crate) fn req_i64(
  map: &Map<String, Value>,
  key: &str,
  context: &str,
) -> Result<i64, String> {
  map
    .get(key)
    .and_then(Value::as_i64)
    .ok_or_else(|| format!("{context}: missing or non-integer field {key:?}"))
}

/// Elm's `optionalField key D.string default`: the default covers an
/// absent field and a present-but-non-string value alike.
pub(crate) fn opt_str_or(
  map: &Map<String, Value>,
  key: &str,
  default: &str,
) -> String {
  map
    .get(key)
    .and_then(Value::as_str)
    .map_or_else(|| default.to_string(), str::to_string)
}

/// Elm's `optionalField key D.int default`.
pub(crate) fn opt_i64_or(
  map: &Map<String, Value>,
  key: &str,
  default: i64,
) -> i64 {
  map.get(key).and_then(Value::as_i64).unwrap_or(default)
}

/// Elm's `optionalField key D.bool default`.
pub(crate) fn opt_bool_or(
  map: &Map<String, Value>,
  key: &str,
  default: bool,
) -> bool {
  map.get(key).and_then(Value::as_bool).unwrap_or(default)
}
