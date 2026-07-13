//! Compendium subcommands for the CLI.
//!
//! Two families live here:
//!
//! - **Database operations** (`list`, `count`, `show`, `import`) —
//!   the compendium proper is relational and per-user: the
//!   read-only bundled SRD set ships inside the binary and each
//!   user's own creatures live in the `user_creatures` table
//!   family.  These subcommands open the same database the server
//!   uses (shared `--database-url` / `--data-dir` resolution) and
//!   go through the server crate's stores, so they work while the
//!   server is stopped — e.g. against a restored backup.
//! - **File operations** (`harvest`, `infer-habitats`) — data
//!   authoring for the bundled set.  These read and write plain
//!   `Creature` JSON files (harvest output, the canonical
//!   `crates/lib/data/bundled-creatures.json`) and never touch the
//!   database.
//!
//! The schema is shared with the server via
//! `ezpz_dndz_lib::compendium::Creature`.

use crate::db::{self, DbArgs, DbCliError};
use crate::habitats::infer_habitats;
use clap::Subcommand;
use ezpz_dndz_lib::compendium::open5e::Page as Open5ePage;
use ezpz_dndz_lib::compendium::{Creature, CreatureDraft};
use ezpz_dndz_server::compendium::{
  BundledCompendium, CompendiumStoreError, UserCompendiumStore,
};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;
use tracing::info;

/// Errors raised by the compendium subcommands.
#[derive(Debug, Error)]
pub enum CompendiumCliError {
  #[error("Failed to read creatures file at {path}: {source}")]
  ReadError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to parse creatures JSON at {path}: {source}")]
  ParseError {
    path: PathBuf,
    source: serde_json::Error,
  },

