//! Compendium type definitions.
//!
//! `Creature` is the canonical stat-block record.  Sub-records
//! follow a flat-ish layout (rather than the deeply-nested
//! `creature.statBlock.armorClass.value` pattern from the legacy
//! JS project) because Elm's record syntax handles flat well and
//! deep nesting poorly.
//!
//! All types serialize via `serde` with default field naming
//! (snake_case) for the wire format.  Frontend Elm decoders match
//! the same shape.

use serde::{Deserialize, Serialize};

/// A single stat-block entry in the compendium.
///
/// Identity is the server-issued `id` — a UUIDv4 stored as a
/// String so the schema generation in `aide` / `schemars` keeps
/// working without an extra feature flag dance.  Names are
/// free-text and may collide.  `created_at` / `updated_at` are
/// epoch-millisecond timestamps so the frontend's "Newest first"
/// sort doesn't have to negotiate timezone conversion.
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct Creature {
  pub id: String,
  pub name: String,
  pub kind: CreatureKind,
  pub size: Size,
  pub race: String,
  pub subrace: String,
  pub alignment: String,
  pub source: String,
  pub description: String,
  pub armor_class: i32,
  pub armor_class_note: String,
  pub max_hp: i32,
  pub hp_formula: String,
  pub initiative_bonus: i32,
  pub speed: Speed,
  pub abilities: Abilities,
  #[serde(default)]
  pub saving_throws: Vec<AbilitySave>,
  #[serde(default)]
  pub skills: Vec<SkillBonus>,
  #[serde(default)]
  pub damage_vulnerabilities: Vec<String>,
  #[serde(default)]
  pub damage_resistances: Vec<String>,
  #[serde(default)]
  pub damage_immunities: Vec<String>,
  #[serde(default)]
  pub condition_immunities: Vec<String>,
  pub senses: Senses,
  #[serde(default)]
  pub languages: Vec<String>,
  pub challenge_rating: String,
  pub xp: i64,
  /// XP awarded when the creature is fought *in its lair*.  D&D
  /// 2024 stat blocks publish this as a parenthetical alternative
  /// on the CR line: "CR 16 (XP 15,000, or 18,000 in lair; PB +5)".
  /// Zero means "no separate lair XP" — either the creature has
  /// no lair, or the source didn't print one.
  #[serde(default)]
  pub xp_in_lair: i64,
  pub proficiency_bonus: i32,
  #[serde(default)]
  pub traits: Vec<Feature>,
  #[serde(default)]
  pub actions: Vec<Feature>,
  #[serde(default)]
  pub bonus_actions: Vec<Feature>,
  #[serde(default)]
  pub reactions: Vec<Feature>,
  #[serde(default)]
  pub legendary_actions: Option<LegendaryActions>,
  #[serde(default)]
  pub lair_actions: Option<LairActions>,
  #[serde(default)]
  pub regional_effects: Option<RegionalEffects>,
  #[serde(default)]
  pub spellcasting: Option<Spellcasting>,
  #[serde(default)]
  pub custom_sections: Vec<CustomSection>,
  /// 2024 Monster Manual habitat tags.  Empty in the bundled
  /// dataset (Open5e's `srd-2024` exposes the field but populates
  /// no values); user edits and successful Paste-Stat-Block parses
  /// fill it in over time.
  #[serde(default)]
  pub habitats: Vec<Habitat>,
  /// 2024 Monster Manual treasure tags.  Same forward-fill model
  /// as `habitats`: empty in the bundle, populated by edits and
  /// successful Paste-Stat-Block parses.
  #[serde(default)]
  pub treasures: Vec<Treasure>,
  /// Free-form user-authored tags.  Single-word strings (no
  /// internal whitespace; underscores allowed) that the UI uses
  /// for filtering.  There is no separate tag DB — a tag "exists"
  /// for as long as some creature carries it.
  #[serde(default)]
  pub tags: Vec<String>,
  pub created_at: i64,
  pub updated_at: i64,
}

