//! One-shot boot import of the legacy JSON stores into the database.
//!
//! Before the relational migration, users lived in `users.json` (a
//! flat `Vec<User>`) and dice history in `dice-history.json` (a
//! `HashMap<UserId, Vec<Value>>`, newest roll first).  On the first
//! boot against a fresh database this module replays both files into
//! the `users` and `dice_rolls` tables inside a single transaction,
//! then records a marker in `schema_meta` so the import never runs
//! twice.  The JSON files are left untouched on disk as the rollback
//! copy.
//!
//! Phase 2 adds the five per-user preset stores (lore groups,
//! condition presets, Save Chain presets, treasure table, treasure
//! profiles), each a `HashMap<UserId, Value>` on disk.  They import
//! under their own marker with one transaction per store, decoding
//! every payload through the lenient wire codecs in
//! [`crate::presets`]; a user entry that fails to decode is logged
//! and skipped rather than aborting the import, since preserving the
//! rest of the data matters more.
//!
//! Phase 3 adds the per-user compendium stores: `user-creatures.json`
//! (`HashMap<UserId, Vec<Creature>>`), `compendium-groups.json`
//! (`HashMap<UserId, Vec<Group>>`), and `compendium-saves.json`
//! (`HashMap<UserId, Vec<SavedCompendium>>`).  They import under one
//! marker with one transaction per store, decoding each user's entry
//! through the shared serde types (which ARE the wire spec); an
//! entry that fails to decode is logged and skipped.  The legacy
//! SHARED compendium (`compendium/creatures.json`) is deliberately
//! NOT imported here — the one-shot split migration in
//! `crate::compendium::migrate` owns that file and keeps reading it
//! from disk (it runs after this import, so the accounts and any
//! imported per-user creatures are already in place).
//!
//! Defensive rules: nothing happens when the marker is present or
//! when none of the relevant legacy files exist, and a database that
//! already contains users is never imported into by the users + dice
//! pass (the marker is written with an explanatory value instead, so
//! the skip is deliberate and permanent rather than re-warned on
//! every boot).  The preset and compendium passes skip individual
//! users who already have rows, for the same reason.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use ezpz_dndz_lib::compendium::{Creature, Group};
use ezpz_dndz_lib::db::{Db, DbError};
use ezpz_dndz_lib::users::{insert_user, User, UserId};
use serde::de::DeserializeOwned;
use serde_json::Value;
use sqlx::AnyConnection;
use thiserror::Error;
use tracing::{info, warn};

use crate::compendium::{
  creature_rows, groups as compendium_groups, saves as compendium_saves,
  CompendiumStoreError, SavedCompendium,
};
use crate::config::RuntimePaths;
use crate::dice::{insert_roll, DiceHistoryError, RollEntry};
use crate::per_user_store::PerUserFeature;
use crate::presets::{
  condition_presets::ConditionPresets, lore_groups::LoreGroups,
  save_chains::SaveChains, treasure_profiles::TreasureProfiles,
  treasure_table::TreasureTable,
};

/// `schema_meta` key marking that the users + dice import has run
/// (or was deliberately skipped).
pub const IMPORT_MARKER_KEY: &str = "json_import_users_dice";

/// `schema_meta` key marking that the per-user preset import has run.
pub const PRESETS_IMPORT_MARKER_KEY: &str = "json_import_presets";

/// `schema_meta` key marking that the per-user compendium import
/// (creatures, groups, saves) has run.
pub const COMPENDIUM_IMPORT_MARKER_KEY: &str = "json_import_compendium";

