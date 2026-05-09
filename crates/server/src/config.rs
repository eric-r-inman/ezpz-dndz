//! Server configuration.
//!
//! Built on the foundation's `MergeConfig` derive.  The macro generates
//! `CliRaw`, `ConfigFileRaw`, the `Config::from_cli_and_file` merge,
//! and the `CliApp` impl that `#[foundation_main]` wires up.
//!
//! Two pieces of resolution sit in `skip` fields:
//!
//! - `paths`: the per-store JSON files default into `<data_dir>/...`,
//!   which is a cross-field rule MergeConfig can't model directly.
//! - `oidc`: assembled from three CLI / file fields plus the systemd
//!   `LoadCredential` directory; partial configurations error out.
//!
//! `extra_cli` and `extra_file` flatten the OIDC + path-override
//! fields into `CliRaw` / `ConfigFileRaw` so they appear as proper
//! command-line flags and TOML keys without bloating the `Config`
//! shape.

use ezpz_dndz_lib::{LogFormat, LogLevel};
use rust_template_foundation::auth::OidcConfig;
use rust_template_foundation::config::credential_secret_path;
use rust_template_foundation::server::runner::{ServerApp, ServerRunConfig};
use rust_template_foundation::MergeConfig;
use serde::Deserialize;
use std::path::PathBuf;
use tokio_listener::ListenerAddress;

/// Path overrides + OIDC bundle, flattened into `CliRaw`.
#[derive(Debug, clap::Args)]
pub struct ExtraCliFields {
  /// OIDC issuer URL
  /// (e.g. https://sso.example.com/application/o/myapp).
  #[arg(long, env = "ezpz_dndz_oidc_issuer")]
  pub oidc_issuer: Option<String>,

  /// OIDC client ID.
  #[arg(long, env = "ezpz_dndz_oidc_client_id")]
  pub oidc_client_id: Option<String>,

  /// Path to a file containing the OIDC client secret.
  #[arg(long, env = "ezpz_dndz_oidc_client_secret_file")]
  pub oidc_client_secret_file: Option<PathBuf>,

  /// Path to the JSON file backing the dice-roller history.
  /// Defaults to `<data_dir>/dice-history.json`.
  #[arg(long, env = "ezpz_dndz_dice_history_path")]
  pub dice_history_path: Option<PathBuf>,

  /// Path to the JSON file backing the creature compendium.
  /// Defaults to `<data_dir>/compendium/creatures.json`.
  #[arg(long, env = "ezpz_dndz_compendium_path")]
  pub compendium_path: Option<PathBuf>,

  /// Path to the JSON file backing user-named compendium snapshots.
  /// Defaults to `<data_dir>/compendium-saves.json`.
  #[arg(long, env = "ezpz_dndz_compendium_saves_path")]
  pub compendium_saves_path: Option<PathBuf>,

  /// Path to the JSON file backing the persisted live encounter.
  /// Defaults to `<data_dir>/encounter.json`.
  #[arg(long, env = "ezpz_dndz_encounter_path")]
  pub encounter_path: Option<PathBuf>,

  /// Path to the JSON file backing user-named saved encounters.
  /// Defaults to `<data_dir>/encounter-saves.json`.
  #[arg(long, env = "ezpz_dndz_encounter_saves_path")]
  pub encounter_saves_path: Option<PathBuf>,
}

/// Companion to `ExtraCliFields` flattened into `ConfigFileRaw`.
#[derive(Debug, Deserialize, Default)]
pub struct ExtraFileFields {
  pub oidc_issuer: Option<String>,
  pub oidc_client_id: Option<String>,
  pub oidc_client_secret_file: Option<PathBuf>,
  pub dice_history_path: Option<PathBuf>,
  pub compendium_path: Option<PathBuf>,
  pub compendium_saves_path: Option<PathBuf>,
  pub encounter_path: Option<PathBuf>,
  pub encounter_saves_path: Option<PathBuf>,
}

/// Concrete on-disk locations for the per-store JSON files,
/// resolved from `data_dir` + per-path overrides.
#[derive(Debug, Clone)]
pub struct RuntimePaths {
  pub dice_history: PathBuf,
  pub compendium: PathBuf,
  pub compendium_saves: PathBuf,
  pub encounter: PathBuf,
  pub encounter_saves: PathBuf,
}

#[derive(Debug, Clone, MergeConfig)]
#[merge_config(
  app_name = "ezpz-dndz",
  extra_cli = "ExtraCliFields",
  extra_file = "ExtraFileFields"
)]
pub struct Config {
  #[merge_config(common)]
  pub log_level: LogLevel,
  #[merge_config(common)]
  pub log_format: LogFormat,

