//! Application state shared by the HTTP handlers.
//!
//! `BaseServerState` (registry, request counter, OIDC client) lives in
//! foundation and is spliced in via `impl_server_state!`.  The custom
//! fields below carry the JSON-backed stores that ezpz-dndz actually
//! serves.

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
use crate::per_user_store::{PerUserStore, PerUserStoreError};

#[derive(Clone)]
pub struct AppState {
  pub base: BaseServerState,
  pub dice_store: DiceStore,
  pub compendium_store: CompendiumStore,
  pub compendium_saves: SavedCompendiumStore,
  pub compendium_groups: CompendiumGroupStore,
  pub user_compendium: UserCompendiumStore,
  pub bundled_compendium: BundledCompendium,
  pub encounter_store: EncounterStore,
  pub encounter_saves: SavedEncounterStore,
  pub user_store: Arc<UserStore>,
  pub auth_rate_limiter: AuthRateLimiter,
  // The five per-user opaque-JSON stores, all served by the shared
  // GET/PUT routers in `per_user_store::routers`.
  pub lore_groups: PerUserStore,
  pub condition_presets: PerUserStore,
  pub save_chain_presets: PerUserStore,
  pub treasure_table: PerUserStore,
  pub treasure_profiles: PerUserStore,
}

impl_server_state!(AppState, base);

#[derive(Debug, Error)]
pub enum AppStateError {
  #[error("Failed to load compendium store: {0}")]
  CompendiumStoreLoad(#[source] crate::compendium::CompendiumStoreError),

  #[error("Failed to load live-encounter store: {0}")]
  EncounterStoreLoad(#[source] crate::encounters::EncounterStoreError),

  #[error("Legacy JSON import failed: {0}")]
  JsonImport(#[source] json_import::JsonImportError),

  #[error("Compendium split migration failed: {0}")]
  CompendiumSplitMigration(#[source] MigrationError),

  // The inner error's Display names the store ("lore-groups store
  // persistence failed: …"), so the semantics of the five per-store
  // variants this replaced are preserved.
  #[error("Failed to load per-user store: {0}")]
  PerUserStoreLoad(#[from] PerUserStoreError),
}

impl AppState {
  /// Build the app-specific portion of state from the database
  /// handle plus `RuntimePaths`, then wrap it around the
  /// foundation-built `BaseServerState`.  `db` arrives already
  /// migrated (see `Db::connect`); the legacy JSON files referenced
  /// by `paths` are only consulted by the one-shot import and by the
  /// stores that later phases haven't ported yet.
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

    let compendium_saves =
      SavedCompendiumStore::load_or_default(paths.compendium_saves.clone())
        .await
        .map_err(AppStateError::CompendiumStoreLoad)?;

    let compendium_groups =
      CompendiumGroupStore::load_or_default(paths.compendium_groups.clone())
        .await
        .map_err(AppStateError::CompendiumStoreLoad)?;

    let user_compendium =
      UserCompendiumStore::load_or_default(paths.user_creatures.clone())
        .await
        .map_err(AppStateError::CompendiumStoreLoad)?;

    let bundled_compendium =
      BundledCompendium::load().map_err(AppStateError::CompendiumStoreLoad)?;

    let encounter_store =
      EncounterStore::load_or_default(paths.encounter.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    let encounter_saves =
      SavedEncounterStore::load_or_default(paths.encounter_saves.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    let lore_groups =
      PerUserStore::load_or_default("lore-groups", paths.lore_groups.clone())
        .await?;

    let condition_presets = PerUserStore::load_or_default(
      "condition-presets",
      paths.condition_presets.clone(),
    )
    .await?;

    let save_chain_presets = PerUserStore::load_or_default(
      "save-chain-presets",
      paths.save_chain_presets.clone(),
    )
    .await?;

    let treasure_table = PerUserStore::load_or_default(
      "treasure-table",
      paths.treasure_table.clone(),
    )
    .await?;

    let treasure_profiles = PerUserStore::load_or_default(
      "treasure-profiles",
      paths.treasure_profiles.clone(),
    )
    .await?;

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
      lore_groups,
      condition_presets,
      save_chain_presets,
      treasure_table,
      treasure_profiles,
    })
  }
}
