//! User accounts: types, password hashing, persistence.
//!
//! The user model is intentionally minimal: a stable `UserId` (UUID
//! v4), an email address used for login, an Argon2id password hash,
//! a free-form display name, and a creation timestamp.  Email +
//! password is the only auth mechanism today; OIDC-via-foundation is
//! left disabled for the homelab-friendly self-service flow.
//!
//! Storage lives in the relational `users` table — see `UserStore`
//! for the SQL layer.  The legacy `users.json` flat list is only
//! read once by the server's one-shot boot import.

mod store;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub use store::{insert_user, UserStore, UserStoreError};

/// Stable identifier for a user account.  The wire format is the
/// hyphenated UUID string; storing as a String keeps `JsonSchema`
/// derives clean and round-trips cleanly through axum extractors.
#[derive(
  Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema,
)]
#[serde(transparent)]
pub struct UserId(pub String);

impl UserId {
  pub fn new() -> Self {
    Self(Uuid::new_v4().to_string())
  }

  pub fn as_str(&self) -> &str {
    &self.0
  }
}

impl Default for UserId {
  fn default() -> Self {
    Self::new()
  }
}

impl std::fmt::Display for UserId {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    self.0.fmt(f)
  }
}

/// A user account record.
///
/// `password_hash` is an Argon2id PHC string — opaque to consumers.
/// `created_at` is a Unix epoch second; no timezone games, no
/// `chrono` dep.  `email` is unique within the store (enforced at
/// registration time).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
  pub id: UserId,
  pub email: String,
  pub password_hash: String,
  pub display_name: String,
  pub created_at: u64,
}

/// Public projection of a `User` — what we send back over the wire
/// to the frontend.  Drops the password hash; everything else is
/// safe to expose to the user themselves.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct UserPublic {
  pub id: String,
  pub email: String,
  pub display_name: String,
  pub created_at: u64,
}

impl From<&User> for UserPublic {
  fn from(u: &User) -> Self {
    Self {
      id: u.id.0.clone(),
      email: u.email.clone(),
      display_name: u.display_name.clone(),
      created_at: u.created_at,
    }
  }
}
