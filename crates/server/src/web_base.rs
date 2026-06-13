//! Application state shared by the HTTP handlers.
//!
//! `BaseServerState` (registry, request counter, OIDC client, frontend
//! path) lives in foundation and is spliced in via `impl_server_state!`.
//! The custom fields below carry the JSON-backed stores that ezpz-dndz
//! actually serves.

use ezpz_dndz_lib::users::UserStore;
use rust_template_foundation::{
  impl_server_state, server::runner::BaseServerState,
};
use std::sync::Arc;
use thiserror::Error;

use crate::auth_rate_limit::AuthRateLimiter;
use crate::card_editor::CardLayoutStore;
use crate::compendium::{
  migrate as compendium_migrate, BundledCompendium, CompendiumGroupStore,
  CompendiumStore, MigrationError, SavedCompendiumStore, UserCompendiumStore,
};
use crate::condition_presets::{
  ConditionPresetStore, ConditionPresetStoreError,
};
use crate::config::RuntimePaths;
use crate::dice::DiceStore;
use crate::encounters::{EncounterStore, SavedEncounterStore};
use crate::lore_groups::{LoreGroupStore, LoreGroupStoreError};
use crate::treasure_profiles::{
  TreasureProfileStore, TreasureProfileStoreError,
};
use crate::treasure_table::{TreasureTableStore, TreasureTableStoreError};

#[derive(Clone)]
pub struct AppState {
  pub base: BaseServerState,
  pub dice_store: DiceStore,
  pub compendium_store: CompendiumStore,
  pub compendium_saves: SavedCompendiumStore,
  pub compendium_groups: CompendiumGroupStore,
  pub user_compendium: UserCompendiumStore,
  pub bundled_compendium: BundledCompendium,
  pub card_layouts: CardLayoutStore,
  pub encounter_store: EncounterStore,
  pub encounter_saves: SavedEncounterStore,
  pub user_store: Arc<UserStore>,
  pub auth_rate_limiter: AuthRateLimiter,
  pub lore_groups: LoreGroupStore,
  pub condition_presets: ConditionPresetStore,
  pub treasure_table: TreasureTableStore,
  pub treasure_profiles: TreasureProfileStore,
}

impl_server_state!(AppState, base);

#[derive(Debug, Error)]
pub enum AppStateError {
  #[error("Failed to load dice history store: {0}")]
  DiceStoreLoad(#[source] crate::dice::DiceHistoryError),

  #[error("Failed to load compendium store: {0}")]
  CompendiumStoreLoad(#[source] crate::compendium::CompendiumStoreError),

  #[error("Failed to load card-layout store: {0}")]
  CardLayoutStoreLoad(#[source] crate::card_editor::CardLayoutStoreError),

  #[error("Failed to load live-encounter store: {0}")]
  EncounterStoreLoad(#[source] crate::encounters::EncounterStoreError),

  #[error("Failed to load user store: {0}")]
  UserStoreLoad(#[source] ezpz_dndz_lib::users::UserStoreError),

  #[error("Compendium split migration failed: {0}")]
  CompendiumSplitMigration(#[source] MigrationError),

  #[error("Failed to load lore-group store: {0}")]
  LoreGroupStoreLoad(#[source] LoreGroupStoreError),

  #[error("Failed to load condition-preset store: {0}")]
  ConditionPresetStoreLoad(#[source] ConditionPresetStoreError),

  #[error("Failed to load treasure-table store: {0}")]
  TreasureTableStoreLoad(#[source] TreasureTableStoreError),

  #[error("Failed to load treasure-profile store: {0}")]
  TreasureProfileStoreLoad(#[source] TreasureProfileStoreError),
}

impl AppState {
  /// Build the app-specific portion of state from `RuntimePaths`,
  /// then wrap it around the foundation-built `BaseServerState`.
  ///
  /// `compendium_claim_user` is the email address passed via
  /// `--compendium-claim-user` (or the equivalent config-file
  /// key).  Consumed by the one-shot per-user compendium split
  /// migration on the first boot of the post-split binary against
  /// a data dir that contains non-bundled creatures in the legacy
  /// shared store; ignored on every other boot.
  pub async fn assemble(
    base: BaseServerState,
    paths: &RuntimePaths,
    compendium_claim_user: Option<&str>,
  ) -> Result<Self, AppStateError> {
    let dice_store = DiceStore::load_or_default(paths.dice_history.clone())
      .await
      .map_err(AppStateError::DiceStoreLoad)?;

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

    let card_layouts =
      CardLayoutStore::load_or_default(paths.card_layouts.clone())
        .await
        .map_err(AppStateError::CardLayoutStoreLoad)?;

    let encounter_store =
      EncounterStore::load_or_default(paths.encounter.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    let encounter_saves =
      SavedEncounterStore::load_or_default(paths.encounter_saves.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    let user_store = UserStore::load_or_default(paths.users.clone())
      .await
      .map_err(AppStateError::UserStoreLoad)?;

    let lore_groups =
      LoreGroupStore::load_or_default(paths.lore_groups.clone())
        .await
        .map_err(AppStateError::LoreGroupStoreLoad)?;

    let condition_presets =
      ConditionPresetStore::load_or_default(paths.condition_presets.clone())
        .await
        .map_err(AppStateError::ConditionPresetStoreLoad)?;

    let treasure_table =
      TreasureTableStore::load_or_default(paths.treasure_table.clone())
        .await
        .map_err(AppStateError::TreasureTableStoreLoad)?;

    let treasure_profiles =
      TreasureProfileStore::load_or_default(paths.treasure_profiles.clone())
        .await
        .map_err(AppStateError::TreasureProfileStoreLoad)?;

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
      card_layouts,
      encounter_store,
      encounter_saves,
      user_store: Arc::new(user_store),
      auth_rate_limiter: AuthRateLimiter::new(),
      lore_groups,
      condition_presets,
      treasure_table,
      treasure_profiles,
    })
  }
}
