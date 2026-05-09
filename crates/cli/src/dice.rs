//! Dice-history subcommands for the CLI.
//!
//! The server's `--dice-history-path` JSON is an array of roll
//! records; we read it as a `Vec<Value>` rather than coupling to
//! the frontend's roll schema.  `clear` writes a fresh empty
//! array (`[]`) — same shape the server expects on first boot.

use clap::Subcommand;
use serde_json::Value;
use std::path::{Path, PathBuf};
use thiserror::Error;
use tracing::info;

#[derive(Debug, Error)]
pub enum DiceCliError {
  #[error("Failed to read dice-history file at {path}: {source}")]
  ReadError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse dice-history JSON at {path}: {source}")]
  ParseError {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error("Failed to write dice-history file at {path}: {source}")]
  WriteError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Dice-history file at {path} is not a JSON array")]
  NotAnArray { path: PathBuf },

  #[error("Failed to serialize dice-history slice to JSON: {0}")]
  SerializeError(#[source] serde_json::Error),
}

/// Subcommands grouped under `ezpz-dndz-cli dice <...>`.
#[derive(Debug, Clone, Subcommand)]
pub enum DiceCommand {
  /// Count the number of recorded rolls.
  Count {
    /// Path to the dice-history JSON file.  Defaults to
    /// `dice-history.json` relative to the current directory
    /// (matches the server's default `--data-dir` layout).
    #[arg(long, default_value = "dice-history.json")]
    path: PathBuf,
  },

  /// Print the last N rolls (defaults to 10) as pretty JSON.
  Tail {
    #[arg(long, default_value = "dice-history.json")]
    path: PathBuf,

    /// How many of the most recent rolls to show.
    #[arg(short, long, default_value_t = 10)]
    n: usize,
  },

  /// Wipe the history.  Writes `[]` to the file.  This is
  /// destructive; pass `--yes` to bypass the confirmation
  /// prompt (the only "ask" the CLI does, since you very rarely
  /// mean to nuke the entire roll log).
  Clear {
    #[arg(long, default_value = "dice-history.json")]
    path: PathBuf,

    /// Skip the interactive confirmation.
    #[arg(long)]
    yes: bool,
  },
}

impl DiceCommand {
  pub fn run(&self) -> Result<(), DiceCliError> {
    match self {
      DiceCommand::Count { path } => count(path),
      DiceCommand::Tail { path, n } => tail(path, *n),
      DiceCommand::Clear { path, yes } => clear(path, *yes),
    }
  }
}

fn read_array(path: &Path) -> Result<Vec<Value>, DiceCliError> {
  let raw = std::fs::read_to_string(path).map_err(|source| {
    DiceCliError::ReadError {
      path: path.to_path_buf(),
      source,
    }
  })?;

  let value: Value =
    serde_json::from_str(&raw).map_err(|source| DiceCliError::ParseError {
      path: path.to_path_buf(),
      source,
    })?;

  match value {
    Value::Array(arr) => Ok(arr),
    _ => Err(DiceCliError::NotAnArray {
      path: path.to_path_buf(),
    }),
  }
}

fn count(path: &Path) -> Result<(), DiceCliError> {
  let rolls = read_array(path)?;
  info!(count = rolls.len(), path = %path.display(), "Counted dice rolls");
  println!("{}", rolls.len());
  Ok(())
}

fn tail(path: &Path, n: usize) -> Result<(), DiceCliError> {
  let rolls = read_array(path)?;
  let total = rolls.len();
  // Server stores newest-first; "tail" semantically means
  // "most-recent N", so we slice from the front.
  let take = n.min(total);
  let slice: Vec<&Value> = rolls.iter().take(take).collect();
  let pretty = serde_json::to_string_pretty(&slice)
    .map_err(DiceCliError::SerializeError)?;
  println!("{pretty}");
  Ok(())
}

fn clear(path: &Path, yes: bool) -> Result<(), DiceCliError> {
  if !yes {
    eprintln!(
      "About to wipe {} (write `[]`).  Pass --yes to confirm.",
      path.display()
    );
    return Ok(());
  }

  std::fs::write(path, "[]\n").map_err(|source| DiceCliError::WriteError {
    path: path.to_path_buf(),
    source,
  })?;

  info!(path = %path.display(), "Cleared dice history");
  println!("Cleared.");
  Ok(())
}
