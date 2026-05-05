//! ezpz-dndz-cli — command-line application for working with
//! the project's data files (compendium, encounters, dice
//! history) outside the running server.
//!
//! Subcommands are dispatched via clap.  All operate file-direct:
//! they read and write the on-disk JSON directly without going
//! through the server's HTTP API.  That keeps the CLI useful when
//! the server isn't running (e.g. inspecting a backup).
//!
//! - `compendium {list, count, show}` — inspect creatures.json.
//! - `encounter {show, count}` — inspect the live encounter file.
//! - `dice {count, tail, clear}` — inspect / wipe the roll log.

mod compendium;
mod config;
mod dice;
mod encounter;
mod logging;

use clap::Parser;
use compendium::CompendiumCliError;
use config::{CliRaw, Command, Config, ConfigError};
use dice::DiceCliError;
use encounter::EncounterCliError;
use logging::init_logging;
use thiserror::Error;
use tracing::info;

#[derive(Debug, Error)]
enum ApplicationError {
  #[error("Failed to load configuration during startup: {0}")]
  ConfigurationLoad(#[from] ConfigError),

  #[error("Compendium subcommand failed: {0}")]
  Compendium(#[from] CompendiumCliError),

  #[error("Encounter subcommand failed: {0}")]
  Encounter(#[from] EncounterCliError),

  #[error("Dice subcommand failed: {0}")]
  Dice(#[from] DiceCliError),
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
    Some(Command::Encounter { command }) => {
      command.run().map_err(ApplicationError::Encounter)
    }
    Some(Command::Dice { command }) => {
      command.run().map_err(ApplicationError::Dice)
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
