//! Deterministic habitat inference for bundled creatures.
//!
//! The Open5e SRD 5.2 dataset exposes the 2024 Monster Manual
//! `habitats` field but populates no values — the habitat lists
//! themselves live in the proprietary 2024 MM and aren't part of
//! the CC-BY SRD.  This module fills the gap by reading what we
//! *do* have on each creature (name, race, descriptive flavour)
//! and emitting the obvious habitats.
//!
//! Coverage is intentionally biased toward iconic D&D monsters
//! (dragons by colour, demons → Abyss, devils → Nine Hells,
//! elementals by element, classic Underdark dwellers).  The long
//! tail of generic beasts gets a best-effort name match; anything
//! the rules can't classify is returned as an empty Vec and the
//! caller leaves the creature untouched.
//!
//! The rules are *facts* about D&D monsters — that a Polar Bear
//! lives in Arctic biomes is not 2024-MM-copyrightable — so the
//! output can ship in the bundle alongside the SRD data without
//! licensing concerns.

use std::collections::BTreeSet;

use ezpz_dndz_lib::compendium::{Creature, Habitat};

/// Pick the habitats for a single creature.  Returns an empty
/// `Vec` if no rule matches — the caller MUST treat that as "no
/// change" rather than overwriting an existing list with nothing.
pub fn infer_habitats(creature: &Creature) -> Vec<Habitat> {
  let name = creature.name.to_lowercase();
  let race = creature.race.to_lowercase();
  let mut out: BTreeSet<Habitat> = BTreeSet::new();

  apply_dragon_rules(&name, &race, &mut out);
  apply_race_rules(&name, &race, &mut out);
  apply_named_monster_rules(&name, &mut out);
  apply_beast_rules(&name, &race, &mut out);

  out.into_iter().collect()
}

/// Chromatic + metallic dragons get habitats by colour.  The
/// 2024 MM associations are well-known D&D lore that long
/// predates that book.
fn apply_dragon_rules(name: &str, race: &str, out: &mut BTreeSet<Habitat>) {
  if race != "dragon" {
    return;
  }

  // Catch every age category for each colour with one substring
  // check — "Adult Black Dragon" / "Black Dragon Wyrmling" /
  // "Young Black Dragon" / "Ancient Black Dragon" all match.
  if name.contains("black dragon") {
    out.insert(Habitat::Swamp);
  }
  if name.contains("blue dragon") {
    out.insert(Habitat::Desert);
  }
  if name.contains("green dragon") {
    out.insert(Habitat::Forest);
  }
  if name.contains("red dragon") {
    out.insert(Habitat::Mountain);
  }
  if name.contains("white dragon") {
    out.insert(Habitat::Arctic);
    out.insert(Habitat::Mountain);
  }
  if name.contains("brass dragon") {
    out.insert(Habitat::Desert);
  }
  if name.contains("bronze dragon") {
    out.insert(Habitat::Coastal);
  }
  if name.contains("copper dragon") {
    out.insert(Habitat::Hill);
  }
  if name.contains("gold dragon") {
    out.insert(Habitat::Mountain);
    out.insert(Habitat::Grassland);
  }
  if name.contains("silver dragon") {
    out.insert(Habitat::Mountain);
  }

  // Dragon outliers — distinct enough to handle by name.
  if name == "dragon turtle" {
    out.insert(Habitat::Coastal);
    out.insert(Habitat::Underwater);
  }
  if name == "pseudodragon" {
    out.insert(Habitat::Forest);
  }
  if name == "wyvern" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Mountain);
  }
  // Kobolds are filed under Dragon in the 2024 MM but live in
  // mundane lairs.
  if name.contains("kobold") {
    out.insert(Habitat::Underdark);
    out.insert(Habitat::Hill);
  }
}

