//! Per-user UI preferences.  *Stub.*
//!
//! This module reserves the future-feature surface area for
//! storing the free-form `preferences` blob attached to each
//! `User`.  The frontend already has `Preferences.elm` shape; the
//! server-side endpoint just round-trips an opaque
//! `serde_json::Value`:
//!
//! ```jsonc
//! {
//!   "theme": "system | light | dark",
//!   "card_density": "compact | regular | spacious",
//!   "sound_enabled": true,
//!   "default_compendium_sort": "name | cr | recency",
//!   "auto_scroll_active_card": true,
//!   "auto_roll_initiative_on_add": true,
//!   "keyboard_shortcuts": { "next_turn": "n", "open_compendium": "/", ... }
//! }
//! ```
//!
//! - HTTP routes (planned):
//!   - `GET  /api/me/preferences`  → Preferences (the user's blob)
//!   - `PUT  /api/me/preferences`  → Preferences
//!
//! - Wire format: a single opaque `serde_json::Value` so adding new
//!   preferences doesn't require a server-side migration.  The
//!   frontend defines the shape; the server just round-trips it.
//!
//! Storage: stored as a `preferences` field on the `User` record
//! once the `users` module materializes.  Until then, frontend
//! state lives in localStorage and resets on logout.