/// What a `CreatureDraft` becomes once the server allocates an
/// `id` and timestamps.  Inserts and pasted-stat-block parses both
/// land here.
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct CreatureDraft {
  pub name: String,
  pub kind: CreatureKind,
  pub size: Size,
  #[serde(default)]
  pub race: String,
  #[serde(default)]
  pub subrace: String,
  #[serde(default)]
  pub alignment: String,
  #[serde(default)]
  pub source: String,
  #[serde(default)]
  pub description: String,
  pub armor_class: i32,
  #[serde(default)]
  pub armor_class_note: String,
  pub max_hp: i32,
  #[serde(default)]
  pub hp_formula: String,
  #[serde(default)]
  pub initiative_bonus: i32,
  #[serde(default)]
  pub speed: Speed,
  #[serde(default)]
  pub abilities: Abilities,
  #[serde(default)]
  pub saving_throws: Vec<AbilitySave>,
  #[serde(default)]
  pub skills: Vec<SkillBonus>,
  #[serde(default)]
  pub damage_vulnerabilities: Vec<String>,
  #[serde(default)]
  pub damage_resistances: Vec<String>,
  #[serde(default)]
  pub damage_immunities: Vec<String>,
  #[serde(default)]
  pub condition_immunities: Vec<String>,
  #[serde(default)]
  pub senses: Senses,
  #[serde(default)]
  pub languages: Vec<String>,
  #[serde(default)]
  pub challenge_rating: String,
  #[serde(default)]
  pub xp: i64,
  #[serde(default)]
  pub xp_in_lair: i64,
  #[serde(default)]
  pub proficiency_bonus: i32,
  #[serde(default)]
  pub traits: Vec<Feature>,
  #[serde(default)]
  pub actions: Vec<Feature>,
  #[serde(default)]
  pub bonus_actions: Vec<Feature>,
  #[serde(default)]
  pub reactions: Vec<Feature>,
  #[serde(default)]
  pub legendary_actions: Option<LegendaryActions>,
  #[serde(default)]
  pub lair_actions: Option<LairActions>,
  #[serde(default)]
  pub regional_effects: Option<RegionalEffects>,
  #[serde(default)]
  pub spellcasting: Option<Spellcasting>,
  #[serde(default)]
  pub custom_sections: Vec<CustomSection>,
  #[serde(default)]
  pub habitats: Vec<Habitat>,
  #[serde(default)]
  pub treasures: Vec<Treasure>,
  #[serde(default)]
  pub tags: Vec<String>,
}

/// 2024 Monster Manual habitat tag.  Material-Plane habitats
/// (Arctic … Urban) and Planar habitats (Abyss … Upper Planes)
/// share one enum so the wire format is a flat `Vec<Habitat>`.
/// The Elm side keeps the same arrangement in `Compendium.Habitat`.
#[derive(
  Debug,
  Clone,
  Copy,
  Serialize,
  Deserialize,
  PartialEq,
  Eq,
  Hash,
  PartialOrd,
  Ord,
  schemars::JsonSchema,
)]
#[serde(rename_all = "kebab-case")]
pub enum Habitat {
  Arctic,
  Coastal,
  Desert,
  Forest,
  Grassland,
  Hill,
  Mountain,
  Swamp,
  Underdark,
  Underwater,
  Urban,
  Abyss,
  Acheron,
  AstralPlane,
  Beastlands,
  ElementalChaos,
  ElementalPlaneOfAir,
  ElementalPlaneOfEarth,
  ElementalPlaneOfFire,
  ElementalPlaneOfWater,
  Feywild,
  Limbo,
  LowerPlanes,
  NineHells,
  UpperPlanes,
}

/// 2024 Monster Manual treasure tag.  Four buckets that classify
/// the kind of magic items in a creature's hoard.  Mirrors the
/// Elm `Compendium.Treasure` ADT.
#[derive(
  Debug,
  Clone,
  Copy,
  Serialize,
  Deserialize,
  PartialEq,
  Eq,
  schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum Treasure {
  Arcana,
  Armaments,
  Implements,
  Relics,
}

#[derive(
  Debug,
  Clone,
  Copy,
  Serialize,
  Deserialize,
  PartialEq,
  Eq,
  schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum CreatureKind {
  Player,
  Enemy,
  Npc,
}

