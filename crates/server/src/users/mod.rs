//! User-account HTTP surface.
//!
//! Endpoints (all under `/api/auth/*`):
//!
//! - `POST /api/auth/register` — create an account.
//! - `POST /api/auth/login`    — verify credentials, attach to session.
//! - `POST /api/auth/logout`   — clear the session.
//! - `GET  /api/auth/me`       — return the current user, or 401.
//!
//! Session shape: a single `user_id` string is stored in
//! `tower_sessions::Session` under [`SESSION_KEY_USER_ID`].  The
//! `require_auth` middleware extracts that key, looks up the `User`
//! record, and inserts a [`CurrentUser`] into request extensions
//! for downstream handlers.

use aide::axum::ApiRouter;
use axum::{
  extract::{Request, State},
  http::StatusCode,
  middleware::{self, Next},
  response::{IntoResponse, Response},
  routing::{get, post},
  Json,
};
use ezpz_dndz_lib::users::{User, UserId, UserPublic, UserStoreError};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use tower_sessions::Session;
use tracing::warn;

use crate::auth_rate_limit;
use crate::web_base::AppState;

/// Session key under which the authenticated `UserId` is stored.
pub const SESSION_KEY_USER_ID: &str = "user_id";

/// Request extension carrying the authenticated `User` so downstream
/// handlers don't have to re-load from disk.  Set by the
/// [`require_auth`] middleware.
#[derive(Clone)]
pub struct CurrentUser(pub User);

// ── request / response bodies ──────────────────────────────────────────────

