//! Opaque JSON value ↔ relational node-tree codec for named
//! encounter saves (migration 0004, `encounter_save_nodes`).
//!
//! Same design as `crate::compendium::save_body` (see migration 0003
//! for the full rationale): the save body has always been an opaque
//! `serde_json::Value` on the HTTP surface — callers may PUT shapes
//! that do not decode as an `Encounter` at all (the integration
//! suite pins 200 OK for `{"creatures":[]}` without the required
//! `activeName` / `round`), and the store promises to echo them back
//! exactly.  Normalizing through the typed live-encounter tables
//! would reject such bodies and change the route contract, so the
//! body decomposes into one row per JSON node: arrays and objects
//! become parent nodes whose children order by `position`, object
//! members carry their `object_key`, and scalars populate exactly
//! one value column selected by `kind`.
//!
//! Numbers are stored as their serde_json canonical token
//! (`Number::to_string`) and re-parsed on the way out, which
//! preserves the int/float distinction (`1` vs `1.0`) and f64
//! precision exactly — serde_json's float formatting is
//! shortest-round-trip.
//!
//! Insertion walks the tree iteratively (a work queue) so deeply
//! nested bodies don't require recursive async functions;
//! reassembly groups the fetched rows by parent id and rebuilds
//! synchronously.

use std::collections::HashMap;

use serde_json::{Map, Number, Value};
use sqlx::{any::AnyRow, AnyConnection, Row};
use uuid::Uuid;

use super::error::EncounterStoreError;

fn read_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::SaveRowsRead { source }
}

fn write_error(source: sqlx::Error) -> EncounterStoreError {
  EncounterStoreError::SaveRowsWrite { source }
}

fn decode_error(detail: String) -> EncounterStoreError {
  EncounterStoreError::SaveRowDecode { detail }
}

/// Insert `value` as `save_id`'s body tree.  Takes a bare
/// connection so callers control the transaction (the save row and
/// its nodes commit together).
pub async fn insert_body(
  conn: &mut AnyConnection,
  save_id: &str,
  value: &Value,
) -> Result<(), EncounterStoreError> {
  // (parent id, position within parent, object key, node) — the
  // root is position 0 under a NULL parent.
  let mut queue: Vec<(Option<String>, i64, Option<String>, &Value)> =
    vec![(None, 0, None, value)];

  while let Some((parent_id, position, object_key, node)) = queue.pop() {
    let node_id = Uuid::new_v4().to_string();
    let (kind, bool_value, number_text, string_value) = match node {
      Value::Null => ("null", None, None, None),
      Value::Bool(b) => ("bool", Some(i64::from(*b)), None, None),
      Value::Number(n) => ("number", None, Some(n.to_string()), None),
      Value::String(s) => ("string", None, None, Some(s.clone())),
      Value::Array(_) => ("array", None, None, None),
      Value::Object(_) => ("object", None, None, None),
    };

    sqlx::query(
      "INSERT INTO encounter_save_nodes (id, save_id, parent_id, \
       position, object_key, kind, bool_value, number_text, string_value) \
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(&node_id)
    .bind(save_id)
    .bind(&parent_id)
    .bind(position)
    .bind(&object_key)
    .bind(kind)
    .bind(bool_value)
    .bind(number_text)
    .bind(string_value)
    .execute(&mut *conn)
    .await
    .map_err(write_error)?;

    match node {
      Value::Array(items) => {
        for (i, item) in items.iter().enumerate() {
          queue.push((Some(node_id.clone()), i as i64, None, item));
        }
      }
      Value::Object(map) => {
        for (i, (key, item)) in map.iter().enumerate() {
          queue.push((
            Some(node_id.clone()),
            i as i64,
            Some(key.clone()),
            item,
          ));
        }
      }
      _ => {}
    }
  }

  Ok(())
}

/// A fetched node, pre-decoded from its row.
struct Node {
  id: String,
  parent_id: Option<String>,
  object_key: Option<String>,
  kind: String,
  bool_value: Option<i64>,
  number_text: Option<String>,
  string_value: Option<String>,
}

fn node_from_row(row: &AnyRow) -> Result<Node, EncounterStoreError> {
  Ok(Node {
    id: row.try_get("id").map_err(read_error)?,
    parent_id: row.try_get("parent_id").map_err(read_error)?,
    object_key: row.try_get("object_key").map_err(read_error)?,
    kind: row.try_get("kind").map_err(read_error)?,
    bool_value: row.try_get("bool_value").map_err(read_error)?,
    number_text: row.try_get("number_text").map_err(read_error)?,
    string_value: row.try_get("string_value").map_err(read_error)?,
  })
}

/// Reassemble `save_id`'s body tree.  A save always has a root node
/// (the body itself), so a missing root is schema corruption.
pub async fn fetch_body(
  conn: &mut AnyConnection,
  save_id: &str,
) -> Result<Value, EncounterStoreError> {
  let rows = sqlx::query(
    "SELECT id, parent_id, object_key, kind, bool_value, number_text, \
     string_value FROM encounter_save_nodes WHERE save_id = $1 \
     ORDER BY position",
  )
  .bind(save_id)
  .fetch_all(&mut *conn)
  .await
  .map_err(read_error)?;

  let nodes = rows
    .iter()
    .map(node_from_row)
    .collect::<Result<Vec<_>, _>>()?;

  // Children grouped by parent, already position-ordered by the
  // query; the root is the sole NULL-parent node.
  let mut children: HashMap<&str, Vec<&Node>> = HashMap::new();
  let mut root: Option<&Node> = None;
  for node in &nodes {
    match &node.parent_id {
      Some(parent) => children.entry(parent).or_default().push(node),
      None => root = Some(node),
    }
  }

  root.map_or_else(
    || Err(decode_error(format!("save {save_id} has no root body node"))),
    |root| value_from_node(root, &children),
  )
}

fn value_from_node(
  node: &Node,
  children: &HashMap<&str, Vec<&Node>>,
) -> Result<Value, EncounterStoreError> {
  match node.kind.as_str() {
    "null" => Ok(Value::Null),
    "bool" => Ok(Value::Bool(node.bool_value.unwrap_or_default() != 0)),
    "number" => {
      let text = node.number_text.as_deref().unwrap_or_default();
      serde_json::from_str::<Number>(text)
        .map(Value::Number)
        .map_err(|_| decode_error(format!("bad stored number token {text:?}")))
    }
    "string" => {
      Ok(Value::String(node.string_value.clone().unwrap_or_default()))
    }
    "array" => children
      .get(node.id.as_str())
      .map(Vec::as_slice)
      .unwrap_or_default()
      .iter()
      .map(|child| value_from_node(child, children))
      .collect::<Result<Vec<_>, _>>()
      .map(Value::Array),
    "object" => children
      .get(node.id.as_str())
      .map(Vec::as_slice)
      .unwrap_or_default()
      .iter()
      .map(|child| {
        Ok((
          child.object_key.clone().unwrap_or_default(),
          value_from_node(child, children)?,
        ))
      })
      .collect::<Result<Map<String, Value>, EncounterStoreError>>()
      .map(Value::Object),
    other => Err(decode_error(format!("unknown node kind {other:?}"))),
  }
}