/// Broad strokes by creature type.  These catch the cases where
/// the creature's race alone is enough to nail the plane —
/// elementals come from elemental planes, etc.  Material-plane
/// types (Beast, Humanoid) need name-level resolution and get
/// no habitats here.
fn apply_race_rules(name: &str, race: &str, out: &mut BTreeSet<Habitat>) {
  match race {
    "fiend" => {
      // Devil names → Nine Hells; demon names → Abyss; the rest
      // get handled in named_monster_rules.
      if is_named_devil(name) {
        out.insert(Habitat::NineHells);
      } else if is_named_demon(name) {
        out.insert(Habitat::Abyss);
      }
    }
    "celestial" => {
      // Sphinxes are celestial in 2024 MM but iconically desert.
      // Pegasus, Giant Eagle/Owl/Elk are material-plane celestials.
      if name.contains("sphinx") {
        out.insert(Habitat::Desert);
      } else if name == "deva" || name == "planetar" || name == "solar" {
        out.insert(Habitat::UpperPlanes);
      } else if name == "couatl" {
        out.insert(Habitat::Forest);
        out.insert(Habitat::UpperPlanes);
      } else if name == "pegasus" || name == "unicorn" {
        out.insert(Habitat::Forest);
      } else if name == "giant eagle" || name == "giant owl" {
        out.insert(Habitat::Mountain);
        out.insert(Habitat::Forest);
      } else if name == "giant elk" {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Grassland);
      } else if name == "guardian naga" {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Swamp);
      }
    }
    "elemental" => {
      // Element-specific lookups; "Elemental" suffix catches the
      // four core elementals.
      if name.contains("fire elemental")
        || name == "efreeti"
        || name == "salamander"
        || name == "magmin"
        || name.contains("azer")
      {
        out.insert(Habitat::ElementalPlaneOfFire);
      }
      if name.contains("water elemental")
        || name == "marid"
        || name.contains("merfolk")
      {
        out.insert(Habitat::ElementalPlaneOfWater);
      }
      if name.contains("air elemental")
        || name == "djinni"
        || name == "invisible stalker"
      {
        out.insert(Habitat::ElementalPlaneOfAir);
      }
      if name.contains("earth elemental") || name == "dao" || name == "xorn" {
        out.insert(Habitat::ElementalPlaneOfEarth);
      }
      if name.contains("mephit") {
        out.insert(Habitat::ElementalChaos);
      }
      if name == "gargoyle" {
        out.insert(Habitat::Mountain);
        out.insert(Habitat::Urban);
      }
    }
    "fey" => {
      // 2024 MM moved goblinoids and worgs to Fey.  They still
      // live in mundane biomes, not the Feywild itself.
      if name.contains("goblin")
        || name.contains("hobgoblin")
        || name.contains("bugbear")
      {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Hill);
        out.insert(Habitat::Underdark);
      } else if name == "worg" {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Hill);
      } else if name == "blink dog"
        || name == "dryad"
        || name == "satyr"
        || name == "sprite"
      {
        out.insert(Habitat::Feywild);
        out.insert(Habitat::Forest);
      } else if name == "green hag" {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Swamp);
      } else if name == "sea hag" {
        out.insert(Habitat::Coastal);
        out.insert(Habitat::Underwater);
      } else if name.contains("centaur") {
        out.insert(Habitat::Forest);
        out.insert(Habitat::Grassland);
      }
    }
    "aberration" => {
      // Aberrations are overwhelmingly Underdark in lore.
      out.insert(Habitat::Underdark);
      // Aboleths and chuuls bridge into Underwater.
      if name == "aboleth" || name == "chuul" {
        out.insert(Habitat::Underwater);
      }
    }
    "undead" => {
      // Most undead either haunt the place they died (Urban)
      // or hide where the living don't go (Underdark).  Catch
      // the genuinely distinct cases separately.
      if name.contains("mummy") {
        out.insert(Habitat::Desert);
      } else {
        out.insert(Habitat::Urban);
        // Liches, wraiths, shadows linger in deeper places too.
        if name == "lich"
          || name == "wraith"
          || name == "shadow"
          || name == "specter"
        {
          out.insert(Habitat::Underdark);
        }
      }
    }
    "giant" => {
      if name.contains("hill giant") || name == "ogre" {
        out.insert(Habitat::Hill);
      }
      if name.contains("frost giant") {
        out.insert(Habitat::Arctic);
        out.insert(Habitat::Mountain);
      }
      if name.contains("stone giant") {
        out.insert(Habitat::Mountain);
        out.insert(Habitat::Underdark);
      }
      if name.contains("fire giant") {
        out.insert(Habitat::Mountain);
      }
      if name.contains("cloud giant") {
        out.insert(Habitat::Mountain);
      }
      if name.contains("storm giant") {
        out.insert(Habitat::Coastal);
        out.insert(Habitat::Underwater);
      }
      if name == "ettin" {
        out.insert(Habitat::Hill);
        out.insert(Habitat::Forest);
      }
      if name == "troll" || name == "troll limb" {
        out.insert(Habitat::Swamp);
        out.insert(Habitat::Forest);
      }
    }
    "construct" => {
      // Most constructs are made-in-a-tower fare → Urban.
      // The exception is a stray Underdark golem, but the bundle
      // doesn't differentiate.
      out.insert(Habitat::Urban);
    }
    "ooze" => {
      // Iconic dungeon dwellers in every edition.
      out.insert(Habitat::Underdark);
    }
    "humanoid" => {
      // The bundle's humanoids are all civilised stock blocks
      // (Bandit, Guard, Knight, Mage, Priest...).  Urban is the
      // canonical 2024 MM habitat for this set.
      out.insert(Habitat::Urban);
    }
    "plant" => {
      // Treants, awakened shrubs, shambling mounds.  Forest /
      // Swamp depending on the species.
      if name.contains("shambling") {
        out.insert(Habitat::Swamp);
      } else if name.contains("fungus") {
        out.insert(Habitat::Underdark);
      } else {
        out.insert(Habitat::Forest);
      }
    }
    _ => {}
  }
}