#[derive(Debug, Error)]
pub enum JsonImportError {
  #[error("Failed to read the import marker: {0}")]
  MarkerRead(#[source] DbError),

  #[error("Failed to write the import marker: {0}")]
  MarkerWrite(#[source] sqlx::Error),

  #[error("Failed to count existing users before the import: {0}")]
  UserCount(#[source] sqlx::Error),

  #[error("Failed to read the legacy JSON file at {path}: {source}")]
  LegacyFileRead {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse the legacy JSON file at {path}: {source}")]
  LegacyFileParse {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Failed to begin the import transaction: {0}")]
  TransactionBegin(#[source] sqlx::Error),

  #[error("Failed to commit the import transaction: {0}")]
  TransactionCommit(#[source] sqlx::Error),

  #[error("Failed to import legacy user {email}: {source}")]
  UserInsert { email: String, source: sqlx::Error },

  #[error("Failed to import a legacy dice roll for user {user_id}: {source}")]
  RollInsert {
    user_id: String,
    source: DiceHistoryError,
  },

  #[error("Failed to list users before the preset import: {0}")]
  UserList(#[source] sqlx::Error),

  #[error(
    "Failed to import the legacy {store} payload for user {user_id}: \
     {source}"
  )]
  PresetInsert {
    store: &'static str,
    user_id: String,
    source: sqlx::Error,
  },

  #[error(
    "Failed to check for existing {store} rows before the import: {source}"
  )]
  PresetExistingCheck {
    store: &'static str,
    source: sqlx::Error,
  },

  #[error(
    "Failed to import the legacy {store} entry for user {user_id}: {source}"
  )]
  CompendiumInsert {
    store: &'static str,
    user_id: String,
    source: CompendiumStoreError,
  },
}

/// Run the one-shot imports.  Called from `AppState::assemble` after
/// migrations (via `Db::connect`) and before anything that needs the
/// imported users, such as the compendium split migration's claim-
/// user lookup.  The preset pass runs second because its foreign
/// keys need the imported accounts.
pub async fn run(db: &Db, paths: &RuntimePaths) -> Result<(), JsonImportError> {
  run_users_dice(db, paths).await?;
  run_presets(db, paths).await?;
  run_compendium(db, paths).await
}

/// The phase-1 users + dice-history import.
async fn run_users_dice(
  db: &Db,
  paths: &RuntimePaths,
) -> Result<(), JsonImportError> {
  if db
    .schema_meta(IMPORT_MARKER_KEY)
    .await
    .map_err(JsonImportError::MarkerRead)?
    .is_some()
  {
    return Ok(());
  }

  if !paths.users.exists() && !paths.dice_history.exists() {
    return Ok(());
  }

  let existing_users: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
    .fetch_one(db.pool())
    .await
    .map_err(JsonImportError::UserCount)?;
  if existing_users > 0 {
    warn!(
      existing_users,
      "legacy JSON files present but the database already has users; \
       skipping the one-shot import permanently"
    );
    sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
      .bind(IMPORT_MARKER_KEY)
      .bind("skipped: database already contained users")
      .execute(db.pool())
      .await
      .map_err(JsonImportError::MarkerWrite)?;
    return Ok(());
  }

  let users: Vec<User> = read_json_or_default(&paths.users).await?;
  let dice: HashMap<UserId, Vec<Value>> =
    read_json_or_default(&paths.dice_history).await?;

  let mut tx = db
    .pool()
    .begin()
    .await
    .map_err(JsonImportError::TransactionBegin)?;

  for user in &users {
    insert_user(&mut tx, user).await.map_err(|source| {
      JsonImportError::UserInsert {
        email: user.email.clone(),
        source,
      }
    })?;
  }

  let known_ids: std::collections::HashSet<&str> =
    users.iter().map(|u| u.id.as_str()).collect();
  let mut imported_rolls = 0usize;
  let mut skipped_rolls = 0usize;
  for (user_id, entries) in &dice {
    if !known_ids.contains(user_id.as_str()) {
      warn!(
        user_id = user_id.as_str(),
        entries = entries.len(),
        "legacy dice history references a user missing from \
         users.json; skipping those rolls"
      );
      skipped_rolls += entries.len();
      continue;
    }
    // The legacy file stores each user's log newest-first; positions
    // count down so the newest entry keeps the highest position.
    let total = entries.len() as i64;
    for (i, raw) in entries.iter().enumerate() {
      match serde_json::from_value::<RollEntry>(raw.clone()) {
        Ok(entry) => {
          insert_roll(&mut tx, user_id, total - i as i64, &entry)
            .await
            .map_err(|source| JsonImportError::RollInsert {
              user_id: user_id.as_str().to_string(),
              source,
            })?;
          imported_rolls += 1;
        }
        Err(error) => {
          warn!(
            user_id = user_id.as_str(),
            %error,
            "legacy dice entry does not match the roll schema; skipping"
          );
          skipped_rolls += 1;
        }
      }
    }
  }

  sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
    .bind(IMPORT_MARKER_KEY)
    .bind("done")
    .execute(&mut *tx)
    .await
    .map_err(JsonImportError::MarkerWrite)?;

  tx.commit()
    .await
    .map_err(JsonImportError::TransactionCommit)?;

  info!(
    users = users.len(),
    rolls = imported_rolls,
    skipped_rolls,
    "imported legacy JSON stores into the database"
  );
  Ok(())
}

/// The phase-2 per-user preset import: replay the five legacy
/// `HashMap<UserId, Value>` files through the lenient wire codecs,
/// one transaction per store, then write the marker.
async fn run_presets(
  db: &Db,
  paths: &RuntimePaths,
) -> Result<(), JsonImportError> {
  if db
    .schema_meta(PRESETS_IMPORT_MARKER_KEY)
    .await
    .map_err(JsonImportError::MarkerRead)?
    .is_some()
  {
    return Ok(());
  }

  let legacy_files = [
    &paths.lore_groups,
    &paths.condition_presets,
    &paths.save_chain_presets,
    &paths.treasure_table,
    &paths.treasure_profiles,
  ];
  if !legacy_files.iter().any(|p| p.exists()) {
    return Ok(());
  }

  // Payload rows are foreign-keyed to users, so entries for accounts
  // the database doesn't know are unimportable and get skipped.
  let known_ids: HashSet<String> =
    sqlx::query_scalar::<_, String>("SELECT id FROM users")
      .fetch_all(db.pool())
      .await
      .map_err(JsonImportError::UserList)?
      .into_iter()
      .collect();

  let mut imported = 0usize;
  let mut skipped = 0usize;
  for (count, skips) in [
    import_preset_store::<LoreGroups>(db, &paths.lore_groups, &known_ids)
      .await?,
    import_preset_store::<ConditionPresets>(
      db,
      &paths.condition_presets,
      &known_ids,
    )
    .await?,
    import_preset_store::<SaveChains>(
      db,
      &paths.save_chain_presets,
      &known_ids,
    )
    .await?,
    import_preset_store::<TreasureTable>(db, &paths.treasure_table, &known_ids)
      .await?,
    import_preset_store::<TreasureProfiles>(
      db,
      &paths.treasure_profiles,
      &known_ids,
    )
    .await?,
  ] {
    imported += count;
    skipped += skips;
  }

  sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
    .bind(PRESETS_IMPORT_MARKER_KEY)
    .bind("done")
    .execute(db.pool())
    .await
    .map_err(JsonImportError::MarkerWrite)?;

  info!(imported, skipped, "imported the legacy per-user preset stores");
  Ok(())
}

/// Import one legacy preset file: decode each user's payload with the
/// feature's lenient codec and insert it inside a single per-store
/// transaction.  Entries that fail to decode, belong to unknown
/// users, or collide with rows the user already has are warned about
/// and skipped — data preservation of the rest matters more than
/// completeness.  Returns (imported, skipped) user counts.
async fn import_preset_store<F: PerUserFeature>(
  db: &Db,
  path: &Path,
  known_ids: &HashSet<String>,
) -> Result<(usize, usize), JsonImportError> {
  let payloads: HashMap<UserId, Value> = read_json_or_default(path).await?;
  if payloads.is_empty() {
    return Ok((0, 0));
  }

  let mut tx = db
    .pool()
    .begin()
    .await
    .map_err(JsonImportError::TransactionBegin)?;

  let mut imported = 0usize;
  let mut skipped = 0usize;
  for (user_id, payload) in &payloads {
    if !known_ids.contains(user_id.as_str()) {
      warn!(
        store = F::LABEL,
        user_id = user_id.as_str(),
        "legacy preset payload references a user missing from the \
         database; skipping"
      );
      skipped += 1;
      continue;
    }

    let existing: i64 = sqlx::query_scalar(&format!(
      "SELECT COUNT(*) FROM {} WHERE user_id = $1",
      F::PARENT_TABLE
    ))
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(|source| JsonImportError::PresetExistingCheck {
      store: F::LABEL,
      source,
    })?;
    if existing > 0 {
      warn!(
        store = F::LABEL,
        user_id = user_id.as_str(),
        "user already has persisted rows; skipping the legacy payload"
      );
      skipped += 1;
      continue;
    }

    match F::decode(payload) {
      Ok(data) => {
        F::insert(&mut tx, user_id, &data).await.map_err(|source| {
          JsonImportError::PresetInsert {
            store: F::LABEL,
            user_id: user_id.as_str().to_string(),
            source,
          }
        })?;
        imported += 1;
      }
      Err(detail) => {
        warn!(
          store = F::LABEL,
          user_id = user_id.as_str(),
          detail,
          "legacy preset payload does not match the wire schema; \
           skipping"
        );
        skipped += 1;
      }
    }
  }

  tx.commit()
    .await
    .map_err(JsonImportError::TransactionCommit)?;

  info!(
    store = F::LABEL,
    imported, skipped, "imported one legacy preset store"
  );
  Ok((imported, skipped))
}

/// The phase-3 per-user compendium import: replay the three legacy
/// `HashMap<UserId, Vec<…>>` files (user creatures, groups, saves)
/// through the shared serde types, one transaction per store, then
/// write the marker.
async fn run_compendium(
  db: &Db,
  paths: &RuntimePaths,
) -> Result<(), JsonImportError> {
  if db
    .schema_meta(COMPENDIUM_IMPORT_MARKER_KEY)
    .await
    .map_err(JsonImportError::MarkerRead)?
    .is_some()
  {
    return Ok(());
  }

  let legacy_files = [
    &paths.user_creatures,
    &paths.compendium_groups,
    &paths.compendium_saves,
  ];
  if !legacy_files.iter().any(|p| p.exists()) {
    return Ok(());
  }

  let known_ids: HashSet<String> =
    sqlx::query_scalar::<_, String>("SELECT id FROM users")
      .fetch_all(db.pool())
      .await
      .map_err(JsonImportError::UserList)?
      .into_iter()
      .collect();

  let mut imported = 0usize;
  let mut skipped = 0usize;
  for (count, skips) in [
    import_compendium_store::<Creature>(db, &paths.user_creatures, &known_ids)
      .await?,
    import_compendium_store::<Group>(db, &paths.compendium_groups, &known_ids)
      .await?,
    import_compendium_store::<SavedCompendium>(
      db,
      &paths.compendium_saves,
      &known_ids,
    )
    .await?,
  ] {
    imported += count;
    skipped += skips;
  }

  sqlx::query("INSERT INTO schema_meta (key, value) VALUES ($1, $2)")
    .bind(COMPENDIUM_IMPORT_MARKER_KEY)
    .bind("done")
    .execute(db.pool())
    .await
    .map_err(JsonImportError::MarkerWrite)?;

  info!(imported, skipped, "imported the legacy per-user compendium stores");
  Ok(())
}

/// One importable per-user compendium record kind: which legacy
/// file it comes from, which parent table detects already-persisted
/// rows, and how one record inserts at a list position.  Mirrors
/// the `PerUserFeature` shape the preset import uses.
trait CompendiumImportRecord: DeserializeOwned {
  /// Store name for logs ("user-creatures", …).
  const STORE: &'static str;

  /// Parent table consulted by the already-has-rows skip check.
  const TABLE: &'static str;

  fn insert<'a>(
    conn: &'a mut AnyConnection,
    user_id: &'a UserId,
    position: i64,
    record: &'a Self,
  ) -> impl std::future::Future<Output = Result<(), CompendiumStoreError>> + Send + 'a;
}

impl CompendiumImportRecord for Creature {
  const STORE: &'static str = "user-creatures";
  const TABLE: &'static str = "user_creatures";

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    position: i64,
    record: &Self,
  ) -> Result<(), CompendiumStoreError> {
    creature_rows::insert_creature(conn, user_id.as_str(), position, record)
      .await
  }
}

