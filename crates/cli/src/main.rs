//! ezpz-dndz-cli — command-line application for operating on the
//! project's persisted data (compendium, encounters, dice history,
//! users) outside the running server.
//!
//! Subcommands are dispatched via clap.  The data subcommands open
//! the same database the server uses — resolved via the shared
//! `--database-url` / `--data-dir` rules — through the server
//! crate's store code, without going through the HTTP API.  That
//! keeps the CLI useful when the server isn't running (e.g.
//! inspecting a restored backup).  The `compendium harvest` /
//! `infer-habitats` pair stays file-based: it authors the bundled
//! creature JSON, which is data, not runtime state.
//!
//! - `compendium {list, count, show, import}` — per-user creatures
//!   plus the bundled set; `{harvest, infer-habitats}` — bundle
//!   authoring.
//! - `encounter {show, count}` — a user's live encounter.
//! - `dice {count, tail, clear}` — a user's roll log.
//! - `users {reset-password}` — operator account admin.
//!
//! `#[foundation_main]` handles CLI parsing, config-file resolution
//! (XDG-aware), and logging init; this file only owns the
//! subcommand dispatch table.

mod compendium;
mod config;
mod db;
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
