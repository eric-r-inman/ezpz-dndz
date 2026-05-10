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

use aide::axum::ApiRouter;
use axum::{
  body::Body,
  http::{Request, StatusCode},
  middleware, Router,
};
use ezpz_dndz_server::{
  compendium, config::RuntimePaths, dice, encounters, users, web_base::AppState,
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
    users: temp.path().join("users.json"),
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

  let auth_state = state.clone();
  let protected: ApiRouter<AppState> = ApiRouter::new()
    .merge(dice::router())
    .merge(compendium::router())
    .merge(encounters::router())
    .layer(middleware::from_fn_with_state(auth_state, users::require_auth));

  Server::new(state.base.clone(), run_config)
    .with_state(move |_base| state)
    .merge(users::router())
    .merge(protected)
    .into_test_router()
}

/// Register a default user and return the session cookie.  Used by
/// every app-route test that needs to be authenticated to even
/// reach the handler.
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
  let cookie = register_and_get_cookie(&app).await;

  let response = app
    .oneshot(
      Request::builder()
        .uri("/api/encounter")
        .header("cookie", &cookie)
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
  let cookie = register_and_get_cookie(&app).await;

  let payload = r#"{"creatures":[],"activeName":"Brakka","round":3}"#;

  let put_response = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/encounter")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
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
        .header("cookie", &cookie)
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
  let cookie = register_and_get_cookie(&app).await;

  let payload = r#"[{"id":"abc","name":"Goblin","cr":"1/4"}]"#;

  let put = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/My%20Bestiary")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
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
        .header("cookie", &cookie)
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
        .header("cookie", &cookie)
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
  let cookie = register_and_get_cookie(&app).await;

  let first = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/compendium/saves/dup")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
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
        .header("cookie", &cookie)
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
        .header("cookie", &cookie)
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
  let cookie = register_and_get_cookie(&app).await;
  let n_rolls = 20usize;

  let mut tasks = tokio::task::JoinSet::new();
  for i in 0..n_rolls {
    let app = app.clone();
    let cookie = cookie.clone();
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
            .header("cookie", cookie)
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

#[tokio::test]
async fn test_protected_route_without_session_is_unauthorized() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  // Same /api/encounter route the round-trip test hits, but without
  // a session cookie — the require_auth middleware should bounce
  // with 401 before the handler runs.
  let response = app
    .oneshot(
      Request::builder()
        .uri("/api/encounter")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── auth ────────────────────────────────────────────────────────────────────

/// Pull the `id` cookie value out of any `Set-Cookie` header(s) on
/// the response so a follow-up request can present it.  Real browsers
/// do this automatically; tests need to do it by hand.
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

#[tokio::test]
async fn test_auth_register_then_me_round_trip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let body = r#"{"email":"alice@example.com","password":"hunter2hunter","display_name":"Alice"}"#;
  let register = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(register.status(), StatusCode::CREATED);
  let cookie = extract_session_cookie(&register).expect("session cookie");
  let register_body = read_body(register).await;
  assert!(register_body.contains("\"email\":\"alice@example.com\""));
  assert!(
    !register_body.contains("password_hash"),
    "register response leaked password hash"
  );

  // Carry the cookie into a subsequent /me request.
  let me = app
    .oneshot(
      Request::builder()
        .uri("/api/auth/me")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(me.status(), StatusCode::OK);
  let me_body = read_body(me).await;
  assert!(me_body.contains("\"display_name\":\"Alice\""));
}

#[tokio::test]
async fn test_auth_me_without_session_is_unauthorized() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let me = app
    .oneshot(
      Request::builder()
        .uri("/api/auth/me")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(me.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_auth_login_after_logout_re_authenticates() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  // Register, logout, login again.
  let register = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"bob@example.com","password":"hunter2hunter","display_name":"Bob"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(register.status(), StatusCode::CREATED);
  let reg_cookie = extract_session_cookie(&register).expect("cookie");

  let logout = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/logout")
        .header("cookie", &reg_cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(logout.status(), StatusCode::NO_CONTENT);

  // /me with the now-flushed cookie returns 401.
  let me_after = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/auth/me")
        .header("cookie", &reg_cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(me_after.status(), StatusCode::UNAUTHORIZED);

  // Login establishes a fresh session.
  let login = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"bob@example.com","password":"hunter2hunter"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(login.status(), StatusCode::OK);
  let login_cookie = extract_session_cookie(&login).expect("login cookie");

  let me_again = app
    .oneshot(
      Request::builder()
        .uri("/api/auth/me")
        .header("cookie", &login_cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(me_again.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_auth_register_validation_errors() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let cases = [
    (
      r#"{"email":"alice@example.com","password":"short","display_name":"Alice"}"#,
      StatusCode::BAD_REQUEST,
    ),
    (
      r#"{"email":"not-an-email","password":"hunter2hunter","display_name":"Alice"}"#,
      StatusCode::BAD_REQUEST,
    ),
    (
      r#"{"email":"alice2@example.com","password":"hunter2hunter","display_name":""}"#,
      StatusCode::BAD_REQUEST,
    ),
  ];

  for (body, expected) in cases {
    let response = app
      .clone()
      .oneshot(
        Request::builder()
          .method("POST")
          .uri("/api/auth/register")
          .header("content-type", "application/json")
          .body(Body::from(body))
          .unwrap(),
      )
      .await
      .unwrap();
    assert_eq!(
      response.status(),
      expected,
      "unexpected status for body: {body}"
    );
  }
}

#[tokio::test]
async fn test_auth_duplicate_email_conflicts() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let body = r#"{"email":"alice@example.com","password":"hunter2hunter","display_name":"Alice"}"#;
  let first = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(first.status(), StatusCode::CREATED);

  let second = app
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(second.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn test_auth_wrong_password_unauthorized() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  app
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
    .unwrap();

  let bad_login = app
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
          r#"{"email":"alice@example.com","password":"wrongpassword"}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(bad_login.status(), StatusCode::UNAUTHORIZED);
}
