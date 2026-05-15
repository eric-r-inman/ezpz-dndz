//! Wire types for the creature-card-layout editor.
//!
//! The frontend's `Card.Layout` module owns the canonical
//! enumeration of widget kinds; the server treats a layout's
//! `body` as opaque JSON (`serde_json::Value`) so the schema
//! can evolve without a server migration every time the
//! `CardWidget` variant list changes.
//!
//! What the server DOES type-check is the wrapper: each saved
//! layout has a `name`, a `body` blob, and timestamps.  Names
//! are unique per-user; the body shape is whatever the frontend
//! posts.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// One named card-layout record as stored / returned by the
/// server.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct NamedCardLayout {
  pub name: String,
  pub body: Value,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Listing-row shape: just the metadata, no body.  Used by
/// `GET /api/card-layouts` so a user with many saved layouts
/// doesn't pay the body-transfer cost when they only want
/// names for a picker.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct NamedCardLayoutMeta {
  pub name: String,
  pub created_at: i64,
  pub updated_at: i64,
}

/// Wire body for the rename endpoint — mirrors `SavedCompendium`'s
/// `RenameBody`.
#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct RenameBody {
  pub new_name: String,
}
