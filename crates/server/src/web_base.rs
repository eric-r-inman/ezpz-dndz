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

use crate::card_editor::CardLayoutStore;
use crate::compendium::{
  BundledCompendium, CompendiumGroupStore, CompendiumStore,
  SavedCompendiumStore, UserCompendiumStore,
};
use crate::config::RuntimePaths;
use crate::dice::DiceStore;
use crate::encounters::{EncounterStore, SavedEncounterStore};

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
}

impl AppState {
  /// Build the app-specific portion of state from `RuntimePaths`,
  /// then wrap it around the foundation-built `BaseServerState`.
  pub async fn assemble(
    base: BaseServerState,
    paths: &RuntimePaths,
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
    })
  }
}
