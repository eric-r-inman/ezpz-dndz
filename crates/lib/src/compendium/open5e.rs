//! Open5e v2 API shapes + a `From` mapping into our
//! `CreatureDraft`.
//!
//! Open5e (https://api.open5e.com) is a community-maintained
//! reflection of the official D&D 5e SRD plus other
//! free-to-redistribute supplements.  The harvester pulls only
//! the documents licensed under CC-BY 4.0 (default filter:
//! `document__key=wotc-srd`) so the resulting JSON file can be
//! bundled with this project under the same license.
//!
//! The struct definitions below name only the fields we map.
//! Serde silently drops everything else, so future API additions
//! don't break us.
//!
//! The conversion is intentionally lossy: Open5e's structured
//! `actions` carry attack rolls, damage dice, and DC fields as
//! separate columns; our `Feature.description` string takes the
//! human-readable rendering and lets the existing inline-dice
//! parser pick out rollable expressions on the frontend.

use crate::compendium::types::{
  Abilities, Ability, AbilitySave, Creature, CreatureDraft, CreatureKind,
  Feature, LegendaryActions, LegendaryOption, Senses, Size, SkillBonus, Speed,
};
use serde::{Deserialize, Deserializer};

/// Serde helper: treat both `null` and a missing field as the
/// type's default value.  `#[serde(default)]` alone only handles
/// the missing-field case; explicit `null` from upstream needs
/// this shim.  Open5e's v2 API emits null for absent numeric
/// fields (proficiency_bonus, ranges, etc.).
fn null_as_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
  D: Deserializer<'de>,
  T: Default + Deserialize<'de>,
{
  Option::<T>::deserialize(deserializer).map(Option::unwrap_or_default)
}

/// Top-level paginated response shape.
#[derive(Debug, Deserialize)]
pub struct Page {
  pub count: i32,
  pub next: Option<String>,
  pub results: Vec<Monster>,
}

/// One Open5e creature.  Only fields we map are listed; serde
/// drops the rest.
#[derive(Debug, Deserialize)]
pub struct Monster {
  /// Stable URL slug — `"goblin"`, `"adult-blue-dragon"`, etc.
  /// Used as the input to a UUIDv5 derivation so the bundled
  /// creature UUIDs are reproducible across re-harvests.
  pub key: String,
  pub name: String,
  pub document: Document,
  #[serde(rename = "type")]
  pub creature_type: NamedKey,
  pub size: NamedKey,
  #[serde(default, deserialize_with = "null_as_default")]
  pub challenge_rating: f32,
  #[serde(default)]
  pub proficiency_bonus: Option<i32>,
  #[serde(default)]
  pub speed_all: SpeedAll,
  #[serde(default)]
  pub alignment: String,
  #[serde(default)]
  pub languages: Languages,
  #[serde(default, deserialize_with = "null_as_default")]
  pub armor_class: i32,
  #[serde(default)]
  pub armor_detail: String,
  #[serde(default, deserialize_with = "null_as_default")]
  pub hit_points: i32,
  #[serde(default)]
  pub hit_dice: String,
  #[serde(default, deserialize_with = "null_as_default")]
  pub experience_points: i64,
  #[serde(default)]
  pub ability_scores: AbilityScores,
  #[serde(default, deserialize_with = "null_as_default")]
  pub initiative_bonus: i32,
  #[serde(default)]
  pub saving_throws_all: AbilityScores,
  #[serde(default)]
  pub skill_bonuses: serde_json::Map<String, serde_json::Value>,
  #[serde(default, deserialize_with = "null_as_default")]
  pub passive_perception: i32,
  #[serde(default)]
  pub resistances_and_immunities: ResistancesAndImmunities,
  #[serde(default, deserialize_with = "null_as_default")]
  pub normal_sight_range: i32,
  #[serde(default, deserialize_with = "null_as_default")]
  pub darkvision_range: i32,
  #[serde(default, deserialize_with = "null_as_default")]
  pub blindsight_range: i32,
  #[serde(default)]
  pub tremorsense_range: Option<i32>,
  #[serde(default)]
  pub truesight_range: Option<i32>,
  #[serde(default)]
  pub actions: Vec<Action>,
  #[serde(default)]
  pub traits: Vec<Trait>,
}

