//! ezpz-dndz-server — entry point.
//!
//! `#[foundation_main]` handles CLI parsing, config resolution
//! (XDG-aware), logging init, OIDC discovery, listener binding,
//! systemd notify / watchdog / socket activation, and graceful
//! shutdown.  This file owns only the application-specific setup:
//! loading the JSON-backed stores and registering app routes.

use aide::axum::ApiRouter;
use axum::middleware;
use ezpz_dndz_lib::db::Db;
use ezpz_dndz_server::{
  compendium, config::Config, dice, encounters, frontend::Frontend,
  per_user_store, users, web_base::AppState,
};
use rust_template_foundation::main as foundation_main;
use rust_template_foundation::Server;
use std::process::ExitCode;
use thiserror::Error;
use tracing::info;

#[derive(Debug, Error)]
enum AppError {
  #[error("Failed to open the database: {0}")]
  Db(#[from] ezpz_dndz_lib::db::DbError),

  #[error("Failed to initialize application state: {0}")]
  StateInit(#[from] ezpz_dndz_server::web_base::AppStateError),

  #[error("Server runtime error: {0}")]
  Server(#[from] rust_template_foundation::ServerError),
}

#[foundation_main]
pub async fn main(
  config: Config,
  server: Server,
) -> Result<ExitCode, AppError> {
  info!("Starting ezpz-dndz-server");

  // Async store loading happens up front: foundation's `with_state`
  // takes a synchronous closure, so AppState has to be assembled
  // before the closure runs.  The closure just hands the pre-built
  // state back.
  // Connect + migrate first: every store hangs off the one Db
  // handle, and `Db::connect` brings the schema up to date before
  // any query runs.
  let db = Db::connect(&config.database_url).await?;

  let base = server.base_state().clone();
  let app_state = AppState::assemble(
    base,
    db,
    &config.paths,
    config.compendium_claim_user.as_deref(),
  )
  .await?;
  let auth_state = app_state.clone();

  // Auth-gated routes: every /api/* endpoint that touches per-user
  // data goes through `require_auth`, which extracts the user_id
  // from the session, looks up the User, and inserts a CurrentUser
  // extension for the handler.  The /api/auth/* endpoints
  // (registration / login / logout / me) merge in unwrapped so an
  // unauthenticated client can use them to obtain a session.
  let protected: ApiRouter<AppState> = ApiRouter::new()
    .merge(dice::router())
    .merge(compendium::router())
    .merge(encounters::router())
    // The five per-user opaque-JSON stores (lore groups, condition
    // presets, save-chain presets, treasure table, treasure
    // profiles), all served by the shared GET/PUT pair.
    .merge(per_user_store::routers(&app_state))
    .layer(middleware::from_fn_with_state(auth_state, users::require_auth));

  let users_state = app_state.clone();
  let server = server
    .with_state(move |_base| app_state)
    .merge(users::router(users_state))
    .merge(protected)
    // Serve the embedded Elm frontend as an SPA fallback: anything the
    // API routers don't claim resolves against the compiled assets, with
    // index.html covering client-side routes.  Assets are baked into the
    // binary in release builds and read from disk in debug builds.
    .spa::<Frontend>();

  server.listen().await?;
  Ok(ExitCode::SUCCESS)
}
