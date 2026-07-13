//! `UserStore` — SQL-backed persistence for `User` records.
//!
//! Wraps the shared [`Db`] handle with the operations that matter:
//! `register`, `authenticate`, `find_by_id`.  Email uniqueness rides
//! on the `users.email` UNIQUE constraint (backed up by mapping the
//! violation to `EmailTaken`), and password hashing lives here so the
//! HTTP handler stays the cheapest possible glue layer.

use argon2::{
  password_hash::{
    rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier,
    SaltString,
  },
  Argon2,
};
use sqlx::{any::AnyRow, AnyConnection, Row};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

use super::{User, UserId};
use crate::db::Db;

#[derive(Debug, Error)]
pub enum UserStoreError {
  #[error("Failed to query the user database: {0}")]
  Query(#[source] sqlx::Error),

  #[error("Failed to persist the user record: {0}")]
  Persist(#[source] sqlx::Error),

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
  db: Db,
}

impl UserStore {
  /// Wrap the shared database handle.  The schema is guaranteed by
  /// `Db::connect`, so construction itself cannot fail.
  pub fn new(db: Db) -> Self {
    Self { db }
  }

  /// Register a new user.  Validates input, ensures email uniqueness
  /// (case-insensitive via lowercasing on the way in), hashes the
  /// password with Argon2id, and persists the new record.  Returns
  /// the inserted `User` so the caller can drop them straight into a
  /// session.
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

    let user = User {
      id: UserId::new(),
      email,
      password_hash: hash_password(password)?,
      display_name,
      created_at: now_secs(),
    };

    let mut conn = self
      .db
      .pool()
      .acquire()
      .await
      .map_err(UserStoreError::Query)?;
    insert_user(&mut conn, &user).await.map_err(|e| {
      if is_unique_violation(&e) {
        UserStoreError::EmailTaken
      } else {
        UserStoreError::Persist(e)
      }
    })?;
    Ok(user)
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
    let user = self
      .find_by_email(email)
      .await?
      .ok_or(UserStoreError::InvalidCredentials)?;
    verify_password(password, &user.password_hash)?;
    Ok(user)
  }

  /// Look up a user by id.  Used by the session-auth middleware to
  /// rehydrate a fresh `User` on every request.
  pub async fn find_by_id(
    &self,
    id: &UserId,
  ) -> Result<Option<User>, UserStoreError> {
    sqlx::query(
      "SELECT id, email, password_hash, display_name, created_at \
       FROM users WHERE id = $1",
    )
    .bind(id.as_str())
    .fetch_optional(self.db.pool())
    .await
    .map_err(UserStoreError::Query)?
    .map(|row| user_from_row(&row))
    .transpose()
    .map_err(UserStoreError::Query)
  }

  /// Look up a user by email address (case-insensitive, trimmed).
  /// Used by the compendium-split migration at boot to resolve the
  /// `--compendium-claim-user <email>` flag into a `UserId`.  Not
  /// suitable for authentication — there's no password check; use
  /// [`Self::authenticate`] for that.
  pub async fn find_by_email(
    &self,
    email: &str,
  ) -> Result<Option<User>, UserStoreError> {
    sqlx::query(
      "SELECT id, email, password_hash, display_name, created_at \
       FROM users WHERE email = $1",
    )
    .bind(email.trim().to_lowercase())
    .fetch_optional(self.db.pool())
    .await
    .map_err(UserStoreError::Query)?
    .map(|row| user_from_row(&row))
    .transpose()
    .map_err(UserStoreError::Query)
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
    let user = self
      .find_by_id(id)
      .await?
      .ok_or(UserStoreError::InvalidCredentials)?;
    sqlx::query("UPDATE users SET display_name = $1 WHERE id = $2")
      .bind(&trimmed)
      .bind(id.as_str())
      .execute(self.db.pool())
      .await
      .map_err(UserStoreError::Persist)?;
    Ok(User {
      display_name: trimmed,
      ..user
    })
  }

  /// Admin-mediated password reset.  Skips the current-password
  /// check that [`Self::change_password`] enforces — intended for
  /// the CLI `users reset-password` subcommand, where the operator
  /// has direct access to the database and runs the binary as the
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
    let user = self
      .find_by_email(email)
      .await?
      .ok_or(UserStoreError::InvalidCredentials)?;
    let new_hash = hash_password(new_password)?;
    self.set_password_hash(&user.id, &new_hash).await?;
    Ok(User {
      password_hash: new_hash,
      ..user
    })
  }

  /// Verify the supplied `current_password` against the stored hash
  /// and, on success, replace the hash with a fresh Argon2id digest
  /// of `new_password`.  Returns `InvalidCredentials` for both "user
  /// missing" and "current password mismatch" so handlers can't leak
  /// account-existence by inspecting the error.
  pub async fn change_password(
    &self,
    id: &UserId,
    current_password: &str,
    new_password: &str,
  ) -> Result<(), UserStoreError> {
    if new_password.len() < MIN_PASSWORD_LEN {
      return Err(UserStoreError::PasswordTooShort);
    }
    // Verify against the current hash BEFORE we touch anything in
    // the database — defence-in-depth against accidentally
    // clobbering an account when the wrong password is supplied.
    let user = self
      .find_by_id(id)
      .await?
      .ok_or(UserStoreError::InvalidCredentials)?;
    verify_password(current_password, &user.password_hash)?;

    let new_hash = hash_password(new_password)?;
    self.set_password_hash(id, &new_hash).await
  }

