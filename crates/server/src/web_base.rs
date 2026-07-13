//! Application state shared by the HTTP handlers.
//!
//! `BaseServerState` (registry, request counter, OIDC client) lives in
//! foundation and is spliced in via `impl_server_state!`.  The custom
//! fields below carry the relational stores that ezpz-dndz actually
//! serves, plus the legacy shared compendium that only feeds the
//! one-shot split migration.

use ezpz_dndz_lib::db::Db;
use ezpz_dndz_lib::users::UserStore;
use rust_template_foundation::{
  impl_server_state, server::runner::BaseServerState,
};
use std::sync::Arc;
use thiserror::Error;

use crate::auth_rate_limit::AuthRateLimiter;
use crate::compendium::{
  migrate as compendium_migrate, BundledCompendium, CompendiumGroupStore,
  CompendiumStore, MigrationError, SavedCompendiumStore, UserCompendiumStore,
};
use crate::config::RuntimePaths;
use crate::dice::DiceStore;
use crate::encounters::{EncounterStore, SavedEncounterStore};
use crate::json_import;

#[derive(Clone)]
pub struct AppState {
  pub base: BaseServerState,
  // The shared database handle.  The five per-user preset stores
  // (lore groups, condition presets, Save Chain presets, treasure
  // table, treasure profiles) issue their SQL through this via the
  // codecs in `crate::presets`; `per_user_store::routers` is their
  // single registration point.
  pub db: Db,
  pub dice_store: DiceStore,
  // The legacy shared compendium.  Post-split it is only input to
  // the one-shot split migration below; no route reads it.
  pub compendium_store: CompendiumStore,
  pub compendium_saves: SavedCompendiumStore,
  pub compendium_groups: CompendiumGroupStore,
  pub user_compendium: UserCompendiumStore,
  pub bundled_compendium: BundledCompendium,
  pub encounter_store: EncounterStore,
  pub encounter_saves: SavedEncounterStore,
  pub user_store: Arc<UserStore>,
  pub auth_rate_limiter: AuthRateLimiter,
}

impl_server_state!(AppState, base);

#[derive(Debug, Error)]
pub enum AppStateError {
  #[error("Failed to load compendium store: {0}")]
  CompendiumStoreLoad(#[source] crate::compendium::CompendiumStoreError),

  #[error("Legacy JSON import failed: {0}")]
  JsonImport(#[source] json_import::JsonImportError),

  #[error("Compendium split migration failed: {0}")]
  CompendiumSplitMigration(#[source] MigrationError),
}

impl AppState {
  /// Build the app-specific portion of state from the database
  /// handle plus `RuntimePaths`, then wrap it around the
  /// foundation-built `BaseServerState`.  `db` arrives already
  /// migrated (see `Db::connect`); the legacy JSON files referenced
  /// by `paths` are only consulted by the one-shot import and the
  /// compendium split migration below — no live store reads them.
  ///
  /// `compendium_claim_user` is the email address passed via
  /// `--compendium-claim-user` (or the equivalent config-file
  /// key).  Consumed by the one-shot per-user compendium split
  /// migration on the first boot of the post-split binary against
  /// a data dir that contains non-bundled creatures in the legacy
  /// shared store; ignored on every other boot.
  pub async fn assemble(
    base: BaseServerState,
    db: Db,
    paths: &RuntimePaths,
    compendium_claim_user: Option<&str>,
  ) -> Result<Self, AppStateError> {
    let dice_store = DiceStore::new(db.clone());
    let user_store = UserStore::new(db.clone());

    // Replay users.json + dice-history.json into the fresh database
    // exactly once.  Must run before the compendium split migration
    // below, whose claim-user lookup expects the imported accounts.
    json_import::run(&db, paths)
      .await
      .map_err(AppStateError::JsonImport)?;

    let compendium_store =
      CompendiumStore::load_or_bootstrap(paths.compendium.clone())
        .await
        .map_err(AppStateError::CompendiumStoreLoad)?;

    // The three per-user compendium stores are relational (migration
    // 0003); their legacy JSON files are only read by the one-shot
    // import above.
    let compendium_saves = SavedCompendiumStore::new(db.clone());
    let compendium_groups = CompendiumGroupStore::new(db.clone());
    let user_compendium = UserCompendiumStore::new(db.clone());

    let bundled_compendium =
      BundledCompendium::load().map_err(AppStateError::CompendiumStoreLoad)?;

    // The encounter stores are relational (migration 0004); their
    // legacy JSON files are only read by the one-shot import above.
    let encounter_store = EncounterStore::new(db.clone());
    let encounter_saves = SavedEncounterStore::new(db.clone());

    let compendium_dir = paths.compendium.parent().map_or_else(
      || std::path::PathBuf::from("."),
      std::path::Path::to_path_buf,
    );
    compendium_migrate::run(
      &compendium_dir,
      &compendium_store,
      &bundled_compendium,
      &user_compendium,
      &user_store,
      compendium_claim_user,
    )
    .await
    .map_err(AppStateError::CompendiumSplitMigration)?;

    Ok(Self {
      base,
      db,
      dice_store,
      compendium_store,
      compendium_saves,
      compendium_groups,
      user_compendium,
      bundled_compendium,
      encounter_store,
      encounter_saves,
      user_store: Arc::new(user_store),
      auth_rate_limiter: AuthRateLimiter::new(),
    })
  }
}