  #[error(
    "Creature with id {id} not found in the bundled set or the \
     searched per-user compendium"
  )]
  CreatureNotFound { id: String },

  #[error("Failed to write creatures file at {path}: {source}")]
  WriteError {
    path: PathBuf,
    source: std::io::Error,
  },

  #[error("Failed to serialize creatures to JSON: {0}")]
  SerializeError(#[source] serde_json::Error),

  #[error("Open5e fetch failed: {0}")]
  HarvestFetchError(#[source] reqwest::Error),

  #[error("Open5e response could not be decoded: {0}")]
  HarvestDecodeError(#[source] reqwest::Error),

  #[error("Database access failed: {0}")]
  Db(#[from] DbCliError),

  #[error("Failed to load the bundled creature set: {0}")]
  BundledLoad(#[source] CompendiumStoreError),

  #[error("Failed to read the per-user compendium: {0}")]
  UserCreaturesRead(#[source] CompendiumStoreError),

  #[error("Failed to write the per-user compendium: {0}")]
  UserCreaturesWrite(#[source] CompendiumStoreError),

  #[error("Failed to list the creature-owning users: {0}")]
  OwnersQuery(#[source] sqlx::Error),

  #[error("Failed to look up the owner of user creatures: {0}")]
  OwnerLookup(#[source] ezpz_dndz_lib::users::UserStoreError),
}

/// Subcommands grouped under `ezpz-dndz-cli compendium <...>`.
#[derive(Debug, Clone, Subcommand)]
pub enum CompendiumCommand {
  /// Print a table of the user-owned creatures in the database
  /// (name / kind / size / CR / owner).  Scope to one user with
  /// `--email`; add the read-only bundled SRD set with
  /// `--bundled`.
  List {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose creatures to list
    /// (case-insensitive).  Without it every user's creatures are
    /// listed, labelled by owner.
    #[arg(long)]
    email: Option<String>,

    /// Also list the bundled SRD set that ships inside the binary.
    #[arg(long, default_value_t = false)]
    bundled: bool,
  },

  /// Count the user-owned creatures in the database.  Scope to one
  /// user with `--email`; add the bundled set with `--bundled`.
  Count {
    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose creatures to count
    /// (case-insensitive).  Without it every user's creatures are
    /// counted together.
    #[arg(long)]
    email: Option<String>,

    /// Also count the bundled SRD set that ships inside the binary.
    #[arg(long, default_value_t = false)]
    bundled: bool,
  },

  /// Print one creature's full stat block (as JSON) by id.  The
  /// bundled set is searched first, then the per-user creatures
  /// (one user's with `--email`, every user's without).
  Show {
    #[command(flatten)]
    db: DbArgs,

    /// The creature's UUID.
    id: String,

    /// Email of the user whose per-user compendium to search after
    /// the bundled set (case-insensitive).
    #[arg(long)]
    email: Option<String>,
  },

  /// Harvest open-licensed creatures from the Open5e API and
  /// write them as a `Creature` JSON file — data authoring for the
  /// bundled set, not a database operation.
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
    /// `compendium/harvested.json` so it doesn't clobber anything
    /// by accident.
    #[arg(long, default_value = "compendium/harvested.json")]
    out: PathBuf,

    /// Maximum number of creatures to fetch.  Useful for
    /// testing the pipeline against a small slice before
    /// committing to a full pull.
    #[arg(long)]
    limit: Option<usize>,
  },

  /// Fill in empty `habitats` fields on the creatures in a JSON
  /// file using deterministic name-and-race rules — data authoring
  /// for the bundled set (point `--path` at
  /// `crates/lib/data/bundled-creatures.json` or a harvest
  /// output), not a database operation.  Creatures that already
  /// have habitats are left alone.  Pass `--dry-run` to print a
  /// coverage summary without mutating the file.
  InferHabitats {
    /// Path to the creatures JSON file to mutate in place.
    #[arg(long, default_value = "compendium/creatures.json")]
    path: PathBuf,

    /// Don't write — just print what would be filled.
    #[arg(long, default_value_t = false)]
    dry_run: bool,
  },

  /// Merge a JSON file of `Creature` records into one user's
  /// per-user compendium, allocating fresh ids and timestamps for
  /// any draft entries (entries without `id` / `created_at`).
  /// Creatures whose ids collide with the bundled set are skipped
  /// (the bundle is read-only), and a re-import of the same file
  /// is idempotent.  The user's existing creatures are preserved
  /// unless `--replace` is set.
  Import {
    /// Source JSON file — typically the output of `harvest` or a
    /// compendium export.  May contain either `Creature` records
    /// (with id + timestamps) or `CreatureDraft` records
    /// (without).
    src: PathBuf,

    #[command(flatten)]
    db: DbArgs,

    /// Email of the user whose compendium receives the creatures
    /// (case-insensitive).
    #[arg(long)]
    email: String,

    /// Replace the user's existing creatures instead of merging.
    /// Implies "wipe everything they had".
    #[arg(long, default_value_t = false)]
    replace: bool,
  },
}

impl CompendiumCommand {
  pub fn run(&self) -> Result<(), CompendiumCliError> {
    match self {
      CompendiumCommand::List { db, email, bundled } => {
        db::block_on(list(db, email.as_deref(), *bundled))
      }
      CompendiumCommand::Count { db, email, bundled } => {
        db::block_on(count(db, email.as_deref(), *bundled))
      }
      CompendiumCommand::Show { db, id, email } => {
        db::block_on(show(db, id, email.as_deref()))
      }
      CompendiumCommand::Harvest {
        document,
        out,
        limit,
      } => harvest(document, out, *limit),
      CompendiumCommand::InferHabitats { path, dry_run } => {
        infer_habitats_cmd(path, *dry_run)
      }
      CompendiumCommand::Import {
        src,
        db,
        email,
        replace,
      } => db::block_on(import(src, db, email, *replace)),
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

/// One user's creatures, labelled with their owner's email for the
/// listing table.
async fn user_rows(
  store: &UserCompendiumStore,
  owner: &ezpz_dndz_lib::users::User,
) -> Result<Vec<(String, Creature)>, CompendiumCliError> {
  Ok(
    store
      .list(&owner.id)
      .await
      .map_err(CompendiumCliError::UserCreaturesRead)?
      .into_iter()
      .map(|c| (owner.email.clone(), c))
      .collect(),
  )
}

/// The operator view of the compendium: user-owned creatures from
/// the database — one user's with `email`, every user's without —
/// optionally prefixed by the read-only bundled set that ships in
/// the binary.  Each creature is paired with an origin label
/// (`bundled` or the owner's email) for the listing table.
async fn gather(
  args: &DbArgs,
  email: Option<&str>,
  include_bundled: bool,
) -> Result<Vec<(String, Creature)>, CompendiumCliError> {
  let mut rows: Vec<(String, Creature)> = if include_bundled {
    BundledCompendium::load()
      .map_err(CompendiumCliError::BundledLoad)?
      .list()
      .iter()
      .cloned()
      .map(|c| ("bundled".to_string(), c))
      .collect()
  } else {
    Vec::new()
  };

  let db = db::connect(args).await?;
  let store = UserCompendiumStore::new(db.clone());
  if let Some(email) = email {
    let user = db::user_by_email(&db, email).await?;
    rows.extend(user_rows(&store, &user).await?);
  } else {
    // Every owner in the database.  There is deliberately no
    // cross-user store API on the server (handlers are always
    // user-scoped), so the CLI asks the parent table who owns
    // rows and then reads each owner through the store.
    let owner_ids: Vec<String> = sqlx::query_scalar(
      "SELECT DISTINCT user_id FROM user_creatures ORDER BY user_id",
    )
    .fetch_all(db.pool())
    .await
    .map_err(CompendiumCliError::OwnersQuery)?;
    let users = ezpz_dndz_lib::users::UserStore::new(db.clone());
    for owner_id in owner_ids {
      let owner = users
        .find_by_id(&ezpz_dndz_lib::users::UserId(owner_id))
        .await
        .map_err(CompendiumCliError::OwnerLookup)?;
      // A missing account would mean a broken foreign key; the
      // filter keeps the listing best-effort either way.
      if let Some(owner) = owner {
        rows.extend(user_rows(&store, &owner).await?);
      }
    }
  }
  Ok(rows)
}

async fn list(
  args: &DbArgs,
  email: Option<&str>,
  include_bundled: bool,
) -> Result<(), CompendiumCliError> {
  let creatures = gather(args, email, include_bundled).await?;
  info!(count = creatures.len(), "Read compendium");

  println!("{:<40}  {:<8}  {:<8}  {:>4}  Owner", "Name", "Kind", "Size", "CR");
  println!("{}", "-".repeat(73));
  for (owner, c) in &creatures {
    println!(
      "{:<40}  {:<8?}  {:<8?}  {:>4}  {}",
      truncate(&c.name, 40),
      c.kind,
      c.size,
      c.challenge_rating,
      owner
    );
  }
  Ok(())
}

async fn count(
  args: &DbArgs,
  email: Option<&str>,
  include_bundled: bool,
) -> Result<(), CompendiumCliError> {
  let creatures = gather(args, email, include_bundled).await?;
  println!("{}", creatures.len());
  Ok(())
}

async fn show(
  args: &DbArgs,
  id: &str,
  email: Option<&str>,
) -> Result<(), CompendiumCliError> {
  let found = gather(args, email, true)
    .await?
    .into_iter()
    .map(|(_, c)| c)
    .find(|c| c.id == id);

  match found {
    Some(creature) => {
      let pretty = serde_json::to_string_pretty(&creature)
        .map_err(CompendiumCliError::SerializeError)?;
      println!("{pretty}");
      Ok(())
    }
    None => Err(CompendiumCliError::CreatureNotFound { id: id.to_string() }),
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
/// The output is a valid creatures JSON file — drop it into
/// `crates/lib/data/bundled-creatures.json` or merge into a user's
/// compendium via `compendium import` without an extra promotion
/// step.
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
    loot: draft.loot,
    created_at: now,
    updated_at: now,
    is_bundled: false,
    has_special_reactions: draft.has_special_reactions,
  }
}

fn epoch_millis() -> i64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}

// ── INFER HABITATS ─────────────────────────────────────────────

/// Read the creatures file, run `infer_habitats` against every
/// creature whose `habitats` is empty, write the result back.
/// Creatures with pre-existing habitats are skipped entirely so
/// authored data (whether by a future bundle bump or by user
/// edits propagated through Paste-Stat-Block) wins over the
/// rules.  Prints a coverage summary grouped by race and lists
/// any creatures left without a habitat — the input to a
/// follow-up rules pass.
fn infer_habitats_cmd(
  path: &Path,
  dry_run: bool,
) -> Result<(), CompendiumCliError> {
  let mut creatures = read_creatures(path)?;

  let mut filled = 0usize;
  let mut skipped_had_habitat = 0usize;
  let mut by_race_filled: std::collections::BTreeMap<String, usize> =
    Default::default();
  let mut by_race_unmatched: std::collections::BTreeMap<String, Vec<String>> =
    Default::default();

  for c in creatures.iter_mut() {
    if !c.habitats.is_empty() {
      skipped_had_habitat += 1;
      continue;
    }
    let inferred = infer_habitats(c);
    if inferred.is_empty() {
      by_race_unmatched
        .entry(c.race.clone())
        .or_default()
        .push(c.name.clone());
    } else {
      filled += 1;
      *by_race_filled.entry(c.race.clone()).or_default() += 1;
      c.habitats = inferred;
    }
  }

  println!("Creatures file: {}", path.display());
  println!("  total creatures:       {}", creatures.len());
  println!("  already had habitats:  {skipped_had_habitat}");
  println!("  filled by rules:       {filled}");
  let unmatched_total: usize =
    by_race_unmatched.values().map(|v| v.len()).sum();
  println!("  still empty:           {unmatched_total}");
  println!();

  if !by_race_filled.is_empty() {
    println!("Filled by race:");
    for (race, n) in &by_race_filled {
      println!("  {race:<14} {n:>3}");
    }
    println!();
  }

  if !by_race_unmatched.is_empty() {
    println!("Unmatched (rules need extending):");
    for (race, names) in &by_race_unmatched {
      println!("  {race} ({}):", names.len());
      for n in names {
        println!("    - {n}");
      }
    }
    println!();
  }

  if dry_run {
    println!("--dry-run set; no changes written.");
    return Ok(());
  }

  if filled == 0 {
    println!("Nothing to write — no creatures gained habitats.");
    return Ok(());
  }

  let json = serde_json::to_string_pretty(&creatures)
    .map_err(CompendiumCliError::SerializeError)?;
  std::fs::write(path, json).map_err(|source| {
    CompendiumCliError::WriteError {
      path: path.to_path_buf(),
      source,
    }
  })?;
  println!("Wrote {} creatures with new habitats.", filled);
  Ok(())
}

// ── IMPORT ─────────────────────────────────────────────────────

/// Merge a JSON file of `Creature` records into one user's
/// per-user compendium.  Source records that look like full
/// `Creature` entries (have `id` + timestamps) pass through;
/// entries that look like `CreatureDraft` (no id) get promoted via
/// `draft_to_creature`.  Ids that collide with the bundled set are
/// skipped — the bundle is read-only and shipped in the binary,
/// mirroring what `POST /api/compendium/import` does.
///
/// `--replace` swaps the user's creature list wholesale; otherwise
/// the import is additive (de-duplicated by `id` so a re-import of
/// the same file is idempotent).
async fn import(
  src: &Path,
  args: &DbArgs,
  email: &str,
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
    if let Ok(creatures) = serde_json::from_str::<Vec<Creature>>(&raw) {
      creatures
    } else {
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
    };

  let bundled =
    BundledCompendium::load().map_err(CompendiumCliError::BundledLoad)?;
  let before_bundled_filter = incoming.len();
  let incoming: Vec<Creature> = incoming
    .into_iter()
    .filter(|c| !bundled.contains(&c.id))
    .collect();
  let skipped_bundled = before_bundled_filter - incoming.len();

  let db = db::connect(args).await?;
  let user = db::user_by_email(&db, email).await?;
  let store = UserCompendiumStore::new(db);

  let (added, total) = if replace {
    let added = incoming.len();
    store
      .replace_for_user(&user.id, incoming)
      .await
      .map_err(CompendiumCliError::UserCreaturesWrite)?;
    (added, added)
  } else {
    let existing = store
      .list(&user.id)
      .await
      .map_err(CompendiumCliError::UserCreaturesRead)?;
    let mut added = 0usize;
    for creature in incoming {
      if existing.iter().any(|e| e.id == creature.id) {
        // Idempotent re-import — skip.
        continue;
      }
      store
        .insert_raw(&user.id, creature)
        .await
        .map_err(CompendiumCliError::UserCreaturesWrite)?;
      added += 1;
    }
    (added, existing.len() + added)
  };

  if skipped_bundled > 0 {
    println!(
      "Skipped {skipped_bundled} creatures whose ids belong to the \
       read-only bundled set."
    );
  }
  println!(
    "Imported {added} creatures into the compendium of {email} \
     (now {total} user-owned total)"
  );
  Ok(())
}