#[derive(
  Debug,
  Clone,
  Copy,
  Serialize,
  Deserialize,
  PartialEq,
  Eq,
  schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum Size {
  Tiny,
  Small,
  Medium,
  Large,
  Huge,
  Gargantuan,
}

#[derive(
  Debug, Clone, Default, Serialize, Deserialize, schemars::JsonSchema,
)]
pub struct Speed {
  #[serde(default)]
  pub walk: i32,
  #[serde(default)]
  pub fly: i32,
  #[serde(default)]
  pub swim: i32,
  #[serde(default)]
  pub climb: i32,
  #[serde(default)]
  pub burrow: i32,
  /// True when "fly N ft. (hover)" — the creature stays put when
  /// not actively flying.  Distinct from "swim" because it's a
  /// movement-mode modifier, not a separate speed.
  #[serde(default)]
  pub hover: bool,
}

#[derive(
  Debug, Clone, Default, Serialize, Deserialize, schemars::JsonSchema,
)]
pub struct Abilities {
  #[serde(default = "default_ability_score")]
  pub str: i32,
  #[serde(default = "default_ability_score")]
  pub dex: i32,
  #[serde(default = "default_ability_score")]
  pub con: i32,
  #[serde(default = "default_ability_score")]
  pub int: i32,
  #[serde(default = "default_ability_score")]
  pub wis: i32,
  #[serde(default = "default_ability_score")]
  pub cha: i32,
}

fn default_ability_score() -> i32 {
  10
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct AbilitySave {
  pub ability: Ability,
  pub bonus: i32,
}

#[derive(
  Debug,
  Clone,
  Copy,
  Serialize,
  Deserialize,
  PartialEq,
  Eq,
  schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum Ability {
  Str,
  Dex,
  Con,
  Int,
  Wis,
  Cha,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct SkillBonus {
  pub name: String,
  pub bonus: i32,
}

#[derive(
  Debug, Clone, Default, Serialize, Deserialize, schemars::JsonSchema,
)]
pub struct Senses {
  #[serde(default)]
  pub blindsight: i32,
  #[serde(default)]
  pub darkvision: i32,
  #[serde(default)]
  pub tremorsense: i32,
  #[serde(default)]
  pub truesight: i32,
  #[serde(default = "default_passive_perception")]
  pub passive_perception: i32,
}

fn default_passive_perception() -> i32 {
  10
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct Feature {
  pub name: String,
  pub description: String,
  #[serde(default)]
  pub usage: Option<Usage>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Usage {
  Recharge { low: i32, high: i32 },
  PerDay { uses: i32 },
  PerShortRest { uses: i32 },
  PerLongRest { uses: i32 },
  AtWill,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct LegendaryActions {
  pub description: String,
  #[serde(default = "default_legendary_uses")]
  pub uses: i32,
  #[serde(default)]
  pub uses_in_lair: i32,
  pub options: Vec<LegendaryOption>,
}

fn default_legendary_uses() -> i32 {
  3
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct LegendaryOption {
  pub name: String,
  #[serde(default = "default_legendary_cost")]
  pub cost: i32,
  pub description: String,
}

fn default_legendary_cost() -> i32 {
  1
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct LairActions {
  #[serde(default = "default_lair_initiative")]
  pub initiative: i32,
  pub description: String,
  pub options: Vec<Feature>,
}

fn default_lair_initiative() -> i32 {
  20
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct RegionalEffects {
  pub description: String,
  pub effects: Vec<Feature>,
  #[serde(default)]
  pub fade_after: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct Spellcasting {
  pub description: String,
  pub ability: Ability,
  #[serde(default)]
  pub save_dc: i32,
  #[serde(default)]
  pub attack_bonus: i32,
  #[serde(default)]
  pub at_will: Vec<String>,
  #[serde(default)]
  pub slots: Vec<SpellSlotLevel>,
  #[serde(default)]
  pub innate_per_day: Vec<InnatePerDay>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct SpellSlotLevel {
  pub level: i32,
  pub slots: i32,
  pub spells: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct InnatePerDay {
  pub uses: i32,
  pub spells: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct CustomSection {
  pub name: String,
  pub body: String,
}
