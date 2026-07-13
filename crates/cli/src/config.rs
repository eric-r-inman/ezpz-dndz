//! CLI configuration.
//!
//! The single `MergeConfig` derive generates `CliRaw`, `ConfigFileRaw`,
//! `Config::from_cli_and_file`, and the `CliApp` impl that
//! `#[foundation_main]` wires up.  Subcommands flow in via the
//! `subcommand` field kind and stay structured as the existing
//! `Command` ADT.

use crate::compendium::CompendiumCommand;
use crate::dice::DiceCommand;
use crate::encounter::EncounterCommand;
use crate::users::UsersCommand;
use clap::Subcommand;
use ezpz_dndz_lib::{LogFormat, LogLevel};
use rust_template_foundation::MergeConfig;

#[derive(Debug, Clone, Subcommand)]
pub enum Command {
  /// Inspect or maintain a compendium JSON file.
  Compendium {
    #[command(subcommand)]
    command: CompendiumCommand,
  },

  /// Inspect the live encounter JSON.
  Encounter {
    #[command(subcommand)]
    command: EncounterCommand,
  },

  /// Inspect or clear the dice-history JSON file.
  Dice {
    #[command(subcommand)]
    command: DiceCommand,
  },

  /// Admin operations against the SQL-backed user store
  /// (password reset, etc.).  Intended for the operator running
  /// the binary on the same host as the data dir.
  Users {
    #[command(subcommand)]
    command: UsersCommand,
  },
}

#[derive(Debug, Clone, MergeConfig)]
#[merge_config(app_name = "ezpz-dndz")]
pub struct Config {
  #[merge_config(common)]
  pub log_level: LogLevel,
  #[merge_config(common)]
  pub log_format: LogFormat,
  #[merge_config(subcommand)]
  pub command: Option<Command>,
}