/// True for the 2024 MM nine-hells residents.  Note we match on
/// the suffix " devil" so "Bone Devil", "Ice Devil", etc. all
/// trigger, but a humanoid named "Devil-Hunter" wouldn't.
fn is_named_devil(name: &str) -> bool {
  name.ends_with(" devil")
    || name == "imp"
    || name == "lemure"
    || name == "pit fiend"
    || name == "erinyes"
    || name == "hell hound"
    || name == "nightmare"
    || name == "rakshasa"
}

/// The chaotic-evil canon.  Type names from the 2024 MM
/// "Demons" entry plus the iconic outliers (Quasit, Yochlol,
/// etc.) that show up across editions.
fn is_named_demon(name: &str) -> bool {
  matches!(
    name,
    "balor"
      | "dretch"
      | "glabrezu"
      | "hezrou"
      | "marilith"
      | "nalfeshnee"
      | "quasit"
      | "vrock"
  )
}

/// Specific monsters whose habitats are well-established lore
/// but whose race alone doesn't pin them down.
fn apply_named_monster_rules(name: &str, out: &mut BTreeSet<Habitat>) {
  // Aberrations (extra biome flavour beyond Underdark).
  if name == "cloaker" || name == "darkmantle" || name == "grick" {
    out.insert(Habitat::Underdark);
  }
  if name == "grimlock" {
    out.insert(Habitat::Underdark);
  }
  if name == "gibbering mouther" || name == "otyugh" {
    out.insert(Habitat::Swamp);
  }
  if name == "roper" {
    out.insert(Habitat::Underdark);
  }

  // Monstrosities — biome by lore.
  if name == "ankheg" || name == "axe beak" {
    out.insert(Habitat::Grassland);
  }
  if name == "basilisk" || name == "cockatrice" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Grassland);
  }
  if name == "behir" || name == "remorhaz" {
    if name == "remorhaz" {
      out.insert(Habitat::Arctic);
    } else {
      out.insert(Habitat::Underdark);
      out.insert(Habitat::Mountain);
    }
  }
  if name == "bulette" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Grassland);
  }
  if name == "chimera" || name == "manticore" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Mountain);
  }
  if name == "death dog" {
    out.insert(Habitat::Desert);
    out.insert(Habitat::Hill);
  }
  if name == "doppelganger" {
    out.insert(Habitat::Urban);
  }
  if name == "drider" {
    out.insert(Habitat::Underdark);
  }
  if name == "ettercap" {
    out.insert(Habitat::Forest);
  }
  if name == "flying snake" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Swamp);
  }
  if name == "giant vulture" {
    out.insert(Habitat::Desert);
    out.insert(Habitat::Hill);
  }
  if name == "griffon" || name == "hippogriff" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Mountain);
  }
  if name == "harpy" {
    out.insert(Habitat::Hill);
    out.insert(Habitat::Coastal);
  }
  if name == "hydra" {
    out.insert(Habitat::Swamp);
  }
  if name == "kraken" {
    out.insert(Habitat::Underwater);
  }
  if name == "medusa" {
    out.insert(Habitat::Urban);
    out.insert(Habitat::Hill);
  }
  if name == "merrow" {
    out.insert(Habitat::Coastal);
    out.insert(Habitat::Underwater);
  }
  if name == "mimic" {
    out.insert(Habitat::Underdark);
    out.insert(Habitat::Urban);
  }
  if name.contains("minotaur") {
    out.insert(Habitat::Underdark);
    out.insert(Habitat::Grassland);
  }
  if name == "owlbear" {
    out.insert(Habitat::Forest);
  }
  if name == "phase spider" {
    out.insert(Habitat::Feywild);
    out.insert(Habitat::Forest);
  }
  if name == "purple worm" {
    out.insert(Habitat::Underdark);
  }
  if name == "roc" {
    out.insert(Habitat::Mountain);
  }
  if name == "rust monster" {
    out.insert(Habitat::Underdark);
  }
  if name == "stirge" {
    out.insert(Habitat::Swamp);
    out.insert(Habitat::Forest);
  }
  if name == "tarrasque" {
    out.insert(Habitat::Mountain);
    out.insert(Habitat::Grassland);
  }
  // Lycanthropes — the human side of the dual stat block.
  if name == "werewolf" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Urban);
  }
  if name == "werebear" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Mountain);
  }
  if name == "wereboar" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Hill);
  }
  if name == "wererat" {
    out.insert(Habitat::Urban);
  }
  if name == "weretiger" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Grassland);
  }
  if name == "winter wolf" {
    out.insert(Habitat::Arctic);
  }

  // Fiend outliers handled here (not name-suffix-matchable).
  if name == "lamia" {
    out.insert(Habitat::Desert);
  }
  if name == "night hag" {
    out.insert(Habitat::LowerPlanes);
  }
  if name == "oni" {
    out.insert(Habitat::Mountain);
    out.insert(Habitat::Forest);
  }
  if name == "spirit naga" {
    out.insert(Habitat::Swamp);
    out.insert(Habitat::Underdark);
  }
  if name == "succubus" || name == "incubus" {
    out.insert(Habitat::LowerPlanes);
    out.insert(Habitat::Urban);
  }
  if name.contains("sahuagin") {
    out.insert(Habitat::Coastal);
    out.insert(Habitat::Underwater);
  }
  if name.contains("gnoll") {
    out.insert(Habitat::Desert);
    out.insert(Habitat::Grassland);
  }
}

