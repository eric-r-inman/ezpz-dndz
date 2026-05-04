//! ezpz-dndz-cli — command-line application for working with
//! the project's data files (compendium, encounters, dice
//! history) outside the running server.
//!
//! Subcommands are dispatched via clap.  Currently shipping:
//!
//! - `compendium list` / `count` / `show` — inspect a
//!   `creatures.json` file.
//!
//! Future commands (per MODULARIZATION_PLAN Phase 11):
//! `compendium import` / `export`, `encounter list` /
//! `restore`, `dice clear`.

mod compendium;
mod config;
mod logging;

use clap::Parser;
use compendium::CompendiumCliError;
use config::{CliRaw, Command, Config, ConfigError};
use logging::init_logging;
use thiserror::Error;
use tracing::info;

#[derive(Debug, Error)]
enum ApplicationError {
  #[error("Failed to load configuration during startup: {0}")]
  ConfigurationLoad(#[from] ConfigError),

  #[error("Compendium subcommand failed: {0}")]
  Compendium(#[from] CompendiumCliError),
}

fn main() -> Result<(), ApplicationError> {
  let cli = CliRaw::parse();

  let config = Config::from_cli_and_file(cli).map_err(|e| {
    eprintln!("Configuration error: {e}");
    ApplicationError::ConfigurationLoad(e)
  })?;

  init_logging(config.log_level, config.log_format);

  info!("Starting ezpz-dndz-cli");

  run(config)?;

  Ok(())
}

fn run(config: Config) -> Result<(), ApplicationError> {
  match config.command {
    Some(Command::Compendium { command }) => {
      command.run().map_err(ApplicationError::Compendium)
    }
    None => {
      println!(
        "ezpz-dndz-cli: no subcommand provided.  Run with --help \
         for usage."
      );
      Ok(())
    }
  }
}
