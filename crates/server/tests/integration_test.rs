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
  card_editor, compendium, condition_presets, config::RuntimePaths, dice,
  encounters, lore_groups, users, web_base::AppState,
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
    compendium_groups: temp.path().join("compendium-groups.json"),
    user_creatures: temp.path().join("user-creatures.json"),
    card_layouts: temp.path().join("card-layouts.json"),
    encounter: temp.path().join("encounter.json"),
    encounter_saves: temp.path().join("encounter-saves.json"),
    users: temp.path().join("users.json"),
    lore_groups: temp.path().join("lore-groups.json"),
    condition_presets: temp.path().join("condition-presets.json"),
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

  let state = AppState::assemble(base, &paths, None)
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
    .merge(card_editor::router())
    .merge(encounters::router())
    .merge(lore_groups::router())
    .merge(condition_presets::router())
    .layer(middleware::from_fn_with_state(auth_state, users::require_auth));

  let users_state = state.clone();
  Server::new(state.base.clone(), run_config)
    .with_state(move |_base| state)
    .merge(users::router(users_state))
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
  let app = build_test_router(state);
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

  // Read the persisted history back via the HTTP API as the same
  // user — exercises the per-user filter rather than peeking at
  // the underlying map directly.
  let history_response = app
    .oneshot(
      Request::builder()
        .uri("/api/dice/history")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(history_response.status(), StatusCode::OK);
  let body = read_body(history_response).await;
  let entries: Vec<serde_json::Value> =
    serde_json::from_str(&body).expect("history is JSON array");
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

/// Variant of `register_and_get_cookie` that takes the email +
/// display name explicitly so a single test can produce multiple
/// independent sessions for cross-user isolation checks.
async fn register_user(
  app: &Router,
  email: &str,
  display_name: &str,
) -> String {
  let body = format!(
    r#"{{"email":"{email}","password":"hunter2hunter","display_name":"{display_name}"}}"#
  );
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
    .expect("register");
  assert_eq!(response.status(), StatusCode::CREATED);
  extract_session_cookie(&response).expect("cookie")
}

#[tokio::test]
async fn test_per_user_isolation_for_saved_encounters() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let alice = register_user(&app, "alice@example.com", "Alice").await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  // Alice creates a save.
  let alice_put = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/encounter/saves/Goblins")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(r#"{"creatures":[]}"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(alice_put.status(), StatusCode::OK);

  // Bob lists his saves — should be empty.
  let bob_list = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/encounter/saves")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(bob_list.status(), StatusCode::OK);
  let bob_body = read_body(bob_list).await;
  assert_eq!(
    bob_body.trim(),
    "[]",
    "Bob should not see Alice's saves; got: {bob_body}"
  );

  // Bob also tries to fetch Alice's save by name — must 404.
  let bob_get = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/encounter/saves/Goblins")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(bob_get.status(), StatusCode::NOT_FOUND);

  // Bob can save under the same name without a conflict — saves
  // are per-user.
  let bob_put = app
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/encounter/saves/Goblins")
        .header("content-type", "application/json")
        .header("cookie", &bob)
        .body(Body::from(r#"{"creatures":[]}"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(bob_put.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_per_user_isolation_for_live_encounter() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let alice = register_user(&app, "alice@example.com", "Alice").await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  // Alice posts an encounter.
  app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/encounter")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(r#"{"activeName":"Alice","round":1}"#))
        .unwrap(),
    )
    .await
    .unwrap();

  // Bob reads — should be null (his own encounter, not Alice's).
  let bob_get = app
    .oneshot(
      Request::builder()
        .uri("/api/encounter")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  let body = read_body(bob_get).await;
  assert_eq!(
    body.trim(),
    "null",
    "Bob should see his own (empty) encounter, not Alice's; got: {body}"
  );
}

#[tokio::test]
async fn test_per_user_isolation_for_dice_history() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let alice = register_user(&app, "alice@example.com", "Alice").await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  // Alice posts one roll.
  app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/dice/history")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(
          r#"{"id":1,"feature":"Test","total":17,"expression":{"dice":[],"constant":0,"damageType":null},"groups":[],"formula":"1d20","kind":"standard","source":{"feature":"Test","target":null}}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();

  // Bob lists his history — should be empty.
  let bob_history = app
    .oneshot(
      Request::builder()
        .uri("/api/dice/history")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(bob_history.status(), StatusCode::OK);
  let body = read_body(bob_history).await;
  assert_eq!(
    body.trim(),
    "[]",
    "Bob should not see Alice's rolls; got: {body}"
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
async fn test_auth_login_rate_limit_returns_429_after_threshold() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  // The limiter caps attempts at MAX_ATTEMPTS_PER_WINDOW (10) per
  // 60-second window.  Every call uses the DIRECT_FALLBACK_IP
  // bucket because the test harness doesn't set X-Forwarded-For,
  // so all attempts share a single bucket and the 11th must 429.
  let body = r#"{"email":"alice@example.com","password":"wrongpassword"}"#;

  // The first 10 attempts go through (and return 401 for bad
  // credentials — the limiter doesn't care about the status,
  // only that the request reached the handler).
  for i in 0..10 {
    let response = app
      .clone()
      .oneshot(
        Request::builder()
          .method("POST")
          .uri("/api/auth/login")
          .header("content-type", "application/json")
          .body(Body::from(body))
          .unwrap(),
      )
      .await
      .unwrap();
    assert_ne!(
      response.status(),
      StatusCode::TOO_MANY_REQUESTS,
      "request {i} (0-indexed) should not be rate-limited"
    );
  }

  let throttled = app
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(throttled.status(), StatusCode::TOO_MANY_REQUESTS);
  assert!(
    throttled.headers().get("retry-after").is_some(),
    "rate-limited response must include a Retry-After header"
  );
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

// ── compendium groups ───────────────────────────────────────────────────────

#[tokio::test]
async fn test_compendium_groups_create_list_get_delete_roundtrip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  // Empty list on a fresh user.
  let list = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/compendium/groups")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(list.status(), StatusCode::OK);
  let body = read_body(list).await;
  assert_eq!(body.trim(), "[]");

  // Create a group with two entries — one normal, one half-HP minion.
  let create_body = serde_json::json!({
      "name": "Goblin Patrol",
      "initiative_mode": { "type": "shared_rolled" },
      "entries": [
          { "creature_id": "goblin", "count": 3, "minion_type": "half" },
          { "creature_id": "wolf",   "count": 1, "minion_type": "none" }
      ]
  });
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/compendium/groups")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(create_body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(create.status(), StatusCode::CREATED);
  let created_body = read_body(create).await;
  let created: serde_json::Value =
    serde_json::from_str(&created_body).expect("created body");
  let id = created["id"].as_str().expect("id").to_string();
  assert!(!id.is_empty(), "server should mint a non-empty id");
  assert_eq!(created["name"], "Goblin Patrol");
  assert_eq!(created["entries"].as_array().unwrap().len(), 2);
  assert!(created["created_at"].as_i64().unwrap() > 0);

  // The new group shows up in the list.
  let list2 = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/compendium/groups")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  let listed_body = read_body(list2).await;
  let listed: serde_json::Value = serde_json::from_str(&listed_body).unwrap();
  assert_eq!(listed.as_array().unwrap().len(), 1);
  assert_eq!(listed[0]["id"], id);

  // GET by id round-trips.
  let single = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri(format!("/api/compendium/groups/{id}"))
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(single.status(), StatusCode::OK);

  // DELETE removes it.
  let deleted = app
    .clone()
    .oneshot(
      Request::builder()
        .method("DELETE")
        .uri(format!("/api/compendium/groups/{id}"))
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

  // GET-after-delete is 404.
  let after = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri(format!("/api/compendium/groups/{id}"))
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(after.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_compendium_groups_update_preserves_created_at() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let create_body = serde_json::json!({
      "name": "Skeletons",
      "initiative_mode": { "type": "each_rolls" },
      "entries": [{ "creature_id": "skeleton", "count": 5, "minion_type": "one" }]
  });
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/compendium/groups")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(create_body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  let mut created: serde_json::Value =
    serde_json::from_str(&read_body(create).await).unwrap();
  let id = created["id"].as_str().unwrap().to_string();
  let original_created_at = created["created_at"].as_i64().unwrap();

  // Bump the name + change initiative to shared_manual.  Send a
  // bogus created_at to confirm the server overrides it.
  created["name"] = serde_json::json!("Restless Skeletons");
  created["initiative_mode"] =
    serde_json::json!({ "type": "shared_manual", "value": 12 });
  created["created_at"] = serde_json::json!(0);

  let put = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri(format!("/api/compendium/groups/{id}"))
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(created.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(put.status(), StatusCode::OK);
  let updated: serde_json::Value =
    serde_json::from_str(&read_body(put).await).unwrap();
  assert_eq!(updated["name"], "Restless Skeletons");
  assert_eq!(updated["initiative_mode"]["type"], "shared_manual");
  assert_eq!(updated["initiative_mode"]["value"], 12);
  assert_eq!(updated["created_at"].as_i64().unwrap(), original_created_at);
  assert!(updated["updated_at"].as_i64().unwrap() >= original_created_at);
}

// ── card layouts ────────────────────────────────────────────────────────────

#[tokio::test]
async fn test_card_layouts_create_get_list_delete_roundtrip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  // Empty list on a fresh user.
  let list = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/card-layouts")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(list.status(), StatusCode::OK);
  assert_eq!(read_body(list).await.trim(), "[]");

  // Save one.  The body is opaque JSON — server doesn't interpret.
  let layout_body = serde_json::json!({
      "rows": [
          { "widgets": ["name", "hit_points"], "alignment": "left" },
          { "widgets": ["conditions"],         "alignment": "center" }
      ],
      "queue_view": "list"
  });
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/card-layouts/Compact")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(layout_body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(create.status(), StatusCode::OK);
  let created: serde_json::Value =
    serde_json::from_str(&read_body(create).await).unwrap();
  assert_eq!(created["name"], "Compact");
  assert_eq!(created["body"]["rows"].as_array().unwrap().len(), 2);
  assert!(created["created_at"].as_i64().unwrap() > 0);

  // Re-PUT without overwrite=true should 409.
  let conflict = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/card-layouts/Compact")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(layout_body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(conflict.status(), StatusCode::CONFLICT);

  // With overwrite=true the same call succeeds.
  let overwrite_body = serde_json::json!({ "rows": [], "queue_view": "grid" });
  let overwrite = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/card-layouts/Compact?overwrite=true")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(overwrite_body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(overwrite.status(), StatusCode::OK);
  let overwritten: serde_json::Value =
    serde_json::from_str(&read_body(overwrite).await).unwrap();
  assert_eq!(overwritten["body"]["queue_view"], "grid");
  assert_eq!(
    overwritten["created_at"].as_i64().unwrap(),
    created["created_at"].as_i64().unwrap(),
    "overwrite must preserve created_at"
  );

  // List metadata.
  let list2 = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/card-layouts")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  let listed: serde_json::Value =
    serde_json::from_str(&read_body(list2).await).unwrap();
  assert_eq!(listed.as_array().unwrap().len(), 1);
  assert_eq!(listed[0]["name"], "Compact");

  // DELETE removes it, and a follow-up GET is 404.
  let deleted = app
    .clone()
    .oneshot(
      Request::builder()
        .method("DELETE")
        .uri("/api/card-layouts/Compact")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

  let after = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/card-layouts/Compact")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(after.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_card_layouts_per_user_isolation() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice_cookie = register_and_get_cookie(&app).await;
  let bob_cookie = register_user(&app, "bob@example.com", "Bob").await;

  // Alice saves a layout.
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/card-layouts/Mine")
        .header("content-type", "application/json")
        .header("cookie", &alice_cookie)
        .body(Body::from(r#"{"rows":[],"queue_view":"list"}"#))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(create.status(), StatusCode::OK);

  // Bob sees an empty list.
  let bob_list = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/card-layouts")
        .header("cookie", &bob_cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(read_body(bob_list).await.trim(), "[]");
}

// ── per-user lore-groups + condition-presets ────────────────────────────────
//
// Both are a single-blob GET/PUT store: one JSON value per user
// (whatever the frontend serializes — Lore.Group list, preset
// map, etc.).  These tests pin the contract that
//   1. an unset user reads `null`
//   2. a PUT round-trips back through GET
//   3. Bob's read is `null` after Alice writes
//
// Same pattern is used for both stores so the suite stays
// symmetric.

#[tokio::test]
async fn test_lore_groups_get_returns_null_when_unset() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let response = app
    .oneshot(
      Request::builder()
        .uri("/api/lore-groups")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK);
  assert_eq!(read_body(response).await.trim(), "null");
}

#[tokio::test]
async fn test_lore_groups_put_then_get_roundtrip() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let payload = r#"[{"id":"horde-1","name":"Goblin warband"}]"#;
  let put = app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/lore-groups")
        .header("content-type", "application/json")
        .header("cookie", &cookie)
        .body(Body::from(payload))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(put.status(), StatusCode::OK);

  let get = app
    .oneshot(
      Request::builder()
        .uri("/api/lore-groups")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  let body = read_body(get).await;
  assert!(
    body.contains("\"id\":\"horde-1\""),
    "expected PUT body to round-trip, got: {body}"
  );
  assert!(
    body.contains("Goblin warband"),
    "expected PUT body to round-trip, got: {body}"
  );
}

#[tokio::test]
async fn test_lore_groups_per_user_isolation() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/lore-groups")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(r#"[{"id":"alice-only","name":"Alice's"}]"#))
        .unwrap(),
    )
    .await
    .unwrap();

  let bob_get = app
    .oneshot(
      Request::builder()
        .uri("/api/lore-groups")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(
    read_body(bob_get).await.trim(),
    "null",
    "Bob must not see Alice's lore groups"
  );
}

#[tokio::test]
async fn test_condition_presets_get_returns_null_when_unset() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let cookie = register_and_get_cookie(&app).await;

  let response = app
    .oneshot(
      Request::builder()
        .uri("/api/condition-presets")
        .header("cookie", &cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK);
  assert_eq!(read_body(response).await.trim(), "null");
}

#[tokio::test]
async fn test_condition_presets_per_user_isolation() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  app
    .clone()
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri("/api/condition-presets")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(r#"{"Stun":{"name":"Stunned","dc":15}}"#))
        .unwrap(),
    )
    .await
    .unwrap();

  let bob_get = app
    .oneshot(
      Request::builder()
        .uri("/api/condition-presets")
        .header("cookie", &bob)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(
    read_body(bob_get).await.trim(),
    "null",
    "Bob must not see Alice's condition presets"
  );
}

// ── per-user compendium creatures ───────────────────────────────────────────
//
// The 5-test cluster below covers the contract introduced by the
// per-user-compendium split:
//
// - Bundled creatures are visible to every authenticated user.
// - User-created creatures are visible only to their author.
// - PUT / DELETE on a bundled id returns 403 BundledNotEditable.
// - POST /:id/duplicate clones into the caller's per-user store
//   with a fresh UUID and a "Copy of …" name.

async fn list_creatures(app: &Router, cookie: &str) -> Vec<serde_json::Value> {
  let response = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/compendium/creatures")
        .header("cookie", cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::OK);
  serde_json::from_str(&read_body(response).await).unwrap()
}

/// Pick a bundled creature id (any) from a real list response.
/// Avoids hard-coding a UUID that could change if the bundle
/// is regenerated.
async fn pick_bundled_id(app: &Router, cookie: &str) -> String {
  list_creatures(app, cookie)
    .await
    .into_iter()
    .find(|c| c["is_bundled"].as_bool() == Some(true))
    .and_then(|c| c["id"].as_str().map(str::to_string))
    .expect("bundle must contain at least one creature")
}

#[tokio::test]
async fn test_compendium_creatures_bundled_visible_to_every_user() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  let alice_list = list_creatures(&app, &alice).await;
  let bob_list = list_creatures(&app, &bob).await;
  let alice_bundled = alice_list
    .iter()
    .filter(|c| c["is_bundled"] == true)
    .count();
  let bob_bundled = bob_list.iter().filter(|c| c["is_bundled"] == true).count();

  assert!(alice_bundled > 0, "Alice should see bundled creatures");
  assert_eq!(
    alice_bundled, bob_bundled,
    "Alice and Bob should see the same bundled set"
  );
}

#[tokio::test]
async fn test_compendium_creatures_per_user_isolation() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bob = register_user(&app, "bob@example.com", "Bob").await;

  // Alice creates a creature (POST takes a CreatureDraft).
  let draft = serde_json::json!({
      "name": "Alice's Hippo",
      "kind": "enemy",
      "size": "huge",
      "race": "Beast",
      "subrace": "",
      "alignment": "unaligned",
      "source": "Test",
      "description": "",
      "armor_class": 14,
      "armor_class_note": "",
      "max_hp": 60,
      "hp_formula": "8d12+8",
      "initiative_bonus": 0,
      "speed": { "walk": 30, "fly": 0, "swim": 30, "climb": 0, "burrow": 0, "hover": false },
      "abilities": { "str": 21, "dex": 8, "con": 15, "int": 2, "wis": 10, "cha": 5 },
      "senses": { "blindsight": 0, "darkvision": 0, "tremorsense": 0, "truesight": 0, "passive_perception": 10 },
      "challenge_rating": "4",
      "xp": 1100,
      "proficiency_bonus": 2
  });
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/compendium/creatures")
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(draft.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(create.status(), StatusCode::CREATED);

  // Alice sees Alice's Hippo; Bob does not.
  let alice_names: Vec<String> = list_creatures(&app, &alice)
    .await
    .into_iter()
    .filter_map(|c| c["name"].as_str().map(str::to_string))
    .collect();
  let bob_names: Vec<String> = list_creatures(&app, &bob)
    .await
    .into_iter()
    .filter_map(|c| c["name"].as_str().map(str::to_string))
    .collect();
  assert!(
    alice_names.iter().any(|n| n == "Alice's Hippo"),
    "Alice should see her own creature; got names: {alice_names:?}"
  );
  assert!(
    !bob_names.iter().any(|n| n == "Alice's Hippo"),
    "Bob must NOT see Alice's creature; got names: {bob_names:?}"
  );
}

#[tokio::test]
async fn test_compendium_update_bundled_returns_forbidden() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;

  let bundled_id = pick_bundled_id(&app, &alice).await;
  let body = serde_json::json!({
      "id": bundled_id,
      "name": "Hacked Aboleth",
      "kind": "enemy",
      "size": "large",
      "race": "Aberration",
      "subrace": "", "alignment": "", "source": "", "description": "",
      "armor_class": 17, "armor_class_note": "", "max_hp": 1, "hp_formula": "",
      "initiative_bonus": 0,
      "speed": { "walk": 0, "fly": 0, "swim": 0, "climb": 0, "burrow": 0, "hover": false },
      "abilities": { "str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10 },
      "senses": { "blindsight": 0, "darkvision": 0, "tremorsense": 0, "truesight": 0, "passive_perception": 10 },
      "challenge_rating": "10", "xp": 5900, "proficiency_bonus": 4,
      "created_at": 0, "updated_at": 0
  });
  let put = app
    .oneshot(
      Request::builder()
        .method("PUT")
        .uri(format!("/api/compendium/creatures/{bundled_id}"))
        .header("content-type", "application/json")
        .header("cookie", &alice)
        .body(Body::from(body.to_string()))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(
    put.status(),
    StatusCode::FORBIDDEN,
    "PUT on a bundled creature must be rejected"
  );
}

#[tokio::test]
async fn test_compendium_delete_bundled_returns_forbidden() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bundled_id = pick_bundled_id(&app, &alice).await;

  let delete = app
    .oneshot(
      Request::builder()
        .method("DELETE")
        .uri(format!("/api/compendium/creatures/{bundled_id}"))
        .header("cookie", &alice)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(
    delete.status(),
    StatusCode::FORBIDDEN,
    "DELETE on a bundled creature must be rejected"
  );
}

#[tokio::test]
async fn test_compendium_duplicate_bundled_creates_per_user_copy() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);
  let alice = register_and_get_cookie(&app).await;
  let bundled_id = pick_bundled_id(&app, &alice).await;

  let duplicate = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri(format!("/api/compendium/creatures/{bundled_id}/duplicate"))
        .header("cookie", &alice)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(duplicate.status(), StatusCode::CREATED);
  let copy: serde_json::Value =
    serde_json::from_str(&read_body(duplicate).await).unwrap();
  let copy_id = copy["id"].as_str().expect("copy id").to_string();
  assert_ne!(
    copy_id, bundled_id,
    "duplicate must mint a fresh id, not echo the bundled one"
  );
  assert_eq!(
    copy["is_bundled"], false,
    "duplicate must land in the user's per-user store"
  );
  let name = copy["name"].as_str().expect("copy name");
  assert!(
    name.starts_with("Copy of "),
    "copy name should be prefixed; got: {name}"
  );

  // The copy now appears in Alice's list; the original bundled
  // row is still there and still bundled.
  let names: Vec<String> = list_creatures(&app, &alice)
    .await
    .into_iter()
    .filter_map(|c| c["name"].as_str().map(str::to_string))
    .collect();
  assert!(
    names.iter().any(|n| n == name),
    "duplicate should appear in subsequent list responses; got: {names:?}"
  );
}

#[tokio::test]
async fn test_compendium_groups_per_user_isolation() {
  let (_temp, state) = stub_app_state().await;
  let app = build_test_router(state);

  let alice_cookie = register_and_get_cookie(&app).await;
  let bob_cookie = register_user(&app, "bob@example.com", "Bob").await;

  // Alice creates a group.
  let create = app
    .clone()
    .oneshot(
      Request::builder()
        .method("POST")
        .uri("/api/compendium/groups")
        .header("content-type", "application/json")
        .header("cookie", &alice_cookie)
        .body(Body::from(
          r#"{"name":"Alice's Crew","initiative_mode":{"type":"each_rolls"},"entries":[]}"#,
        ))
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(create.status(), StatusCode::CREATED);

  // Bob sees an empty list.
  let bob_list = app
    .clone()
    .oneshot(
      Request::builder()
        .method("GET")
        .uri("/api/compendium/groups")
        .header("cookie", &bob_cookie)
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(read_body(bob_list).await.trim(), "[]");
}
