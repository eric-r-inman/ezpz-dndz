//! Dice-roll history persistence.
//!
//! The Elm dice roller is a pure rules engine that produces a `Roll`
//! JSON blob per click.  The frontend can't reach `localStorage`
//! without hand-written JS glue, which the project explicitly avoids,
//! so persistence rides through this crate instead: a relational
//! store over the shared [`Db`] handle with three HTTP endpoints.
//!
//! Endpoints:
//!
//! - `GET    /api/dice/history`  — return the stored roll log
//!   (newest first; bounded by `MAX_ENTRIES`).
//! - `POST   /api/dice/history`  — append one roll, truncate to
//!   `MAX_ENTRIES`, and return the updated log.
//! - `DELETE /api/dice/history`  — clear the log.
//!
//! The wire schema is owned by the Elm frontend
//! (`frontend/src/Dice.elm`, `encodeRoll` / `decodeRoll`); the serde
//! types below mirror it field for field, including its leniency:
//! `timestamp` and `source` may be absent, and unknown top-level
//! scalar fields round-trip untouched (they land in
//! `dice_roll_extras`).  Everything else is normalized into real
//! tables — no JSON columns anywhere — so future backends and
//! reporting queries can see inside the rolls.
//!
//! Concurrency: `Db` caps SQLite at one pooled connection, so
//! concurrent POSTs queue on the pool instead of racing; the
//! read-modify-write (max position, insert, cap eviction) runs in a
//! transaction either way.

use aide::{
  axum::{
    routing::delete_with, routing::get_with, routing::post_with, ApiRouter,
  },
  transform::TransformOperation,
};
use axum::{
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
  Extension, Json,
};
use ezpz_dndz_lib::{db::Db, users::UserId};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{AnyConnection, Row};
use std::collections::HashMap;
use thiserror::Error;
use tracing::warn;
use uuid::Uuid;

use crate::users::CurrentUser;
use crate::web_base::AppState;

/// Hard cap on persisted rolls.  Matches the in-memory cap on the
/// frontend (`Dice.maxHistoryEntries`) so the two stay in lockstep.
pub const MAX_ENTRIES: usize = 30;

