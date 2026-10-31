//! User-account HTTP surface.
//!
//! Endpoints (all under `/api/auth/*`):
//!
//! - `POST /api/auth/register` — create an account.
//! - `POST /api/auth/login`    — verify credentials, attach to session.
//! - `POST /api/auth/logout`   — clear the session.
//! - `GET  /api/auth/me`       — return the current user, or 401.
//!
//! Session shape: the `user_id` string is stored in
//! `tower_sessions::Session` under [`SESSION_KEY_USER_ID`].  The stamp
//! of the password the session signed in with sits under
//! [`SESSION_KEY_PASSWORD_STAMP`].  The `require_auth` middleware
//! extracts both, looks up the `User` record, and inserts a
//! [`CurrentUser`] into request extensions for downstream handlers.  A
//! stale stamp means the session signed in before a password change.
//! Such a session is refused.

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

/// Session key under which the stamp of the password a session signed
/// in with is stored.
pub const SESSION_KEY_PASSWORD_STAMP: &str = "password_stamp";

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
    sign_in(&session, &user).await?;
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
    sign_in(&session, &user).await?;
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

/// The password stamp a session carries.  A password change gives the
/// hash a fresh salt, so every older session's stamp stops matching.
/// The digest keeps the hash itself out of the session store.
fn password_stamp(user: &User) -> String {
  crate::digest::sha256_hex(user.password_hash.as_bytes())
}

/// Attach `user` to the session.  The session carries the stamp of
/// their current password.
async fn sign_in(session: &Session, user: &User) -> Result<(), AuthHttpError> {
  session
    .insert(SESSION_KEY_USER_ID, user.id.0.clone())
    .await
    .map_err(|e| AuthHttpError::Session(e.to_string()))?;
  session
    .insert(SESSION_KEY_PASSWORD_STAMP, password_stamp(user))
    .await
    .map_err(|e| AuthHttpError::Session(e.to_string()))
}

/// The user the session signed in as.  Every authenticated path
/// resolves through here: the `require_auth` layer and the
/// `/api/auth/*` endpoints merged outside it.
async fn session_user(
  state: &AppState,
  session: &Session,
) -> Result<User, AuthHttpError> {
  let id: String = session
    .get(SESSION_KEY_USER_ID)
    .await
    .map_err(|e| AuthHttpError::Session(e.to_string()))?
    .ok_or(AuthHttpError::SignInRequired)?;
  let stamp: Option<String> = session
    .get(SESSION_KEY_PASSWORD_STAMP)
    .await
    .map_err(|e| AuthHttpError::Session(e.to_string()))?;
  state
    .user_store
    .find_by_id(&UserId(id))
    .await?
    .filter(|user| stamp.as_deref() == Some(password_stamp(user).as_str()))
    .ok_or(AuthHttpError::SignInRequired)
}

async fn update_profile_handler(
  State(state): State<AppState>,
  session: Session,
  Json(body): Json<UpdateProfileRequest>,
) -> Response {
  let result: Result<Json<UserPublic>, AuthHttpError> = async {
    let user = session_user(&state, &session).await?;
    let updated = state
      .user_store
      .update_display_name(&user.id, &body.display_name)
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
    let user = session_user(&state, &session).await?;
    state
      .user_store
      .change_password(&user.id, &body.current_password, &body.new_password)
      .await?;
    // The new hash signs every other session out.  This one takes
    // its new stamp and stays signed in.
    let changed = state
      .user_store
      .find_by_id(&user.id)
      .await?
      .ok_or(AuthHttpError::SignInRequired)?;
    sign_in(&session, &changed).await?;
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
  let result: Result<Json<UserPublic>, AuthHttpError> =
    session_user(&state, &session)
      .await
      .map(|user| Json(UserPublic::from(&user)));
  match result {
    Ok(ok) => ok.into_response(),
    Err(e) => e.into_response(),
  }
}

// ── middleware ─────────────────────────────────────────────────────────────

/// Layer to wrap around any router that requires an authenticated
/// session.  Returns 401 with a JSON body when `session_user` refuses
/// the session.  On success, the looked-up `User` is inserted into
/// `Request::extensions` as [`CurrentUser`].
pub async fn require_auth(
  State(state): State<AppState>,
  session: Session,
  mut request: Request,
  next: Next,
) -> Response {
  match session_user(&state, &session).await {
    Ok(user) => {
      request.extensions_mut().insert(CurrentUser(user));
      next.run(request).await
    }
    Err(e) => e.into_response(),
  }
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
/// error-text differences is harder.  A request with no session
/// gets its own 401 that names no credential.
pub enum AuthHttpError {
  Unauthorized,
  SignInRequired,
  CurrentPasswordIncorrect,
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
      UserStoreError::CurrentPasswordIncorrect => {
        Self::CurrentPasswordIncorrect
      }
      UserStoreError::PasswordTooShort => Self::PasswordTooShort,
      UserStoreError::EmailInvalid => Self::EmailInvalid,
      UserStoreError::DisplayNameEmpty => Self::DisplayNameEmpty,
      UserStoreError::Query(e) | UserStoreError::Persist(e) => {
        Self::Internal(e.to_string())
      }
      UserStoreError::Hash(s) => Self::Internal(s),
      stand_in @ UserStoreError::UnknownEmailHash(_) => {
        Self::Internal(stand_in.to_string())
      }
    }
  }
}

impl IntoResponse for AuthHttpError {
  fn into_response(self) -> Response {
    let (status, message) = match self {
      Self::Unauthorized => {
        (StatusCode::UNAUTHORIZED, "Invalid email or password".to_string())
      }
      Self::SignInRequired => {
        (StatusCode::UNAUTHORIZED, "Sign in required".to_string())
      }
      // A 401 here would read as a lost session to the frontend.
      Self::CurrentPasswordIncorrect => {
        (StatusCode::FORBIDDEN, "Current password is incorrect".to_string())
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
