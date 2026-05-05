//! User identity + role management.  *Stub.*
//!
//! This module reserves the future-feature surface area:
//!
//! - First-login upsert keyed on the OIDC subject claim, materializing
//!   a `User` row with a stable internal UUID.
//! - Role enum (`Admin` / `Dm` / `Player`) + a `require_role(Admin)`
//!   middleware to gate compendium / encounter mutation routes.
//! - HTTP routes (planned):
//!   - `GET    /api/me/profile`     → User
//!   - `PUT    /api/me/profile`     → User (display_name only)
//!   - `GET    /api/admin/users`    → Vec<User>     (admin role)
//!   - `PUT    /api/admin/users/:id/role` → User    (admin role)
//!
//! Storage: initially `JsonFileStore<HashMap<UserId, User>>` under
//! `<data_dir>/users/users.json` (mirrors the dice + compendium
//! pattern); SQLite migration alongside encounter persistence.
//!
//! Until this is implemented, OIDC sessions still work (see
//! `crate::auth`) but the `/me` endpoint just echoes the subject
//! claim without a backing record.
