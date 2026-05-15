//! Compendium **group** types.
//!
//! A `Group` bundles one or more compendium creatures into a unit
//! that adds to an encounter as a whole.  Lives alongside
//! [`Creature`](super::Creature) in this crate because the server
//! HTTP wire format and the frontend JSON decoders both consume it,
//! and we want a single source of truth for the schema.
//!
//! Identity is the server-issued `id` (UUIDv4 as a String) so the
//! `aide` / `schemars` integration keeps working without an extra
//! feature flag.  Timestamps are epoch-milliseconds for parity with
//! [`Creature`](super::Creature).

use serde::{Deserialize, Serialize};

/// A group of creatures with shared initiative semantics.
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct Group {
  pub id: String,
  pub name: String,
  pub initiative_mode: InitiativeMode,
  #[serde(default)]
  pub entries: Vec<GroupEntry>,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Client-supplied draft used by `POST /api/compendium/groups`.
/// `id` and timestamps are server-issued, so the draft omits them.
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct GroupDraft {
  pub name: String,
  pub initiative_mode: InitiativeMode,
  #[serde(default)]
  pub entries: Vec<GroupEntry>,
}

/// One creature row inside a group.
///
/// `creature_id` references a [`Creature`](super::Creature) by id.
/// `count` is the spawn multiplier — three goblins becomes a single
/// entry with `count = 3`.  `minion_type` optionally rewrites the
/// spawned instance's max HP at materialise-time on the frontend;
/// the server stores the override but performs no HP math.
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct GroupEntry {
  pub creature_id: String,
  pub count: i32,
  #[serde(default)]
  pub minion_type: MinionType,
}

/// How initiative is rolled when the group is added to an encounter.
///
/// Tagged with `type` so the wire format reads cleanly:
///
/// ```json
/// { "type": "each_rolls" }
/// { "type": "shared_rolled" }
/// { "type": "shared_manual", "value": 12 }
/// ```
///
/// The frontend Elm side decodes the same shape via
/// [`Compendium.GroupWire`](../../../frontend/src/Compendium/GroupWire.elm).
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InitiativeMode {
  EachRolls,
  SharedRolled,
  SharedManual { value: i32 },
}

/// Optional max-HP override applied per-entry at encounter-spawn time.
#[derive(
  Debug, Clone, Copy, Serialize, Deserialize, schemars::JsonSchema, Default,
)]
#[serde(rename_all = "snake_case")]
pub enum MinionType {
  #[default]
  None,
  Half,
  One,
}