#[derive(Debug, Deserialize)]
pub struct Document {
  pub name: String,
  pub key: String,
}

#[derive(Debug, Deserialize)]
pub struct NamedKey {
  pub name: String,
  pub key: String,
}

#[derive(Debug, Deserialize, Default)]
pub struct SpeedAll {
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
  #[serde(default)]
  pub hover: bool,
}

#[derive(Debug, Deserialize, Default)]
pub struct Languages {
  #[serde(default)]
  pub as_string: String,
}

#[derive(Debug, Deserialize, Default)]
pub struct AbilityScores {
  #[serde(default)]
  pub strength: Option<i32>,
  #[serde(default)]
  pub dexterity: Option<i32>,
  #[serde(default)]
  pub constitution: Option<i32>,
  #[serde(default)]
  pub intelligence: Option<i32>,
  #[serde(default)]
  pub wisdom: Option<i32>,
  #[serde(default)]
  pub charisma: Option<i32>,
}

#[derive(Debug, Deserialize, Default)]
pub struct ResistancesAndImmunities {
  #[serde(default)]
  pub damage_immunities: Vec<NamedKey>,
  #[serde(default)]
  pub damage_resistances: Vec<NamedKey>,
  #[serde(default)]
  pub damage_vulnerabilities: Vec<NamedKey>,
  #[serde(default)]
  pub condition_immunities: Vec<NamedKey>,
}

#[derive(Debug, Deserialize)]
pub struct Action {
  pub name: String,
  pub desc: String,
  /// `action`, `bonus`, `reaction`, `legendary`, or others.
  pub action_type: String,
  #[serde(default)]
  pub legendary_action_cost: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct Trait {
  pub name: String,
  pub desc: String,
}

// ── MAPPING ────────────────────────────────────────────────────

impl Monster {
  /// Promote an Open5e creature directly to a full `Creature`,
  /// using a deterministic UUIDv5 derived from `self.key` so the
  /// resulting bundle is reproducible across re-harvests.
  /// `now` stamps both `created_at` and `updated_at`.
  pub fn into_creature(self, now: i64) -> Creature {
    let id = stable_uuid_from_key(&self.key).to_string();
    let draft: CreatureDraft = self.into();
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
      created_at: now,
      updated_at: now,
    }
  }
}

impl From<Monster> for CreatureDraft {
  fn from(m: Monster) -> Self {
    let abilities = Abilities {
      str: m.ability_scores.strength.unwrap_or(10),
      dex: m.ability_scores.dexterity.unwrap_or(10),
      con: m.ability_scores.constitution.unwrap_or(10),
      int: m.ability_scores.intelligence.unwrap_or(10),
      wis: m.ability_scores.wisdom.unwrap_or(10),
      cha: m.ability_scores.charisma.unwrap_or(10),
    };

    let saving_throws = saving_throws_from(&m.saving_throws_all);
    let skills = skills_from(&m.skill_bonuses);
    let speed = Speed {
      walk: m.speed_all.walk,
      fly: m.speed_all.fly,
      swim: m.speed_all.swim,
      climb: m.speed_all.climb,
      burrow: m.speed_all.burrow,
      hover: m.speed_all.hover,
    };

    let senses = Senses {
      blindsight: m.blindsight_range,
      darkvision: m.darkvision_range,
      tremorsense: m.tremorsense_range.unwrap_or(0),
      truesight: m.truesight_range.unwrap_or(0),
      // Open5e fills `passive_perception` at the creature level
      // when the SRD prints it; otherwise default to 10 (matches
      // the stat-block parser's behavior).
      passive_perception: if m.passive_perception > 0 {
        m.passive_perception
      } else {
        10
      },
    };

    let partitioned = partition_features(m.traits, m.actions);

    CreatureDraft {
      name: m.name,
      kind: CreatureKind::Enemy,
      size: size_from_key(&m.size.key),
      race: m.creature_type.name,
      subrace: String::new(),
      alignment: m.alignment,
      source: format!("Open5e — {}", m.document.name),
      description: String::new(),
      armor_class: m.armor_class,
      armor_class_note: m.armor_detail,
      max_hp: m.hit_points,
      hp_formula: m.hit_dice,
      initiative_bonus: m.initiative_bonus,
      speed,
      abilities,
      saving_throws,
      skills,
      damage_vulnerabilities: named_key_names(
        m.resistances_and_immunities.damage_vulnerabilities,
      ),
      damage_resistances: named_key_names(
        m.resistances_and_immunities.damage_resistances,
      ),
      damage_immunities: named_key_names(
        m.resistances_and_immunities.damage_immunities,
      ),
      condition_immunities: named_key_names(
        m.resistances_and_immunities.condition_immunities,
      ),
      senses,
      languages: parse_languages(&m.languages.as_string),
      challenge_rating: cr_to_string(m.challenge_rating),
      xp: m.experience_points,
      xp_in_lair: 0,
      proficiency_bonus: m.proficiency_bonus.unwrap_or(0),
      traits: partitioned.traits,
      actions: partitioned.actions,
      bonus_actions: partitioned.bonus_actions,
      reactions: partitioned.reactions,
      legendary_actions: partitioned.legendary_actions,
      lair_actions: None,
      regional_effects: None,
      spellcasting: None,
      custom_sections: Vec::new(),
      habitats: Vec::new(),
      treasures: Vec::new(),
      tags: Vec::new(),
    }
  }
}

