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
//!
//! `#[foundation_main]` handles CLI parsing, config-file resolution
//! (XDG-aware), and logging init; this file only owns the
//! subcommand dispatch table.

mod compendium;
mod config;
mod dice;
mod encounter;
mod habitats;
mod users;

use compendium::CompendiumCliError;
use config::{Command, Config};
use dice::DiceCliError;
use encounter::EncounterCliError;
use rust_template_foundation::main as foundation_main;
use std::process::ExitCode;
use thiserror::Error;
use tracing::info;
use users::UsersCliError;

#[derive(Debug, Error)]
enum ApplicationError {
  #[error("Compendium subcommand failed: {0}")]
  Compendium(#[from] CompendiumCliError),

  #[error("Encounter subcommand failed: {0}")]
  Encounter(#[from] EncounterCliError),

  #[error("Dice subcommand failed: {0}")]
  Dice(#[from] DiceCliError),

  #[error("Users subcommand failed: {0}")]
  Users(#[from] UsersCliError),
}

#[foundation_main]
pub fn main(config: Config) -> Result<ExitCode, ApplicationError> {
  info!("Starting ezpz-dndz-cli");

  match config.command {
    Some(Command::Compendium { command }) => command.run()?,
    Some(Command::Encounter { command }) => command.run()?,
    Some(Command::Dice { command }) => command.run()?,
    Some(Command::Users { command }) => command.run()?,
    None => {
      println!(
        "ezpz-dndz-cli: no subcommand provided.  Run with --help \
         for usage."
      );
    }
  }

  Ok(ExitCode::SUCCESS)
}
