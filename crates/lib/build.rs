//! Recompile this crate whenever the embedded migrations change.
//!
//! `sqlx::migrate!()` embeds the `migrations/` directory at compile
//! time, but cargo does not fingerprint that directory on its own —
//! without this hint, adding a migration file leaves stale build
//! artifacts (for some feature-unification variants) that silently
//! miss the new schema.

fn main() {
  println!("cargo:rerun-if-changed=migrations");
}
