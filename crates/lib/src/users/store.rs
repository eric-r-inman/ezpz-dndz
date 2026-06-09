//! `UserStore` — persistent backing for `User` records.
//!
//! Wraps `JsonFileStore<Vec<User>>` with the operations that matter:
//! `register`, `authenticate`, `find_by_id`.  Email uniqueness and
//! password hashing both live here so the HTTP handler is the
//! cheapest possible glue layer.

use argon2::{
  password_hash::{
    rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier,
    SaltString,
  },
  Argon2,
};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

use super::{User, UserId};
use crate::json_file_store::{JsonFileStore, JsonFileStoreError};

#[derive(Debug, Error)]
pub enum UserStoreError {
  #[error("Failed to load user store: {0}")]
  StoreLoad(#[source] JsonFileStoreError),

  #[error("Failed to persist user store: {0}")]
  StorePersist(#[source] JsonFileStoreError),

  #[error("Email is already registered")]
  EmailTaken,

  #[error("Invalid email or password")]
  InvalidCredentials,

  #[error("Password must be at least 8 characters")]
  PasswordTooShort,

  #[error("Email must look like an email address")]
  EmailInvalid,

  #[error("Display name must not be empty")]
  DisplayNameEmpty,

  #[error("Password hashing failed: {0}")]
  Hash(String),
}

/// Lower bound on password length.  No further complexity rules —
/// that's a battle better fought with a passphrase mindset than with
/// arbitrary character-class checks.
pub const MIN_PASSWORD_LEN: usize = 8;

pub struct UserStore {
  inner: JsonFileStore<Vec<User>>,
}

impl UserStore {
  pub async fn load_or_default(path: PathBuf) -> Result<Self, UserStoreError> {
    let inner = JsonFileStore::load_or_default(path)
      .await
      .map_err(UserStoreError::StoreLoad)?;
    Ok(Self { inner })
  }

  /// Register a new user.  Validates input, ensures email uniqueness
  /// (case-insensitive), hashes the password with Argon2id, and
  /// persists the new record.  Returns the inserted `User` so the
  /// caller can drop them straight into a session.
  pub async fn register(
    &self,
    email: &str,
    password: &str,
    display_name: &str,
  ) -> Result<User, UserStoreError> {
    let email = email.trim().to_lowercase();
    let display_name = display_name.trim().to_string();

    if !is_email_shape(&email) {
      return Err(UserStoreError::EmailInvalid);
    }
    if display_name.is_empty() {
      return Err(UserStoreError::DisplayNameEmpty);
    }
    if password.len() < MIN_PASSWORD_LEN {
      return Err(UserStoreError::PasswordTooShort);
    }

    let password_hash = hash_password(password)?;
    let user = User {
      id: UserId::new(),
      email,
      password_hash,
      display_name,
      created_at: now_secs(),
    };

    let inserted = self
      .inner
      .mutate(|users| {
        if users.iter().any(|u| u.email == user.email) {
          Err(UserStoreError::EmailTaken)
        } else {
          users.push(user.clone());
          Ok(user)
        }
      })
      .await
      .map_err(UserStoreError::StorePersist)?;

    inserted
  }

  /// Verify credentials and return the matching `User`.  Returns
  /// `InvalidCredentials` for both "no such email" and "wrong
  /// password" — the caller MUST NOT distinguish the two in HTTP
  /// responses (account-enumeration prevention).
  pub async fn authenticate(
    &self,
    email: &str,
    password: &str,
  ) -> Result<User, UserStoreError> {
    let email = email.trim().to_lowercase();
    let users = self.inner.read().await;
    let user = users
      .into_iter()
      .find(|u| u.email == email)
      .ok_or(UserStoreError::InvalidCredentials)?;

    verify_password(password, &user.password_hash)?;
    Ok(user)
  }

  /// Look up a user by id.  Used by the session-auth middleware to
  /// rehydrate a fresh `User` on every request.
  pub async fn find_by_id(&self, id: &UserId) -> Option<User> {
    self.inner.read().await.into_iter().find(|u| &u.id == id)
  }

  /// Set the display name on an existing user.  Trims and rejects
  /// empty input.  Returns the updated `User` so the caller can
  /// respond without re-fetching.
  pub async fn update_display_name(
    &self,
    id: &UserId,
    new_display_name: &str,
  ) -> Result<User, UserStoreError> {
    let trimmed = new_display_name.trim().to_string();
    if trimmed.is_empty() {
      return Err(UserStoreError::DisplayNameEmpty);
    }
    let id_owned = id.clone();
    let updated = self
      .inner
      .mutate(move |users| match users.iter_mut().find(|u| u.id == id_owned) {
        Some(slot) => {
          slot.display_name = trimmed;
          Ok(slot.clone())
        }
        None => Err(UserStoreError::InvalidCredentials),
      })
      .await
      .map_err(UserStoreError::StorePersist)?;
    updated
  }

  /// Verify the supplied `current_password` against the stored hash
  /// and, on success, replace the hash with a fresh Argon2id digest
  /// of `new_password`.  Returns `InvalidCredentials` for both "user
  /// missing" and "current password mismatch" so handlers can't leak
  /// account-existence by inspecting the error.
  /// Admin-mediated password reset.  Skips the current-password
  /// check that [`Self::change_password`] enforces — intended for
  /// the CLI `users reset-password` subcommand, where the
  /// operator has direct disk access and runs the binary as the
  /// service account.
  ///
  /// Looks the user up by email (case-insensitive, trimmed) and
  /// returns the user record so the CLI can print "reset password
  /// for {display_name}" as confirmation.  Returns
  /// `InvalidCredentials` when no matching email exists so the
  /// error vocabulary stays uniform across all lookup paths.
  pub async fn admin_reset_password(
    &self,
    email: &str,
    new_password: &str,
  ) -> Result<User, UserStoreError> {
    if new_password.len() < MIN_PASSWORD_LEN {
      return Err(UserStoreError::PasswordTooShort);
    }
    let normalized = email.trim().to_lowercase();
    let user = self
      .inner
      .read()
      .await
      .into_iter()
      .find(|u| u.email == normalized)
      .ok_or(UserStoreError::InvalidCredentials)?;
    let new_hash = hash_password(new_password)?;
    let user_id = user.id.clone();
    self
      .inner
      .mutate(move |users| match users.iter_mut().find(|u| u.id == user_id) {
        Some(slot) => {
          slot.password_hash = new_hash;
          Ok(())
        }
        None => Err(UserStoreError::InvalidCredentials),
      })
      .await
      .map_err(UserStoreError::StorePersist)??;
    Ok(user)
  }

  pub async fn change_password(
    &self,
    id: &UserId,
    current_password: &str,
    new_password: &str,
  ) -> Result<(), UserStoreError> {
    if new_password.len() < MIN_PASSWORD_LEN {
      return Err(UserStoreError::PasswordTooShort);
    }
    // Verify against the current hash BEFORE we touch anything on
    // disk — defence-in-depth against accidentally clobbering an
    // account when the wrong password is supplied.
    let user = self
      .find_by_id(id)
      .await
      .ok_or(UserStoreError::InvalidCredentials)?;
    verify_password(current_password, &user.password_hash)?;

    let new_hash = hash_password(new_password)?;
    let id_owned = id.clone();
    self
      .inner
      .mutate(move |users| match users.iter_mut().find(|u| u.id == id_owned) {
        Some(slot) => {
          slot.password_hash = new_hash;
          Ok(())
        }
        None => Err(UserStoreError::InvalidCredentials),
      })
      .await
      .map_err(UserStoreError::StorePersist)?
  }
}

/// Argon2id with the crate's recommended defaults.  Output is a
/// PHC-format string that stores algorithm, parameters, salt, and
/// hash all in one — `verify_password` handles the round-trip.
fn hash_password(password: &str) -> Result<String, UserStoreError> {
  let salt = SaltString::generate(&mut OsRng);
  Argon2::default()
    .hash_password(password.as_bytes(), &salt)
    .map(|h| h.to_string())
    .map_err(|e| UserStoreError::Hash(e.to_string()))
}

fn verify_password(password: &str, phc: &str) -> Result<(), UserStoreError> {
  let parsed =
    PasswordHash::new(phc).map_err(|_| UserStoreError::InvalidCredentials)?;
  Argon2::default()
    .verify_password(password.as_bytes(), &parsed)
    .map_err(|_| UserStoreError::InvalidCredentials)
}

/// Cheap email shape check: must contain a single `@`, no
/// whitespace, and at least one character either side.  Full RFC
/// 5322 validation is a famous tar pit and not worth the dependency
/// for our purposes.
fn is_email_shape(email: &str) -> bool {
  if email.chars().any(char::is_whitespace) {
    return false;
  }
  let mut parts = email.splitn(2, '@');
  match (parts.next(), parts.next(), parts.next()) {
    (Some(local), Some(domain), None) => {
      !local.is_empty() && !domain.is_empty() && domain.contains('.')
    }
    _ => false,
  }
}

fn now_secs() -> u64 {
  SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map(|d| d.as_secs())
    .unwrap_or(0)
}
