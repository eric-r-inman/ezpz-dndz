//! Opaque JSON value ↔ relational node-tree codec for named
//! compendium snapshots (migration 0003, `compendium_save_nodes`).
//!
//! The snapshot body has always been an opaque `serde_json::Value`
//! on the HTTP surface — callers may PUT shapes that do not decode
//! as `Creature` at all, and the store promises to echo them back
//! exactly.  Normalizing through the typed creature tables would
//! reject such bodies and change the route contract, so the body is
//! instead decomposed into one row per JSON node: arrays and objects
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
//! Reassembly groups the fetched rows by parent id and rebuilds
//! synchronously.

use std::collections::HashMap;

use serde_json::{Map, Number, Value};
use sqlx::{any::AnyRow, AnyConnection, AssertSqlSafe, Row};
use uuid::Uuid;

use super::error::CompendiumStoreError;

fn read_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::SaveRowsRead { source }
}

fn write_error(source: sqlx::Error) -> CompendiumStoreError {
  CompendiumStoreError::SaveRowsWrite { source }
}

fn decode_error(detail: String) -> CompendiumStoreError {
  CompendiumStoreError::SaveRowDecode { detail }
}

/// One node of a body tree, ready to insert.
struct NodeRow<'a> {
  id: String,
  parent_id: Option<String>,
  position: i64,
  object_key: Option<&'a str>,
  kind: &'static str,
  bool_value: Option<i64>,
  number_text: Option<String>,
  string_value: Option<&'a str>,
}

/// Nodes per INSERT.  Timed on a release build with a whole-library
/// body: one node per statement saved in about 0.58 seconds, 20 per
/// statement in about 0.33, and 500 in about 1.2.  A long statement
/// costs more to bind than it saves.
const ROWS_PER_INSERT: usize = 20;

/// Insert `value` as `save_id`'s body tree.  Takes a bare
/// connection so callers control the transaction (the snapshot row
/// and its nodes commit together).  A whole library runs to tens of
/// thousands of nodes, so they go in multi-row INSERTs.
pub async fn insert_body(
  conn: &mut AnyConnection,
  save_id: &str,
  value: &Value,
) -> Result<(), CompendiumStoreError> {
  for batch in node_rows(value).chunks(ROWS_PER_INSERT) {
    let placeholders = (0..batch.len())
      .map(|row| {
        let first = row * 9;
        format!(
          "(${}, ${}, ${}, ${}, ${}, ${}, ${}, ${}, ${})",
          first + 1,
          first + 2,
          first + 3,
          first + 4,
          first + 5,
          first + 6,
          first + 7,
          first + 8,
          first + 9,
        )
      })
      .collect::<Vec<_>>()
      .join(", ");
    batch
      .iter()
      .fold(
        // The only text spliced in is `$n` placeholders numbered from
        // row indexes.  No request data reaches the SQL.
        sqlx::query(AssertSqlSafe(format!(
          "INSERT INTO compendium_save_nodes (id, save_id, parent_id, \
           position, object_key, kind, bool_value, number_text, \
           string_value) VALUES {placeholders}"
        ))),
        |query, row| {
          query
            .bind(&row.id)
            .bind(save_id)
            .bind(&row.parent_id)
            .bind(row.position)
            .bind(row.object_key)
            .bind(row.kind)
            .bind(row.bool_value)
            .bind(&row.number_text)
            .bind(row.string_value)
        },
      )
      .execute(&mut *conn)
      .await
      .map_err(write_error)?;
  }
  Ok(())
}

/// Every node of `value` as a row.  The tree is walked with a work
/// queue, so deeply nested bodies need no recursion.
fn node_rows(value: &Value) -> Vec<NodeRow<'_>> {
  // (parent id, position within parent, object key, node) — the
  // root is position 0 under a NULL parent.
  let mut queue: Vec<(Option<String>, i64, Option<&str>, &Value)> =
    vec![(None, 0, None, value)];

  std::iter::from_fn(move || {
    queue.pop().map(|(parent_id, position, object_key, node)| {
      let id = Uuid::new_v4().to_string();
      let (kind, bool_value, number_text, string_value) = match node {
        Value::Null => ("null", None, None, None),
        Value::Bool(b) => ("bool", Some(i64::from(*b)), None, None),
        Value::Number(n) => ("number", None, Some(n.to_string()), None),
        Value::String(s) => ("string", None, None, Some(s.as_str())),
        Value::Array(_) => ("array", None, None, None),
        Value::Object(_) => ("object", None, None, None),
      };
      match node {
        Value::Array(items) => queue.extend(
          items
            .iter()
            .enumerate()
            .map(|(i, item)| (Some(id.clone()), i as i64, None, item)),
        ),
        Value::Object(map) => {
          queue.extend(map.iter().enumerate().map(|(i, (key, item))| {
            (Some(id.clone()), i as i64, Some(key.as_str()), item)
          }))
        }
        _ => {}
      }
      NodeRow {
        id,
        parent_id,
        position,
        object_key,
        kind,
        bool_value,
        number_text,
        string_value,
      }
    })
  })
  .collect()
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

fn node_from_row(row: &AnyRow) -> Result<Node, CompendiumStoreError> {
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

/// Reassemble `save_id`'s body tree.  A snapshot always has a root
/// node (the body itself), so a missing root is schema corruption.
pub async fn fetch_body(
  conn: &mut AnyConnection,
  save_id: &str,
) -> Result<Value, CompendiumStoreError> {
  let rows = sqlx::query(
    "SELECT id, parent_id, object_key, kind, bool_value, number_text, \
     string_value FROM compendium_save_nodes WHERE save_id = $1 \
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
    || Err(decode_error(format!("snapshot {save_id} has no root body node"))),
    |root| value_from_node(root, &children),
  )
}

fn value_from_node(
  node: &Node,
  children: &HashMap<&str, Vec<&Node>>,
) -> Result<Value, CompendiumStoreError> {
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
      .collect::<Result<Map<String, Value>, CompendiumStoreError>>()
      .map(Value::Object),
    other => Err(decode_error(format!("unknown node kind {other:?}"))),
  }
}
