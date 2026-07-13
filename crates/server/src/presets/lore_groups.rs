//! Wire codec + SQL for user-authored lore groups.
//!
//! Mirrors `frontend/src/Encounter/RandomEncounter/Lore/Wire.elm`:
//! the payload is a JSON LIST of groups, each with an ordered member
//! list.  Decoder leniency, per the Elm module: `weight` defaults to
//! 3, `source` to `"user"`, `description` to `""`; member `role`
//! defaults to `"member"` (unknown strings fall back rather than
//! fail, since user data takes precedence over strict validation) and
//! the count bounds to 1.
//!
//! One deliberate server-side extra beyond the Elm decoder: an absent
//! `members` field decodes as the empty list.  The Elm encoder always
//! writes it, but historical hand-shaped payloads (and the
//! integration suite's partial fixtures) omit it, and defaulting is
//! strictly safer than rejecting.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::{json, Value};
use sqlx::{AnyConnection, Row};
use uuid::Uuid;

use super::{as_object, opt_i64_or, opt_str_or, req_str};
use crate::per_user_store::PerUserFeature;

pub struct Group {
  pub group_id: String,
  pub name: String,
  pub weight: i64,
  pub source: String,
  pub members: Vec<Slot>,
  pub description: String,
}

pub struct Slot {
  pub name: String,
  pub role: String,
  pub count_min: i64,
  pub count_max: i64,
}

/// The lore-groups feature: a `Vec<Group>` per user.
pub struct LoreGroups;

impl PerUserFeature for LoreGroups {
  const LABEL: &'static str = "lore-groups";
  const PARENT_TABLE: &'static str = "lore_group_sets";
  type Data = Vec<Group>;

  fn decode(payload: &Value) -> Result<Self::Data, String> {
    payload
      .as_array()
      .ok_or_else(|| "expected a JSON array of lore groups".to_string())?
      .iter()
      .enumerate()
      .map(|(i, raw)| decode_group(raw, i))
      .collect()
  }

  fn encode(data: &Self::Data) -> Value {
    Value::Array(data.iter().map(encode_group).collect())
  }

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    data: &Self::Data,
  ) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO lore_group_sets (user_id) VALUES ($1)")
      .bind(user_id.as_str())
      .execute(&mut *conn)
      .await?;

    for (i, group) in data.iter().enumerate() {
      let row_id = Uuid::new_v4().to_string();
      sqlx::query(
        "INSERT INTO lore_groups (id, user_id, position, group_id, \
         name, weight, source, description) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
      )
      .bind(&row_id)
      .bind(user_id.as_str())
      .bind(i as i64)
      .bind(&group.group_id)
      .bind(&group.name)
      .bind(group.weight)
      .bind(&group.source)
      .bind(&group.description)
      .execute(&mut *conn)
      .await?;

      for (j, member) in group.members.iter().enumerate() {
        sqlx::query(
          "INSERT INTO lore_group_members (group_row_id, position, \
           name, role, count_min, count_max) \
           VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(&row_id)
        .bind(j as i64)
        .bind(&member.name)
        .bind(&member.role)
        .bind(member.count_min)
        .bind(member.count_max)
        .execute(&mut *conn)
        .await?;
      }
    }
    Ok(())
  }

  async fn fetch(
    db: &Db,
    user_id: &UserId,
  ) -> Result<Option<Self::Data>, sqlx::Error> {
    if sqlx::query("SELECT user_id FROM lore_group_sets WHERE user_id = $1")
      .bind(user_id.as_str())
      .fetch_optional(db.pool())
      .await?
      .is_none()
    {
      return Ok(None);
    }

    let mut groups: Vec<(String, Group)> = sqlx::query(
      "SELECT id, group_id, name, weight, source, description \
       FROM lore_groups WHERE user_id = $1 ORDER BY position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    .iter()
    .map(|row| {
      Ok::<_, sqlx::Error>((
        row.try_get::<String, _>("id")?,
        Group {
          group_id: row.try_get("group_id")?,
          name: row.try_get("name")?,
          weight: row.try_get("weight")?,
          source: row.try_get("source")?,
          members: Vec::new(),
          description: row.try_get("description")?,
        },
      ))
    })
    .collect::<Result<_, _>>()?;

    for row in sqlx::query(
      "SELECT m.group_row_id, m.name, m.role, m.count_min, m.count_max \
       FROM lore_group_members m \
       JOIN lore_groups g ON g.id = m.group_row_id \
       WHERE g.user_id = $1 ORDER BY m.position",
    )
    .bind(user_id.as_str())
    .fetch_all(db.pool())
    .await?
    {
      let owner: String = row.try_get("group_row_id")?;
      if let Some((_, group)) = groups.iter_mut().find(|(id, _)| *id == owner) {
        group.members.push(Slot {
          name: row.try_get("name")?,
          role: row.try_get("role")?,
          count_min: row.try_get("count_min")?,
          count_max: row.try_get("count_max")?,
        });
      }
    }

    Ok(Some(groups.into_iter().map(|(_, g)| g).collect()))
  }
}

fn decode_group(raw: &Value, index: usize) -> Result<Group, String> {
  let context = format!("lore group {index}");
  let map = as_object(raw, &context)?;
  Ok(Group {
    group_id: req_str(map, "id", &context)?,
    name: req_str(map, "name", &context)?,
    weight: opt_i64_or(map, "weight", 3),
    source: normalized_source(&opt_str_or(map, "source", "user")),
    members: map
      .get("members")
      .map(|raw_members| decode_members(raw_members, &context))
      .transpose()?
      .unwrap_or_default(),
    description: opt_str_or(map, "description", ""),
  })
}

fn decode_members(raw: &Value, context: &str) -> Result<Vec<Slot>, String> {
  raw
    .as_array()
    .ok_or_else(|| format!("{context}: \"members\" is not an array"))?
    .iter()
    .enumerate()
    .map(|(j, raw_slot)| {
      let slot_context = format!("{context}, member {j}");
      let map = as_object(raw_slot, &slot_context)?;
      Ok(Slot {
        name: req_str(map, "name", &slot_context)?,
        role: normalized_role(&opt_str_or(map, "role", "member")),
        count_min: opt_i64_or(map, "count_min", 1),
        count_max: opt_i64_or(map, "count_max", 1),
      })
    })
    .collect()
}

/// Mirror of the Elm `decodeRole`: unknown strings fall back to
/// `member`.
fn normalized_role(raw: &str) -> String {
  match raw {
    "leader" | "minion" | "pet" => raw.to_string(),
    _ => "member".to_string(),
  }
}

/// Mirror of the Elm `decodeSource`: anything but `bundled` is
/// user-curated.
fn normalized_source(raw: &str) -> String {
  match raw {
    "bundled" => raw.to_string(),
    _ => "user".to_string(),
  }
}

fn encode_group(group: &Group) -> Value {
  json!({
    "id": group.group_id,
    "name": group.name,
    "weight": group.weight,
    "source": group.source,
    "members": group.members.iter().map(encode_slot).collect::<Vec<_>>(),
    "description": group.description,
  })
}

fn encode_slot(slot: &Slot) -> Value {
  json!({
    "name": slot.name,
    "role": slot.role,
    "count_min": slot.count_min,
    "count_max": slot.count_max,
  })
}
