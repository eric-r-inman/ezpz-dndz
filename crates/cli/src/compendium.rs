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
use ezpz_dndz_lib::compendium::open5e::Page as Open5ePage;
use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;
use tracing::{info, warn};

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

  #[error("Failed to write compendium file at {path}: {source}")]
  WriteError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to serialize compendium to JSON: {0}")]
  SerializeError(#[source] serde_json::Error),

  #[error("Open5e fetch failed: {0}")]
  HarvestFetchError(#[source] reqwest::Error),

  #[error("Open5e response could not be decoded: {0}")]
  HarvestDecodeError(#[source] reqwest::Error),
}

/// Subcommands grouped under `ezpz-dndz-cli compendium <...>`.
#[derive(Debug, Clone, Subcommand)]
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

  /// Harvest open-licensed creatures from the Open5e API and
  /// write them as a `Creature` JSON file ready for import.
  ///
  /// Defaults to the 2024 SRD (`document__key=srd-2024`), which
  /// is licensed under Creative Commons CC-BY 4.0 and freely
  /// redistributable with attribution.  Other CC-BY 4.0
  /// document keys: `srd-2014`, `bfrd`, `core`.  The `source`
  /// field on each emitted creature carries the attribution.
  Harvest {
    /// Open5e document key to filter on (e.g. `srd-2024`,
    /// `srd-2014`).  Pass `all` to drop the filter and pull
    /// every creature in the database — only do that if you've
    /// checked the licensing of the other documents (the
    /// majority are OGL 1.0a, not CC-BY).
    #[arg(long, default_value = "srd-2024")]
    document: String,

    /// Output path for the harvested JSON.  Defaults to
    /// `compendium/harvested.json` so it doesn't clobber the
    /// live `creatures.json` by accident.
    #[arg(long, default_value = "compendium/harvested.json")]
    out: PathBuf,

    /// Maximum number of creatures to fetch.  Useful for
    /// testing the pipeline against a small slice before
    /// committing to a full pull.
    #[arg(long)]
    limit: Option<usize>,
  },

  /// Merge a JSON file of `Creature` records into the
  /// compendium store, allocating fresh ids and timestamps for
  /// any draft entries (entries without `id` / `created_at`).
  /// Existing creatures in the destination are preserved unless
  /// `--replace` is set.
  Import {
    /// Source JSON file — typically the output of `harvest`.
    /// May contain either `Creature` records (with id +
    /// timestamps) or `CreatureDraft` records (without).
    src: PathBuf,

    /// Destination compendium file.
    #[arg(long, default_value = "compendium/creatures.json")]
    dst: PathBuf,

    /// Replace the destination contents instead of merging.
    /// Implies "wipe everything that was there".
    #[arg(long, default_value_t = false)]
    replace: bool,
  },
}

impl CompendiumCommand {
  pub fn run(&self) -> Result<(), CompendiumCliError> {
    match self {
      CompendiumCommand::List { path } => list(path),
      CompendiumCommand::Count { path } => count(path),
      CompendiumCommand::Show { path, id } => show(path, id),
      CompendiumCommand::Harvest {
        document,
        out,
        limit,
      } => harvest(document, out, *limit),
      CompendiumCommand::Import { src, dst, replace } => {
        import(src, dst, *replace)
      }
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
      let pretty = serde_json::to_string_pretty(creature)
        .map_err(CompendiumCliError::SerializeError)?;
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

// ── HARVEST ────────────────────────────────────────────────────

/// Pull every page of `/v2/creatures/` matching the document
/// filter, map each entry to a full `Creature` with a
/// deterministic UUIDv5 derived from its Open5e key slug, and
/// write the result as JSON.
///
/// Deterministic UUIDs mean re-running the harvester produces
/// the same id for the same source creature — the server's
/// bundle-version merge logic dedupes by id, so a future
/// re-harvest can ship as a new version without duplicating
/// existing creatures.
///
/// The output is a valid `creatures.json` file — drop it into
/// `crates/lib/data/bundled-creatures.json` or merge via
/// `compendium import` without an extra promotion step.
fn harvest(
  document: &str,
  out: &Path,
  limit: Option<usize>,
) -> Result<(), CompendiumCliError> {
  let client = reqwest::blocking::Client::builder()
    .user_agent("ezpz-dndz-cli/0.1 (+harvest)")
    .build()
    .map_err(CompendiumCliError::HarvestFetchError)?;

  let mut url = if document == "all" {
    "https://api.open5e.com/v2/creatures/?limit=100".to_string()
  } else {
    format!(
      "https://api.open5e.com/v2/creatures/?document__key={document}&limit=100"
    )
  };

  let now = epoch_millis();
  let mut creatures: Vec<Creature> = Vec::new();

  loop {
    info!(url = %url, fetched = creatures.len(), "Fetching Open5e page");

    let page: Open5ePage = client
      .get(&url)
      .send()
      .map_err(CompendiumCliError::HarvestFetchError)?
      .error_for_status()
      .map_err(CompendiumCliError::HarvestFetchError)?
      .json()
      .map_err(CompendiumCliError::HarvestDecodeError)?;

    for monster in page.results {
      creatures.push(monster.into_creature(now));
      if let Some(cap) = limit {
        if creatures.len() >= cap {
          break;
        }
      }
    }

    if let Some(cap) = limit {
      if creatures.len() >= cap {
        break;
      }
    }

    match page.next {
      Some(next) => url = next,
      None => break,
    }
  }

  info!(harvested = creatures.len(), "Harvest complete");

  if let Some(parent) = out.parent() {
    std::fs::create_dir_all(parent).map_err(|source| {
      CompendiumCliError::WriteError {
        path: parent.to_path_buf(),
        source,
      }
    })?;
  }

  let json = serde_json::to_string_pretty(&creatures)
    .map_err(CompendiumCliError::SerializeError)?;
  std::fs::write(out, json).map_err(|source| {
    CompendiumCliError::WriteError {
      path: out.to_path_buf(),
      source,
    }
  })?;

  println!("Wrote {} creatures to {}", creatures.len(), out.display());
  Ok(())
}

/// Promote a `CreatureDraft` to a fully-formed `Creature` by
/// assigning a fresh UUID and stamping `created_at` /
/// `updated_at` to the supplied epoch-millis instant.
fn draft_to_creature(draft: CreatureDraft, now: i64) -> Creature {
  Creature {
    id: uuid::Uuid::new_v4().to_string(),
    name: draft.name,
    kind: draft.kind,
    size: draft.size,
    race: draft.race,
    subrace: draft.subrace,
    alignment: draft.alignment,
    source: draft.source,
    description: draft.description,
    armor_class: draft.armor_class,
    armor_class_note: draft.armor_class_note,
    max_hp: draft.max_hp,
    hp_formula: draft.hp_formula,
    initiative_bonus: draft.initiative_bonus,
    speed: draft.speed,
    abilities: draft.abilities,
    saving_throws: draft.saving_throws,
    skills: draft.skills,
    damage_vulnerabilities: draft.damage_vulnerabilities,
    damage_resistances: draft.damage_resistances,
    damage_immunities: draft.damage_immunities,
    condition_immunities: draft.condition_immunities,
    senses: draft.senses,
    languages: draft.languages,
    challenge_rating: draft.challenge_rating,
    xp: draft.xp,
    xp_in_lair: draft.xp_in_lair,
    proficiency_bonus: draft.proficiency_bonus,
    traits: draft.traits,
    actions: draft.actions,
    bonus_actions: draft.bonus_actions,
    reactions: draft.reactions,
    legendary_actions: draft.legendary_actions,
    lair_actions: draft.lair_actions,
    regional_effects: draft.regional_effects,
    spellcasting: draft.spellcasting,
    custom_sections: draft.custom_sections,
    habitats: draft.habitats,
    treasures: draft.treasures,
    tags: draft.tags,
    created_at: now,
    updated_at: now,
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}

// ── IMPORT ─────────────────────────────────────────────────────

/// Merge a JSON file of `Creature` records into the destination
/// compendium.  Source records that look like full `Creature`
/// entries (have `id` + timestamps) pass through; entries that
/// look like `CreatureDraft` (no id) get promoted via
/// `draft_to_creature`.
///
/// `--replace` swaps the file contents wholesale; otherwise the
/// import is additive (de-duplicated by `id` so a re-import of
/// the same file is idempotent).
fn import(
  src: &Path,
  dst: &Path,
  replace: bool,
) -> Result<(), CompendiumCliError> {
  let raw = std::fs::read_to_string(src).map_err(|source| {
    CompendiumCliError::ReadError {
      path: src.to_path_buf(),
      source,
    }
  })?;

  // Try Creature first (full records).  Fall back to
  // CreatureDraft for files that came out of an external tool.
  let now = epoch_millis();
  let incoming: Vec<Creature> =
    match serde_json::from_str::<Vec<Creature>>(&raw) {
      Ok(creatures) => creatures,
      Err(_) => {
        let drafts: Vec<CreatureDraft> =
          serde_json::from_str(&raw).map_err(|source| {
            CompendiumCliError::ParseError {
              path: src.to_path_buf(),
              source,
            }
          })?;
        drafts
          .into_iter()
          .map(|d| draft_to_creature(d, now))
          .collect()
      }
    };

  let mut merged: Vec<Creature> = if replace {
    Vec::new()
  } else {
    match read_creatures(dst) {
      Ok(existing) => existing,
      Err(CompendiumCliError::ReadError { .. }) => {
        warn!(path = %dst.display(), "Destination missing — creating");
        Vec::new()
      }
      Err(e) => return Err(e),
    }
  };

  let mut added = 0usize;
  for c in incoming {
    if merged.iter().any(|existing| existing.id == c.id) {
      // Idempotent re-import — skip.
      continue;
    }
    merged.push(c);
    added += 1;
  }

  if let Some(parent) = dst.parent() {
    std::fs::create_dir_all(parent).map_err(|source| {
      CompendiumCliError::WriteError {
        path: parent.to_path_buf(),
        source,
      }
    })?;
  }

  let json = serde_json::to_string_pretty(&merged)
    .map_err(CompendiumCliError::SerializeError)?;
  std::fs::write(dst, json).map_err(|source| {
    CompendiumCliError::WriteError {
      path: dst.to_path_buf(),
      source,
    }
  })?;

  println!(
    "Imported {} creatures into {} (now {} total)",
    added,
    dst.display(),
    merged.len()
  );
  Ok(())
}
