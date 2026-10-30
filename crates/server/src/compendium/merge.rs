//! Moving a signed-out session's compendium into an account.

use std::collections::HashMap;

use ezpz_dndz_lib::compendium::{Creature, Group, GroupEntry};

/// Creatures and groups under the ids they will have in the account.
pub struct Rekeyed {
  pub creatures: Vec<Creature>,
  pub groups: Vec<Group>,
}

/// The incoming creatures and groups under fresh ids.
///
/// Two browsers can mint the same local id.  Nothing keeps the id it arrived
/// with.  A group entry follows its creature to the new id.  An entry that
/// names a bundled creature keeps that id.  Bundled creatures in the body are
/// dropped.  The bundle is read-only.
pub fn rekeyed(
  creatures: Vec<Creature>,
  groups: Vec<Group>,
  is_bundled: impl Fn(&str) -> bool,
  mut fresh_id: impl FnMut() -> String,
) -> Rekeyed {
  let moved: Vec<(String, Creature)> = creatures
    .into_iter()
    .filter(|creature| !is_bundled(&creature.id))
    .map(|creature| {
      let old_id = creature.id.clone();
      (
        old_id,
        Creature {
          id: fresh_id(),
          ..creature
        },
      )
    })
    .collect();
  let new_id_of: HashMap<&str, &str> = moved
    .iter()
    .map(|(old_id, creature)| (old_id.as_str(), creature.id.as_str()))
    .collect();
  let groups = groups
    .into_iter()
    .map(|group| Group {
      id: fresh_id(),
      entries: group
        .entries
        .into_iter()
        .map(|entry| GroupEntry {
          creature_id: new_id_of
            .get(entry.creature_id.as_str())
            .map_or(entry.creature_id.clone(), |id| (*id).to_string()),
          ..entry
        })
        .collect(),
      ..group
    })
    .collect();
  Rekeyed {
    creatures: moved.into_iter().map(|(_, creature)| creature).collect(),
    groups,
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::compendium::user_store::creature_from_draft;
  use ezpz_dndz_lib::compendium::{CreatureDraft, InitiativeMode, MinionType};

  fn creature(id: &str) -> Creature {
    let draft: CreatureDraft = serde_json::from_value(serde_json::json!({
      "name": id,
      "kind": "enemy",
      "size": "medium",
      "armor_class": 12,
      "max_hp": 10,
    }))
    .expect("draft");
    creature_from_draft(draft, id.to_string(), 0)
  }

  fn group(id: &str, members: &[&str]) -> Group {
    Group {
      id: id.to_string(),
      name: id.to_string(),
      initiative_mode: InitiativeMode::EachRolls,
      entries: members
        .iter()
        .map(|member| GroupEntry {
          creature_id: member.to_string(),
          count: 1,
          minion_type: MinionType::default(),
        })
        .collect(),
      created_at: 1,
      updated_at: 1,
    }
  }

  #[test]
  fn every_creature_and_group_gets_a_fresh_id_and_entries_follow() {
    let mut next = 0;
    let rekeyed = rekeyed(
      vec![creature("local-1"), creature("local-2")],
      vec![group("g", &["local-2", "bundled-ogre"])],
      |id| id.starts_with("bundled-"),
      || {
        next += 1;
        format!("new-{next}")
      },
    );
    let ids: Vec<&str> =
      rekeyed.creatures.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(ids, ["new-1", "new-2"]);
    assert_eq!(rekeyed.groups[0].id, "new-3");
    let members: Vec<&str> = rekeyed.groups[0]
      .entries
      .iter()
      .map(|e| e.creature_id.as_str())
      .collect();
    assert_eq!(members, ["new-2", "bundled-ogre"]);
  }

  #[test]
  fn bundled_creatures_in_the_body_are_dropped() {
    let rekeyed = rekeyed(
      vec![creature("bundled-ogre"), creature("local-1")],
      vec![],
      |id| id.starts_with("bundled-"),
      || "fresh".to_string(),
    );
    assert_eq!(rekeyed.creatures.len(), 1);
    assert_eq!(rekeyed.creatures[0].name, "local-1");
  }
}
