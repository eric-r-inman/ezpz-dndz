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

  /// Path to the JSON file backing per-user compendium groups.
  /// Defaults to `<data_dir>/compendium-groups.json`.
  #[arg(long, env = "ezpz_dndz_compendium_groups_path")]
  pub compendium_groups_path: Option<PathBuf>,

  /// Path to the JSON file backing the per-user compendium
  /// creature store.  Defaults to
  /// `<data_dir>/compendium/user-creatures.json`.
  #[arg(long, env = "ezpz_dndz_user_creatures_path")]
  pub user_creatures_path: Option<PathBuf>,

  /// Email address of the user who should receive the legacy
  /// shared-compendium creatures during the one-time per-user
  /// split migration.  Only consulted on first boot of the post-
  /// split binary against a data dir that has non-bundled
  /// creatures in the legacy shared store; absent on subsequent
  /// boots because the migration writes a sidecar marker file
  /// that suppresses re-runs.
  #[arg(long, env = "ezpz_dndz_compendium_claim_user")]
  pub compendium_claim_user: Option<String>,

  /// Path to the JSON file backing per-user saved card layouts.
  /// Defaults to `<data_dir>/card-layouts.json`.
  #[arg(long, env = "ezpz_dndz_card_layouts_path")]
  pub card_layouts_path: Option<PathBuf>,

  /// Path to the JSON file backing the persisted live encounter.
  /// Defaults to `<data_dir>/encounter.json`.
  #[arg(long, env = "ezpz_dndz_encounter_path")]
  pub encounter_path: Option<PathBuf>,

  /// Path to the JSON file backing user-named saved encounters.
  /// Defaults to `<data_dir>/encounter-saves.json`.
  #[arg(long, env = "ezpz_dndz_encounter_saves_path")]
  pub encounter_saves_path: Option<PathBuf>,

  /// Path to the JSON file backing the user-account database.
  /// Defaults to `<data_dir>/users.json`.
  #[arg(long, env = "ezpz_dndz_users_path")]
  pub users_path: Option<PathBuf>,

  /// Path to the JSON file backing per-user user-authored Lore
  /// groups for the Random Encounter generator.  Defaults to
  /// `<data_dir>/lore-groups.json`.
  #[arg(long, env = "ezpz_dndz_lore_groups_path")]
  pub lore_groups_path: Option<PathBuf>,

  /// Path to the JSON file backing per-user saved presets for
  /// the Add-Condition modal.  Defaults to
  /// `<data_dir>/condition-presets.json`.
  #[arg(long, env = "ezpz_dndz_condition_presets_path")]
  pub condition_presets_path: Option<PathBuf>,

  /// Path to the JSON file backing per-user singular treasure
  /// tables for the Treasure generator.  Defaults to
  /// `<data_dir>/treasure-table.json`.
  #[arg(long, env = "ezpz_dndz_treasure_table_path")]
  pub treasure_table_path: Option<PathBuf>,
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
  pub compendium_groups_path: Option<PathBuf>,
  pub user_creatures_path: Option<PathBuf>,
  pub card_layouts_path: Option<PathBuf>,
  pub encounter_path: Option<PathBuf>,
  pub encounter_saves_path: Option<PathBuf>,
  pub lore_groups_path: Option<PathBuf>,
  pub condition_presets_path: Option<PathBuf>,
  pub treasure_table_path: Option<PathBuf>,
  pub users_path: Option<PathBuf>,
  pub compendium_claim_user: Option<String>,
}

/// Concrete on-disk locations for the per-store JSON files,
/// resolved from `data_dir` + per-path overrides.
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
  pub treasure_table: PathBuf,
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
      compendium_groups: pick(
        cli.extra.compendium_groups_path.as_ref(),
        file.extra.compendium_groups_path.as_ref(),
        "compendium-groups.json",
      ),
      user_creatures: cli
        .extra
        .user_creatures_path
        .clone()
        .or_else(|| file.extra.user_creatures_path.clone())
        .unwrap_or_else(|| {
          data_dir.join("compendium").join("user-creatures.json")
        }),
      card_layouts: pick(
        cli.extra.card_layouts_path.as_ref(),
        file.extra.card_layouts_path.as_ref(),
        "card-layouts.json",
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
      users: pick(
        cli.extra.users_path.as_ref(),
        file.extra.users_path.as_ref(),
        "users.json",
      ),
      lore_groups: pick(
        cli.extra.lore_groups_path.as_ref(),
        file.extra.lore_groups_path.as_ref(),
        "lore-groups.json",
      ),
      condition_presets: pick(
        cli.extra.condition_presets_path.as_ref(),
        file.extra.condition_presets_path.as_ref(),
        "condition-presets.json",
      ),
      treasure_table: pick(
        cli.extra.treasure_table_path.as_ref(),
        file.extra.treasure_table_path.as_ref(),
        "treasure-table.json",
      ),
    })
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
      frontend_path: Some(self.frontend_path.clone()),
      base_url: self.base_url.clone(),
      oidc: self.oidc.clone(),
    }]
  }
}