impl CompendiumImportRecord for Group {
  const STORE: &'static str = "compendium-groups";
  const TABLE: &'static str = "compendium_groups";

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    position: i64,
    record: &Self,
  ) -> Result<(), CompendiumStoreError> {
    compendium_groups::insert_group(conn, user_id, position, record).await
  }
}

impl CompendiumImportRecord for SavedCompendium {
  const STORE: &'static str = "compendium-saves";
  const TABLE: &'static str = "compendium_saves";

  async fn insert(
    conn: &mut AnyConnection,
    user_id: &UserId,
    position: i64,
    record: &Self,
  ) -> Result<(), CompendiumStoreError> {
    compendium_saves::insert_snapshot(conn, user_id, position, record).await
  }
}

/// Import one legacy compendium file: decode each user's entry list
/// with the shared serde types and insert it inside a single
/// per-store transaction.  Entries that fail to decode, belong to
/// unknown users, or collide with rows the user already has are
/// warned about and skipped — data preservation of the rest matters
/// more than completeness.  Returns (imported, skipped) user counts.
async fn import_compendium_store<T: CompendiumImportRecord>(
  db: &Db,
  path: &Path,
  known_ids: &HashSet<String>,
) -> Result<(usize, usize), JsonImportError> {
  let payloads: HashMap<UserId, Value> = read_json_or_default(path).await?;
  if payloads.is_empty() {
    return Ok((0, 0));
  }

  let mut tx = db
    .pool()
    .begin()
    .await
    .map_err(JsonImportError::TransactionBegin)?;

  let mut imported = 0usize;
  let mut skipped = 0usize;
  for (user_id, raw) in &payloads {
    if !known_ids.contains(user_id.as_str()) {
      warn!(
        store = T::STORE,
        user_id = user_id.as_str(),
        "legacy compendium entry references a user missing from the \
         database; skipping"
      );
      skipped += 1;
      continue;
    }

    // `T::TABLE` is a compile-time constant, so the format! is not
    // an injection surface; sqlx's Any driver has no placeholder
    // for identifiers.
    let existing: i64 = sqlx::query_scalar(&format!(
      "SELECT COUNT(*) FROM {} WHERE user_id = $1",
      T::TABLE
    ))
    .bind(user_id.as_str())
    .fetch_one(&mut *tx)
    .await
    .map_err(|source| JsonImportError::PresetExistingCheck {
      store: T::STORE,
      source,
    })?;
    if existing > 0 {
      warn!(
        store = T::STORE,
        user_id = user_id.as_str(),
        "user already has persisted rows; skipping the legacy entry"
      );
      skipped += 1;
      continue;
    }

    match serde_json::from_value::<Vec<T>>(raw.clone()) {
      Ok(records) => {
        for (i, record) in records.iter().enumerate() {
          T::insert(&mut tx, user_id, i as i64, record)
            .await
            .map_err(|source| JsonImportError::CompendiumInsert {
              store: T::STORE,
              user_id: user_id.as_str().to_string(),
              source,
            })?;
        }
        imported += 1;
      }
      Err(error) => {
        warn!(
          store = T::STORE,
          user_id = user_id.as_str(),
          %error,
          "legacy compendium entry does not match the schema; skipping"
        );
        skipped += 1;
      }
    }
  }

  tx.commit()
    .await
    .map_err(JsonImportError::TransactionCommit)?;

  info!(
    store = T::STORE,
    imported, skipped, "imported one legacy compendium store"
  );
  Ok((imported, skipped))
}

/// Read + parse a legacy JSON file, treating a missing file as the
/// type's default so "users.json exists but dice-history.json does
/// not" (and vice versa) imports cleanly.
async fn read_json_or_default<T>(path: &Path) -> Result<T, JsonImportError>
where
  T: serde::de::DeserializeOwned + Default,
{
  match tokio::fs::read(path).await {
    Ok(bytes) => serde_json::from_slice(&bytes).map_err(|source| {
      JsonImportError::LegacyFileParse {
        path: path.to_path_buf(),
        source,
      }
    }),
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
    Err(source) => Err(JsonImportError::LegacyFileRead {
      path: path.to_path_buf(),
      source,
    }),
  }
}
