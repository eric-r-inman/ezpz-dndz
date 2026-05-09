//! Encounter subcommands for the CLI.
//!
//! The server stores the live encounter as opaque JSON written by
//! the Elm frontend (`Encounter.Wire.encodeEncounter`); this CLI
//! reads it back as a free-form `serde_json::Value` rather than
//! coupling the CLI to the frontend's wire schema.  Keeps the CLI
//! useful for inspecting backups even if the schema drifts a
//! little between versions.

use clap::Subcommand;
use serde_json::Value;
use std::path::{Path, PathBuf};
use thiserror::Error;
use tracing::info;

#[derive(Debug, Error)]
pub enum EncounterCliError {
  #[error("Failed to read encounter file at {path}: {source}")]
  Read {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse encounter JSON at {path}: {source}")]
  Parse {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Failed to serialize encounter to JSON: {0}")]
  Serialize(#[source] serde_json::Error),
}

/// Subcommands grouped under `ezpz-dndz-cli encounter <...>`.
#[derive(Debug, Subcommand)]
pub enum EncounterCommand {
  /// Pretty-print the live encounter JSON.
  Show {
    /// Path to the encounter JSON file.  Defaults to
    /// `encounter.json` relative to the current directory
    /// (matches the server's default `--data-dir` layout).
    #[arg(long, default_value = "encounter.json")]
    path: PathBuf,
  },

  /// Count the creatures in the queue.
  Count {
    #[arg(long, default_value = "encounter.json")]
    path: PathBuf,
  },
}

impl EncounterCommand {
  pub fn run(&self) -> Result<(), EncounterCliError> {
    match self {
      EncounterCommand::Show { path } => show(path),
      EncounterCommand::Count { path } => count(path),
    }
  }
}

fn read_value(path: &Path) -> Result<Value, EncounterCliError> {
  let raw = std::fs::read_to_string(path).map_err(|source| {
    EncounterCliError::Read {
      path: path.to_path_buf(),
      source,
    }
  })?;

  serde_json::from_str(&raw).map_err(|source| EncounterCliError::Parse {
    path: path.to_path_buf(),
    source,
  })
}

fn show(path: &Path) -> Result<(), EncounterCliError> {
  let value = read_value(path)?;
  let pretty = serde_json::to_string_pretty(&value)
    .map_err(EncounterCliError::Serialize)?;
  println!("{pretty}");
  Ok(())
}

fn count(path: &Path) -> Result<(), EncounterCliError> {
  let value = read_value(path)?;
  let n = value
    .get("creatures")
    .and_then(|v| v.as_array())
    .map(|a| a.len())
    .unwrap_or(0);
  info!(count = n, path = %path.display(), "Counted creatures");
  println!("{n}");
  Ok(())
}
