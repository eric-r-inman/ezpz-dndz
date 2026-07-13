//! Shared compendium types — `Creature` stat blocks plus the
//! supporting enums and sub-records.  Lives in the lib crate so
//! the server (HTTP wire format), the CLI (import / export
//! commands), and any future tooling all consume the same
//! definitions.
//!
//! Persistence and HTTP routes are not in this crate; they live
//! in `crates/server/src/compendium/` on top of the relational
//! [`Db`](crate::db::Db) handle from this crate's `db` module.

pub mod group;
pub mod open5e;
pub mod types;

pub use group::{Group, GroupDraft, GroupEntry, InitiativeMode, MinionType};
pub use types::*;

use serde::{Deserialize, Serialize};

/// Combined export bundle — what a "save my compendium" produces.
///
/// Wraps the shared bestiary (`creatures`) and the *caller's*
/// per-user groups (`groups`) into a single JSON object so a
/// device download / server snapshot / wholesale import round-
/// trips both halves of a user's compendium customization.
///
/// Backward compatibility on import: the server accepts either
/// this bundle shape OR a bare `Vec<Creature>` for older exports
/// (see `crates/server/src/compendium/mod.rs::import_compendium`).
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
pub struct CompendiumExport {
  #[serde(default)]
  pub creatures: Vec<Creature>,
  #[serde(default)]
  pub groups: Vec<Group>,
}
