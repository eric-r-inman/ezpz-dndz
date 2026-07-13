//! Integration tests for the relational-storage migration (phase 1):
//! the one-shot users + dice-history JSON import, the byte-level
//! dice round-trip against the Elm wire shape, and the per-user cap
//! eviction now implemented in SQL.

// File-scoped overrides: `allow-expect-in-tests` covers items inside
// `#[test]` / `#[cfg(test)]`, but the helpers below sit at crate
// scope.  Test failure via panic is the desired signal here.
#![allow(clippy::expect_used, clippy::unwrap_used)]

use aide::axum::ApiRouter;
use argon2::{
  password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
  Argon2,
};
use axum::{
  body::Body,
  http::{Request, StatusCode},
  middleware, Router,
};
use ezpz_dndz_lib::db::{default_sqlite_url, Db};
use ezpz_dndz_server::{
  compendium, config::RuntimePaths, dice, encounters, per_user_store, users,
  web_base::AppState,
};
use rust_template_foundation::server::runner::{
  BaseServerState, ServerRunConfig,
};
use rust_template_foundation::Server;
use serde_json::{json, Value};
use tempfile::TempDir;
use tokio_listener::ListenerAddress;
use tower::ServiceExt;

/// Build an `AppState` over an EXISTING data dir so tests can drop
/// legacy JSON fixtures in place before the boot-time import runs.
async fn app_state_for_dir(dir: &TempDir) -> AppState {
  let paths = RuntimePaths::from_data_dir(dir.path());
  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };
  let base = BaseServerState::init(&run_config)
    .await
    .expect("base server state");
  let db = Db::connect(&default_sqlite_url(dir.path()))
    .await
    .expect("test database");
  AppState::assemble(base, db, &paths, None)
    .await
    .expect("app state assemble")
}

fn build_test_router(state: AppState) -> Router {
  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };

  let auth_state = state.clone();
  let protected: ApiRouter<AppState> = ApiRouter::new()
    .merge(dice::router())
    .merge(compendium::router())
    .merge(encounters::router())
    .merge(per_user_store::routers(&state))
    .layer(middleware::from_fn_with_state(auth_state, users::require_auth));

  let users_state = state.clone();
  Server::new(state.base.clone(), run_config)
    .with_state(move |_base| state)
    .merge(users::router(users_state))
    .merge(protected)
    .into_test_router()
}

fn extract_session_cookie(
  response: &axum::response::Response,
) -> Option<String> {
  response
    .headers()
    .get_all(axum::http::header::SET_COOKIE)
    .iter()
    .filter_map(|v| v.to_str().ok())
    .find_map(|raw| {
      raw
        .split(';')
        .next()
        .and_then(|first| first.trim().strip_prefix("id=").map(str::to_string))
        .map(|val| format!("id={val}"))
    })
}

async fn read_body(response: axum::response::Response) -> String {
  let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .expect("read body");
  String::from_utf8(bytes.to_vec()).expect("utf-8 body")
}

async fn register_and_get_cookie(app: &Router) -> String {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"alice@example.com","password":"hunter2hunter","display_name":"Alice"}"#,
        ))
        .unwrap(),
    )
    .await
    .expect("register request");
  assert_eq!(response.status(), StatusCode::CREATED);
  extract_session_cookie(&response).expect("session cookie on register")
}

async fn post_roll(app: &Router, cookie: &str, payload: &Value) -> StatusCode {
  app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/dice/history")
        .header("content-type", "application/json")
        .header("cookie", cookie)
        .body(Body::from(payload.to_string()))
        .unwrap(),
    )
    .await
    .unwrap()
    .status()
}

async fn get_history(app: &Router, cookie: &str) -> Vec<Value> {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/dice/history")
        .header("cookie", cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK);
  serde_json::from_str(&read_body(response).await).expect("history JSON")
}

/// A full-shape roll exactly as `Dice.encodeRoll` emits it (field
/// set copied from frontend/src/Dice.elm).
fn elm_shaped_roll(total: i64, timestamp: i64) -> Value {
  json!({
    "kind": "standard",
    "formula": "3d6 Radiant",
    "total": total,
    "timestamp": timestamp,
    "expression": {
      "dice": [ { "count": 3, "faces": 6, "sign": "positive" } ],
      "constant": 0,
      "damageType": "Radiant"
    },
    "groups": [
      {
        "dice": { "count": 3, "faces": 6, "sign": "positive" },
        "rolled": [
          { "face": 1, "kept": true },
          { "face": 3, "kept": true },
          { "face": 6, "kept": true }
        ],
        "subtotal": 10
      }
    ],
    "source": { "feature": "Damage", "target": "Goblin" }
  })
}

// ── dice wire round-trip ────────────────────────────────────────────────────

#[tokio::test]
async fn test_dice_elm_shaped_roll_round_trips_exactly() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = elm_shaped_roll(11, 1714502400000);
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let history = get_history(&app, &cookie).await;
  assert_eq!(history.len(), 1);
  assert_eq!(
    history[0], roll,
    "GET must return exactly the JSON that was POSTed"
  );
}