/// Convert a fractional CR float into the canonical string the
/// rest of the app expects: `"1/8"`, `"1/4"`, `"1/2"`, or
/// `"<int>"` for whole numbers.  Anything else becomes the float
/// printed with one decimal place — those don't appear in
/// official content but the fallback keeps the conversion total.
fn cr_to_string(cr: f32) -> String {
  if cr <= 0.0 {
    return "0".to_string();
  }

  // Compare with a small epsilon since the API serializes 1/8 as
  // 0.125, 1/4 as 0.25, etc. — exact in binary, but be defensive.
  let eps = 0.001;
  if (cr - 0.125).abs() < eps {
    return "1/8".to_string();
  }
  if (cr - 0.25).abs() < eps {
    return "1/4".to_string();
  }
  if (cr - 0.5).abs() < eps {
    return "1/2".to_string();
  }

  if (cr - cr.round()).abs() < eps {
    return (cr as i32).to_string();
  }

  format!("{cr:.1}")
}

fn size_from_key(key: &str) -> Size {
  match key {
    "tiny" => Size::Tiny,
    "small" => Size::Small,
    "large" => Size::Large,
    "huge" => Size::Huge,
    "gargantuan" => Size::Gargantuan,
    // Default to medium for "medium" and any unexpected values.
    _ => Size::Medium,
  }
}

/// Open5e returns damage / condition immunity arrays as objects
/// shaped `{key, name}`, not plain strings.  Project to the
/// human-readable `name` for our flat `Vec<String>` slot.
fn named_key_names(items: Vec<NamedKey>) -> Vec<String> {
  items.into_iter().map(|n| n.name).collect()
}

/// Fixed UUIDv5 namespace for harvested creatures.  Picking a
/// constant project-specific namespace + the Open5e `key` slug
/// gives every bundled creature a stable, reproducible UUID:
/// re-running the harvester always produces the same UUIDs, so
/// the server's bundle-version merge logic (which dedupes by
/// id) keeps working.
///
/// The namespace value is arbitrary but must never change once
/// shipped — that would invalidate every existing bundle.
const HARVEST_NAMESPACE: uuid::Uuid = uuid::Uuid::from_bytes([
  0x6e, 0x7a, 0x70, 0x7a, 0x2d, 0x64, 0x6e, 0x64, 0x7a, 0x2d, 0x6f, 0x70, 0x65,
  0x6e, 0x35, 0x65,
]);

/// Derive a deterministic UUID for a bundled creature from its
/// Open5e stable `key` slug.
pub fn stable_uuid_from_key(key: &str) -> uuid::Uuid {
  uuid::Uuid::new_v5(&HARVEST_NAMESPACE, key.as_bytes())
}