#[derive(Debug, Deserialize, JsonSchema)]
pub struct RegisterRequest {
  pub email: String,
  pub password: String,
  pub display_name: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct LoginRequest {
  pub email: String,
  pub password: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct UpdateProfileRequest {
  pub display_name: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ChangePasswordRequest {
  pub current_password: String,
  pub new_password: String,
}

#[derive(Debug, Serialize, JsonSchema)]
pub struct ErrorBody {
  pub error: String,
}

// ── handlers ───────────────────────────────────────────────────────────────

// Handlers return `Response` directly (rather than
// `Result<T, AuthHttpError>`) so they fit aide's `OperationHandler`
// trait — which is implemented for `Response` but not for an
// arbitrary user-defined error type.  The `?`-on-Result style is
// retained internally via a small helper closure.
async fn register_handler(
  State(state): State<AppState>,
  session: Session,
  Json(body): Json<RegisterRequest>,
) -> Response {
  let result: Result<(StatusCode, Json<UserPublic>), AuthHttpError> = async {
    let user = state
      .user_store
      .register(&body.email, &body.password, &body.display_name)
      .await?;
    // Successful registration also logs the user in — saves a
    // round trip and matches what every "sign up" form does.
    session
      .insert(SESSION_KEY_USER_ID, user.id.0.clone())
      .await
      .map_err(|e| AuthHttpError::Session(e.to_string()))?;
    Ok((StatusCode::CREATED, Json(UserPublic::from(&user))))
  }
  .await;
  match result {
    Ok(ok) => ok.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn login_handler(
  State(state): State<AppState>,
  session: Session,
  Json(body): Json<LoginRequest>,
) -> Response {
  let result: Result<Json<UserPublic>, AuthHttpError> = async {
    let user = state
      .user_store
      .authenticate(&body.email, &body.password)
      .await?;
    // Cycle the session id on a successful login to defeat session
    // fixation: any value an attacker may have planted in the
    // cookie before login becomes useless.
    session
      .cycle_id()
      .await
      .map_err(|e| AuthHttpError::Session(e.to_string()))?;
    session
      .insert(SESSION_KEY_USER_ID, user.id.0.clone())
      .await
      .map_err(|e| AuthHttpError::Session(e.to_string()))?;
    Ok(Json(UserPublic::from(&user)))
  }
  .await;
  match result {
    Ok(ok) => ok.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn logout_handler(session: Session) -> Response {
  // Best-effort: even if flushing fails we still want to look
  // logged-out from the caller's perspective.  Failures are logged
  // for visibility but not propagated.
  if let Err(e) = session.flush().await {
    warn!(error = %e, "session flush failed during logout");
  }
  StatusCode::NO_CONTENT.into_response()
}

/// Resolve the `UserId` from the session cookie.  Mirrors what
/// `me_handler` does — used by the authenticated `/api/auth/*`
/// endpoints that aren't covered by the `require_auth` layer (the
/// `users::router()` is merged outside the protected subtree so
/// unauthenticated clients can hit `/register` / `/login`).
async fn current_user_id(session: &Session) -> Result<UserId, AuthHttpError> {
  let id: Option<String> = session
    .get(SESSION_KEY_USER_ID)
    .await
    .map_err(|e| AuthHttpError::Session(e.to_string()))?;
  id.map(UserId).ok_or(AuthHttpError::Unauthorized)
}

async fn update_profile_handler(
  State(state): State<AppState>,
  session: Session,
  Json(body): Json<UpdateProfileRequest>,
) -> Response {
  let result: Result<Json<UserPublic>, AuthHttpError> = async {
    let id = current_user_id(&session).await?;
    let updated = state
      .user_store
      .update_display_name(&id, &body.display_name)
      .await?;
    Ok(Json(UserPublic::from(&updated)))
  }
  .await;
  match result {
    Ok(ok) => ok.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn change_password_handler(
  State(state): State<AppState>,
  session: Session,
  Json(body): Json<ChangePasswordRequest>,
) -> Response {
  let result: Result<StatusCode, AuthHttpError> = async {
    let id = current_user_id(&session).await?;
    state
      .user_store
      .change_password(&id, &body.current_password, &body.new_password)
      .await?;
    Ok(StatusCode::NO_CONTENT)
  }
  .await;
  match result {
    Ok(status) => status.into_response(),
    Err(e) => e.into_response(),
  }
}

async fn me_handler(
  State(state): State<AppState>,
  session: Session,
) -> Response {
  let result: Result<Json<UserPublic>, AuthHttpError> = async {
    let user_id: Option<String> = session
      .get(SESSION_KEY_USER_ID)
      .await
      .map_err(|e| AuthHttpError::Session(e.to_string()))?;
    let id = user_id.ok_or(AuthHttpError::Unauthorized)?;
    let user = state
      .user_store
      .find_by_id(&UserId(id))
      .await?
      .ok_or(AuthHttpError::Unauthorized)?;
    Ok(Json(UserPublic::from(&user)))
  }
  .await;
  match result {
    Ok(ok) => ok.into_response(),
    Err(e) => e.into_response(),
  }
}

// ── middleware ─────────────────────────────────────────────────────────────

/// Layer to wrap around any router that requires an authenticated
/// session.  Returns 401 with a JSON body when there is no session
/// or the session points at a missing user; on success, the
/// looked-up `User` is inserted into `Request::extensions` as
/// [`CurrentUser`].
pub async fn require_auth(
  State(state): State<AppState>,
  session: Session,
  mut request: Request,
  next: Next,
) -> Response {
  let user_id_opt: Option<String> = match session.get(SESSION_KEY_USER_ID).await
  {
    Ok(v) => v,
    Err(e) => {
      return AuthHttpError::Session(e.to_string()).into_response();
    }
  };

  let Some(id) = user_id_opt else {
    return AuthHttpError::Unauthorized.into_response();
  };

  let user = match state.user_store.find_by_id(&UserId(id)).await {
    Ok(Some(user)) => user,
    Ok(None) => return AuthHttpError::Unauthorized.into_response(),
    Err(e) => return AuthHttpError::from(e).into_response(),
  };

  request.extensions_mut().insert(CurrentUser(user));
  next.run(request).await
}

// ── router ─────────────────────────────────────────────────────────────────

pub fn router(state: AppState) -> ApiRouter<AppState> {
  // Plain `route` instead of `api_route` — aide's `OperationHandler`
  // trait has no impl for `tower_sessions::Session`, so these
  // endpoints can't participate in the OpenAPI schema today.  Their
  // behaviour is documented in the module docs above; no /scalar UI
  // entry is generated for them.
  //
  // The credential-checking endpoints (register, login) carry a
  // per-IP rate limit so a brute-forcer can't burn the box's CPU
  // on Argon2id verification.  The session-only endpoints (logout,
  // me, password) are NOT rate-limited — they need a valid cookie
  // to reach, and the cookie is the implicit gate.
  let rate_limited: ApiRouter<AppState> = ApiRouter::new()
    .route("/api/auth/register", post(register_handler))
    .route("/api/auth/login", post(login_handler))
    .layer(middleware::from_fn_with_state(
      state.auth_rate_limiter.clone(),
      auth_rate_limit::middleware,
    ));

  ApiRouter::new()
    .merge(rate_limited)
    .route("/api/auth/logout", post(logout_handler))
    .route("/api/auth/me", get(me_handler).put(update_profile_handler))
    .route("/api/auth/password", post(change_password_handler))
}

// ── error type ─────────────────────────────────────────────────────────────

/// HTTP-side error type for the auth surface.  Maps
/// `UserStoreError` and session-store errors onto status codes
/// and JSON bodies.  The credential-check variants collapse to
/// `401 Unauthorized` so account enumeration via timing or
/// error-text differences is harder.
pub enum AuthHttpError {
  Unauthorized,
  EmailTaken,
  PasswordTooShort,
  EmailInvalid,
  DisplayNameEmpty,
  Internal(String),
  Session(String),
}

impl From<UserStoreError> for AuthHttpError {
  fn from(e: UserStoreError) -> Self {
    match e {
      UserStoreError::EmailTaken => Self::EmailTaken,
      UserStoreError::InvalidCredentials => Self::Unauthorized,
      UserStoreError::PasswordTooShort => Self::PasswordTooShort,
      UserStoreError::EmailInvalid => Self::EmailInvalid,
      UserStoreError::DisplayNameEmpty => Self::DisplayNameEmpty,
      UserStoreError::Query(e) | UserStoreError::Persist(e) => {
        Self::Internal(e.to_string())
      }
      UserStoreError::Hash(s) => Self::Internal(s),
    }
  }
}

impl IntoResponse for AuthHttpError {
  fn into_response(self) -> Response {
    let (status, message) = match self {
      Self::Unauthorized => {
        (StatusCode::UNAUTHORIZED, "Invalid email or password".to_string())
      }
      Self::EmailTaken => {
        (StatusCode::CONFLICT, "Email is already registered".to_string())
      }
      Self::PasswordTooShort => (
        StatusCode::BAD_REQUEST,
        "Password must be at least 8 characters".to_string(),
      ),
      Self::EmailInvalid => (
        StatusCode::BAD_REQUEST,
        "Email must look like an email address".to_string(),
      ),
      Self::DisplayNameEmpty => {
        (StatusCode::BAD_REQUEST, "Display name must not be empty".to_string())
      }
      Self::Internal(detail) => {
        warn!(detail, "auth handler hit an internal error");
        (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
      }
      Self::Session(detail) => {
        warn!(detail, "session-store operation failed");
        (
          StatusCode::INTERNAL_SERVER_ERROR,
          "Session operation failed".to_string(),
        )
      }
    };
    (status, Json(ErrorBody { error: message })).into_response()
  }
}