  /// Write a new password hash for `id`.  Maps "no row updated" to
  /// `InvalidCredentials` to match the lookup paths.
  async fn set_password_hash(
    &self,
    id: &UserId,
    new_hash: &str,
  ) -> Result<(), UserStoreError> {
    let updated =
      sqlx::query("UPDATE users SET password_hash = $1 WHERE id = $2")
        .bind(new_hash)
        .bind(id.as_str())
        .execute(self.db.pool())
        .await
        .map_err(UserStoreError::Persist)?;
    if updated.rows_affected() == 0 {
      return Err(UserStoreError::InvalidCredentials);
    }
    Ok(())
  }
}

/// Insert a fully-formed `User` row.  Shared by `register` and the
/// server's one-shot JSON import, which replays legacy records inside
/// its own transaction — hence the bare connection parameter rather
/// than a pool.
pub async fn insert_user(
  conn: &mut AnyConnection,
  user: &User,
) -> Result<(), sqlx::Error> {
  sqlx::query(
    "INSERT INTO users (id, email, password_hash, display_name, \
     created_at) VALUES ($1, $2, $3, $4, $5)",
  )
  .bind(user.id.as_str())
  .bind(&user.email)
  .bind(&user.password_hash)
  .bind(&user.display_name)
  .bind(i64::try_from(user.created_at).unwrap_or(i64::MAX))
  .execute(&mut *conn)
  .await
  .map(|_| ())
}

fn user_from_row(row: &AnyRow) -> Result<User, sqlx::Error> {
  Ok(User {
    id: UserId(row.try_get::<String, _>("id")?),
    email: row.try_get("email")?,
    password_hash: row.try_get("password_hash")?,
    display_name: row.try_get("display_name")?,
    created_at: u64::try_from(row.try_get::<i64, _>("created_at")?)
      .unwrap_or(0),
  })
}

/// Whether `e` is a UNIQUE-constraint violation, reported natively by
/// either backend through the `Any` driver.  The only UNIQUE surface
/// on `users` besides the UUID primary key is `email`, so this maps
/// cleanly to `EmailTaken`.
fn is_unique_violation(e: &sqlx::Error) -> bool {
  e.as_database_error()
    .is_some_and(|db_err| db_err.is_unique_violation())
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

#[cfg(test)]
mod tests {
  use super::*;
  use crate::db::default_sqlite_url;
  use tempfile::TempDir;

  async fn store() -> (TempDir, UserStore) {
    let dir = TempDir::new().unwrap();
    let db = Db::connect(&default_sqlite_url(dir.path()))
      .await
      .expect("connect");
    (dir, UserStore::new(db))
  }

  #[tokio::test]
  async fn register_then_authenticate_round_trips() {
    let (_dir, store) = store().await;
    let created = store
      .register("Alice@Example.com ", "hunter2hunter", " Alice ")
      .await
      .expect("register");
    assert_eq!(created.email, "alice@example.com");
    assert_eq!(created.display_name, "Alice");

    let authed = store
      .authenticate("alice@example.com", "hunter2hunter")
      .await
      .expect("authenticate");
    assert_eq!(authed.id, created.id);
  }

  #[tokio::test]
  async fn duplicate_email_is_rejected() {
    let (_dir, store) = store().await;
    store
      .register("alice@example.com", "hunter2hunter", "Alice")
      .await
      .expect("first registration");
    let second = store
      .register("alice@example.com", "hunter2hunter", "Alice Again")
      .await;
    assert!(matches!(second, Err(UserStoreError::EmailTaken)));
  }

  #[tokio::test]
  async fn wrong_password_is_invalid_credentials() {
    let (_dir, store) = store().await;
    store
      .register("alice@example.com", "hunter2hunter", "Alice")
      .await
      .expect("register");
    let bad = store.authenticate("alice@example.com", "wrong-pass").await;
    assert!(matches!(bad, Err(UserStoreError::InvalidCredentials)));
  }

  #[tokio::test]
  async fn admin_reset_password_changes_the_hash() {
    let (_dir, store) = store().await;
    store
      .register("alice@example.com", "hunter2hunter", "Alice")
      .await
      .expect("register");
    store
      .admin_reset_password("alice@example.com", "newpassword9")
      .await
      .expect("reset");
    assert!(store
      .authenticate("alice@example.com", "hunter2hunter")
      .await
      .is_err());
    store
      .authenticate("alice@example.com", "newpassword9")
      .await
      .expect("authenticate with the new password");
  }

  #[tokio::test]
  async fn find_by_id_and_email_return_none_for_missing_users() {
    let (_dir, store) = store().await;
    assert!(store
      .find_by_id(&UserId::new())
      .await
      .expect("query")
      .is_none());
    assert!(store
      .find_by_email("ghost@example.com")
      .await
      .expect("query")
      .is_none());
  }

  #[tokio::test]
  async fn change_password_requires_the_current_password() {
    let (_dir, store) = store().await;
    let user = store
      .register("alice@example.com", "hunter2hunter", "Alice")
      .await
      .expect("register");
    let bad = store
      .change_password(&user.id, "not-the-password", "newpassword9")
      .await;
    assert!(matches!(bad, Err(UserStoreError::InvalidCredentials)));

    store
      .change_password(&user.id, "hunter2hunter", "newpassword9")
      .await
      .expect("change password");
    store
      .authenticate("alice@example.com", "newpassword9")
      .await
      .expect("authenticate with the new password");
  }
}