fn parse_languages(raw: &str) -> Vec<String> {
  if raw.trim().is_empty() {
    return Vec::new();
  }
  raw
    .split(',')
    .map(str::trim)
    .filter(|s| !s.is_empty())
    .map(str::to_string)
    .collect()
}

fn saving_throws_from(scores: &AbilityScores) -> Vec<AbilitySave> {
  let mut out = Vec::new();
  if let Some(b) = scores.strength {
    out.push(AbilitySave {
      ability: Ability::Str,
      bonus: b,
    });
  }
  if let Some(b) = scores.dexterity {
    out.push(AbilitySave {
      ability: Ability::Dex,
      bonus: b,
    });
  }
  if let Some(b) = scores.constitution {
    out.push(AbilitySave {
      ability: Ability::Con,
      bonus: b,
    });
  }
  if let Some(b) = scores.intelligence {
    out.push(AbilitySave {
      ability: Ability::Int,
      bonus: b,
    });
  }
  if let Some(b) = scores.wisdom {
    out.push(AbilitySave {
      ability: Ability::Wis,
      bonus: b,
    });
  }
  if let Some(b) = scores.charisma {
    out.push(AbilitySave {
      ability: Ability::Cha,
      bonus: b,
    });
  }
  out
}

fn skills_from(
  raw: &serde_json::Map<String, serde_json::Value>,
) -> Vec<SkillBonus> {
  raw
    .iter()
    .filter_map(|(k, v)| {
      let bonus = v.as_i64()? as i32;
      Some(SkillBonus {
        name: titlecase_skill(k),
        bonus,
      })
    })
    .collect()
}

/// `"animal_handling"` → `"Animal Handling"`.
fn titlecase_skill(snake: &str) -> String {
  snake
    .split('_')
    .map(|word| {
      let mut chars = word.chars();
      match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().chain(chars).collect::<String>(),
      }
    })
    .collect::<Vec<_>>()
    .join(" ")
}

/// Output of [`partition_features`] — the four flat buckets we
/// store on `Creature` plus the optional `LegendaryActions`
/// block.  Named struct so the call site can use field-access
/// rather than tuple-position destructuring (and so clippy
/// stops complaining about the very-complex tuple type).
struct PartitionedFeatures {
  traits: Vec<Feature>,
  actions: Vec<Feature>,
  bonus_actions: Vec<Feature>,
  reactions: Vec<Feature>,
  legendary_actions: Option<LegendaryActions>,
}