/// Semantic errors from dice-history persistence.
#[derive(Debug, Error)]
pub enum DiceHistoryError {
  #[error("Failed to query the dice-roll history: {0}")]
  HistoryQuery(#[source] sqlx::Error),

  #[error("Failed to persist the dice roll: {0}")]
  RollPersist(#[source] sqlx::Error),

  #[error("Failed to open a dice-history transaction: {0}")]
  TransactionBegin(#[source] sqlx::Error),

  #[error("Failed to commit the dice-history transaction: {0}")]
  TransactionCommit(#[source] sqlx::Error),

  #[error(
    "Unsupported roll field {key:?}: only scalar JSON values can \
     round-trip outside the known roll schema"
  )]
  ExtraFieldUnsupported { key: String },

  #[error("Roll payload does not match the dice-roll schema: {0}")]
  RollDecode(#[source] serde_json::Error),
}

impl IntoResponse for DiceHistoryError {
  fn into_response(self) -> Response {
    warn!(error = %self, "dice history operation failed");
    let status = match &self {
      Self::ExtraFieldUnsupported { .. } | Self::RollDecode(_) => {
        StatusCode::BAD_REQUEST
      }
      _ => StatusCode::INTERNAL_SERVER_ERROR,
    };
    (status, Json(serde_json::json!({ "error": self.to_string() })))
      .into_response()
  }
}

// ── wire types ───────────────────────────────────────────────────────────────
//
// Field order matches the Elm encoder so re-serialized entries read
// the same as what the frontend produced.  `timestamp` and `source`
// are optional-and-omitted (not null) when absent, mirroring the Elm
// decoder's tolerance; `damageType` and `target` are always emitted,
// null when unset, because the Elm decoder requires those fields.

/// One persisted roll, as encoded by `Dice.encodeRoll`.  Unknown
/// top-level fields are captured in `extras` and re-emitted verbatim
/// so the historical "opaque JSON" contract of this endpoint holds.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollEntry {
  pub kind: String,
  pub formula: String,
  pub total: i64,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  pub timestamp: Option<i64>,
  pub expression: RollExpression,
  pub groups: Vec<RollGroup>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  pub source: Option<RollSource>,
  #[serde(flatten)]
  pub extras: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollExpression {
  pub dice: Vec<RollDice>,
  pub constant: i64,
  #[serde(rename = "damageType")]
  pub damage_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollDice {
  pub count: i64,
  pub faces: i64,
  pub sign: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollGroup {
  pub dice: RollDice,
  pub rolled: Vec<RolledDie>,
  pub subtotal: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RolledDie {
  pub face: i64,
  pub kept: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RollSource {
  pub feature: String,
  pub target: Option<String>,
}

// ── store ────────────────────────────────────────────────────────────────────

/// SQL-backed dice history store, scoped per user.  Each user has
/// their own log, independently capped at `MAX_ENTRIES`.
#[derive(Clone)]
pub struct DiceStore {
  db: Db,
}

impl DiceStore {
  /// Wrap the shared database handle.  The schema is guaranteed by
  /// `Db::connect`, so construction itself cannot fail.
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  /// Read the given user's history, newest first.  Returns an empty
  /// `Vec` for users who haven't rolled anything yet.
  pub async fn load(
    &self,
    user_id: &UserId,
  ) -> Result<Vec<RollEntry>, DiceHistoryError> {
    let rolls = sqlx::query(
      "SELECT id, kind, formula, total, timestamp_ms, \
       expression_constant, expression_damage_type, source_feature, \
       source_target \
       FROM dice_rolls WHERE user_id = $1 ORDER BY position DESC",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(DiceHistoryError::HistoryQuery)?;

    let mut expression_dice: HashMap<String, Vec<RollDice>> = HashMap::new();
    for row in sqlx::query(
      "SELECT d.roll_id, d.die_count, d.die_faces, d.die_sign \
       FROM dice_roll_expression_dice d \
       JOIN dice_rolls r ON r.id = d.roll_id \
       WHERE r.user_id = $1 ORDER BY d.position",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(DiceHistoryError::HistoryQuery)?
    {
      expression_dice
        .entry(
          row
            .try_get("roll_id")
            .map_err(DiceHistoryError::HistoryQuery)?,
        )
        .or_default()
        .push(dice_from_row(&row).map_err(DiceHistoryError::HistoryQuery)?);
    }

    let mut faces: HashMap<String, Vec<RolledDie>> = HashMap::new();
    for row in sqlx::query(
      "SELECT f.group_id, f.face, f.kept \
       FROM dice_roll_faces f \
       JOIN dice_roll_groups g ON g.id = f.group_id \
       JOIN dice_rolls r ON r.id = g.roll_id \
       WHERE r.user_id = $1 ORDER BY f.position",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(DiceHistoryError::HistoryQuery)?
    {
      faces
        .entry(
          row
            .try_get("group_id")
            .map_err(DiceHistoryError::HistoryQuery)?,
        )
        .or_default()
        .push(RolledDie {
          face: row
            .try_get("face")
            .map_err(DiceHistoryError::HistoryQuery)?,
          kept: row
            .try_get::<i64, _>("kept")
            .map_err(DiceHistoryError::HistoryQuery)?
            != 0,
        });
    }

    let mut groups: HashMap<String, Vec<RollGroup>> = HashMap::new();
    for row in sqlx::query(
      "SELECT g.id, g.roll_id, g.die_count, g.die_faces, g.die_sign, \
       g.subtotal \
       FROM dice_roll_groups g \
       JOIN dice_rolls r ON r.id = g.roll_id \
       WHERE r.user_id = $1 ORDER BY g.position",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(DiceHistoryError::HistoryQuery)?
    {
      let group_id: String =
        row.try_get("id").map_err(DiceHistoryError::HistoryQuery)?;
      groups
        .entry(
          row
            .try_get("roll_id")
            .map_err(DiceHistoryError::HistoryQuery)?,
        )
        .or_default()
        .push(RollGroup {
          dice: dice_from_row(&row).map_err(DiceHistoryError::HistoryQuery)?,
          rolled: faces.remove(&group_id).unwrap_or_default(),
          subtotal: row
            .try_get("subtotal")
            .map_err(DiceHistoryError::HistoryQuery)?,
        });
    }

    let mut extras: HashMap<String, serde_json::Map<String, Value>> =
      HashMap::new();
    for row in sqlx::query(
      "SELECT e.roll_id, e.key, e.value_kind, e.bool_value, \
       e.int_value, e.real_value, e.text_value \
       FROM dice_roll_extras e \
       JOIN dice_rolls r ON r.id = e.roll_id \
       WHERE r.user_id = $1 ORDER BY e.key",
    )
    .bind(user_id.as_str())
    .fetch_all(self.db.pool())
    .await
    .map_err(DiceHistoryError::HistoryQuery)?
    {
      let (key, value) =
        extra_from_row(&row).map_err(DiceHistoryError::HistoryQuery)?;
      extras
        .entry(
          row
            .try_get("roll_id")
            .map_err(DiceHistoryError::HistoryQuery)?,
        )
        .or_default()
        .insert(key, value);
    }

    rolls
      .iter()
      .map(|row| {
        let roll_id: String =
          row.try_get("id").map_err(DiceHistoryError::HistoryQuery)?;
        Ok(RollEntry {
          kind: row
            .try_get("kind")
            .map_err(DiceHistoryError::HistoryQuery)?,
          formula: row
            .try_get("formula")
            .map_err(DiceHistoryError::HistoryQuery)?,
          total: row
            .try_get("total")
            .map_err(DiceHistoryError::HistoryQuery)?,
          timestamp: row
            .try_get("timestamp_ms")
            .map_err(DiceHistoryError::HistoryQuery)?,
          expression: RollExpression {
            dice: expression_dice.remove(&roll_id).unwrap_or_default(),
            constant: row
              .try_get("expression_constant")
              .map_err(DiceHistoryError::HistoryQuery)?,
            damage_type: row
              .try_get("expression_damage_type")
              .map_err(DiceHistoryError::HistoryQuery)?,
          },
          groups: groups.remove(&roll_id).unwrap_or_default(),
          source: row
            .try_get::<Option<String>, _>("source_feature")
            .map_err(DiceHistoryError::HistoryQuery)?
            .map(|feature| {
              Ok::<_, DiceHistoryError>(RollSource {
                feature,
                target: row
                  .try_get("source_target")
                  .map_err(DiceHistoryError::HistoryQuery)?,
              })
            })
            .transpose()?,
          extras: extras.remove(&roll_id).unwrap_or_default(),
        })
      })
      .collect()
  }

  /// Prepend `roll` to the user's history, evict entries beyond
  /// `MAX_ENTRIES`, and return the user's updated history.
  pub async fn append(
    &self,
    user_id: &UserId,
    roll: RollEntry,
  ) -> Result<Vec<RollEntry>, DiceHistoryError> {
    let mut tx = self
      .db
      .pool()
      .begin()
      .await
      .map_err(DiceHistoryError::TransactionBegin)?;

    let position: i64 = sqlx::query_scalar(
      "SELECT COALESCE(MAX(position), 0) + 1 FROM dice_rolls \
       WHERE user_id = $1",
    )
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(DiceHistoryError::HistoryQuery)?;

    insert_roll(&mut tx, user_id, position, &roll).await?;

    // Cap eviction: keep the MAX_ENTRIES newest rolls; child rows
    // follow via ON DELETE CASCADE.
    sqlx::query(
      "DELETE FROM dice_rolls WHERE user_id = $1 AND id NOT IN \
       (SELECT id FROM dice_rolls WHERE user_id = $1 \
        ORDER BY position DESC LIMIT $2)",
    )
    .bind(user_id.as_str())
    .bind(MAX_ENTRIES as i64)
    .execute(&mut *tx)
    .await
    .map_err(DiceHistoryError::RollPersist)?;

    tx.commit()
      .await
      .map_err(DiceHistoryError::TransactionCommit)?;

    self.load(user_id).await
  }

  /// Clear the user's history.
  pub async fn clear(&self, user_id: &UserId) -> Result<(), DiceHistoryError> {
    sqlx::query("DELETE FROM dice_rolls WHERE user_id = $1")
      .bind(user_id.as_str())
      .execute(self.db.pool())
      .await
      .map_err(DiceHistoryError::RollPersist)?;
    Ok(())
  }
}

/// Insert one roll and its child rows at `position`.  Takes a bare
/// connection so callers control the transaction — `append` wraps it
/// with cap eviction, and the one-shot JSON import replays a whole
/// legacy history inside a single transaction.
pub(crate) async fn insert_roll(
  conn: &mut AnyConnection,
  user_id: &UserId,
  position: i64,
  roll: &RollEntry,
) -> Result<(), DiceHistoryError> {
  let roll_id = Uuid::new_v4().to_string();

  sqlx::query(
    "INSERT INTO dice_rolls (id, user_id, position, kind, formula, \
     total, timestamp_ms, expression_constant, \
     expression_damage_type, source_feature, source_target) \
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
  )
  .bind(&roll_id)
  .bind(user_id.as_str())
  .bind(position)
  .bind(&roll.kind)
  .bind(&roll.formula)
  .bind(roll.total)
  .bind(roll.timestamp)
  .bind(roll.expression.constant)
  .bind(&roll.expression.damage_type)
  .bind(roll.source.as_ref().map(|s| s.feature.clone()))
  .bind(roll.source.as_ref().and_then(|s| s.target.clone()))
  .execute(&mut *conn)
  .await
  .map_err(DiceHistoryError::RollPersist)?;

  for (i, die) in roll.expression.dice.iter().enumerate() {
    sqlx::query(
      "INSERT INTO dice_roll_expression_dice (roll_id, position, \
       die_count, die_faces, die_sign) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&roll_id)
    .bind(i as i64)
    .bind(die.count)
    .bind(die.faces)
    .bind(&die.sign)
    .execute(&mut *conn)
    .await
    .map_err(DiceHistoryError::RollPersist)?;
  }

  for (i, group) in roll.groups.iter().enumerate() {
    let group_id = Uuid::new_v4().to_string();
    sqlx::query(
      "INSERT INTO dice_roll_groups (id, roll_id, position, \
       die_count, die_faces, die_sign, subtotal) \
       VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(&group_id)
    .bind(&roll_id)
    .bind(i as i64)
    .bind(group.dice.count)
    .bind(group.dice.faces)
    .bind(&group.dice.sign)
    .bind(group.subtotal)
    .execute(&mut *conn)
    .await
    .map_err(DiceHistoryError::RollPersist)?;

    for (j, die) in group.rolled.iter().enumerate() {
      sqlx::query(
        "INSERT INTO dice_roll_faces (group_id, position, face, kept) \
         VALUES ($1, $2, $3, $4)",
      )
      .bind(&group_id)
      .bind(j as i64)
      .bind(die.face)
      .bind(i64::from(die.kept))
      .execute(&mut *conn)
      .await
      .map_err(DiceHistoryError::RollPersist)?;
    }
  }

  for (key, value) in &roll.extras {
    let columns = ExtraColumns::from_value(key, value)?;
    sqlx::query(
      "INSERT INTO dice_roll_extras (roll_id, key, value_kind, \
       bool_value, int_value, real_value, text_value) \
       VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(&roll_id)
    .bind(key)
    .bind(columns.kind)
    .bind(columns.bool_value)
    .bind(columns.int_value)
    .bind(columns.real_value)
    .bind(columns.text_value)
    .execute(&mut *conn)
    .await
    .map_err(DiceHistoryError::RollPersist)?;
  }

  Ok(())
}

/// Column projection of one unknown scalar field.  Exactly one value
/// column is non-NULL, selected by `kind`.
struct ExtraColumns {
  kind: &'static str,
  bool_value: Option<i64>,
  int_value: Option<i64>,
  real_value: Option<f64>,
  text_value: Option<String>,
}

impl ExtraColumns {
  fn empty() -> Self {
    Self {
      kind: "null",
      bool_value: None,
      int_value: None,
      real_value: None,
      text_value: None,
    }
  }

  fn from_value(key: &str, value: &Value) -> Result<Self, DiceHistoryError> {
    match value {
      Value::Null => Ok(Self::empty()),
      Value::Bool(b) => Ok(Self {
        kind: "bool",
        bool_value: Some(i64::from(*b)),
        ..Self::empty()
      }),
      Value::Number(n) => n
        .as_i64()
        .map(|i| Self {
          kind: "int",
          int_value: Some(i),
          ..Self::empty()
        })
        .or_else(|| {
          n.as_f64().map(|f| Self {
            kind: "float",
            real_value: Some(f),
            ..Self::empty()
          })
        })
        .ok_or_else(|| DiceHistoryError::ExtraFieldUnsupported {
          key: key.to_string(),
        }),
      Value::String(s) => Ok(Self {
        kind: "string",
        text_value: Some(s.clone()),
        ..Self::empty()
      }),
      // Nested objects and arrays outside the known roll schema
      // cannot be normalized without a document column, which the
      // storage design forbids.  The Elm encoder never produces
      // them, so rejecting is safe.
      Value::Array(_) | Value::Object(_) => {
        Err(DiceHistoryError::ExtraFieldUnsupported {
          key: key.to_string(),
        })
      }
    }
  }
}

fn dice_from_row(row: &sqlx::any::AnyRow) -> Result<RollDice, sqlx::Error> {
  Ok(RollDice {
    count: row.try_get("die_count")?,
    faces: row.try_get("die_faces")?,
    sign: row.try_get("die_sign")?,
  })
}

fn extra_from_row(
  row: &sqlx::any::AnyRow,
) -> Result<(String, Value), sqlx::Error> {
  let key: String = row.try_get("key")?;
  let kind: String = row.try_get("value_kind")?;
  let value = match kind.as_str() {
    "bool" => Value::Bool(row.try_get::<i64, _>("bool_value")? != 0),
    "int" => Value::from(row.try_get::<i64, _>("int_value")?),
    "float" => Value::from(row.try_get::<f64, _>("real_value")?),
    "string" => Value::String(row.try_get("text_value")?),
    // "null" and anything unrecognized decode to JSON null; the
    // insert path only ever writes the five known kinds.
    _ => Value::Null,
  };
  Ok((key, value))
}

// ── HTTP handlers ────────────────────────────────────────────────────────────
//
// Handlers return `Response` directly (rather than `Result<T, E>`) because
// aide's `OperationHandler` trait requires `OperationOutput` on the return
// type, and we don't want to commit to an aide-specific trait impl on our
// own error enum.  The error → response mapping rides on
// `impl IntoResponse for DiceHistoryError` so the handler bodies stay
// tight: success path picks one branch, error path picks the other.

async fn get_history(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  match state.dice_store.load(&user.id).await {
    Ok(entries) => Json(entries).into_response(),
    Err(err) => err.into_response(),
  }
}

async fn post_roll(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
  Json(roll): Json<Value>,
) -> Response {
  // Decode by hand rather than extracting `Json<RollEntry>`: aide's
  // OperationHandler would demand a JsonSchema for the flattened
  // extras map, and the manual step lets schema mismatches surface
  // as our own 400 body instead of an axum rejection.
  match serde_json::from_value::<RollEntry>(roll)
    .map_err(DiceHistoryError::RollDecode)
  {
    Ok(entry) => match state.dice_store.append(&user.id, entry).await {
      Ok(entries) => Json(entries).into_response(),
      Err(err) => err.into_response(),
    },
    Err(err) => err.into_response(),
  }
}

async fn delete_history(
  State(state): State<AppState>,
  Extension(CurrentUser(user)): Extension<CurrentUser>,
) -> Response {
  match state.dice_store.clear(&user.id).await {
    Ok(()) => StatusCode::NO_CONTENT.into_response(),
    Err(err) => err.into_response(),
  }
}

/// Build the `/api/dice/*` subrouter, ready to be merged into the
/// base `ApiRouter`.  Returning `ApiRouter<AppState>` (rather than a
/// plain `axum::Router`) lets the three endpoints participate in the
/// OpenAPI schema served at `/api-docs/openapi.json` and browsable
/// at `/scalar`.
pub fn router() -> ApiRouter<AppState> {
  ApiRouter::new()
    .api_route(
      "/api/dice/history",
      get_with(get_history, |op: TransformOperation| {
        op.description("Return the persisted dice-roll history (newest first).")
      }),
    )
    .api_route(
      "/api/dice/history",
      post_with(post_roll, |op: TransformOperation| {
        op.description(
          "Append one roll to the history, truncating older entries past MAX_ENTRIES.",
        )
      }),
    )
    .api_route(
      "/api/dice/history",
      delete_with(delete_history, |op: TransformOperation| {
        op.description("Clear the persisted dice-roll history.")
      }),
    )
}
