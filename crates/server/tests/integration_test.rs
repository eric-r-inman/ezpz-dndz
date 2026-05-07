use axum::{
  body::Body,
  http::{Request, StatusCode},
  Router,
};
use ezpz_dndz_server::web_base::{base_router, AppState};
use openidconnect::{
  core::{
    CoreClient, CoreJwsSigningAlgorithm, CoreProviderMetadata,
    CoreResponseType, CoreSubjectIdentifierType,
  },
  AuthUrl, ClientId, EmptyAdditionalProviderMetadata, IssuerUrl,
  JsonWebKeySetUrl, ResponseTypes,
};
use prometheus::{IntCounter, Registry};
use std::{path::PathBuf, sync::Arc};
use tower::ServiceExt;
use tower_sessions::{cookie::SameSite, MemoryStore, SessionManagerLayer};

// ── state helpers ────────────────────────────────────────────────────────────

async fn stub_state_no_auth(frontend_path: PathBuf) -> AppState {
  let registry = Registry::new();
  let request_counter =
    IntCounter::new("http_requests_total", "Total HTTP requests")
      .expect("counter creation");
  registry
    .register(Box::new(request_counter.clone()))
    .expect("counter registration");

  AppState {
    registry: Arc::new(registry),
    request_counter,
    frontend_path,
    dice_store: ezpz_dndz_server::dice::DiceStore::load_or_default(
      tempfile::NamedTempFile::new()
        .expect("tempfile")
        .into_temp_path()
        .to_path_buf(),
    )
    .await
    .expect("test dice store"),
    compendium_store:
      ezpz_dndz_server::compendium::CompendiumStore::load_or_bootstrap(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test compendium store"),
    compendium_saves:
      ezpz_dndz_server::compendium::SavedCompendiumStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test compendium saves store"),
    encounter_store:
      ezpz_dndz_server::encounters::EncounterStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test encounter store"),
    encounter_saves:
      ezpz_dndz_server::encounters::SavedEncounterStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test encounter saves store"),
    oidc_client: None,
  }
}

async fn stub_state_with_auth(frontend_path: PathBuf) -> AppState {
  let registry = Registry::new();
  let request_counter =
    IntCounter::new("http_requests_total", "Total HTTP requests")
      .expect("counter creation");
  registry
    .register(Box::new(request_counter.clone()))
    .expect("counter registration");

  let issuer = IssuerUrl::new("https://stub.invalid".to_string()).unwrap();
  let metadata = CoreProviderMetadata::new(
    issuer,
    AuthUrl::new("https://stub.invalid/authorize".to_string()).unwrap(),
    JsonWebKeySetUrl::new("https://stub.invalid/jwks".to_string()).unwrap(),
    vec![ResponseTypes::new(vec![CoreResponseType::Code])],
    vec![CoreSubjectIdentifierType::Public],
    vec![CoreJwsSigningAlgorithm::RsaSsaPkcs1V15Sha256],
    EmptyAdditionalProviderMetadata {},
  );
  let oidc_client = CoreClient::from_provider_metadata(
    metadata,
    ClientId::new("stub-client".to_string()),
    None,
  );

  AppState {
    registry: Arc::new(registry),
    request_counter,
    frontend_path,
    dice_store: ezpz_dndz_server::dice::DiceStore::load_or_default(
      tempfile::NamedTempFile::new()
        .expect("tempfile")
        .into_temp_path()
        .to_path_buf(),
    )
    .await
    .expect("test dice store"),
    compendium_store:
      ezpz_dndz_server::compendium::CompendiumStore::load_or_bootstrap(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test compendium store"),
    compendium_saves:
      ezpz_dndz_server::compendium::SavedCompendiumStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test compendium saves store"),
    encounter_store:
      ezpz_dndz_server::encounters::EncounterStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test encounter store"),
    encounter_saves:
      ezpz_dndz_server::encounters::SavedEncounterStore::load_or_default(
        tempfile::NamedTempFile::new()
          .expect("tempfile")
          .into_temp_path()
          .to_path_buf(),
      )
      .await
      .expect("test encounter saves store"),
    oidc_client: Some(Arc::new(oidc_client)),
  }
}

async fn state_without_frontend() -> AppState {
  stub_state_no_auth(PathBuf::from("/nonexistent")).await
}

/// Wraps `base_router` with auth routes and a session layer, mirroring
/// the production `create_app` structure.
fn app_with_session(state: AppState) -> Router {
  use axum::routing::get;
  use ezpz_dndz_server::auth;

  let session_store = MemoryStore::default();
  let session_layer = SessionManagerLayer::new(session_store)
    .with_secure(false)
    .with_same_site(SameSite::Lax);

  let auth_router = Router::new()
    .route("/auth/login", get(auth::login_handler))
    .route("/auth/callback", get(auth::callback_handler))
    .route("/auth/logout", get(auth::logout_handler))
    .with_state(state.clone());

  base_router(state).merge(auth_router).layer(session_layer)
}

// ── existing route tests ─────────────────────────────────────────────────────

#[tokio::test]
async fn test_healthz_endpoint() {
  let app = base_router(state_without_frontend().await);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/healthz")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let body_str = String::from_utf8(body.to_vec()).unwrap();

  assert!(body_str.contains("healthy"));
}

#[tokio::test]
async fn test_metrics_endpoint() {
  let app = base_router(state_without_frontend().await);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/metrics")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let body_str = String::from_utf8(body.to_vec()).unwrap();

  assert!(
    body_str.contains("http_requests_total"),
    "Metrics should contain http_requests_total counter"
  );
}

#[tokio::test]
async fn test_openapi_json_endpoint() {
  let app = base_router(state_without_frontend().await);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/api-docs/openapi.json")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let body_str = String::from_utf8(body.to_vec()).unwrap();

  assert!(body_str.contains("openapi"), "Response should be an OpenAPI spec");
  assert!(body_str.contains("/healthz"), "Spec should document /healthz");
  assert!(body_str.contains("/metrics"), "Spec should document /metrics");
}

#[tokio::test]
async fn test_scalar_ui_endpoint() {
  let app = base_router(state_without_frontend().await);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/scalar")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();

  assert!(
    body.starts_with(b"<!doctype html>")
      || body.starts_with(b"<!DOCTYPE html>"),
    "Scalar endpoint should return HTML"
  );
}

#[tokio::test]
async fn test_spa_fallback_serves_index_html() {
  let frontend_dir = tempfile::tempdir().unwrap();
  std::fs::write(
    frontend_dir.path().join("index.html"),
    b"<!doctype html><title>ezpz-dndz</title>",
  )
  .unwrap();

  let app =
    base_router(stub_state_no_auth(frontend_dir.path().to_path_buf()).await);

  for path in ["/some-page", "/nested/route", "/unknown"] {
    let response = app
      .clone()
      .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
      .await
      .unwrap();
    assert_eq!(
      response.status(),
      StatusCode::OK,
      "expected 200 for SPA path {path}"
    );
  }
}

// ── /me endpoint tests ───────────────────────────────────────────────────────

#[tokio::test]
async fn test_me_no_oidc() {
  let state = stub_state_no_auth(PathBuf::from("/nonexistent")).await;
  let app = app_with_session(state);

  let response = app
    .oneshot(Request::builder().uri("/me").body(Body::empty()).unwrap())
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

  assert_eq!(json["name"], "admin");
  assert_eq!(json["auth_enabled"], false);
}

#[tokio::test]
async fn test_me_with_oidc_no_session() {
  let state = stub_state_with_auth(PathBuf::from("/nonexistent")).await;
  let app = app_with_session(state);

  let response = app
    .oneshot(Request::builder().uri("/me").body(Body::empty()).unwrap())
    .await
    .unwrap();

  assert_eq!(response.status(), StatusCode::OK);

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

  assert_eq!(json["name"], "anonymous");
  assert_eq!(json["auth_enabled"], true);
}

// ── auth route guard tests ───────────────────────────────────────────────────

#[tokio::test]
async fn test_auth_routes_return_404_without_oidc() {
  let state = stub_state_no_auth(PathBuf::from("/nonexistent")).await;
  let app = app_with_session(state);

  for path in ["/auth/login", "/auth/logout"] {
    let response = app
      .clone()
      .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
      .await
      .unwrap();
    assert_eq!(
      response.status(),
      StatusCode::NOT_FOUND,
      "expected 404 for {path} without OIDC"
    );
  }

  // callback needs query params; without them Axum rejects before our guard,
  // but we can confirm it still doesn't 500 or 200.
  let response = app
    .oneshot(
      Request::builder()
        .uri("/auth/callback?code=x&state=y")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_auth_login_redirects_with_oidc() {
  let state = stub_state_with_auth(PathBuf::from("/nonexistent")).await;
  let app = app_with_session(state);

  let response = app
    .oneshot(
      Request::builder()
        .uri("/auth/login")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();

  // The stub provider's authorize URL should trigger a redirect.
  assert_eq!(response.status(), StatusCode::SEE_OTHER);
  let location = response
    .headers()
    .get("location")
    .expect("redirect should have Location header")
    .to_str()
    .unwrap();
  assert!(
    location.contains("stub.invalid"),
    "redirect should point at the stub OIDC provider"
  );
}

// ── config tests ─────────────────────────────────────────────────────────────

#[tokio::test]
async fn test_config_no_oidc() {
  use ezpz_dndz_server::config::{CliRaw, Config};

  let cli = CliRaw {
    log_level: None,
    log_format: None,
    config: None,
    listen: None,
    frontend_path: None,
    data_dir: None,
    dice_history_path: None,
    compendium_path: None,
    compendium_saves_path: None,
    encounter_path: None,
    encounter_saves_path: None,
    base_url: Some("https://example.com".to_string()),
    oidc_issuer: None,
    oidc_client_id: None,
    oidc_client_secret_file: None,
  };

  let config = Config::from_cli_and_file(cli).unwrap();
  assert!(config.oidc.is_none());
}

#[tokio::test]
async fn test_config_full_oidc() {
  use ezpz_dndz_server::config::{CliRaw, Config};

  let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
    .join("tests/fixtures/oidc-client-secret");

  let cli = CliRaw {
    log_level: None,
    log_format: None,
    config: None,
    listen: None,
    frontend_path: None,
    data_dir: None,
    dice_history_path: None,
    compendium_path: None,
    compendium_saves_path: None,
    encounter_path: None,
    encounter_saves_path: None,
    base_url: Some("https://example.com".to_string()),
    oidc_issuer: Some("https://sso.example.com".to_string()),
    oidc_client_id: Some("my-client".to_string()),
    oidc_client_secret_file: Some(fixture),
  };

  let config = Config::from_cli_and_file(cli).unwrap();
  let oidc = config.oidc.expect("OIDC config should be Some");
  assert_eq!(oidc.issuer, "https://sso.example.com");
  assert_eq!(oidc.client_id, "my-client");
  assert_eq!(oidc.client_secret, "test-secret-not-for-production");
}

#[tokio::test]
async fn test_config_partial_oidc_errors() {
  use ezpz_dndz_server::config::{CliRaw, Config};

  let cli = CliRaw {
    log_level: None,
    log_format: None,
    config: None,
    listen: None,
    frontend_path: None,
    data_dir: None,
    dice_history_path: None,
    compendium_path: None,
    compendium_saves_path: None,
    encounter_path: None,
    encounter_saves_path: None,
    base_url: Some("https://example.com".to_string()),
    oidc_issuer: Some("https://sso.example.com".to_string()),
    oidc_client_id: None,
    oidc_client_secret_file: None,
  };

  let err = Config::from_cli_and_file(cli).unwrap_err();
  let msg = err.to_string();
  assert!(
    msg.contains("partial OIDC") && msg.contains("missing"),
    "error should describe partial OIDC config, got: {msg}"
  );
}

// ── encounter persistence ────────────────────────────────────────────────────

#[tokio::test]
async fn test_encounter_get_returns_null_when_unset() {
  let app = base_router(state_without_frontend().await);

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

  let body = axum::body::to_bytes(response.into_body(), usize::MAX)
    .await
    .unwrap();
  let body_str = String::from_utf8(body.to_vec()).unwrap();

  // Default is `serde_json::Value::Null`, which serializes as the
  // literal "null" — the frontend reads that as "use the empty
  // default" rather than failing the boot.
  assert_eq!(body_str.trim(), "null");
}

#[tokio::test]
async fn test_encounter_put_then_get_roundtrip() {
  let state = state_without_frontend().await;
  let app = base_router(state);

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

  let body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
    .await
    .unwrap();
  let body_str = String::from_utf8(body.to_vec()).unwrap();

  // The server stores opaque JSON, so after a PUT the GET should
  // return the same payload back (as a normalized JSON string).
  assert!(
    body_str.contains("\"activeName\":\"Brakka\""),
    "expected PUT body to round-trip, got: {body_str}"
  );
  assert!(
    body_str.contains("\"round\":3"),
    "expected PUT body to round-trip, got: {body_str}"
  );
}

#[tokio::test]
async fn test_compendium_save_create_list_get_roundtrip() {
  let state = state_without_frontend().await;
  let app = base_router(state);

  let payload = r#"[{"id":"abc","name":"Goblin","cr":"1/4"}]"#;

  let put_response = app
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
  assert_eq!(put_response.status(), StatusCode::OK);

  let list_response = app
    .clone()
    .oneshot(
      Request::builder()
        .uri("/api/compendium/saves")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(list_response.status(), StatusCode::OK);
  let list_body = axum::body::to_bytes(list_response.into_body(), usize::MAX)
    .await
    .unwrap();
  let list_str = String::from_utf8(list_body.to_vec()).unwrap();
  assert!(
    list_str.contains("\"name\":\"My Bestiary\""),
    "expected listing to include the new save, got: {list_str}"
  );

  let get_response = app
    .oneshot(
      Request::builder()
        .uri("/api/compendium/saves/My%20Bestiary")
        .body(Body::empty())
        .unwrap(),
    )
    .await
    .unwrap();
  assert_eq!(get_response.status(), StatusCode::OK);
  let get_body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
    .await
    .unwrap();
  let get_str = String::from_utf8(get_body.to_vec()).unwrap();
  assert!(
    get_str.contains("\"name\":\"Goblin\""),
    "expected creature payload to round-trip, got: {get_str}"
  );
}

#[tokio::test]
async fn test_compendium_save_overwrite_conflicts_without_flag() {
  let state = state_without_frontend().await;
  let app = base_router(state);

  // First create — succeeds.
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

  // Second create under the same name — 409 without
  // `?overwrite=true` so the modal can prompt.
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

#[tokio::test]
async fn test_dice_history_concurrent_appends_lose_nothing() {
  // 20 concurrent POSTs each with a unique roll id; every one
  // should land in the file (under the 30-entry MAX cap), and
  // every id should appear exactly once.
  let state = state_without_frontend().await;
  let app = base_router(state.clone());
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