  /// Address to listen on: host:port for TCP, /path/to.sock for
  /// Unix socket, or sd-listen to inherit from systemd.
  #[merge_config(
    name = "listen",
    env,
    default = "\"127.0.0.1:3000\".to_string()",
    parse
  )]
  pub listen_address: ListenerAddress,

  /// Path to compiled frontend static assets.
  #[merge_config(
    env,
    default = "std::path::PathBuf::from(\"frontend/public\")"
  )]
  pub frontend_path: PathBuf,

  /// Root directory for runtime persistence.  All
  /// `--*-path` overrides default into this directory; deployments
  /// only have to bind-mount a single directory.
  #[merge_config(env, default = "std::path::PathBuf::from(\".\")")]
  pub data_dir: PathBuf,

  /// Base URL of the service (e.g. https://example.com), used to
  /// construct the OIDC redirect URI.
  #[merge_config(env, default = "\"http://localhost:3000\".to_string()")]
  pub base_url: String,

  /// Resolved on-disk locations for the per-store JSON files.
  #[merge_config(skip)]
  pub paths: RuntimePaths,

  /// Resolved OIDC client config, or `None` if OIDC is disabled.
  #[merge_config(skip)]
  pub oidc: Option<OidcConfig>,
}

impl Config {
  fn resolve_paths(
    cli: &CliRaw,
    file: &ConfigFileRaw,
  ) -> Result<RuntimePaths, ConfigError> {
    let data_dir = cli
      .data_dir
      .clone()
      .or_else(|| file.data_dir.clone())
      .unwrap_or_else(|| PathBuf::from("."));

    let pick = |cli_val: Option<&PathBuf>,
                file_val: Option<&PathBuf>,
                default_rel: &str| {
      cli_val
        .cloned()
        .or_else(|| file_val.cloned())
        .unwrap_or_else(|| data_dir.join(default_rel))
    };

    Ok(RuntimePaths {
      dice_history: pick(
        cli.extra.dice_history_path.as_ref(),
        file.extra.dice_history_path.as_ref(),
        "dice-history.json",
      ),
      compendium: cli
        .extra
        .compendium_path
        .clone()
        .or_else(|| file.extra.compendium_path.clone())
        .unwrap_or_else(|| data_dir.join("compendium").join("creatures.json")),
      compendium_saves: pick(
        cli.extra.compendium_saves_path.as_ref(),
        file.extra.compendium_saves_path.as_ref(),
        "compendium-saves.json",
      ),
      encounter: pick(
        cli.extra.encounter_path.as_ref(),
        file.extra.encounter_path.as_ref(),
        "encounter.json",
      ),
      encounter_saves: pick(
        cli.extra.encounter_saves_path.as_ref(),
        file.extra.encounter_saves_path.as_ref(),
        "encounter-saves.json",
      ),
    })
  }

  fn resolve_oidc(
    cli: &CliRaw,
    file: &ConfigFileRaw,
  ) -> Result<Option<OidcConfig>, ConfigError> {
    let oidc_issuer = cli
      .extra
      .oidc_issuer
      .clone()
      .or_else(|| file.extra.oidc_issuer.clone());
    let oidc_client_id = cli
      .extra
      .oidc_client_id
      .clone()
      .or_else(|| file.extra.oidc_client_id.clone());
    let oidc_secret_file = cli
      .extra
      .oidc_client_secret_file
      .clone()
      .or_else(|| file.extra.oidc_client_secret_file.clone());

    match (&oidc_issuer, &oidc_client_id) {
      (None, None) if oidc_secret_file.is_none() => Ok(None),
      (Some(issuer), Some(client_id)) => {
        let secret_file = oidc_secret_file
          .or_else(credential_secret_path)
          .ok_or_else(|| {
            ConfigError::Validation(
              "oidc_client_secret_file is required when oidc_issuer \
               and oidc_client_id are set (set it explicitly or run \
               under systemd with LoadCredential)"
                .to_string(),
            )
          })?;

        let client_secret = std::fs::read_to_string(&secret_file)
          .map(|s| s.trim().to_string())
          .map_err(|source| {
            ConfigError::Validation(format!(
              "Failed to read OIDC client secret file at {}: {}",
              secret_file.display(),
              source,
            ))
          })?;

        Ok(Some(OidcConfig {
          issuer: issuer.clone(),
          client_id: client_id.clone(),
          client_secret,
        }))
      }
      _ => {
        let mut present = Vec::new();
        let mut missing = Vec::new();
        for (name, val) in [
          ("oidc_issuer", oidc_issuer.is_some()),
          ("oidc_client_id", oidc_client_id.is_some()),
          (
            "oidc_client_secret_file",
            oidc_secret_file.is_some() || credential_secret_path().is_some(),
          ),
        ] {
          if val {
            present.push(name);
          } else {
            missing.push(name);
          }
        }
        Err(ConfigError::Validation(format!(
          "partial OIDC configuration: set all three fields or none. \
           present: [{}], missing: [{}]",
          present.join(", "),
          missing.join(", "),
        )))
      }
    }
  }
}

impl ServerApp for Config {
  fn server_run_configs(&self) -> Vec<ServerRunConfig> {
    vec![ServerRunConfig {
      app_name: <Self as rust_template_foundation::CliApp>::app_name()
        .to_string(),
      listen_address: self.listen_address.clone(),
      frontend_path: Some(self.frontend_path.clone()),
      base_url: self.base_url.clone(),
      oidc: self.oidc.clone(),
    }]
  }
}