/// Split Open5e's flat `actions` list by `action_type` into our
/// four buckets, plus convert the legendary slice into a single
/// `LegendaryActions` block.  Traits go straight through.
fn partition_features(
  traits_in: Vec<Trait>,
  actions_in: Vec<Action>,
) -> PartitionedFeatures {
  let traits: Vec<Feature> = traits_in
    .into_iter()
    .map(|t| Feature {
      name: t.name,
      description: t.desc,
      usage: None,
    })
    .collect();

  let mut actions = Vec::new();
  let mut bonus_actions = Vec::new();
  let mut reactions = Vec::new();
  let mut legendary_options: Vec<LegendaryOption> = Vec::new();

  for a in actions_in {
    // Open5e v2 emits action_type as `ACTION` / `BONUS_ACTION`
    // / `REACTION` / `LEGENDARY_ACTION` (uppercase).  Normalize
    // to lowercase before matching so a future shape change to
    // either case keeps working.
    let key = a.action_type.to_lowercase();
    match key.as_str() {
      "bonus" | "bonus_action" => bonus_actions.push(Feature {
        name: a.name,
        description: a.desc,
        usage: None,
      }),
      "reaction" => reactions.push(Feature {
        name: a.name,
        description: a.desc,
        usage: None,
      }),
      "legendary" | "legendary_action" => {
        legendary_options.push(LegendaryOption {
          name: a.name,
          cost: a.legendary_action_cost.unwrap_or(1),
          description: a.desc,
        })
      }
      _ => actions.push(Feature {
        name: a.name,
        description: a.desc,
        usage: None,
      }),
    }
  }

  let legendary_actions = if legendary_options.is_empty() {
    None
  } else {
    Some(LegendaryActions {
      // Open5e doesn't carry the legendary-actions preamble as a
      // separate field; leave the description blank and let the
      // GM fill in the standard "can take 3 legendary actions…"
      // text in the editor if needed.
      description: String::new(),
      uses: 3,
      uses_in_lair: 0,
      options: legendary_options,
    })
  };

  PartitionedFeatures {
    traits,
    actions,
    bonus_actions,
    reactions,
    legendary_actions,
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn cr_to_string_handles_fractions_and_whole_numbers() {
    assert_eq!(cr_to_string(0.0), "0");
    assert_eq!(cr_to_string(0.125), "1/8");
    assert_eq!(cr_to_string(0.25), "1/4");
    assert_eq!(cr_to_string(0.5), "1/2");
    assert_eq!(cr_to_string(1.0), "1");
    assert_eq!(cr_to_string(11.0), "11");
    assert_eq!(cr_to_string(20.0), "20");
  }

  #[test]
  fn size_from_key_falls_back_to_medium() {
    assert!(matches!(size_from_key("tiny"), Size::Tiny));
    assert!(matches!(size_from_key("huge"), Size::Huge));
    assert!(matches!(size_from_key("medium"), Size::Medium));
    assert!(matches!(size_from_key("nonsense"), Size::Medium));
  }

  #[test]
  fn parse_languages_splits_and_trims() {
    assert_eq!(
      parse_languages("Common, Draconic, Telepathy 120 ft."),
      vec![
        "Common".to_string(),
        "Draconic".to_string(),
        "Telepathy 120 ft.".to_string(),
      ]
    );
    assert!(parse_languages("").is_empty());
    assert!(parse_languages("   ").is_empty());
  }

  #[test]
  fn titlecase_skill_unsnakes() {
    assert_eq!(titlecase_skill("perception"), "Perception");
    assert_eq!(titlecase_skill("animal_handling"), "Animal Handling");
    assert_eq!(titlecase_skill("sleight_of_hand"), "Sleight Of Hand");
  }

  #[test]
  fn partition_features_buckets_action_types() {
    // Mix uppercase (what Open5e v2 actually emits) and lowercase
    // (defensive — protects against either case appearing in
    // future API revisions).
    let actions = vec![
      Action {
        name: "Slam".to_string(),
        desc: "Melee attack".to_string(),
        action_type: "ACTION".to_string(),
        legendary_action_cost: None,
      },
      Action {
        name: "Quick Step".to_string(),
        desc: "Move 10 ft.".to_string(),
        action_type: "BONUS_ACTION".to_string(),
        legendary_action_cost: None,
      },
      Action {
        name: "Parry".to_string(),
        desc: "Add 3 to AC".to_string(),
        action_type: "REACTION".to_string(),
        legendary_action_cost: None,
      },
      Action {
        name: "Tail Swipe".to_string(),
        desc: "Costs 2 actions".to_string(),
        action_type: "LEGENDARY_ACTION".to_string(),
        legendary_action_cost: Some(2),
      },
      // Lowercase fallback — same buckets.
      Action {
        name: "Wing".to_string(),
        desc: "Wing attack".to_string(),
        action_type: "legendary".to_string(),
        legendary_action_cost: Some(1),
      },
    ];

    let p = partition_features(Vec::new(), actions);

    assert!(p.traits.is_empty());
    assert_eq!(p.actions.len(), 1, "ACTION should bucket as actions");
    assert_eq!(p.bonus_actions.len(), 1, "BONUS_ACTION should bucket as bonus");
    assert_eq!(p.reactions.len(), 1, "REACTION should bucket as reactions");

    let legendary = p.legendary_actions.expect("expected legendary block");
    assert_eq!(
      legendary.options.len(),
      2,
      "LEGENDARY_ACTION + lowercase legendary should both bucket as legendary"
    );
    assert_eq!(legendary.options[0].cost, 2);
    assert_eq!(legendary.options[1].cost, 1);
  }
}