/// Beasts and animals by name fragment.  Catches the
/// long tail (90 creatures) that don't get habitats from the
/// race-level rules.
fn apply_beast_rules(name: &str, race: &str, out: &mut BTreeSet<Habitat>) {
  if race != "beast" {
    return;
  }

  // Arctic dwellers.
  if name.contains("polar")
    || name == "mammoth"
    || name == "saber-toothed tiger"
  {
    out.insert(Habitat::Arctic);
    return;
  }

  // Marine — fish, cephalopods, marine mammals.
  if name.contains("shark")
    || name.contains("octopus")
    || name.contains("piranha")
    || name == "killer whale"
    || name == "plesiosaurus"
    || name == "seahorse"
    || name == "giant seahorse"
    || name == "archelon"
  {
    out.insert(Habitat::Coastal);
    out.insert(Habitat::Underwater);
    return;
  }
  if name.contains("crab") {
    out.insert(Habitat::Coastal);
    return;
  }

  // Swamp + waterside.
  if name.contains("crocodile")
    || name.contains("frog")
    || name.contains("toad")
    || name == "hippopotamus"
  {
    out.insert(Habitat::Swamp);
    return;
  }

  // Desert.
  if name == "camel" || name == "giant scorpion" || name == "scorpion" {
    out.insert(Habitat::Desert);
    return;
  }

  // Grassland — savannah / plains beasts.
  if name == "lion"
    || name == "elephant"
    || name == "rhinoceros"
    || name == "hyena"
    || name == "giant hyena"
    || name == "jackal"
    || name == "axe beak"
    || name == "triceratops"
    || name == "ankylosaurus"
    || name == "tyrannosaurus rex"
  {
    out.insert(Habitat::Grassland);
    return;
  }

  // Forest — the catch-all for woodland fauna.
  if name == "tiger"
    || name == "panther"
    || name == "wolf"
    || name == "dire wolf"
    || name == "boar"
    || name == "giant boar"
    || name == "deer"
    || name == "elk"
    || name == "owl"
    || name == "vulture"
    || name == "ape"
    || name == "giant ape"
    || name == "baboon"
    || name == "constrictor snake"
    || name == "giant constrictor snake"
    || name == "venomous snake"
    || name == "giant venomous snake"
    || name == "swarm of venomous snakes"
    || name == "allosaurus"
    || name == "pteranodon"
  {
    out.insert(Habitat::Forest);
    return;
  }

  // Bears split between forest and arctic edges.
  if name.contains("bear") {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Hill);
    return;
  }

  // Mountain & high-altitude raptors.
  if name == "hawk"
    || name == "blood hawk"
    || name == "eagle"
    || name == "giant eagle"
    || name == "goat"
    || name == "giant goat"
  {
    out.insert(Habitat::Mountain);
    out.insert(Habitat::Hill);
    return;
  }

  // Urban critters and domesticated animals.
  if name == "rat"
    || name == "giant rat"
    || name == "swarm of rats"
    || name == "cat"
    || name == "raven"
    || name == "swarm of ravens"
    || name == "mastiff"
    || name == "mule"
    || name == "pony"
    || name == "riding horse"
    || name == "draft horse"
    || name == "warhorse"
  {
    out.insert(Habitat::Urban);
    return;
  }

  // Cave-dwelling small fauna.
  if name == "bat"
    || name == "giant bat"
    || name == "swarm of bats"
    || name == "giant fire beetle"
    || name == "giant centipede"
    || name == "giant wolf spider"
  {
    out.insert(Habitat::Underdark);
    return;
  }

  // Spiders and bugs split forest + underdark.
  if name == "spider" || name == "giant spider" || name == "giant wasp" {
    out.insert(Habitat::Forest);
    out.insert(Habitat::Underdark);
    return;
  }

  // Generic small fauna — go forest as the default.
  if name == "badger"
    || name == "giant badger"
    || name == "weasel"
    || name == "giant weasel"
    || name == "lizard"
    || name == "giant lizard"
    || name == "swarm of insects"
  {
    out.insert(Habitat::Forest);
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use ezpz_dndz_lib::compendium::{
    Abilities, CreatureKind, Senses, Size, Speed,
  };

  fn fixture(name: &str, race: &str) -> Creature {
    Creature {
      id: "test".into(),
      name: name.into(),
      kind: CreatureKind::Enemy,
      size: Size::Medium,
      race: race.into(),
      subrace: String::new(),
      alignment: String::new(),
      source: String::new(),
      description: String::new(),
      armor_class: 10,
      armor_class_note: String::new(),
      max_hp: 1,
      hp_formula: String::new(),
      initiative_bonus: 0,
      speed: Speed::default(),
      abilities: Abilities::default(),
      saving_throws: vec![],
      skills: vec![],
      damage_vulnerabilities: vec![],
      damage_resistances: vec![],
      damage_immunities: vec![],
      condition_immunities: vec![],
      senses: Senses::default(),
      languages: vec![],
      challenge_rating: "0".into(),
      xp: 0,
      xp_in_lair: 0,
      proficiency_bonus: 0,
      traits: vec![],
      actions: vec![],
      bonus_actions: vec![],
      reactions: vec![],
      legendary_actions: None,
      lair_actions: None,
      regional_effects: None,
      spellcasting: None,
      custom_sections: vec![],
      habitats: vec![],
      treasures: vec![],
      tags: vec![],
      created_at: 0,
      updated_at: 0,
    }
  }

  #[test]
  fn black_dragon_is_swamp() {
    let cases = [
      "Adult Black Dragon",
      "Black Dragon Wyrmling",
      "Ancient Black Dragon",
    ];
    for n in cases {
      let h = infer_habitats(&fixture(n, "Dragon"));
      assert!(h.contains(&Habitat::Swamp), "{n}: {h:?}");
    }
  }

  #[test]
  fn polar_bear_is_arctic() {
    let h = infer_habitats(&fixture("Polar Bear", "Beast"));
    assert_eq!(h, vec![Habitat::Arctic]);
  }

  #[test]
  fn bone_devil_is_nine_hells() {
    let h = infer_habitats(&fixture("Bone Devil", "Fiend"));
    assert!(h.contains(&Habitat::NineHells));
  }

  #[test]
  fn balor_is_abyss() {
    let h = infer_habitats(&fixture("Balor", "Fiend"));
    assert!(h.contains(&Habitat::Abyss));
  }

  #[test]
  fn fire_elemental_is_elemental_plane_of_fire() {
    let h = infer_habitats(&fixture("Fire Elemental", "Elemental"));
    assert!(h.contains(&Habitat::ElementalPlaneOfFire));
  }

  #[test]
  fn aboleth_gets_underdark_and_underwater() {
    let h = infer_habitats(&fixture("Aboleth", "Aberration"));
    assert!(h.contains(&Habitat::Underdark));
    assert!(h.contains(&Habitat::Underwater));
  }

  #[test]
  fn mummy_is_desert_not_urban() {
    let h = infer_habitats(&fixture("Mummy", "Undead"));
    assert!(h.contains(&Habitat::Desert));
    assert!(!h.contains(&Habitat::Urban));
  }

  #[test]
  fn unknown_returns_empty() {
    let h = infer_habitats(&fixture("Made-Up Thing", "Plant"));
    // Plants default to Forest, so this should hit Forest.
    assert_eq!(h, vec![Habitat::Forest]);
  }
}