#[tokio::test]
async fn test_dice_advantage_roll_with_nulls_round_trips_exactly() {
  // Advantage roll: dropped die (kept: false), null damageType and
  // null target — the fields the Elm decoder requires to be present
  // as literal null rather than absent.
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = json!({
    "kind": "advantage",
    "formula": "1d20+5",
    "total": 23,
    "timestamp": 1714502500000i64,
    "expression": {
      "dice": [ { "count": 1, "faces": 20, "sign": "positive" } ],
      "constant": 5,
      "damageType": null
    },
    "groups": [
      {
        "dice": { "count": 2, "faces": 20, "sign": "positive" },
        "rolled": [
          { "face": 18, "kept": true },
          { "face": 4, "kept": false }
        ],
        "subtotal": 18
      }
    ],
    "source": { "feature": "Attack", "target": null }
  });
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let history = get_history(&app, &cookie).await;
  assert_eq!(history.len(), 1);
  assert_eq!(history[0], roll);
}

#[tokio::test]
async fn test_dice_cap_evicts_oldest_beyond_max_entries() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let n = dice::MAX_ENTRIES + 5;
  for i in 0..n {
    let mut roll = elm_shaped_roll(i as i64, 1714502400000 + i as i64);
    // A scalar extra field, like the legacy opaque contract allowed;
    // also serves as the marker for eviction-order assertions.
    roll["id"] = json!(i);
    assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);
  }

  let history = get_history(&app, &cookie).await;
  assert_eq!(
    history.len(),
    dice::MAX_ENTRIES,
    "history must be capped at MAX_ENTRIES"
  );
  let ids: Vec<i64> = history
    .iter()
    .map(|e| e["id"].as_i64().expect("id extra"))
    .collect();
  let expected: Vec<i64> = (5..n as i64).rev().collect();
  assert_eq!(
    ids, expected,
    "newest rolls first; the oldest five must have been evicted"
  );
}

#[tokio::test]
async fn test_dice_clear_empties_the_history() {
  let dir = TempDir::new().expect("tempdir");
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let roll = elm_shaped_roll(9, 1714502400000);
  assert_eq!(post_roll(&app, &cookie, &roll).await, StatusCode::OK);

  let delete = app
    .clone()
    .oneshot(
      Request::builder()
        .method("DELETE")
        .uri("/api/dice/history")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(delete.status(), StatusCode::NO_CONTENT);

  assert_eq!(get_history(&app, &cookie).await, Vec::<Value>::new());
}

// ── legacy JSON import ──────────────────────────────────────────────────────

fn argon2id_hash(password: &str) -> String {
  let salt = SaltString::generate(&mut OsRng);
  Argon2::default()
    .hash_password(password.as_bytes(), &salt)
    .expect("hash fixture password")
    .to_string()
}

/// Write the legacy users.json + dice-history.json fixtures in the
/// exact shapes the JsonFileStore-era server persisted.
fn write_legacy_fixtures(dir: &TempDir, user_id: &str) -> (Value, Value) {
  let users = json!([
    {
      "id": user_id,
      "email": "legacy@example.com",
      "password_hash": argon2id_hash("hunter2hunter"),
      "display_name": "Legacy",
      "created_at": 1700000000u64
    }
  ]);
  // Newest first, matching the on-disk order the old store kept.
  let newest = elm_shaped_roll(15, 1714502500000);
  let oldest = elm_shaped_roll(7, 1714502400000);
  let dice_history = json!({ user_id: [newest, oldest] });

  std::fs::write(
    dir.path().join("users.json"),
    serde_json::to_vec_pretty(&users).expect("encode users fixture"),
  )
  .expect("write users.json");
  std::fs::write(
    dir.path().join("dice-history.json"),
    serde_json::to_vec_pretty(&dice_history).expect("encode dice fixture"),
  )
  .expect("write dice-history.json");
  (users, dice_history)
}

#[tokio::test]
async fn test_json_import_users_and_dice_round_trip() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "07d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  let (_users, dice_history) = write_legacy_fixtures(&dir, user_id);

  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  // The imported account can log in with the original password.
  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");
  let login_body: Value =
    serde_json::from_str(&read_body(login).await).expect("login body");
  assert_eq!(login_body["id"], user_id);
  assert_eq!(login_body["display_name"], "Legacy");
  assert_eq!(login_body["created_at"], 1700000000u64);

  // The imported dice history reads back identically, newest first.
  let history = get_history(&app, &cookie).await;
  assert_eq!(
    Value::Array(history),
    dice_history[user_id],
    "imported dice history must match the legacy file exactly"
  );

  // The legacy files are left in place as the rollback copy.
  assert!(dir.path().join("users.json").exists());
  assert!(dir.path().join("dice-history.json").exists());
}

#[tokio::test]
async fn test_json_import_runs_only_once() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "17d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);

  // First boot imports; second boot must see the marker and leave
  // the database alone (no duplicate users or rolls).
  let _first = app_state_for_dir(&dir).await;
  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let cookie = extract_session_cookie(&login).expect("login cookie");
  assert_eq!(
    get_history(&app, &cookie).await.len(),
    2,
    "re-boot must not duplicate the imported rolls"
  );
}

#[tokio::test]
async fn test_json_import_preserves_duplicate_email_rejection() {
  let dir = TempDir::new().expect("tempdir");
  let user_id = "27d6a89a-9bb3-4b1b-87ef-6a12d6ce157c";
  write_legacy_fixtures(&dir, user_id);

  let state = app_state_for_dir(&dir).await;
  let app = build_test_router(state);

  // Registering the imported address must hit the UNIQUE constraint
  // and surface as the same 409 the JSON store produced.
  let conflict = app
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"legacy@example.com","password":"hunter2hunter","display_name":"Impostor"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(conflict.status(), StatusCode::CONFLICT);
}
