//! Compendium subcommands for the CLI.
//!
//! Operations are file-direct — we read and write
//! `compendium/creatures.json` synchronously without going
//! through the server's HTTP API.  That keeps the CLI useful
//! when the server isn't running (e.g. inspecting a backup) and
//! avoids having to spin up a tokio runtime for what is
//! conceptually one-shot work.
//!
//! The schema is shared with the server via
//! `ezpz_dndz_lib::compendium::Creature`.

use clap::Subcommand;
use ezpz_dndz_lib::compendium::Creature;
use std::path::{Path, PathBuf};
use thiserror::Error;
use tracing::info;

/// Errors raised by the compendium subcommands.
#[derive(Debug, Error)]
pub enum CompendiumCliError {
  #[error("Failed to read compendium file at {path}: {source}")]
  ReadError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse compendium JSON at {path}: {source}")]
  ParseError {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Creature with id {id} not found in compendium at {path}")]
  CreatureNotFound { id: String, path: PathBuf },
}

/// Subcommands grouped under `ezpz-dndz-cli compendium <...>`.
#[derive(Debug, Subcommand)]
pub enum CompendiumCommand {
  /// Print a table of creatures (name / kind / CR) from the
  /// given JSON file.
  List {
    /// Path to the compendium JSON file.  Defaults to
    /// `compendium/creatures.json` relative to the current
    /// directory.
    #[arg(long, default_value = "compendium/creatures.json")]
    path: PathBuf,
  },

  /// Count the creatures in the file.
  Count {
    #[arg(long, default_value = "compendium/creatures.json")]
    path: PathBuf,
  },

  /// Print one creature's full stat block (as JSON) by id.
  Show {
    #[arg(long, default_value = "compendium/creatures.json")]
    path: PathBuf,

    /// The creature's UUID.
    id: String,
  },
}

impl CompendiumCommand {
  pub fn run(&self) -> Result<(), CompendiumCliError> {
    match self {
      CompendiumCommand::List { path } => list(path),
      CompendiumCommand::Count { path } => count(path),
      CompendiumCommand::Show { path, id } => show(path, id),
    }
  }
}

fn read_creatures(path: &Path) -> Result<Vec<Creature>, CompendiumCliError> {
  let raw = std::fs::read_to_string(path).map_err(|source| {
    CompendiumCliError::ReadError {
      path: path.to_path_buf(),
      source,
    }
  })?;

  serde_json::from_str(&raw).map_err(|source| CompendiumCliError::ParseError {
    path: path.to_path_buf(),
    source,
  })
}

fn list(path: &Path) -> Result<(), CompendiumCliError> {
  let creatures = read_creatures(path)?;
  info!(count = creatures.len(), "Read compendium");

  println!("{:<40}  {:<8}  {:<8}  {:>4}", "Name", "Kind", "Size", "CR");
  println!("{}", "-".repeat(64));
  for c in &creatures {
    println!(
      "{:<40}  {:<8?}  {:<8?}  {:>4}",
      truncate(&c.name, 40),
      c.kind,
      c.size,
      c.challenge_rating
    );
  }
  Ok(())
}

fn count(path: &Path) -> Result<(), CompendiumCliError> {
  let creatures = read_creatures(path)?;
  println!("{}", creatures.len());
  Ok(())
}

fn show(path: &Path, id: &str) -> Result<(), CompendiumCliError> {
  let creatures = read_creatures(path)?;
  let found = creatures.iter().find(|c| c.id == id);

  match found {
    Some(creature) => {
      // Pretty-print JSON; unwrap is safe since the type is
      // serializable and we just round-tripped it from disk.
      let pretty = serde_json::to_string_pretty(creature)
        .expect("Compendium Creature is serializable");
      println!("{pretty}");
      Ok(())
    }
    None => Err(CompendiumCliError::CreatureNotFound {
      id: id.to_string(),
      path: path.to_path_buf(),
    }),
  }
}

fn truncate(s: &str, max: usize) -> String {
  if s.chars().count() <= max {
    s.to_string()
  } else {
    let mut out: String = s.chars().take(max - 1).collect();
    out.push('…');
    out
  }
}
