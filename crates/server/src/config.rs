//! Server configuration.
//!
//! Built on the foundation's `MergeConfig` derive.  The macro generates
//! `CliRaw`, `ConfigFileRaw`, the `Config::from_cli_and_file` merge,
//! and the `CliApp` impl that `#[foundation_main]` wires up.
//!
//! Two pieces of resolution sit in `skip` fields:
//!
//! - `paths`: every per-store JSON file lives at a fixed name inside
//!   `data_dir`, which is a cross-field rule MergeConfig can't model
//!   directly.  There are deliberately no per-store path overrides —
//!   deployments bind-mount one directory and every store follows.
//! - `oidc`: assembled from three CLI / file fields plus the systemd
//!   `LoadCredential` directory; partial configurations error out.
//!
//! `extra_cli` and `extra_file` flatten the OIDC + migration fields
//! into `CliRaw` / `ConfigFileRaw` so they appear as proper
//! command-line flags and TOML keys without bloating the `Config`
//! shape.

use ezpz_dndz_lib::{LogFormat, LogLevel};
use rust_template_foundation::auth::OidcConfig;
use rust_template_foundation::config::credential_secret_path;
use rust_template_foundation::server::runner::{ServerApp, ServerRunConfig};
use rust_template_foundation::MergeConfig;
use serde::Deserialize;
use std::path::{Path, PathBuf};
use tokio_listener::ListenerAddress;

/// OIDC bundle + migration one-shots, flattened into `CliRaw`.
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

  /// Email address of the user who should receive the legacy
  /// shared-compendium creatures during the one-time per-user
  /// split migration.  Only consulted on first boot of the post-
  /// split binary against a data dir that has non-bundled
  /// creatures in the legacy shared store; absent on subsequent
  /// boots because the migration writes a sidecar marker file
  /// that suppresses re-runs.
  #[arg(long, env = "ezpz_dndz_compendium_claim_user")]
  pub compendium_claim_user: Option<String>,
}

/// Companion to `ExtraCliFields` flattened into `ConfigFileRaw`.
#[derive(Debug, Deserialize, Default)]
pub struct ExtraFileFields {
  pub oidc_issuer: Option<String>,
  pub oidc_client_id: Option<String>,
  pub oidc_client_secret_file: Option<PathBuf>,
  pub compendium_claim_user: Option<String>,
}

/// Concrete on-disk locations for the per-store JSON files.  Every
/// path is a fixed name inside `data_dir` — see
/// [`RuntimePaths::from_data_dir`].
#[derive(Debug, Clone)]
pub struct RuntimePaths {
  pub dice_history: PathBuf,
  pub compendium: PathBuf,
  pub compendium_saves: PathBuf,
  pub compendium_groups: PathBuf,
  pub user_creatures: PathBuf,
  pub card_layouts: PathBuf,
  pub encounter: PathBuf,
  pub encounter_saves: PathBuf,
  pub users: PathBuf,
  pub lore_groups: PathBuf,
  pub condition_presets: PathBuf,
  pub save_chain_presets: PathBuf,
  pub treasure_table: PathBuf,
  pub treasure_profiles: PathBuf,
}

impl RuntimePaths {
  /// Derive every store location from the single data directory.
  /// The two compendium stores live in a `compendium/` subdirectory
  /// (the split migration's sidecar marker lands there too); every
  /// other store is a flat JSON file.
  pub fn from_data_dir(data_dir: &Path) -> Self {
    Self {
      dice_history: data_dir.join("dice-history.json"),
      compendium: data_dir.join("compendium").join("creatures.json"),
      compendium_saves: data_dir.join("compendium-saves.json"),
      compendium_groups: data_dir.join("compendium-groups.json"),
      user_creatures: data_dir.join("compendium").join("user-creatures.json"),
      card_layouts: data_dir.join("card-layouts.json"),
      encounter: data_dir.join("encounter.json"),
      encounter_saves: data_dir.join("encounter-saves.json"),
      users: data_dir.join("users.json"),
      lore_groups: data_dir.join("lore-groups.json"),
      condition_presets: data_dir.join("condition-presets.json"),
      save_chain_presets: data_dir.join("save-chain-presets.json"),
      treasure_table: data_dir.join("treasure-table.json"),
      treasure_profiles: data_dir.join("treasure-profiles.json"),
    }
  }
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

  /// Root directory for runtime persistence.  Every store file
  /// lives at a fixed name inside this directory, so deployments
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

  /// Email address that should receive the legacy shared-compendium
  /// creatures during the one-time per-user split migration.
  /// `None` after the migration has run (the sidecar marker
  /// suppresses re-runs regardless of this value).
  #[merge_config(skip)]
  pub compendium_claim_user: Option<String>,
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
    Ok(RuntimePaths::from_data_dir(&data_dir))
  }

  /// One-shot input for the per-user-compendium split migration.
  /// CLI flag wins over the TOML config file value; both are
  /// optional, since the migration only requires a value on the
  /// first boot of the post-split binary that actually finds
  /// non-bundled creatures in the legacy shared store.
  fn resolve_compendium_claim_user(
    cli: &CliRaw,
    file: &ConfigFileRaw,
  ) -> Result<Option<String>, ConfigError> {
    Ok(
      cli
        .extra
        .compendium_claim_user
        .clone()
        .or_else(|| file.extra.compendium_claim_user.clone()),
    )
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
      base_url: self.base_url.clone(),
      oidc: self.oidc.clone(),
    }]
  }
}
