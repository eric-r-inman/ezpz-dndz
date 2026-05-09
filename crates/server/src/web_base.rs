//! Application state shared by the HTTP handlers.
//!
//! `BaseServerState` (registry, request counter, OIDC client, frontend
//! path) lives in foundation and is spliced in via `impl_server_state!`.
//! The custom fields below carry the JSON-backed stores that ezpz-dndz
//! actually serves.

use rust_template_foundation::{
  impl_server_state, server::runner::BaseServerState,
};
use thiserror::Error;

use crate::compendium::{CompendiumStore, SavedCompendiumStore};
use crate::config::RuntimePaths;
use crate::dice::DiceStore;
use crate::encounters::{EncounterStore, SavedEncounterStore};

#[derive(Clone)]
pub struct AppState {
  pub base: BaseServerState,
  pub dice_store: DiceStore,
  pub compendium_store: CompendiumStore,
  pub compendium_saves: SavedCompendiumStore,
  pub encounter_store: EncounterStore,
  pub encounter_saves: SavedEncounterStore,
}

impl_server_state!(AppState, base);

#[derive(Debug, Error)]
pub enum AppStateError {
  #[error("Failed to load dice history store: {0}")]
  DiceStoreLoad(#[source] crate::dice::DiceHistoryError),

  #[error("Failed to load compendium store: {0}")]
  CompendiumStoreLoad(#[source] crate::compendium::CompendiumStoreError),

  #[error("Failed to load live-encounter store: {0}")]
  EncounterStoreLoad(#[source] crate::encounters::EncounterStoreError),
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

    let encounter_store =
      EncounterStore::load_or_default(paths.encounter.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    let encounter_saves =
      SavedEncounterStore::load_or_default(paths.encounter_saves.clone())
        .await
        .map_err(AppStateError::EncounterStoreLoad)?;

    Ok(Self {
      base,
      dice_store,
      compendium_store,
      compendium_saves,
      encounter_store,
      encounter_saves,
    })
  }
}
