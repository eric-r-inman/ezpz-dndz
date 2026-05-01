//! Saved-encounter CRUD + auto-snapshots.  *Stub.*
//!
//! Per OPTIMIZATION_AND_COMPLIANCE_PLAN Phase 7, this module
//! reserves the future-feature surface area:
//!
//! - HTTP routes (planned):
//!   - `GET    /api/me/encounters`           → Vec<EncounterSummary>
//!   - `POST   /api/me/encounters`           → Encounter
//!   - `GET    /api/me/encounters/:id`       → Encounter (full state)
//!   - `PUT    /api/me/encounters/:id`       → Encounter
//!   - `DELETE /api/me/encounters/:id`       → 204
//!   - `POST   /api/me/encounters/:id/snapshot`   → EncounterSnapshot
//!     (manual save point for undo)
//!   - `GET    /api/me/encounters/:id/snapshots`  → Vec<EncounterSnapshot>
//!
//! - Auto-snapshot policy: every Next Turn click debounced to one
//!   write per ~5 seconds, retained as a rolling window of the last
//!   20 plus all snapshots tagged `manual` or `undo_point`.
//!
//! - Wire format mirrors the existing `Encounter.elm` JSON shape:
//!   the saved state is whatever the frontend serializes for the
//!   live combat queue.  No re-modeling on the backend; the
//!   server is a thin storage layer until SQLite arrives.
//!
//! - Templates are a sibling concern (see `templates.rs` when it
//!   lands): a template is a list of `(creature_id, count,
//!   suggested_init_mod)` tuples, distinct from a saved
//!   encounter's full state.  Templates are shareable; saved
//!   encounters are private.
//!
//! Storage shape (until SQLite): `JsonFileStore<HashMap<EncounterId,
//! Encounter>>` per user under `<data_dir>/users/<user_id>/
//! encounters.json`, plus a sibling `snapshots/` directory.
