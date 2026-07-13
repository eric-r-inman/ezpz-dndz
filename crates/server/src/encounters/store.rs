//! Live-encounter persistence, relational edition.
//!
//! Stores each user's single active combat (queue + active marker +
//! round counter + treasure state) fully typed: PUT bodies decode
//! through the lenient wire codec in [`super::wire`] (the mirror of
//! `frontend/src/Encounter/Wire.elm`) and normalize into the
//! `encounters` table family (migration 0004) via the row codec in
//! [`super::rows`].  The live encounter is the write-hot core state
//! the relational migration exists for, so it gets the typed-rows
//! treatment rather than the opaque node tree the named saves use —
//! see `encounters/mod.rs` and migration 0004 for the store-by-store
//! rationale.
//!
//! GET semantics are unchanged from the JSON era: a user who has
//! never persisted an encounter reads as `Value::Null` (no parent
//! row), which the frontend's boot path treats as "use the empty
//! default".  Everyone else reads the canonical re-encoding of the
//! persisted structure.  PUT is a transactional swap: delete the
//! parent row (children cascade), insert the decoded replacement,
//! commit.

use ezpz_dndz_lib::{db::Db, users::UserId};
use serde_json::Value;

use super::error::EncounterStoreError;
use super::{rows, wire};

#[derive(Clone)]
pub struct EncounterStore {
  db: Db,
}

impl EncounterStore {
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  /// Return the given user's encounter, or `Value::Null` when they
  /// haven't auto-saved one yet.
  pub async fn read(
    &self,
    user_id: &UserId,
  ) -> Result<Value, EncounterStoreError> {
    let mut conn = self
      .db
      .pool()
      .acquire()
      .await
      .map_err(|source| EncounterStoreError::LiveRowsRead { source })?;
    Ok(
      rows::fetch_encounter(&mut conn, user_id.as_str())
        .await?
        .map_or(Value::Null, |enc| wire::encode_encounter(&enc)),
    )
  }

  /// Replace the persisted live encounter with `next`.  The body
  /// must decode through the wire codec; a body that doesn't is
  /// rejected with a 400-mapped error before anything is written.
  pub async fn replace(
    &self,
    user_id: &UserId,
    next: &Value,
  ) -> Result<(), EncounterStoreError> {
    let encounter = wire::decode_encounter(next)
      .map_err(|detail| EncounterStoreError::LiveEncounterDecode { detail })?;

    let mut tx = self.db.pool().begin().await.map_err(|source| {
      EncounterStoreError::TransactionBegin {
        store: "live-encounter",
        source,
      }
    })?;
    sqlx::query("DELETE FROM encounters WHERE user_id = $1")
      .bind(user_id.as_str())
      .execute(&mut *tx)
      .await
      .map_err(|source| EncounterStoreError::LiveRowsWrite { source })?;
    rows::insert_encounter(&mut tx, user_id.as_str(), &encounter).await?;
    tx.commit()
      .await
      .map_err(|source| EncounterStoreError::TransactionCommit {
        store: "live-encounter",
        source,
      })
  }
}
