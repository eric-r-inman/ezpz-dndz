//! Integration tests for the ezpz-dndz application routes.
//!
//! Foundation-owned routes (healthz, metrics, /me, /api-docs, /scalar,
//! SPA fallback, OIDC handlers) are covered by the foundation crate's
//! own integration tests; this file keeps only the app-route coverage:
//! encounter PUT/GET round-trips, compendium-save persistence, and
//! dice-history concurrency.

// File-scoped overrides: `allow-expect-in-tests` covers items inside
// `#[test]` / `#[cfg(test)]`, but the helpers below sit at crate
// scope.  Test failure via panic is the desired signal here.
#![allow(clippy::expect_used, clippy::unwrap_used)]

use axum::{
  body::Body,
  http::{Request, StatusCode},
  Router,
};
use ezpz_dndz_server::{
  compendium, config::RuntimePaths, dice, encounters, web_base::AppState,
};
use rust_template_foundation::server::runner::{
  BaseServerState, ServerRunConfig,
};
use rust_template_foundation::Server;
use tempfile::TempDir;
use tokio_listener::ListenerAddress;
use tower::ServiceExt;

/// Build an `AppState` backed by fresh temp-dir paths and an
/// OIDC-less `BaseServerState`.  Returns the temp dir alongside so
/// the caller can keep it alive for the duration of the test.
async fn stub_app_state() -> (TempDir, AppState) {
  let temp = TempDir::new().expect("tempdir");
  let paths = RuntimePaths {
    dice_history: temp.path().join("dice-history.json"),
    compendium: temp.path().join("compendium.json"),
    compendium_saves: temp.path().join("compendium-saves.json"),
    encounter: temp.path().join("encounter.json"),
    encounter_saves: temp.path().join("encounter-saves.json"),
  };

  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    frontend_path: None,
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };

  let base = BaseServerState::init(&run_config)
    .await
    .expect("base server state");

  let state = AppState::assemble(base, &paths)
    .await
    .expect("app state assemble");

  (temp, state)
}

/// Build the test router used by every app-route test.
fn build_test_router(state: AppState) -> Router {
  // We need a ServerRunConfig for `Server::new`; reuse the same
  // shape as `stub_app_state`'s.  In test mode `with_state` just
  // returns the pre-built AppState we already assembled.
  let run_config = ServerRunConfig {
    app_name: "ezpz-dndz".to_string(),
    listen_address: "127.0.0.1:0"
      .parse::<ListenerAddress>()
      .expect("listen address"),
    frontend_path: None,
    base_url: "http://localhost:0".to_string(),
    oidc: None,
  };

  Server::new(state.base.clone(), run_config)
    .with_state(move |_base| state)
    .merge(dice::router())
    .merge(compendium::router())
    .merge(encounters::router())
    .into_test_router()
}

async fn read_body(response: axum::response::Response) -> String {
  let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .expect("read body");
  String::from_utf8(bytes.to_vec()).expect("utf-8 body")
}

// ── encounter ───────────────────────────────────────────────────────────────

#[tokio::test]
async fn test_encounter_get_returns_null_when_unset() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/api/encounter")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);
  let body = read_body(response).await;
  // Default is `serde_json::Value::Null`, which serialises as
  // literal "null" — the frontend reads that as "use the empty
  // default" rather than failing on boot.
  assert_eq!(body.trim(), "null");
}

#[tokio::test]
async fn test_encounter_put_then_get_roundtrip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let payload = r#"{"creatures":[],"activeName":"Brakka","round":3}"#;

  let put_response = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/encounter")
        .header("content-type", "application/json")
        .body(Body::from(payload))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(put_response.status(), StatusCode::OK);

  let get_response = app
    .oneshot(
      Request::builder()
        .uri("/api/encounter")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(get_response.status(), StatusCode::OK);

  let body = read_body(get_response).await;
  assert!(
    body.contains("\"activeName\":\"Brakka\""),
    "expected PUT body to round-trip, got: {body}"
  );
  assert!(
    body.contains("\"round\":3"),
    "expected PUT body to round-trip, got: {body}"
  );
}

// ── compendium-save ─────────────────────────────────────────────────────────

#[tokio::test]
async fn test_compendium_save_create_list_get_roundtrip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let payload = r#"[{"id":"abc","name":"Goblin","cr":"1/4"}]"#;

  let put = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/My%20Bestiary")
        .header("content-type", "application/json")
        .body(Body::from(payload))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(put.status(), StatusCode::OK);

  let list = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/compendium/saves")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(list.status(), StatusCode::OK);
  let list_body = read_body(list).await;
  assert!(
    list_body.contains("\"name\":\"My Bestiary\""),
    "expected listing to include the new save, got: {list_body}"
  );

  let get = app
    .oneshot(
      Request::builder()
        .uri("/api/compendium/saves/My%20Bestiary")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(get.status(), StatusCode::OK);
  let get_body = read_body(get).await;
  assert!(
    get_body.contains("\"name\":\"Goblin\""),
    "expected creature payload, got: {get_body}"
  );
}

#[tokio::test]
async fn test_compendium_save_overwrite_conflicts_without_flag() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let first = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/dup")
        .header("content-type", "application/json")
        .body(Body::from(r#"[]"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(first.status(), StatusCode::OK);

  let second = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/dup")
        .header("content-type", "application/json")
        .body(Body::from(r#"[]"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(second.status(), StatusCode::CONFLICT);

  // Same call with `?overwrite=true` succeeds.
  let third = app
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/dup?overwrite=true")
        .header("content-type", "application/json")
        .body(Body::from(r#"[]"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(third.status(), StatusCode::OK);
}

// ── dice ────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn test_dice_history_concurrent_appends_lose_nothing() {
  // 20 concurrent POSTs each with a unique roll id; every one
  // should land in the file (under the 30-entry MAX cap), and
  // every id should appear exactly once.
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state.clone());
  let n_rolls = 20usize;

  let mut tasks = tokio::task::JoinSet::new();
  for i in 0..n_rolls {
    let app = app.clone();
    tasks.spawn(async move {
      let payload = format!(
        r#"{{"id":{i},"feature":"Test","total":{i},"expression":{{"dice":[],"constant":0,"damageType":null}},"groups":[],"formula":"1d20","kind":"standard","source":{{"feature":"Test","target":null}}}}"#
      );
      let response = app
        .oneshot(
          Request::builder()
            .method("POST")
            .uri("/api/dice/history")
            .header("content-type", "application/json")
            .body(Body::from(payload))
            .unwrap(),
        )
        .await
        .unwrap();
      assert_eq!(
        response.status(),
        StatusCode::OK,
        "expected POST to succeed for roll {i}"
      );
    });
  }
  while let Some(res) = tasks.join_next().await {
    res.expect("spawned task panicked");
  }

  // Read the persisted history back through the in-memory store
  // (the file is auto-flushed on every mutate).
  let entries = state.dice_store.load().await;
  assert_eq!(
    entries.len(),
    n_rolls,
    "expected exactly {n_rolls} entries after concurrent POSTs, got {}",
    entries.len()
  );

  let mut ids: Vec<i64> = entries
    .iter()
    .filter_map(|v| v.get("id").and_then(|x| x.as_i64()))
    .collect();
  ids.sort();
  let expected: Vec<i64> = (0..n_rolls as i64).collect();
  assert_eq!(
    ids, expected,
    "expected every roll id 0..{n_rolls} to appear exactly once, got {ids:?}"
  );
}
