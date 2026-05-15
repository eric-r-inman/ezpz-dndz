//! Shared compendium types — `Creature` stat blocks plus the
//! supporting enums and sub-records.  Lives in the lib crate so
//! the server (HTTP wire format), the CLI (import / export
//! commands), and any future tooling all consume the same
//! definitions.
//!
//! Persistence and HTTP routes are not in this crate; they live
//! in `crates/server/src/compendium.rs` on top of the shared
//! `JsonFileStore<Vec<Creature>>` from this crate's
//! `json_file_store` module.

pub mod group;
pub mod open5e;
pub mod types;

pub use group::{Group, GroupDraft, GroupEntry, InitiativeMode, MinionType};
pub use types::*;
